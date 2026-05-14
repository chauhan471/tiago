defmodule TiagoWeb.PartyLive.Show do
  use TiagoWeb, :live_view
  on_mount {TiagoWeb.Live.OrgHook, :default}
  alias Tiago.Parties
  import TiagoWeb.Helpers

  def mount(%{"id" => id}, _session, socket) do
    party = Parties.get_party!(id)
    {:ok, assign(socket, page_title: party.name, party: party, editing_gstn: nil)}
  end

  def handle_event("edit_gstn", %{"id" => id}, socket) do
    gstn = Parties.get_party_gstn!(id)
    {:noreply, assign(socket, editing_gstn: gstn)}
  end

  def handle_event("cancel_edit", _, socket) do
    {:noreply, assign(socket, editing_gstn: nil)}
  end

  def handle_event("delete_gstn", %{"id" => id}, socket) do
    gstn = Parties.get_party_gstn!(id)
    {:ok, _} = Parties.delete_party_gstn(gstn)
    party = Parties.get_party!(socket.assigns.party.id)
    {:noreply, socket |> assign(party: party) |> put_flash(:info, "GSTN deleted")}
  end

  def handle_event("save_gstn", %{"gstn" => gstn_val}, socket) do
    gstn_val = String.trim(gstn_val)
    
    result = if socket.assigns.editing_gstn do
      Parties.update_party_gstn(socket.assigns.editing_gstn, %{gstn: gstn_val})
    else
      Parties.add_gstn_to_party(socket.assigns.party.id, gstn_val)
    end
    
    case result do
      {:ok, _} ->
        party = Parties.get_party!(socket.assigns.party.id)
        msg = if socket.assigns.editing_gstn, do: "GSTN updated", else: "GSTN added"
        {:noreply, socket |> assign(party: party, editing_gstn: nil) |> put_flash(:info, msg)}
      {:error, cs} ->
        msg = cs.errors |> Enum.map(fn {f, {m, _}} -> "#{f}: #{m}" end) |> Enum.join(", ")
        {:noreply, put_flash(socket, :error, msg)}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4 py-8">
      <.link navigate={~p"/parties"} class="text-sm text-gray-500 hover:text-gray-700 mb-6 block">← Back</.link>
      <div class="bg-white shadow rounded-lg p-6 mb-6">
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-bold"><%= @party.name %></h1>
            <span class={"mt-1 px-3 py-1 text-sm rounded-full font-medium #{party_type_badge_class(@party.type)}"}><%= party_type_label(@party.type) %></span>
          </div>
          <.link navigate={~p"/parties/#{@party.id}/ledger"} class="bg-green-600 text-white rounded-lg px-4 py-2 font-medium hover:bg-green-700">View Ledger →</.link>
        </div>
      </div>
      <div class="bg-white shadow rounded-lg p-6">
        <h2 class="text-lg font-semibold mb-4">GSTN Numbers</h2>
        <%= for g <- @party.party_gstns do %>
          <div class={"bg-gray-50 rounded-lg px-4 py-3 mb-2 flex justify-between items-center #{if @editing_gstn && @editing_gstn.id == g.id, do: "ring-2 ring-blue-400"}"}>
            <div>
              <span class="font-mono text-sm font-medium"><%= g.gstn %></span>
              <span class="text-xs text-gray-500 ml-2"><%= g.state_name %></span>
            </div>
            <div class="space-x-3">
              <button phx-click="edit_gstn" phx-value-id={g.id} class="text-xs font-medium text-blue-600 hover:text-blue-800">Edit</button>
              <button phx-click="delete_gstn" phx-value-id={g.id} data-confirm="Delete this GSTN?" class="text-xs font-medium text-red-600 hover:text-red-800">Delete</button>
            </div>
          </div>
        <% end %>
        <%= if @party.party_gstns == [] do %><p class="text-gray-500 mb-4">No GSTNs yet.</p><% end %>
        <form phx-submit="save_gstn" class="flex gap-2 mt-4 items-center">
          <input type="text" name="gstn" value={if @editing_gstn, do: @editing_gstn.gstn, else: ""} placeholder="e.g. 04AAAAA0000A1Z5" class="flex-1 rounded-lg border-gray-300 text-sm font-mono" required />
          <button type="submit" class="bg-blue-600 text-white rounded-lg px-4 py-2 text-sm font-medium hover:bg-blue-700">
            <%= if @editing_gstn, do: "Save Changes", else: "Add GSTN" %>
          </button>
          <%= if @editing_gstn do %>
            <button type="button" phx-click="cancel_edit" class="bg-gray-200 text-gray-700 rounded-lg px-4 py-2 text-sm font-medium">Cancel</button>
          <% end %>
        </form>
      </div>
    </div>
    """
  end
end
