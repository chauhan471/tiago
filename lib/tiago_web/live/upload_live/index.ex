defmodule TiagoWeb.UploadLive.Index do
  use TiagoWeb, :live_view
  on_mount {TiagoWeb.Live.OrgHook, :default}

  alias Tiago.Import.{GstrParser, BankStatementParser, Utils}
  alias Tiago.Accounting

  def mount(_params, _session, socket) do
    org_id = socket.assigns.current_org.id
    bank_accounts = Accounting.list_bank_accounts(org_id)

    {:ok,
     socket
     |> assign(page_title: "Upload Files", file_type: "gstr1", result: nil,
               bank_accounts: bank_accounts,
               selected_bank_id: if(length(bank_accounts) == 1, do: to_string(hd(bank_accounts).id), else: ""))
     |> allow_upload(:data_file, accept: ~w(.zip .csv .json), max_entries: 1, max_file_size: 50_000_000)}
  end

  def handle_event("validate", _params, socket), do: {:noreply, socket}
  def handle_event("select_type", %{"type" => t}, socket), do: {:noreply, assign(socket, file_type: t)}
  def handle_event("select_bank", %{"bank_id" => id}, socket), do: {:noreply, assign(socket, selected_bank_id: id)}

  def handle_event("upload", _params, socket) do
    org_id = socket.assigns.current_org.id

    result =
      consume_uploaded_entries(socket, :data_file, fn %{path: path}, entry ->
        ext = Path.extname(entry.client_name)
        tmp = Path.join(System.tmp_dir!(), "tiago_#{:erlang.unique_integer([:positive])}#{ext}")
        File.cp!(path, tmp)
        {:ok, {tmp, entry.client_name}}
      end)

    case result do
      [{tmp_path, filename}] ->
        proc = process_file(org_id, socket.assigns.file_type, tmp_path, socket.assigns.selected_bank_id)
        File.rm(tmp_path)
        {:noreply, socket |> assign(result: %{filename: filename, type: socket.assigns.file_type, result: proc}) |> put_flash(:info, "Processed: #{filename}")}
      _ ->
        {:noreply, put_flash(socket, :error, "No file")}
    end
  end

  defp process_file(org_id, "gstr1", path, _) do
    if String.ends_with?(path, ".json") do
      json = File.read!(path) |> Jason.decode!()
      GstrParser.process_gstr1_json(org_id, json)
    else
      process_zip(path, fn json -> GstrParser.process_gstr1_json(org_id, json) end)
    end
  end

  defp process_file(org_id, "gstr2b", path, _) do
    if String.ends_with?(path, ".json") do
      json = File.read!(path) |> Jason.decode!()
      GstrParser.process_gstr2b_json(org_id, json)
    else
      process_zip(path, fn json -> GstrParser.process_gstr2b_json(org_id, json) end)
    end
  end

  defp process_file(org_id, "bank_statement", path, bank_id) do
    bid = if bank_id == "", do: nil, else: String.to_integer(bank_id)
    BankStatementParser.process_csv(org_id, path, bid)
  end

  defp process_file(_, _, _, _), do: {:error, "Unknown file type"}

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
    <div class="max-w-4xl mx-auto px-4 py-8">
      <h1 class="text-3xl font-bold mb-2">Upload Files</h1>
      <p class="text-gray-600 mb-8">Upload GSTR1, GSTR2B, or bank statement files.</p>
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
            <option value="">-- Select --</option>
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
      <%= if @result do %>
        <div class="bg-white shadow rounded-lg p-6">
          <h3 class="text-lg font-semibold mb-2">Result</h3>
          <p class="text-sm text-gray-600">File: <span class="font-medium"><%= @result.filename %></span></p>
          <%= case @result.result do %>
            <% {:ok, stats} -> %><div class="mt-2 p-3 bg-green-50 rounded text-green-800 text-sm">✅ Journals: <b><%= Map.get(stats, :journals_created, 0) %></b></div>
            <% {:error, reason} -> %><div class="mt-2 p-3 bg-red-50 rounded text-red-800 text-sm">❌ <%= inspect(reason) %></div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
