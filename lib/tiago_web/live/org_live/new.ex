defmodule TiagoWeb.OrgLive.New do
  use TiagoWeb, :live_view
  on_mount {TiagoWeb.Live.OrgHook, :auth_only}
  alias Tiago.Organizations
  alias Tiago.Organizations.Organization

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "New Organization",
       form: to_form(Organization.changeset(%Organization{}, %{}))
     )}
  end

  def handle_event("save", %{"organization" => params}, socket) do
    user = socket.assigns.current_user

    case Organizations.create_organization(params, user.id) do
      {:ok, org} ->
        {:noreply,
         socket
         |> put_flash(:info, "Organization '#{org.name}' created! You are the admin.")
         |> push_navigate(to: ~p"/organizations")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-lg mx-auto px-4 py-12">
      <.link
        navigate={~p"/organizations"}
        class="text-sm text-gray-500 hover:text-gray-700 mb-4 block"
      >
        ← Back
      </.link>
      <h1 class="text-2xl font-bold mb-6">Create Organization</h1>
      <.form for={@form} phx-submit="save" class="space-y-4">
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Organization Name</label>
          <.input field={@form[:name]} type="text" placeholder="e.g. M/s Gupta Traders" required />
        </div>
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">GSTN (optional)</label>
          <.input field={@form[:gstn]} type="text" placeholder="e.g. 04AAAAA0000A1Z5" />
        </div>
        <button
          type="submit"
          class="w-full bg-blue-600 text-white rounded-lg py-2.5 font-medium hover:bg-blue-700"
        >
          Create
        </button>
      </.form>
    </div>
    """
  end
end
