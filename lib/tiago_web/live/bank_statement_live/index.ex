defmodule TiagoWeb.BankStatementLive.Index do
  use TiagoWeb, :live_view
  on_mount {TiagoWeb.Live.OrgHook, :default}

  alias Tiago.Import.BankStatements
  alias Tiago.{Accounting, Parties}
  import TiagoWeb.Helpers

  def mount(_params, _session, socket) do
    org_id = socket.assigns.current_org.id
    bank_accounts = Accounting.list_bank_accounts(org_id)
    parties = Parties.list_parties(org_id)
    all_accounts = Accounting.list_accounts(org_id)

    selected_account_id = if length(bank_accounts) > 0, do: hd(bank_accounts).id, else: nil

    socket =
      socket
      |> assign(
        page_title: "Bank Statements",
        bank_accounts: bank_accounts,
        parties: parties,
        all_accounts: all_accounts,
        selected_account_id: selected_account_id,
        status_filter: "unprocessed",
        statements: fetch_statements(selected_account_id, "unprocessed"),
        selected_statement_ids: MapSet.new(),
        bank_format: "sbi_xls"
      )
      |> allow_upload(:statement_file,
        accept: ~w(.csv .xls .xlsx .txt),
        max_entries: 1,
        max_file_size: 50_000_000
      )

    {:ok, socket}
  end

  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("select_account", %{"account_id" => id}, socket) do
    id = if id == "", do: nil, else: String.to_integer(id)
    statements = fetch_statements(id, socket.assigns.status_filter)
    {:noreply, assign(socket, selected_account_id: id, statements: statements, selected_statement_ids: MapSet.new())}
  end
  
  def handle_event("select_status", %{"status" => status}, socket) do
    statements = fetch_statements(socket.assigns.selected_account_id, status)
    {:noreply, assign(socket, status_filter: status, statements: statements, selected_statement_ids: MapSet.new())}
  end

  def handle_event("select_format", %{"format" => format}, socket) do
    {:noreply, assign(socket, bank_format: format)}
  end

  def handle_event("upload", _params, socket) do
    org_id = socket.assigns.current_org.id
    account_id = socket.assigns.selected_account_id
    format = socket.assigns.bank_format

    if account_id do
      result =
        consume_uploaded_entries(socket, :statement_file, fn %{path: path}, entry ->
          ext = Path.extname(entry.client_name)
          safe_tmp = Path.join(System.tmp_dir!(), "tiago_import_#{:erlang.unique_integer([:positive])}#{ext}")
          File.cp!(path, safe_tmp)
          {:ok, safe_tmp}
        end)

      case result do
        [tmp_path] ->
          case BankStatements.process_file(account_id, org_id, tmp_path, format) do
            {:ok, %{rows_inserted: count}} ->
              File.rm(tmp_path)
              statements = fetch_statements(account_id, socket.assigns.status_filter)
              
              {:noreply,
               socket
               |> assign(statements: statements)
               |> put_flash(:info, "Successfully imported #{count} rows.")}
               
            {:error, reason} ->
              File.rm(tmp_path)
              {:noreply, put_flash(socket, :error, "Failed to import: #{inspect(reason)}")}
          end

        _ ->
          {:noreply, put_flash(socket, :error, "No file uploaded.")}
      end
    else
      {:noreply, put_flash(socket, :error, "Please select a bank account first.")}
    end
  end
  
  def handle_event("update_mapping", %{"statement_id" => sid, "mapping_json" => mapping_json}, socket) do
    statement = Enum.find(socket.assigns.statements, &(to_string(&1.id) == sid))
    
    mapping = if mapping_json == "", do: %{}, else: Jason.decode!(mapping_json)
    party_id = Map.get(mapping, "party_id")
    counter_account_id = Map.get(mapping, "account_id")
    
    if statement do
      {:ok, updated} = BankStatements.update_statement(statement, %{party_id: party_id, counter_account_id: counter_account_id})
      
      updated_statements = Enum.map(socket.assigns.statements, fn s ->
        if s.id == updated.id, do: updated, else: s
      end)
      
      {:noreply, assign(socket, statements: updated_statements)}
    else
      {:noreply, socket}
    end
  end
  
  def handle_event("process_statement", %{"id" => id}, socket) do
    org_id = socket.assigns.current_org.id
    statement = Enum.find(socket.assigns.statements, &(to_string(&1.id) == id))
    
    case BankStatements.process_statement_to_ledger(statement.id, org_id) do
      {:ok, _} ->
        statements = fetch_statements(socket.assigns.selected_account_id, socket.assigns.status_filter)
        {:noreply, assign(socket, statements: statements) |> put_flash(:info, "Processed!")}
        
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
    end
  end

  def handle_event("delete_statement", %{"id" => id}, socket) do
    statement = Enum.find(socket.assigns.statements, &(to_string(&1.id) == id))
    
    if statement do
      {:ok, _} = BankStatements.delete_statement(statement)
      statements = fetch_statements(socket.assigns.selected_account_id, socket.assigns.status_filter)
      {:noreply, assign(socket, statements: statements, selected_statement_ids: MapSet.delete(socket.assigns.selected_statement_ids, statement.id)) |> put_flash(:info, "Statement deleted.")}
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle_selection", %{"id" => id}, socket) do
    id = String.to_integer(id)
    selected = socket.assigns.selected_statement_ids
    selected = if MapSet.member?(selected, id), do: MapSet.delete(selected, id), else: MapSet.put(selected, id)
    {:noreply, assign(socket, selected_statement_ids: selected)}
  end

  def handle_event("toggle_all", _, socket) do
    # Only select unprocessed visible statements
    visible_unprocessed_ids = 
      socket.assigns.statements
      |> Enum.reject(& &1.is_processed)
      |> Enum.map(& &1.id)
      |> MapSet.new()

    selected = socket.assigns.selected_statement_ids

    # If all visible unprocessed are selected, deselect all visible. Otherwise, select all visible unprocessed.
    all_selected? = MapSet.size(visible_unprocessed_ids) > 0 and MapSet.subset?(visible_unprocessed_ids, selected)
    
    new_selected =
      if all_selected? do
        MapSet.difference(selected, visible_unprocessed_ids)
      else
        MapSet.union(selected, visible_unprocessed_ids)
      end

    {:noreply, assign(socket, selected_statement_ids: new_selected)}
  end

  def handle_event("delete_selected", _, socket) do
    ids = MapSet.to_list(socket.assigns.selected_statement_ids)
    if length(ids) > 0 do
      {count, _} = BankStatements.delete_statements(ids)
      statements = fetch_statements(socket.assigns.selected_account_id, socket.assigns.status_filter)
      {:noreply, assign(socket, statements: statements, selected_statement_ids: MapSet.new()) |> put_flash(:info, "Deleted #{count} statements.")}
    else
      {:noreply, socket}
    end
  end

  defp fetch_statements(nil, _), do: []
  defp fetch_statements(account_id, status) do
    BankStatements.list_statements(account_id, status: status)
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <h1 class="text-3xl font-bold mb-2">Bank Statements</h1>
      <p class="text-gray-600 mb-8">Upload and process your bank statements.</p>

      <div class="bg-white shadow rounded-lg p-6 mb-8 border-t-4 border-blue-600">
        <h2 class="text-lg font-semibold mb-4">Upload Statement</h2>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Select Bank Account</label>
            <select
              phx-change="select_account"
              name="account_id"
              class="rounded-lg border-gray-300 text-sm w-full mb-4"
            >
              <option value="">-- Select Bank Account --</option>
              <%= for ba <- @bank_accounts do %>
                <option value={ba.id} selected={@selected_account_id == ba.id}>
                  <%= ba.name %> <%= if ba.is_default, do: "(default)" %>
                </option>
              <% end %>
            </select>
            
            <label class="block text-sm font-medium text-gray-700 mb-1">File Format</label>
            <select
              phx-change="select_format"
              name="format"
              class="rounded-lg border-gray-300 text-sm w-full"
            >
              <option value="sbi_xls" selected={@bank_format == "sbi_xls"}>SBI Bank (.xls tab-separated)</option>
              <option value="generic_csv" selected={@bank_format == "generic_csv"}>Generic CSV</option>
            </select>
          </div>
          
          <div>
            <form id="upload-form" phx-submit="upload" phx-change="validate">
              <div class="border-2 border-dashed border-gray-300 rounded-lg p-4 text-center hover:border-gray-400 h-full flex flex-col justify-center">
                <.live_file_input upload={@uploads.statement_file} class="mb-4" />
                <%= for entry <- @uploads.statement_file.entries do %>
                  <div class="mt-2 text-sm text-green-700 font-medium">
                    <%= entry.client_name %> (<%= div(entry.client_size, 1024) %> KB)
                  </div>
                <% end %>
                <button
                  type="submit"
                  class="mt-4 bg-blue-600 text-white rounded-lg px-6 py-2 font-medium disabled:opacity-50"
                  disabled={@uploads.statement_file.entries == [] or is_nil(@selected_account_id)}
                >
                  Upload & Parse
                </button>
              </div>
            </form>
          </div>
        </div>
      </div>
      
      <%= if @selected_account_id do %>
        <div class="bg-white shadow rounded-lg overflow-hidden">
          <div class="p-4 bg-gray-50 border-b flex items-center justify-between">
            <h3 class="font-semibold text-gray-700">Transactions</h3>
            <div class="flex gap-2">
              <button phx-click="select_status" phx-value-status="all" class={"px-3 py-1 text-sm rounded-full #{if @status_filter == "all", do: "bg-gray-800 text-white", else: "bg-gray-200 text-gray-700"}"}>All</button>
              <button phx-click="select_status" phx-value-status="unprocessed" class={"px-3 py-1 text-sm rounded-full #{if @status_filter == "unprocessed", do: "bg-blue-600 text-white", else: "bg-blue-50 text-blue-700"}"}>Unprocessed</button>
              <button phx-click="select_status" phx-value-status="processed" class={"px-3 py-1 text-sm rounded-full #{if @status_filter == "processed", do: "bg-green-600 text-white", else: "bg-green-50 text-green-700"}"}>Processed</button>
            </div>
          </div>
          
          <%= if @statements == [] do %>
            <div class="px-6 py-12 text-center text-gray-500">No transactions found.</div>
          <% else %>
            <div class="mt-4 flex items-center justify-between mb-4 px-4">
              <div class="flex items-center gap-2 text-sm text-gray-500">
                <span><%= length(Enum.filter(@statements, &(&1.is_processed))) %> processed</span>
                <span>&middot;</span>
                <span><%= length(Enum.reject(@statements, &(&1.is_processed))) %> unprocessed</span>
              </div>
              <%= if MapSet.size(@selected_statement_ids) > 0 do %>
                <button
                  phx-click="delete_selected"
                  data-confirm="Are you sure you want to delete the selected statements?"
                  class="bg-red-600 text-white text-sm px-3 py-1.5 rounded-md font-medium hover:bg-red-700 shadow-sm transition"
                >
                  Delete Selected (<%= MapSet.size(@selected_statement_ids) %>)
                </button>
              <% end %>
            </div>
            
            <div class="overflow-x-auto">
              <table class="min-w-full divide-y divide-gray-200">
                <thead class="bg-gray-50">
                  <tr>
                    <th scope="col" class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider w-8">
                      <input
                        type="checkbox"
                        class="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                        phx-click="toggle_all"
                        checked={
                          unprocessed_ids = Enum.reject(@statements, &(&1.is_processed)) |> Enum.map(&(&1.id)) |> MapSet.new()
                          MapSet.size(unprocessed_ids) > 0 and MapSet.subset?(unprocessed_ids, @selected_statement_ids)
                        }
                      />
                    </th>
                    <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Date</th>
                    <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Description & Ref</th>
                    <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Amount</th>
                    <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Counterparty</th>
                    <th class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase">Action</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-gray-200">
                  <%= for s <- @statements do %>
                    <tr class={"hover:bg-gray-50 #{if s.is_processed, do: "bg-gray-50 opacity-75"}"}>
                      <td class="px-4 py-3 text-left whitespace-nowrap">
                        <%= if not s.is_processed do %>
                          <input
                            type="checkbox"
                            class="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                            phx-click="toggle_selection"
                            phx-value-id={s.id}
                            checked={MapSet.member?(@selected_statement_ids, s.id)}
                          />
                        <% end %>
                      </td>
                      <td class="px-4 py-3 text-sm whitespace-nowrap"><%= if s.date, do: fmt_date(s.date), else: "—" %></td>
                      <td class="px-4 py-3">
                        <div class="text-sm font-medium text-gray-900 break-words max-w-md"><%= s.description || "—" %></div>
                        <div class="text-xs text-gray-500 break-words max-w-md"><%= s.payment_reference %></div>
                      </td>
                      <td class="px-4 py-3 text-right">
                        <%= if s.debit do %><div class="text-sm font-mono text-red-600 font-medium"><%= fmt_money(s.debit) %></div><% end %>
                        <%= if s.credit do %><div class="text-sm font-mono text-green-600 font-medium"><%= fmt_money(s.credit) %></div><% end %>
                      </td>
                      <td class="px-4 py-3 text-sm min-w-[200px]">
                        <%= if s.is_processed do %>
                          <% p = Enum.find(@parties, & &1.id == s.party_id) %>
                          <% a = Enum.find(@all_accounts, & &1.id == s.counter_account_id) %>
                          <span class="font-medium text-gray-700">
                            <%= if p, do: p.name, else: (if a, do: a.name, else: "—") %>
                          </span>
                        <% else %>
                          <form phx-change="update_mapping" class="m-0">
                            <input type="hidden" name="statement_id" value={s.id} />
                            <select
                              name="mapping_json"
                              class={"rounded-lg text-sm w-full p-2 #{if s.party_id || s.counter_account_id, do: "border-green-300 bg-green-50", else: "border-red-300 bg-red-50"}"}
                            >
                              <option value="">-- Match To --</option>
                              <optgroup label="Parties (Customers/Suppliers)">
                                <%= for p <- @parties do %>
                                  <option value={Jason.encode!(%{party_id: p.id})} selected={s.party_id == p.id}><%= p.name %></option>
                                <% end %>
                              </optgroup>
                              <optgroup label="Internal Accounts">
                                <%= for a <- Enum.reject(@all_accounts, &(&1.id == @selected_account_id)) do %>
                                  <option value={Jason.encode!(%{account_id: a.id})} selected={s.counter_account_id == a.id}><%= a.name %></option>
                                <% end %>
                              </optgroup>
                            </select>
                          </form>
                        <% end %>
                      </td>
                      <td class="px-4 py-3 text-right whitespace-nowrap">
                        <%= if s.is_processed do %>
                          <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
                            Processed
                          </span>
                        <% else %>
                          <div class="flex items-center justify-end gap-2">
                            <button
                              phx-click="process_statement"
                              phx-value-id={s.id}
                              disabled={(is_nil(s.party_id) and is_nil(s.counter_account_id)) or is_nil(s.date)}
                              title={if is_nil(s.date), do: "Cannot process: Date is missing (re-upload to fix).", else: (if is_nil(s.party_id) and is_nil(s.counter_account_id), do: "Cannot process: Please match to a counterparty.", else: "Process transaction")}
                              class="bg-blue-600 text-white text-xs px-3 py-1.5 rounded font-medium disabled:bg-gray-300 disabled:cursor-not-allowed hover:bg-blue-700"
                            >
                              Process
                            </button>
                            <button
                              phx-click="delete_statement"
                              phx-value-id={s.id}
                              class="text-red-600 hover:text-red-800 p-1"
                              title="Delete statement row"
                            >
                              <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                              </svg>
                            </button>
                          </div>
                        <% end %>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
