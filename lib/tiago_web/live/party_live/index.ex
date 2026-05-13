defmodule TiagoWeb.PartyLive.Index do
  use TiagoWeb, :live_view
  on_mount {TiagoWeb.Live.OrgHook, :default}
  alias Tiago.Parties
  alias Tiago.Parties.Party

  def mount(params, _session, socket) do
    org_id = socket.assigns.current_org.id
    type_filter = Map.get(params, "type")
    filters = if type_filter in ["customer", "supplier"], do: [type: String.to_atom(type_filter)], else: []
    {:ok, assign(socket, page_title: "Parties", type_filter: type_filter, parties: Parties.list_parties(org_id, filters), show_form: false, form: to_form(Party.changeset(%Party{}, %{})))}
  end

  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _), do: assign(socket, show_form: true, form: to_form(Party.changeset(%Party{}, %{})))
  defp apply_action(socket, :index, params) do
    org_id = socket.assigns.current_org.id
    tf = Map.get(params, "type")
    filters = if tf in ["customer", "supplier"], do: [type: String.to_atom(tf)], else: []
    assign(socket, show_form: false, type_filter: tf, parties: Parties.list_parties(org_id, filters))
  end

  def handle_event("save_party", %{"party" => params}, socket) do
    case Parties.create_party(socket.assigns.current_org.id, params) do
      {:ok, _} -> {:noreply, socket |> put_flash(:info, "Party created!") |> push_navigate(to: ~p"/parties")}
      {:error, cs} -> {:noreply, assign(socket, form: to_form(cs))}
    end
  end

  def handle_event("delete_party", %{"id" => id}, socket) do
    party = Parties.get_party!(id)
    {:ok, _} = Parties.delete_party(party)
    {:noreply, socket |> put_flash(:info, "Deleted") |> assign(parties: Parties.list_parties(socket.assigns.current_org.id))}
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <div class="flex items-center justify-between mb-6">
        <h1 class="text-3xl font-bold">Parties</h1>
        <.link navigate={~p"/parties/new"} class="bg-blue-600 text-white rounded-lg px-4 py-2 font-medium hover:bg-blue-700">+ Add Party</.link>
      </div>
      <div class="flex gap-2 mb-6">
        <.link patch={~p"/parties"} class={"px-4 py-2 rounded-lg text-sm font-medium #{if @type_filter == nil, do: "bg-gray-900 text-white", else: "bg-gray-100 text-gray-700"}"}>All</.link>
        <.link patch={~p"/parties?type=customer"} class={"px-4 py-2 rounded-lg text-sm font-medium #{if @type_filter == "customer", do: "bg-blue-600 text-white", else: "bg-blue-50 text-blue-700"}"}>Customers</.link>
        <.link patch={~p"/parties?type=supplier"} class={"px-4 py-2 rounded-lg text-sm font-medium #{if @type_filter == "supplier", do: "bg-green-600 text-white", else: "bg-green-50 text-green-700"}"}>Suppliers</.link>
      </div>
      <%= if @show_form do %>
        <div class="bg-white shadow rounded-lg p-6 mb-6 border-2 border-blue-200">
          <h2 class="text-lg font-semibold mb-4">Add New Party</h2>
          <.form for={@form} phx-submit="save_party" class="space-y-4">
            <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
              <div><label class="block text-sm font-medium text-gray-700 mb-1">Name</label><.input field={@form[:name]} type="text" required /></div>
              <div><label class="block text-sm font-medium text-gray-700 mb-1">Type</label><.input field={@form[:type]} type="select" options={[{"Customer", :customer}, {"Supplier", :supplier}]} required /></div>
              <div><label class="block text-sm font-medium text-gray-700 mb-1">Notes</label><.input field={@form[:notes]} type="text" /></div>
            </div>
            <div class="flex gap-2">
              <button type="submit" class="bg-blue-600 text-white rounded-lg px-4 py-2 font-medium hover:bg-blue-700">Save</button>
              <.link navigate={~p"/parties"} class="bg-gray-200 text-gray-700 rounded-lg px-4 py-2 font-medium">Cancel</.link>
            </div>
          </.form>
        </div>
      <% end %>
      <div class="bg-white shadow rounded-lg overflow-hidden">
        <%= if @parties == [] do %>
          <div class="px-6 py-12 text-center text-gray-500">No parties found.</div>
        <% else %>
          <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gray-50">
              <tr>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Name</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Type</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">GSTN(s)</th>
                <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">Actions</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-gray-200">
              <%= for party <- @parties do %>
                <tr class="hover:bg-gray-50">
                  <td class="px-6 py-4 text-sm font-medium"><.link navigate={~p"/parties/#{party.id}"} class="text-blue-600 hover:text-blue-800"><%= party.name %></.link></td>
                  <td class="px-6 py-4 text-sm"><span class={"px-2 py-1 text-xs rounded-full font-medium #{if party.type == :customer, do: "bg-blue-100 text-blue-800", else: "bg-green-100 text-green-800"}"}><%= party.type %></span></td>
                  <td class="px-6 py-4 text-sm text-gray-500">
                    <%= for g <- party.party_gstns do %><span class="inline-block bg-gray-100 text-xs px-2 py-1 rounded mr-1 font-mono"><%= g.gstn %></span><% end %>
                    <%= if party.party_gstns == [], do: "—" %>
                  </td>
                  <td class="px-6 py-4 text-sm text-right space-x-2">
                    <.link navigate={~p"/parties/#{party.id}/ledger"} class="text-green-600 hover:text-green-800 font-medium">Ledger</.link>
                    <%= if @current_role == :admin do %>
                      <button phx-click="delete_party" phx-value-id={party.id} data-confirm="Delete?" class="text-red-600 hover:text-red-800 font-medium">Delete</button>
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
