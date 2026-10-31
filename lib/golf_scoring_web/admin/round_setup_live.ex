defmodule GolfScoringWeb.Admin.RoundSetupLive do
  @moduledoc false

  use GolfScoringWeb, :live_view

  alias GolfScoring.Accounts.Checks.ActiveEventRole
  alias GolfScoring.Accounts.StaffUser
  alias GolfScoring.Competition
  alias GolfScoring.Competition.Round
  alias GolfScoring.Competition.Services.ClearRoundTeeSnapshots
  alias GolfScoring.Competition.Services.ConfigureRoundLayout
  alias GolfScoring.Competition.Services.SnapshotRoundTeeProfiles
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

      {:ok,
       socket
       |> assign(:current_staff_user, fresh)
       |> assign(:page_title, "Round setup")
       |> assign(:event_id, event_uuid)
       |> assign(:round, round)
       |> assign(:can_mutate, true)
       |> refresh_round_state(round)}
    else
      _ ->
        {:ok,
         socket
         |> put_flash(:error, "You are not allowed to configure this Round.")
         |> push_navigate(to: ~p"/admin")}
    end
  end

  @impl true
  def handle_event("save_route", %{"route" => route_params}, socket) do
    staff = Repo.get!(StaffUser, socket.assigns.current_staff_user.id)
    round = socket.assigns.round

    case parse_route_selections(route_params) do
      {:error, :invalid_input} ->
        {:noreply,
         put_flash(socket, :error, "Choose a valid course hole for every play position.")}

      {:ok, course_hole_ids} ->
        case ConfigureRoundLayout.run(staff, round.id, course_hole_ids) do
          {:ok, route} ->
            {:noreply,
             socket
             |> put_flash(:info, "Round route saved (#{length(route)} holes).")
             |> refresh_round_state(round)}

          {:error, :forbidden} ->
            {:noreply,
             put_flash(socket, :error, "You are not allowed to configure this Round route.")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Route save failed: #{format_error(reason)}")}
        end
    end
  end

  @impl true
  def handle_event("snapshot_tees", %{"snapshot" => params}, socket) do
    staff = Repo.get!(StaffUser, socket.assigns.current_staff_user.id)
    round = socket.assigns.round

    profile_ids = Map.get(params, "profile_ids", []) |> List.wrap()

    case InputParsing.parse_uuids(profile_ids) do
      {:error, :invalid_input} ->
        {:noreply, put_flash(socket, :error, "Selected tee profiles must be valid.")}

      {:ok, selected} ->
        if selected == [] do
          {:noreply,
           put_flash(
             socket,
             :error,
             "Select at least one tee profile to snapshot. To remove snapshots, use Clear all snapshots."
           )}
        else
          respond_to_snapshot_run(staff, round, selected, socket)
        end
    end
  end

  def handle_event("clear_snapshots", _params, socket) do
    staff = Repo.get!(StaffUser, socket.assigns.current_staff_user.id)
    round = socket.assigns.round

    case ClearRoundTeeSnapshots.run(staff, round.id) do
      {:ok, []} ->
        {:noreply,
         socket
         |> put_flash(:info, "Cleared all tee profile snapshots.")
         |> refresh_round_state(round)}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, "You are not allowed to clear tee snapshots.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Clear snapshots failed: #{format_error(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section id="round-setup" class="space-y-6">
        <header class="space-y-2">
          <p class="text-sm font-medium text-base-content/70">
            Event {@event_id} · Round {@round.id}
          </p>
          <h1 class="text-2xl font-semibold tracking-tight">Round setup</h1>
          <p id="round-state" class="text-sm text-base-content/70">State: {@round.state}</p>
        </header>

        <%= if @can_mutate do %>
          <div class="rounded-2xl border border-base-300 bg-base-100 p-6 shadow-sm space-y-4">
            <h2 class="text-lg font-semibold">Round route</h2>
            <ol id="round-route-list" class="list-decimal pl-5 text-sm space-y-1">
              <li :for={hole <- @round_holes}>
                play {hole.play_order} · course hole {hole.course_hole_id}
              </li>
            </ol>
            <.form id="round-route-form" for={%{}} phx-submit="save_route">
              <div id="round-route-selectors" class="grid gap-3 sm:grid-cols-2">
                <%= for play_order <- 1..18 do %>
                  <.input
                    id={"round-route-hole-#{play_order}"}
                    name={"route[hole_#{play_order}]"}
                    type="select"
                    label={"Play #{play_order}"}
                    value={Map.get(@route_selections, play_order, "")}
                    options={@course_hole_options}
                    prompt="Select course hole"
                  />
                <% end %>
              </div>
              <button id="round-route-save-button" type="submit" class="btn btn-primary mt-3">
                Save route
              </button>
            </.form>
          </div>

          <div class="rounded-2xl border border-base-300 bg-base-100 p-6 shadow-sm space-y-4">
            <h2 class="text-lg font-semibold">Tee profile snapshots</h2>
            <ul id="snapshot-status-list" class="text-sm space-y-1">
              <li :for={snapshot <- @snapshots}>
                {snapshot.rating_label} · source {snapshot.source_tee_rating_profile_id}
              </li>
            </ul>
            <.form id="round-snapshot-form" for={%{}} phx-submit="snapshot_tees">
              <div id="tee-profile-options" class="space-y-2">
                <%= for profile <- @available_profiles do %>
                  <label class="flex items-center gap-2 text-sm">
                    <input
                      type="checkbox"
                      name="snapshot[profile_ids][]"
                      value={profile.id}
                      checked={profile.id in @selected_profile_ids}
                    />
                    {profile.rating_label} ({profile.tee_set_name})
                  </label>
                <% end %>
              </div>
              <button id="round-snapshot-button" type="submit" class="btn btn-primary mt-3">
                Snapshot selected profiles
              </button>
            </.form>
            <button
              id="round-clear-snapshots-button"
              type="button"
              class="btn btn-outline mt-3"
              phx-click="clear_snapshots"
            >
              Clear all snapshots
            </button>
          </div>
        <% end %>
      </section>
    </Layouts.app>
    """
  end

  defp respond_to_snapshot_run(staff, round, selected, socket) do
    case SnapshotRoundTeeProfiles.run(staff, round.id, selected) do
      {:ok, snapshots} ->
        {:noreply,
         socket
         |> put_flash(:info, snapshot_success_message(snapshots))
         |> refresh_round_state(round)}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, "You are not allowed to snapshot tee profiles.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Snapshot failed: #{format_error(reason)}")}
    end
  end

  defp snapshot_success_message(snapshots),
    do: "Snapshotted #{length(snapshots)} tee profile(s)."

  defp fetch_round(round_id) do
    case Competition.get_round_by_id(round_id, authorize?: false) do
      {:ok, round} -> {:ok, round}
      {:error, _} -> :error
    end
  end

  defp refresh_round_state(socket, round) do
    round_holes = list_round_holes(round.id)
    course_holes = list_course_holes(round.course_id)
    snapshots = list_snapshots(round.id)
    available = list_available_profiles(round.course_id)

    course_hole_options =
      Enum.map(course_holes, fn hole ->
        {"Hole #{hole.hole_number}", hole.id}
      end)

    route_selections =
      round_holes
      |> Enum.sort_by(& &1.play_order)
      |> Map.new(fn hole -> {hole.play_order, hole.course_hole_id} end)

    selected_profile_ids = Enum.map(snapshots, & &1.source_tee_rating_profile_id)

    socket
    |> assign(:round, Repo.get!(Round, round.id))
    |> assign(:round_holes, round_holes)
    |> assign(:course_holes, course_holes)
    |> assign(:course_hole_options, course_hole_options)
    |> assign(:route_selections, route_selections)
    |> assign(:snapshots, snapshots)
    |> assign(:available_profiles, available)
    |> assign(:selected_profile_ids, selected_profile_ids)
  end

  defp parse_route_selections(route_params) do
    1..18
    |> Enum.reduce_while({:ok, []}, fn play_order, {:ok, acc} ->
      key = "hole_#{play_order}"

      case InputParsing.parse_uuid(Map.get(route_params, key)) do
        {:ok, course_hole_id} -> {:cont, {:ok, [course_hole_id | acc]}}
        {:error, _} -> {:halt, {:error, :invalid_input}}
      end
    end)
    |> case do
      {:ok, ids} -> {:ok, Enum.reverse(ids)}
      error -> error
    end
  end

  defp format_error({:invalid_round_state, state}), do: "invalid round state #{state}"
  defp format_error(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_error(reason), do: inspect(reason)

  defp list_round_holes(round_id) do
    Repo.query!(
      """
      SELECT course_hole_id::text, play_order
      FROM round_holes
      WHERE round_id = $1::uuid
      ORDER BY play_order
      """,
      [Ecto.UUID.dump!(round_id)]
    ).rows
    |> Enum.map(fn [course_hole_id, play_order] ->
      %{course_hole_id: Ecto.UUID.cast!(course_hole_id), play_order: play_order}
    end)
  end

  defp list_course_holes(course_id) do
    Repo.query!(
      "SELECT id::text, hole_number FROM course_holes WHERE course_id = $1::uuid ORDER BY hole_number",
      [Ecto.UUID.dump!(course_id)]
    ).rows
    |> Enum.map(fn [id, n] -> %{id: Ecto.UUID.cast!(id), hole_number: n} end)
  end

  defp list_snapshots(round_id) do
    Repo.query!(
      """
      SELECT id::text, rating_label, source_tee_rating_profile_id::text
      FROM round_tee_profile_snapshots
      WHERE round_id = $1::uuid
      ORDER BY rating_label
      """,
      [Ecto.UUID.dump!(round_id)]
    ).rows
    |> Enum.map(fn [id, label, source_id] ->
      %{
        id: Ecto.UUID.cast!(id),
        rating_label: label,
        source_tee_rating_profile_id: Ecto.UUID.cast!(source_id)
      }
    end)
  end

  defp list_available_profiles(course_id) do
    Repo.query!(
      """
      SELECT p.id::text, p.rating_label, t.name
      FROM tee_rating_profiles p
      INNER JOIN tee_sets t ON t.id = p.tee_set_id
      WHERE t.course_id = $1::uuid
      ORDER BY p.rating_label
      """,
      [Ecto.UUID.dump!(course_id)]
    ).rows
    |> Enum.map(fn [id, label, tee_set_name] ->
      %{id: Ecto.UUID.cast!(id), rating_label: label, tee_set_name: tee_set_name}
    end)
  end
end
