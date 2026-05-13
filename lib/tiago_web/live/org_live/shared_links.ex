defmodule TiagoWeb.OrgLive.SharedLinks do
  use TiagoWeb, :live_view
  on_mount {TiagoWeb.Live.OrgHook, :default}
  alias Tiago.{Sharing, Parties}

  def mount(_params, _session, socket) do
    org_id = socket.assigns.current_org.id
    links = Sharing.list_links_for_org(org_id)
    parties = Parties.list_parties(org_id)
    {:ok, assign(socket, page_title: "Shared Links", links: links, parties: parties, selected_party: "")}
  end

  def handle_event("create_link", %{"party_id" => pid, "label" => label}, socket) do
    user = socket.assigns.current_user
    org_id = socket.assigns.current_org.id
    {:ok, _} = Sharing.create_shared_link(%{party_id: String.to_integer(pid), organization_id: org_id, created_by_id: user.id, label: label})
    {:noreply, socket |> put_flash(:info, "Link created!") |> assign(links: Sharing.list_links_for_org(org_id))}
  end

  def handle_event("deactivate", %{"id" => id}, socket) do
    {:ok, _} = Sharing.deactivate_link(String.to_integer(id))
    {:noreply, socket |> put_flash(:info, "Link deactivated") |> assign(links: Sharing.list_links_for_org(socket.assigns.current_org.id))}
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4 py-8">
      <h1 class="text-2xl font-bold mb-6">Shared Ledger Links</h1>
      <div class="bg-white shadow rounded-lg p-6 mb-6">
        <h2 class="text-lg font-semibold mb-4">Create New Link</h2>
        <form phx-submit="create_link" class="flex gap-2 items-end">
          <div class="flex-1">
            <label class="block text-xs text-gray-500 mb-1">Party</label>
            <select name="party_id" required class="w-full rounded-lg border-gray-300 text-sm">
              <option value="">-- Select --</option>
              <%= for p <- @parties do %><option value={p.id}><%= p.name %> (<%= p.type %>)</option><% end %>
            </select>
          </div>
          <div class="flex-1"><label class="block text-xs text-gray-500 mb-1">Label</label>
            <input type="text" name="label" placeholder="e.g. Shared with ABC Ltd" class="w-full rounded-lg border-gray-300 text-sm" /></div>
          <button type="submit" class="bg-blue-600 text-white rounded-lg px-4 py-2 text-sm font-medium">Create</button>
        </form>
      </div>
      <div class="bg-white shadow rounded-lg overflow-hidden">
        <%= if @links == [] do %>
          <div class="px-6 py-8 text-center text-gray-500">No shared links yet.</div>
        <% else %>
          <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gray-50"><tr>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Party</th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Label</th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Link</th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Status</th>
              <th class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase">Actions</th>
            </tr></thead>
            <tbody class="divide-y divide-gray-200">
              <%= for l <- @links do %>
                <tr>
                  <td class="px-4 py-3 text-sm"><%= l.party.name %></td>
                  <td class="px-4 py-3 text-sm text-gray-500"><%= l.label || "—" %></td>
                  <td class="px-4 py-3 text-sm"><code class="text-xs bg-gray-100 px-2 py-1 rounded">/shared/<%= l.token %></code></td>
                  <td class="px-4 py-3 text-sm">
                    <span class={"px-2 py-1 text-xs rounded-full #{if l.active, do: "bg-green-100 text-green-800", else: "bg-red-100 text-red-800"}"}><%= if l.active, do: "Active", else: "Inactive" %></span>
                  </td>
                  <td class="px-4 py-3 text-sm text-right">
                    <%= if l.active do %>
                      <button phx-click="deactivate" phx-value-id={l.id} class="text-red-600 text-sm hover:underline">Deactivate</button>
                    <% end %>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        <% end %>
      </div>
    </div>
    """
  end
end
