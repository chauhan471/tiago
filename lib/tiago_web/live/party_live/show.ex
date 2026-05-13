defmodule TiagoWeb.PartyLive.Show do
  use TiagoWeb, :live_view
  on_mount {TiagoWeb.Live.OrgHook, :default}
  alias Tiago.Parties

  def mount(%{"id" => id}, _session, socket) do
    party = Parties.get_party!(id)
    {:ok, assign(socket, page_title: party.name, party: party)}
  end

  def handle_event("add_gstn", %{"gstn" => gstn}, socket) do
    case Parties.add_gstn_to_party(socket.assigns.party.id, String.trim(gstn)) do
      {:ok, _} ->
        party = Parties.get_party!(socket.assigns.party.id)
        {:noreply, socket |> assign(party: party) |> put_flash(:info, "GSTN added")}
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
            <span class={"mt-1 px-3 py-1 text-sm rounded-full font-medium #{if @party.type == :customer, do: "bg-blue-100 text-blue-800", else: "bg-green-100 text-green-800"}"}><%= @party.type %></span>
          </div>
          <.link navigate={~p"/parties/#{@party.id}/ledger"} class="bg-green-600 text-white rounded-lg px-4 py-2 font-medium hover:bg-green-700">View Ledger →</.link>
        </div>
      </div>
      <div class="bg-white shadow rounded-lg p-6">
        <h2 class="text-lg font-semibold mb-4">GSTN Numbers</h2>
        <%= for g <- @party.party_gstns do %>
          <div class="bg-gray-50 rounded-lg px-4 py-3 mb-2 flex justify-between">
            <span class="font-mono text-sm font-medium"><%= g.gstn %></span>
            <span class="text-xs text-gray-500"><%= g.state_name %></span>
          </div>
        <% end %>
        <%= if @party.party_gstns == [] do %><p class="text-gray-500 mb-4">No GSTNs yet.</p><% end %>
        <form phx-submit="add_gstn" class="flex gap-2 mt-4">
          <input type="text" name="gstn" placeholder="e.g. 04AAAAA0000A1Z5" class="flex-1 rounded-lg border-gray-300 text-sm font-mono" required />
          <button type="submit" class="bg-blue-600 text-white rounded-lg px-4 py-2 text-sm font-medium hover:bg-blue-700">Add GSTN</button>
        </form>
      </div>
    </div>
    """
  end
end
