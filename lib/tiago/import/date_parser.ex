defmodule Tiago.Import.DateParser do
  @moduledoc "Date parsing supporting DD-MM-YYYY, DD/MM/YYYY, and ISO 8601."

  def parse_date(date_string) do
    date_string = String.trim(date_string)
    cond do
      Regex.match?(~r/^\d{4}-\d{2}-\d{2}$/, date_string) -> Date.from_iso8601(date_string)
      Regex.match?(~r/^\d{1,2}-\d{1,2}-\d{4}$/, date_string) -> parse_dmy(date_string, "-")
      Regex.match?(~r/^\d{1,2}\/\d{1,2}\/\d{4}$/, date_string) -> parse_dmy(date_string, "/")
      true -> {:error, "Unrecognized date format: #{date_string}"}
    end
  end

  defp parse_dmy(date_string, sep) do
    [dd, mm, yyyy] = date_string |> String.split(sep) |> Enum.map(&String.to_integer/1)
    Date.new(yyyy, mm, dd)
  end
end
