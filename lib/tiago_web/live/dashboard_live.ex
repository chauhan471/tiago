defmodule TiagoWeb.DashboardLive do
  use TiagoWeb, :live_view
  on_mount {TiagoWeb.Live.OrgHook, :default}

  alias Tiago.{Parties, Accounting}
  import TiagoWeb.Helpers

  def mount(_params, _session, socket) do
    org_id = socket.assigns.current_org.id
    parties = Parties.list_parties(org_id)
    customers = Enum.count(parties, &(&1.type in [:customer, :both_customer_and_supplier]))
    suppliers = Enum.count(parties, &(&1.type in [:supplier, :both_customer_and_supplier]))
    journals = Accounting.list_journals(org_id) |> Enum.take(10)

    {:ok,
     socket
     |> assign(page_title: "Dashboard", total_customers: customers,
               total_suppliers: suppliers, total_parties: length(parties),
               recent_journals: journals)}
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <h1 class="text-3xl font-bold text-gray-900 mb-8"><%= @current_org.name %> — Dashboard</h1>

      <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-10">
        <.link navigate={~p"/parties?type=customer"} class="bg-white shadow rounded-lg p-6 hover:shadow-md transition">
          <p class="text-sm font-medium text-gray-600">Customers</p>
          <p class="text-3xl font-bold mt-1"><%= @total_customers %></p>
        </.link>
        <.link navigate={~p"/parties?type=supplier"} class="bg-white shadow rounded-lg p-6 hover:shadow-md transition">
          <p class="text-sm font-medium text-gray-600">Suppliers</p>
          <p class="text-3xl font-bold mt-1"><%= @total_suppliers %></p>
        </.link>
        <.link navigate={~p"/parties"} class="bg-white shadow rounded-lg p-6 hover:shadow-md transition">
          <p class="text-sm font-medium text-gray-600">Total Parties</p>
          <p class="text-3xl font-bold mt-1"><%= @total_parties %></p>
        </.link>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-10">
        <.link navigate={~p"/parties/new"} class="flex items-center justify-center gap-2 bg-blue-600 text-white rounded-lg px-6 py-3 font-medium hover:bg-blue-700 transition">+ Add Party</.link>
        <.link navigate={~p"/uploads"} class="flex items-center justify-center gap-2 bg-green-600 text-white rounded-lg px-6 py-3 font-medium hover:bg-green-700 transition">📤 Upload Files</.link>
        <.link navigate={~p"/parties"} class="flex items-center justify-center gap-2 bg-purple-600 text-white rounded-lg px-6 py-3 font-medium hover:bg-purple-700 transition">📒 View Ledgers</.link>
      </div>

      <div class="bg-white shadow rounded-lg overflow-hidden">
        <div class="px-6 py-4 border-b"><h2 class="text-lg font-semibold">Recent Journals</h2></div>
        <%= if @recent_journals == [] do %>
          <div class="px-6 py-12 text-center text-gray-500">No journals yet. Upload files to get started.</div>
        <% else %>
          <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gray-50">
              <tr>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Date</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Description</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Type</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Party</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-gray-200">
              <%= for j <- @recent_journals do %>
                <tr class="hover:bg-gray-50">
                  <% entry = List.first(j.entries) || %{} %>
                  <td class="px-6 py-4 text-sm"><%= fmt_date(j.date) %></td>
                  <td class="px-6 py-4 text-sm"><%= Map.get(entry, :description, "—") %></td>
                  <td class="px-6 py-4 text-sm"><span class="px-2 py-1 text-xs rounded-full bg-gray-100"><%= Map.get(entry, :transaction_type, "—") %></span></td>
                  <td class="px-6 py-4 text-sm text-gray-500"><%= if j.party, do: j.party.name, else: "—" %></td>
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
