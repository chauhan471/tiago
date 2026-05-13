defmodule TiagoWeb.OrgLive.Index do
  use TiagoWeb, :live_view
  on_mount {TiagoWeb.Live.OrgHook, :auth_only}
  alias Tiago.Organizations

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    orgs = Organizations.list_user_organizations(user.id)
    {:ok, assign(socket, page_title: "Organizations", orgs: orgs)}
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto px-4 py-12">
      <h1 class="text-3xl font-bold text-gray-900 mb-2">Your Organizations</h1>
      <p class="text-gray-600 mb-8">Select an organization to work with, or create a new one.</p>

      <%= if @orgs == [] do %>
        <div class="bg-gray-50 rounded-lg p-8 text-center mb-6">
          <p class="text-gray-500 mb-4">You don't belong to any organization yet.</p>
        </div>
      <% else %>
        <div class="space-y-3 mb-6">
          <%= for %{organization: org, role: role} <- @orgs do %>
            <form action={~p"/organizations/select"} method="post" class="block">
              <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
              <input type="hidden" name="org_id" value={org.id} />
              <button type="submit" class="w-full text-left bg-white shadow rounded-lg p-5 hover:shadow-md transition flex justify-between items-center">
                <div>
                  <p class="font-semibold text-gray-900"><%= org.name %></p>
                  <%= if org.gstn do %>
                    <p class="text-sm text-gray-500 font-mono mt-1"><%= org.gstn %></p>
                  <% end %>
                </div>
                <span class={"px-2 py-1 text-xs rounded-full font-medium #{if role == :admin, do: "bg-purple-100 text-purple-800", else: "bg-blue-100 text-blue-800"}"}><%= role %></span>
              </button>
            </form>
          <% end %>
        </div>
      <% end %>

      <.link navigate={~p"/organizations/new"} class="inline-flex items-center gap-2 bg-blue-600 text-white rounded-lg px-5 py-2.5 font-medium hover:bg-blue-700 transition">
        + Create Organization
      </.link>
    </div>
    """
  end
end
