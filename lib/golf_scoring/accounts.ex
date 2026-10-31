defmodule GolfScoring.Accounts do
  @moduledoc "Staff account domain."

  use Ash.Domain

  alias GolfScoring.Accounts.Services.IssuePlayerAccess
  alias GolfScoring.Accounts.Services.ReissuePlayerAccess
  alias GolfScoring.Accounts.Services.RevokePlayerAccess

  resources do
    resource GolfScoring.Accounts.StaffUser do
      define :grant_system_admin, action: :grant_system_admin
      define :revoke_system_admin, action: :revoke_system_admin
      define :suspend_staff_user, action: :suspend_staff_user
      define :reactivate_staff_user, action: :reactivate_staff_user
      define :disable_staff_user, action: :disable_staff_user
    end

    resource GolfScoring.Accounts.EventStaffAssignment do
      define :assign_event_staff_role, action: :assign_event_staff_role
      define :revoke_event_staff_role, action: :revoke_event_staff_role
    end

    resource GolfScoring.Accounts.PlayerAccessGrant
  end

  @spec issue_player_access(map(), Ecto.UUID.t(), Ecto.UUID.t(), keyword()) ::
          {:ok, %{grant: struct(), token: String.t()}} | {:error, term()}
  def issue_player_access(actor, event_id, player_id, opts \\ []) do
    IssuePlayerAccess.run(actor, event_id, player_id, opts)
  end

  @spec reissue_player_access(map(), Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, %{grant: struct(), token: String.t()}} | {:error, term()}
  def reissue_player_access(actor, event_id, player_id) do
    ReissuePlayerAccess.run(actor, event_id, player_id)
  end

  @spec revoke_player_access(map(), Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, struct()} | {:error, term()}
  def revoke_player_access(actor, event_id, player_id) do
    RevokePlayerAccess.run(actor, event_id, player_id)
  end
end
