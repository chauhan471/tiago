defmodule TiagoWeb.UploadLive.Index do
  use TiagoWeb, :live_view
  on_mount {TiagoWeb.Live.OrgHook, :default}

  alias Tiago.Import.{GstrParser, BankStatements, Utils}
  alias Tiago.{Accounting, Parties}
  import TiagoWeb.Helpers

  def mount(_params, _session, socket) do
    org_id = socket.assigns.current_org.id
    bank_accounts = Accounting.list_bank_accounts(org_id)
    parties = Parties.list_parties(org_id)

    {:ok,
     socket
     |> assign(page_title: "Upload Files", file_type: "gstr1", result: nil,
               bank_accounts: bank_accounts, parties: parties,
               selected_bank_id: if(length(bank_accounts) == 1, do: to_string(hd(bank_accounts).id), else: ""),
               step: :upload, import: nil, headers: [], filepath: nil, column_mapping: %{
                 "date" => "", "description" => "", "reference" => "", "debit" => "", "credit" => ""
               })
     |> allow_upload(:data_file, accept: ~w(.zip .csv .json), max_entries: 1, max_file_size: 50_000_000)}
  end

  def handle_event("validate", _params, socket), do: {:noreply, socket}
  def handle_event("select_type", %{"type" => t}, socket), do: {:noreply, assign(socket, file_type: t)}
  def handle_event("select_bank", %{"bank_id" => id}, socket), do: {:noreply, assign(socket, selected_bank_id: id)}

  def handle_event("upload", _params, socket) do
    org_id = socket.assigns.current_org.id
    file_type = socket.assigns.file_type

    result =
      consume_uploaded_entries(socket, :data_file, fn %{path: path}, entry ->
        ext = Path.extname(entry.client_name)
        # We store the temp file in a stable location so it survives LiveView events during mapping
        safe_tmp = Path.join(System.tmp_dir!(), "tiago_import_#{:erlang.unique_integer([:positive])}#{ext}")
        File.cp!(path, safe_tmp)
        {:ok, {safe_tmp, entry.client_name}}
      end)

    case result do
      [{tmp_path, filename}] ->
        if file_type == "bank_statement" do
          bid = if socket.assigns.selected_bank_id == "", do: nil, else: String.to_integer(socket.assigns.selected_bank_id)
          
          # Create import record
          {:ok, import} = BankStatements.create_import(%{
            organization_id: org_id,
            bank_account_id: bid,
            filename: filename,
            status: "mapping"
          })

          case BankStatements.read_headers_and_sample(tmp_path) do
            {:ok, headers, _sample} ->
              # Try to auto-guess mapping
              mapping = guess_mapping(headers)
              {:noreply, assign(socket, step: :map_columns, import: import, headers: headers, filepath: tmp_path, column_mapping: mapping)}
            {:error, reason} ->
              {:noreply, put_flash(socket, :error, "Failed to read CSV: #{reason}")}
          end
        else
          # Process GSTR immediately
          proc = process_gstr(org_id, file_type, tmp_path)
          File.rm(tmp_path)
          {:noreply, socket |> assign(result: %{filename: filename, type: file_type, result: proc}) |> put_flash(:info, "Processed: #{filename}")}
        end
      _ ->
        {:noreply, put_flash(socket, :error, "No file")}
    end
  end

  def handle_event("update_mapping", %{"field" => field, "header" => header}, socket) do
    new_mapping = Map.put(socket.assigns.column_mapping, field, header)
    {:noreply, assign(socket, column_mapping: new_mapping)}
  end

  def handle_event("save_columns", _, socket) do
    import = socket.assigns.import
    BankStatements.process_raw_csv(import, socket.assigns.filepath, socket.assigns.column_mapping)
    import_with_rows = BankStatements.get_import_with_rows!(import.id)
    {:noreply, assign(socket, step: :map_parties, import: import_with_rows)}
  end

  def handle_event("update_party", %{"row_id" => row_id, "party_id" => party_id}, socket) do
    # Update row in DB
    row = Enum.find(socket.assigns.import.rows, &(to_string(&1.id) == row_id))
    party_id = if party_id == "", do: nil, else: String.to_integer(party_id)
    
    if row do
      {:ok, updated_row} = BankStatements.update_row(row, %{party_id: party_id})
      # Update state
      updated_rows = Enum.map(socket.assigns.import.rows, fn r -> 
        if r.id == updated_row.id, do: updated_row, else: r
      end)
      updated_import = %{socket.assigns.import | rows: updated_rows}
      {:noreply, assign(socket, import: updated_import)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("confirm_import", _, socket) do
    import_id = socket.assigns.import.id
    case BankStatements.create_journals_for_import(import_id) do
      {:ok, _} ->
        if socket.assigns.filepath, do: File.rm(socket.assigns.filepath)
        {:noreply, socket |> assign(step: :completed, result: %{filename: socket.assigns.import.filename, type: "bank_statement", result: {:ok, %{journals_created: length(socket.assigns.import.rows)}}})}
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
    end
  end

  def handle_event("cancel_import", _, socket) do
    if socket.assigns.filepath, do: File.rm(socket.assigns.filepath)
    {:noreply, assign(socket, step: :upload, import: nil, filepath: nil, headers: [], column_mapping: %{})}
  end

  # Auto-guess common headers
  defp guess_mapping(headers) do
    find = fn aliases -> 
      match = Enum.find(headers, fn h -> String.downcase(h) in aliases end)
      match || ""
    end

    %{
      "date" => find.(["date", "txn date", "transaction date", "value date"]),
      "description" => find.(["description", "narration", "particulars", "details"]),
      "reference" => find.(["ref", "ref no", "ref no./cheque no.", "cheque no", "chq no"]),
      "debit" => find.(["debit", "withdrawal", "dr"]),
      "credit" => find.(["credit", "deposit", "cr"])
    }
  end

  defp process_gstr(org_id, "gstr1", path) do
    if String.ends_with?(path, ".json") do
      json = File.read!(path) |> Jason.decode!()
      GstrParser.process_gstr1_json(org_id, json)
    else
      process_zip(path, fn json -> GstrParser.process_gstr1_json(org_id, json) end)
    end
  end

  defp process_gstr(org_id, "gstr2b", path) do
    if String.ends_with?(path, ".json") do
      json = File.read!(path) |> Jason.decode!()
      GstrParser.process_gstr2b_json(org_id, json)
    else
      process_zip(path, fn json -> GstrParser.process_gstr2b_json(org_id, json) end)
    end
  end

  defp process_zip(path, processor_fn) do
    Utils.read_zip_file(path)
    |> Enum.flat_map(fn {:ok, _, json} -> [json]; _ -> [] end)
    |> Enum.reduce({0, 0}, fn json, {ok, err} ->
      case processor_fn.(json) do
        {:ok, %{journals_created: j}} -> {ok + j, err}
        _ -> {ok, err + 1}
      end
    end)
    |> then(fn {ok, err} -> {:ok, %{journals_created: ok, errors: err}} end)
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto px-4 py-8">
      <h1 class="text-3xl font-bold mb-2">Upload Files</h1>
      <p class="text-gray-600 mb-8">Upload GSTR1, GSTR2B, or bank statement files.</p>
      
      <%= if @step == :upload do %>
        <div class="flex gap-2 mb-6">
          <%= for {label, key} <- [{"GSTR1 (Sales)", "gstr1"}, {"GSTR2B (Purchases)", "gstr2b"}, {"Bank Statement", "bank_statement"}] do %>
            <button phx-click="select_type" phx-value-type={key}
                    class={"px-4 py-2 rounded-lg text-sm font-medium transition #{if @file_type == key, do: "bg-blue-600 text-white", else: "bg-blue-50 text-blue-700"}"}><%= label %></button>
          <% end %>
        </div>
        <%= if @file_type == "bank_statement" and length(@bank_accounts) > 1 do %>
          <div class="mb-4">
            <label class="block text-sm font-medium text-gray-700 mb-1">Select Bank Account</label>
            <select phx-change="select_bank" name="bank_id" class="rounded-lg border-gray-300 text-sm">
              <option value="">-- Select Default --</option>
              <%= for ba <- @bank_accounts do %>
                <option value={ba.id} selected={to_string(ba.id) == @selected_bank_id}><%= ba.name %> <%= if ba.is_default, do: "(default)" %></option>
              <% end %>
            </select>
          </div>
        <% end %>
        <form id="upload-form" phx-submit="upload" phx-change="validate" class="mb-8">
          <div class="border-2 border-dashed border-gray-300 rounded-lg p-8 text-center hover:border-gray-400">
            <.live_file_input upload={@uploads.data_file} class="mb-4" />
            <%= for entry <- @uploads.data_file.entries do %>
              <div class="mt-4 text-sm"><span class="font-medium"><%= entry.client_name %></span> (<%= div(entry.client_size, 1024) %> KB)</div>
            <% end %>
            <button type="submit" class="mt-4 bg-blue-600 text-white rounded-lg px-6 py-2 font-medium disabled:opacity-50" disabled={@uploads.data_file.entries == []}>Upload & Process</button>
          </div>
        </form>
      <% end %>

      <%= if @step == :map_columns do %>
        <div class="bg-white shadow rounded-lg p-6">
          <div class="flex justify-between items-center mb-6">
            <h2 class="text-xl font-bold">Map CSV Columns</h2>
            <button phx-click="cancel_import" class="text-gray-500 hover:text-gray-700">Cancel</button>
          </div>
          <p class="text-sm text-gray-600 mb-6">Select which column from your CSV matches the required fields.</p>
          
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-8">
            <%= for {field, label} <- [{"date", "Transaction Date"}, {"description", "Description / Narration"}, {"reference", "Ref / Cheque No."}, {"debit", "Debit / Withdrawal"}, {"credit", "Credit / Deposit"}] do %>
              <div class="flex flex-col">
                <label class="text-sm font-medium text-gray-700 mb-1"><%= label %></label>
                <select phx-change="update_mapping" phx-value-field={field} class="rounded-lg border-gray-300 text-sm">
                  <option value="">-- Ignore --</option>
                  <%= for h <- @headers do %>
                    <option value={h} selected={@column_mapping[field] == h}><%= h %></option>
                  <% end %>
                </select>
              </div>
            <% end %>
          </div>
          <button phx-click="save_columns" class="bg-blue-600 text-white rounded-lg px-6 py-2 font-medium hover:bg-blue-700">Continue →</button>
        </div>
      <% end %>

      <%= if @step == :map_parties do %>
        <div class="bg-white shadow rounded-lg p-6">
          <div class="flex justify-between items-center mb-6">
            <h2 class="text-xl font-bold">Review & Map Parties</h2>
            <button phx-click="cancel_import" class="text-gray-500 hover:text-gray-700">Cancel</button>
          </div>
          <p class="text-sm text-gray-600 mb-6">We've auto-detected parties where possible. Please review and select parties for the remaining transactions.</p>
          
          <div class="overflow-x-auto mb-6">
            <table class="min-w-full divide-y divide-gray-200">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Date</th>
                  <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Description</th>
                  <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Ref</th>
                  <th class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase">Debit</th>
                  <th class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase">Credit</th>
                  <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Party</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-200">
                <%= for row <- @import.rows do %>
                  <tr class="hover:bg-gray-50">
                    <td class="px-4 py-3 text-sm whitespace-nowrap"><%= fmt_date(row.date) %></td>
                    <td class="px-4 py-3 text-sm"><%= row.description %></td>
                    <td class="px-4 py-3 text-sm text-gray-500"><%= row.reference %></td>
                    <td class="px-4 py-3 text-sm text-right text-red-600 font-mono"><%= if row.debit, do: fmt_money(row.debit) %></td>
                    <td class="px-4 py-3 text-sm text-right text-green-600 font-mono"><%= if row.credit, do: fmt_money(row.credit) %></td>
                    <td class="px-4 py-3 text-sm">
                      <select phx-change="update_party" phx-value-row_id={row.id} class={"rounded-lg text-sm w-full #{if row.party_id, do: "border-green-300 bg-green-50", else: "border-red-300 bg-red-50"}"}>
                        <option value="">-- Select Party --</option>
                        <%= for p <- @parties do %>
                          <option value={p.id} selected={row.party_id == p.id}><%= p.name %></option>
                        <% end %>
                      </select>
                      <%= if row.party_detected do %><span class="text-xs text-green-600 block mt-1">Auto-detected</span><% end %>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
          
          <div class="flex gap-4">
            <button phx-click="confirm_import" class="bg-green-600 text-white rounded-lg px-6 py-2 font-medium hover:bg-green-700">Confirm & Save Journals</button>
            <.link navigate={~p"/parties/new"} target="_blank" class="text-blue-600 hover:underline flex items-center text-sm font-medium">Open New Party Window ↗</.link>
          </div>
        </div>
      <% end %>

      <%= if @step == :completed do %>
        <div class="bg-white shadow rounded-lg p-6 text-center">
          <h2 class="text-2xl font-bold text-green-600 mb-2">Import Successful!</h2>
          <p class="text-gray-600 mb-6">Your bank statement was processed and journals were created.</p>
          <button phx-click="cancel_import" class="bg-blue-600 text-white rounded-lg px-6 py-2 font-medium hover:bg-blue-700">Upload Another File</button>
        </div>
      <% end %>
    </div>
    """
  end
end
