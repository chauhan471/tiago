defmodule Tiago.Import.DateParser do
  @moduledoc "Date parsing supporting DD-MM-YYYY, DD/MM/YYYY, and ISO 8601."

  def parse_date(date_string) do
    date_string = String.trim(date_string)

    cond do
      Regex.match?(~r/^\d{4}-\d{2}-\d{2}$/, date_string) -> 
        Date.from_iso8601(date_string)
      Regex.match?(~r/^\d{1,2}-\d{1,2}-\d{4}$/, date_string) -> 
        parse_dmy(date_string, "-")
      Regex.match?(~r/^\d{1,2}\/\d{1,2}\/\d{4}$/, date_string) -> 
        parse_dmy(date_string, "/")
      Regex.match?(~r/^\d{1,2}[-\s][a-zA-Z]{3}[-\s]\d{2,4}$/, date_string) ->
        parse_dmy_alpha(date_string)
      true -> 
        {:error, "Unrecognized date format: #{date_string}"}
    end
  end

  defp parse_dmy(date_string, sep) do
    [dd, mm, yyyy] = date_string |> String.split(sep) |> Enum.map(&String.to_integer/1)
    Date.new(yyyy, mm, dd)
  end
  
  defp parse_dmy_alpha(date_string) do
    [dd_str, mm_str, yyyy_str] = String.split(date_string, ~r/[-\s]/)
    
    dd = String.to_integer(dd_str)
    
    mm = case String.downcase(mm_str) do
      "jan" -> 1
      "feb" -> 2
      "mar" -> 3
      "apr" -> 4
      "may" -> 5
      "jun" -> 6
      "jul" -> 7
      "aug" -> 8
      "sep" -> 9
      "oct" -> 10
      "nov" -> 11
      "dec" -> 12
      _ -> 0
    end
    
    yyyy = String.to_integer(yyyy_str)
    yyyy = if yyyy < 100, do: 2000 + yyyy, else: yyyy
    
    if mm > 0 do
      Date.new(yyyy, mm, dd)
    else
      {:error, "Invalid month"}
    end
  end
end
