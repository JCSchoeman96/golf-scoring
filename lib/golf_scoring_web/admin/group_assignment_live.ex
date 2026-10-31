defmodule GolfScoringWeb.Admin.GroupAssignmentLive do
  @moduledoc false

  use GolfScoringWeb, :live_view

  require Ash.Query

  alias GolfScoring.Accounts.Checks.ActiveEventRole
  alias GolfScoring.Accounts.StaffUser
  alias GolfScoring.Competition
  alias GolfScoring.Competition.PlayingGroup
  alias GolfScoring.Competition.PlayingGroupReadiness
  alias GolfScoring.Competition.Round
  alias GolfScoring.Competition.RoundEntry
  alias GolfScoring.Competition.RoundHole
  alias GolfScoring.Competition.Services.AssignEntryToGroup
  alias GolfScoring.Competition.Services.AssignPlayingGroupStart
  alias GolfScoring.Competition.StartingPositionLabel
  alias GolfScoring.Repo
  alias GolfScoringWeb.Admin.InputParsing

  @setup_roles [:event_admin, :competition_manager]

  @impl true
  def mount(%{"event_id" => event_id, "round_id" => round_id}, _session, socket) do
    with %StaffUser{status: :active} = staff <- socket.assigns[:current_staffuser],
         {:ok, event_uuid} <- Ecto.UUID.cast(event_id),
         {:ok, round_uuid} <- Ecto.UUID.cast(round_id),
         {:ok, round} <- fetch_round(round_uuid),
         true <- round.event_id == event_uuid,
         true <- ActiveEventRole.authorized?(staff.id, event_uuid, @setup_roles) do
      fresh = Repo.get!(StaffUser, staff.id)

      socket =
        socket
        |> assign(:current_staff_user, fresh)
        |> assign(:page_title, "Group assignment")
        |> assign(:event_id, event_uuid)
        |> assign(:round, round)
        |> assign(:can_mutate, pre_open?(round))
        |> refresh_assignments(round)

      {:ok, socket}
    else
      _ ->
        {:ok,
         socket
         |> put_flash(:error, "You are not allowed to configure PlayingGroups for this Round.")
         |> push_navigate(to: ~p"/admin")}
    end
  end

  @impl true
  def handle_event("create_group", _params, socket) do
    staff = Repo.get!(StaffUser, socket.assigns.current_staff_user.id)
    round = socket.assigns.round
    event_id = socket.assigns.event_id

    case Competition.create_playing_group(event_id, round.id, actor: staff) do
      {:ok, _group} ->
        {:noreply,
         socket
         |> put_flash(:info, "Playing group created.")
         |> refresh_assignments(round)}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, "Could not create Playing group.")}
    end
  end

  def handle_event(
        "assign_entry",
        %{"assignment" => %{"entry_id" => entry_id, "group_id" => group_id}},
        socket
      ) do
    staff = Repo.get!(StaffUser, socket.assigns.current_staff_user.id)
    round = socket.assigns.round
    event_id = socket.assigns.event_id

    with {:ok, entry_uuid} <- InputParsing.parse_uuid(entry_id),
         {:ok, group_uuid} <- InputParsing.parse_uuid(group_id) do
      case AssignEntryToGroup.run(staff, event_id, round.id, entry_uuid, group_uuid) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "Entry assigned to group.")
           |> refresh_assignments(round)}

        {:error, :forbidden} ->
          {:noreply, put_flash(socket, :error, "You are not allowed to assign group membership.")}

        {:error, :group_capacity_exceeded} ->
          {:noreply, put_flash(socket, :error, "That group is already full (maximum 4 players).")}

        {:error, {:invalid_round_state, state}} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             "Group assignment is not allowed while the Round is #{state}."
           )}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not assign entry to group.")}
      end
    else
      {:error, :invalid_input} ->
        {:noreply, put_flash(socket, :error, "Entry and group must be valid identifiers.")}
    end
  end

  def handle_event(
        "assign_start",
        %{
          "start" => %{
            "group_id" => group_id,
            "round_hole_id" => round_hole_id,
            "position" => position
          }
        },
        socket
      ) do
    staff = Repo.get!(StaffUser, socket.assigns.current_staff_user.id)
    round = socket.assigns.round
    event_id = socket.assigns.event_id

    with {:ok, group_uuid} <- InputParsing.parse_uuid(group_id),
         {:ok, hole_uuid} <- InputParsing.parse_uuid(round_hole_id),
         {:ok, position_int} <- InputParsing.parse_positive_integer(position) do
      case AssignPlayingGroupStart.run(
             staff,
             event_id,
             round.id,
             group_uuid,
             hole_uuid,
             position_int
           ) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "Starting assignment saved.")
           |> refresh_assignments(round)}

        {:error, :forbidden} ->
          {:noreply, put_flash(socket, :error, "You are not allowed to assign shotgun starts.")}

        {:error, {:invalid_round_state, state}} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             "Start assignment is not allowed while the Round is #{state}."
           )}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not assign shotgun start.")}
      end
    else
      {:error, :invalid_input} ->
        {:noreply, put_flash(socket, :error, "Group, hole, and position must be valid values.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section id="group-assignment" class="space-y-6">
        <header class="space-y-2">
          <p class="text-sm font-medium text-base-content/70">
            Event {@event_id} · Round {@round.id}
          </p>
          <h1 class="text-2xl font-semibold tracking-tight">Playing group assignment</h1>
          <p id="round-state" class="text-sm text-base-content/70">State: {@round.state}</p>
        </header>

        <%= if @can_mutate do %>
          <div class="flex gap-3">
            <button
              id="create-playing-group-button"
              type="button"
              phx-click="create_group"
              class="btn btn-primary btn-sm"
            >
              Create empty group
            </button>
          </div>
        <% end %>

        <div id="unassigned-entries" class="rounded-2xl border border-base-300 bg-base-100 p-4">
          <h2 class="text-lg font-semibold">Unassigned entries</h2>
          <ul class="mt-2 space-y-1 text-sm">
            <li :for={entry <- @unassigned_entries} id={"unassigned-entry-#{entry.id}"}>
              Entry {entry.id}
            </li>
          </ul>
        </div>

        <div id="group-list" class="space-y-4">
          <article
            :for={group <- @groups}
            id={"playing-group-#{group.id}"}
            class="rounded-2xl border border-base-300 bg-base-100 p-4 space-y-3"
          >
            <header class="flex flex-wrap items-baseline justify-between gap-2">
              <h2 class="font-semibold">Group {String.slice(group.id, 0, 8)}</h2>
              <p id={"group-member-count-#{group.id}"} class="text-sm text-base-content/70">
                Members: {group.member_count} / {PlayingGroupReadiness.setup_capacity_max()}
                <%= if not group.starting_ready? do %>
                  <span class="text-warning"> · incomplete setup</span>
                <% end %>
              </p>
            </header>

            <p id={"group-start-label-#{group.id}"} class="text-sm">
              Start: {group.start_label}
            </p>

            <ul id={"group-members-#{group.id}"} class="text-sm list-disc pl-5">
              <li :for={member_id <- group.member_ids}>Entry {member_id}</li>
            </ul>

            <%= if @can_mutate do %>
              <.form
                id={"assign-entry-form-#{group.id}"}
                for={%{}}
                phx-submit="assign_entry"
                class="flex flex-wrap gap-2 items-end"
              >
                <input type="hidden" name="assignment[group_id]" value={group.id} />
                <.input
                  id={"assign-entry-select-#{group.id}"}
                  name="assignment[entry_id]"
                  type="select"
                  label="Assign entry"
                  value=""
                  options={entry_options(@unassigned_entries)}
                  prompt="Select entry"
                />
                <button type="submit" class="btn btn-sm btn-outline">Assign</button>
              </.form>

              <.form
                id={"assign-start-form-#{group.id}"}
                for={%{}}
                phx-submit="assign_start"
                class="flex flex-wrap gap-2 items-end"
              >
                <input type="hidden" name="start[group_id]" value={group.id} />
                <.input
                  id={"assign-start-hole-#{group.id}"}
                  name="start[round_hole_id]"
                  type="select"
                  label="Starting hole"
                  value=""
                  options={@round_hole_options}
                  prompt="Select hole"
                />
                <.input
                  id={"assign-start-position-#{group.id}"}
                  name="start[position]"
                  type="number"
                  label="Position"
                  value=""
                />
                <button type="submit" class="btn btn-sm btn-outline">Save start</button>
              </.form>
            <% end %>
          </article>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp fetch_round(round_id) do
    case Ash.get(Round, round_id, authorize?: false) do
      {:ok, round} -> {:ok, round}
      {:error, error} -> {:error, error}
    end
  end

  defp pre_open?(round), do: round.state in [:draft, :ready]

  defp refresh_assignments(socket, round) do
    round = Repo.get!(Round, round.id)

    groups = list_groups(round.id)
    unassigned = list_unassigned_entries(round.id)
    round_holes = list_round_holes(round.id)

    socket
    |> assign(:round, round)
    |> assign(:can_mutate, pre_open?(round))
    |> assign(:groups, groups)
    |> assign(:unassigned_entries, unassigned)
    |> assign(:round_hole_options, round_hole_options(round_holes))
  end

  defp list_groups(round_id) do
    holes_by_id =
      round_id
      |> list_round_holes()
      |> Map.new(&{&1.id, &1})

    PlayingGroup
    |> Ash.Query.filter(round_id == ^round_id)
    |> Ash.read!(authorize?: false)
    |> Enum.sort_by(&Ecto.UUID.dump!(&1.id))
    |> Enum.map(fn group ->
      member_ids = member_ids_for_group(group.id)
      member_count = length(member_ids)

      start_label =
        case {group.starting_round_hole_id, group.starting_position} do
          {hole_id, pos} when not is_nil(hole_id) and not is_nil(pos) ->
            hole = Map.fetch!(holes_by_id, hole_id)
            StartingPositionLabel.format(hole.display_hole_number, pos)

          _ ->
            "Not assigned"
        end

      %{
        id: group.id,
        member_ids: member_ids,
        member_count: member_count,
        starting_ready?: PlayingGroupReadiness.starting_ready?(member_count),
        start_label: start_label
      }
    end)
  end

  defp member_ids_for_group(group_id) do
    Repo.query!(
      """
      SELECT id::text FROM round_entries
      WHERE playing_group_id = $1::uuid
      ORDER BY id
      """,
      [Ecto.UUID.dump!(group_id)]
    ).rows
    |> Enum.map(fn [id] -> id end)
  end

  defp list_unassigned_entries(round_id) do
    RoundEntry
    |> Ash.Query.filter(round_id == ^round_id and is_nil(playing_group_id))
    |> Ash.read!(authorize?: false)
    |> Enum.sort_by(&Ecto.UUID.dump!(&1.id))
  end

  defp list_round_holes(round_id) do
    RoundHole
    |> Ash.Query.filter(round_id == ^round_id)
    |> Ash.Query.sort(play_order: :asc)
    |> Ash.read!(authorize?: false)
  end

  defp round_hole_options(holes) do
    Enum.map(holes, fn hole ->
      {"Hole #{hole.display_hole_number} (play #{hole.play_order})", hole.id}
    end)
  end

  defp entry_options(entries) do
    Enum.map(entries, fn entry -> {entry.id, entry.id} end)
  end
end
