defmodule Tiago.Import.Utils do
  @moduledoc "Utility functions for reading and decoding files."

  def read_and_decode_files(path) do
    path |> Path.expand() |> handle_path() |> List.flatten()
  end

  defp handle_path(path) do
    cond do
      File.dir?(path) -> path |> File.ls!() |> Enum.map(&handle_path(Path.join(path, &1)))
      String.ends_with?(path, ".zip") -> read_zip_file(path)
      String.ends_with?(path, ".json") -> [read_and_decode_file(path)]
      true -> []
    end
  end

  def read_zip_file(zip_path) do
    {:ok, zip_bin} = File.read(zip_path)
    {:ok, files} = :zip.extract(zip_bin, [:memory])

    files
    |> Enum.filter(fn {name, _} -> String.ends_with?(List.to_string(name), ".json") end)
    |> Enum.map(fn {name, content} ->
      case Jason.decode(content) do
        {:ok, decoded} -> {:ok, "#{zip_path}:#{List.to_string(name)}", decoded}
        {:error, reason} -> {:error, "#{zip_path}:#{List.to_string(name)}", reason}
      end
    end)
  end

  defp read_and_decode_file(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, decoded} -> {:ok, file_path, decoded}
          {:error, reason} -> {:error, file_path, reason}
        end

      {:error, reason} ->
        {:error, file_path, reason}
    end
  end
end
