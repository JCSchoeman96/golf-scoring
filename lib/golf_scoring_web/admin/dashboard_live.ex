defmodule GolfScoringWeb.Admin.DashboardLive do
  @moduledoc false

  use GolfScoringWeb, :live_view

  alias GolfScoring.Accounts.StaffUser
  alias GolfScoring.Competition.Services.CreateEvent
  alias GolfScoring.Repo

  @impl true
  def mount(_params, _session, socket) do
    case socket.assigns[:current_staffuser] do
      %StaffUser{status: :active} = staff ->
        fresh = Repo.get!(StaffUser, staff.id)

        {:ok,
         socket
         |> assign(:current_staff_user, fresh)
         |> assign(:page_title, "Admin")
         |> assign(:can_create_event, can_create_event?(fresh))
         |> assign(:last_event_id, nil)}

      _ ->
        {:ok, push_navigate(socket, to: ~p"/admin/sign-in")}
    end
  end

  @impl true
  def handle_event("create_event", _params, socket) do
    staff = Repo.get!(StaffUser, socket.assigns.current_staff_user.id)

    case CreateEvent.create(staff, %{"source" => "admin_dashboard"}) do
      {:ok, %{event: event}} ->
        {:noreply,
         socket
         |> put_flash(:info, "Event created.")
         |> assign(:last_event_id, event.id)}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, "You are not allowed to create Events.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Event creation failed.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section id="admin-dashboard" class="space-y-6">
        <header class="space-y-2">
          <p class="text-sm font-medium text-base-content/70">Staff administration</p>
          <h1 class="text-2xl font-semibold tracking-tight">Admin dashboard</h1>
        </header>

        <div class="rounded-2xl border border-base-300 bg-base-100 p-6 shadow-sm">
          <h2 class="text-lg font-semibold">Events</h2>
          <p class="mt-2 text-sm text-base-content/70">
            Create a draft Event with an initial Event Admin assignment.
          </p>

          <div class="mt-4 flex flex-wrap items-center gap-3">
            <%= if @can_create_event do %>
              <.button id="create-event-button" phx-click="create_event">
                Create Event
              </.button>
            <% else %>
              <p id="create-event-unavailable" class="text-sm text-base-content/70">
                Event creation requires an active SYSTEM_ADMIN account.
              </p>
            <% end %>
          </div>

          <%= if @last_event_id do %>
            <p id="last-created-event" class="mt-4 text-sm text-success">
              Latest Event: {@last_event_id}
            </p>
          <% end %>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp can_create_event?(%StaffUser{status: :active, system_admin: true}), do: true
  defp can_create_event?(_), do: false
end
