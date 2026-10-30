defmodule GolfScoring.Accounts.SystemAdminGuard do
  @moduledoc """
  Serializes SYSTEM_ADMIN capability changes with PostgreSQL advisory key
  `(0x475343, 1)`. `0x475343` is the stable GSC namespace and `1` identifies
  the global SYSTEM_ADMIN lifecycle. Future SYSTEM_ADMIN-affecting actions
  must acquire this same transaction-scoped lock.
  """

  use Ash.Resource.Change

  alias GolfScoring.Accounts.StaffUser
  alias GolfScoring.Audit
  alias GolfScoring.Repo

  @lock_namespace 0x475343
  @lock_identity 1

  @impl true
  def change(changeset, opts, context) do
    operation = Keyword.fetch!(opts, :operation)
    actor = context.actor

    changeset
    |> Ash.Changeset.before_action(fn changeset ->
      lock_and_validate(changeset, actor, operation)
    end)
    |> Ash.Changeset.after_action(fn _changeset, target ->
      write_audit(actor, target, operation)
    end)
  end

  @doc false
  def acquire_lock!(repo \\ Repo) do
    unless repo.in_transaction?() do
      raise ArgumentError, "SYSTEM_ADMIN advisory lock requires an open repository transaction"
    end

    repo.query!("SELECT pg_advisory_xact_lock($1, $2)", [@lock_namespace, @lock_identity])
    :ok
  end

  defp lock_and_validate(changeset, actor, operation) do
    acquire_lock!()

    target_id = changeset.data.id
    actor_id = actor && Map.get(actor, :id)
    locked_users = lock_staff_users([actor_id, target_id])

    actor_row = Map.get(locked_users, actor_id)
    target_row = Map.get(locked_users, target_id)

    with :ok <- active_system_admin(actor_row),
         :ok <- valid_target(target_row, operation),
         :ok <- active_admin_remains(target_row, operation) do
      changeset =
        case target_row do
          %{record: record} -> %{changeset | data: record}
          _ -> changeset
        end

      Ash.Changeset.force_change_attribute(
        changeset,
        :system_admin,
        operation == :grant
      )
    else
      {:error, message} ->
        Ash.Changeset.add_error(changeset, field: :system_admin, message: message)
    end
  end

  defp lock_staff_users(ids) do
    ids
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort_by(&Ecto.UUID.dump!/1)
    |> Map.new(fn id ->
      result =
        Repo.query!(
          """
          SELECT id::text, status, system_admin
          FROM staff_users
          WHERE id = $1::uuid
          FOR UPDATE
          """,
          [Ecto.UUID.dump!(id)]
        )

      case result.rows do
        [[row_id, status, system_admin]] ->
          {id,
           %{
             id: row_id,
             status: status,
             system_admin: system_admin,
             record: Repo.get!(StaffUser, id)
           }}

        [] ->
          {id, nil}
      end
    end)
  end

  defp active_system_admin(%{status: "active", system_admin: true}), do: :ok

  defp active_system_admin(_actor) do
    {:error, "an active SYSTEM_ADMIN is required"}
  end

  defp valid_target(nil, _operation), do: {:error, "target StaffUser does not exist"}

  defp valid_target(%{system_admin: false, status: "active"}, :grant), do: :ok

  defp valid_target(%{status: status}, :grant) when status != "active" do
    {:error, "SYSTEM_ADMIN can only be granted to active staff"}
  end

  defp valid_target(%{system_admin: true}, :grant) do
    {:error, "target StaffUser is already a SYSTEM_ADMIN"}
  end

  defp valid_target(%{system_admin: true}, :revoke), do: :ok

  defp valid_target(%{system_admin: false}, :revoke) do
    {:error, "target StaffUser is not a SYSTEM_ADMIN"}
  end

  defp active_admin_remains(%{status: "active"}, :revoke) do
    case Repo.query!(
           "SELECT count(*) FROM staff_users WHERE status = 'active' AND system_admin = TRUE"
         ).rows do
      [[1]] -> {:error, "cannot revoke the last active SYSTEM_ADMIN"}
      [[count]] when count > 1 -> :ok
    end
  end

  defp active_admin_remains(_target, _operation), do: :ok

  defp write_audit(actor, target, operation) do
    {action, from, to} =
      case operation do
        :grant -> {"system_admin_granted", false, true}
        :revoke -> {"system_admin_revoked", true, false}
      end

    attributes = %{
      actor_staff_user_id: actor.id,
      action: action,
      target_type: "staff_user",
      target_id: target.id,
      changes: %{"system_admin" => %{"from" => from, "to" => to}}
    }

    case Audit.record_staff_event(attributes, authorize?: false) do
      {:ok, _event} -> {:ok, target}
      {:error, error} -> {:error, error}
    end
  end
end
