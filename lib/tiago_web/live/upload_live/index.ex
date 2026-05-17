defmodule TiagoWeb.UploadLive.Index do
  use TiagoWeb, :live_view
  on_mount {TiagoWeb.Live.OrgHook, :default}

  alias Tiago.Import.{GstrParser, Utils}

  def mount(_params, _session, socket) do

    {:ok,
     socket
     |> assign(
       page_title: "Upload GSTR Files",
       file_type: "gstr1",
       result: nil
     )
     |> allow_upload(:data_file,
       accept: ~w(.zip .json),
       max_entries: 1,
       max_file_size: 50_000_000
     )}
  end

  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("select_type", %{"type" => t}, socket),
    do: {:noreply, assign(socket, file_type: t)}

  def handle_event("upload", _params, socket) do
    org_id = socket.assigns.current_org.id
    file_type = socket.assigns.file_type

    result =
      consume_uploaded_entries(socket, :data_file, fn %{path: path}, entry ->
        ext = Path.extname(entry.client_name)

        safe_tmp =
          Path.join(
            System.tmp_dir!(),
            "tiago_gstr_#{:erlang.unique_integer([:positive])}#{ext}"
          )

        File.cp!(path, safe_tmp)
        {:ok, {safe_tmp, entry.client_name}}
      end)

    case result do
      [{tmp_path, filename}] ->
        proc = process_gstr(org_id, file_type, tmp_path)
        File.rm(tmp_path)

        {:noreply,
         socket
         |> assign(result: %{filename: filename, type: file_type, result: proc})
         |> put_flash(:info, "Processed: #{filename}")}

      _ ->
        {:noreply, put_flash(socket, :error, "No file uploaded")}
    end
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
    |> Enum.flat_map(fn
      {:ok, _, json} -> [json]
      _ -> []
    end)
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
      <h1 class="text-3xl font-bold mb-2">Upload GSTR Files</h1>
      <p class="text-gray-600 mb-8">Upload GSTR1 or GSTR2B JSON/ZIP files.</p>

      <div class="flex gap-2 mb-6">
        <%= for {label, key} <- [{"GSTR1 (Sales)", "gstr1"}, {"GSTR2B (Purchases)", "gstr2b"}] do %>
          <button
            phx-click="select_type"
            phx-value-type={key}
            class={"px-4 py-2 rounded-lg text-sm font-medium transition #{if @file_type == key, do: "bg-blue-600 text-white", else: "bg-blue-50 text-blue-700"}"}
          >
            <%= label %>
          </button>
        <% end %>
      </div>

      <form id="upload-form" phx-submit="upload" phx-change="validate" class="mb-8">
        <div class="border-2 border-dashed border-gray-300 rounded-lg p-8 text-center hover:border-gray-400">
          <.live_file_input upload={@uploads.data_file} class="mb-4" />
          <%= for entry <- @uploads.data_file.entries do %>
            <div class="mt-4 text-sm">
              <span class="font-medium"><%= entry.client_name %></span>
              (<%= div(entry.client_size, 1024) %> KB)
            </div>
          <% end %>
          <button
            type="submit"
            class="mt-4 bg-blue-600 text-white rounded-lg px-6 py-2 font-medium disabled:opacity-50"
            disabled={@uploads.data_file.entries == []}
          >
            Upload & Process
          </button>
        </div>
      </form>

      <%= if @result do %>
        <div class="bg-white shadow rounded-lg p-6">
          <h2 class="text-xl font-bold mb-4">Results for <%= @result.filename %></h2>
          <%= case @result.result do %>
            <% {:ok, res} -> %>
              <div class="text-green-700 bg-green-50 p-4 rounded-lg">
                <p class="font-medium">Success!</p>
                <ul class="list-disc ml-5 mt-2 text-sm">
                  <li>Journals Created: <%= res.journals_created %></li>
                  <%= if Map.get(res, :errors, 0) > 0 do %>
                    <li class="text-red-600">Errors: <%= res.errors %></li>
                  <% end %>
                </ul>
              </div>
            <% {:error, reason} -> %>
              <div class="text-red-700 bg-red-50 p-4 rounded-lg">
                <p class="font-medium">Failed to process file</p>
                <p class="text-sm mt-1"><%= inspect(reason) %></p>
              </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
