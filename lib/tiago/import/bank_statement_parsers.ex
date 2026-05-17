defmodule Tiago.Import.BankStatementParsers do
  @moduledoc """
  Abstracts parsing logic for different bank statement formats.
  Provides a unified stream of parsed maps to the core import logic.
  """

  @doc """
  Returns a stream of maps where keys are header names and values are the string contents.
  """
  def stream_rows(filepath, "generic_csv") do
    filepath
    |> File.stream!()
    |> CSV.decode!(headers: true)
  end

  def stream_rows(filepath, "sbi_xls") do
    # SBI exports are actually TSV files named .xls
    # They usually contain preamble lines before the actual transaction table.
    filepath
    |> File.stream!()
    |> Stream.drop_while(fn line ->
      # Drop lines until we hit the header row
      not String.contains?(line, "Txn Date") and not String.contains?(line, "Debit")
    end)
    |> CSV.decode!(separator: ?\t, headers: true)
  end

  @doc """
  Reads the first 3 lines of the table data for previewing and verifying headers.
  """
  def read_headers_and_sample(filepath, format) do
    filepath
    |> stream_rows(format)
    |> Enum.take(3)
    |> case do
      [] -> {:error, "Empty or invalid file format"}
      [first | _] = sample -> {:ok, Map.keys(first), sample}
    end
  end

  @doc """
  Provides a default mapping of core fields to known column headers for a specific format.
  """
  def default_mapping("sbi_xls") do
    %{
      "date" => "Txn Date",
      "description" => "Description",
      "reference" => "Ref No./Cheque No.",
      "debit" => "Debit",
      "credit" => "Credit"
    }
  end

  def default_mapping("generic_csv") do
    %{
      "date" => "",
      "description" => "",
      "reference" => "",
      "debit" => "",
      "credit" => ""
    }
  end
end
