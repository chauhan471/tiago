defmodule TiagoWeb.Helpers do
  @moduledoc "Shared view helpers for formatting."

  @doc "Formats a Date as DD-MM-YYYY."
  def fmt_date(%Date{} = d), do: Calendar.strftime(d, "%d-%m-%Y")
  def fmt_date(d) when is_binary(d), do: d
  def fmt_date(_), do: "—"

  @doc "Formats Money for display (with ₹ symbol)."
  def fmt_money(%Money{} = m), do: Money.to_string!(m)
  def fmt_money(_), do: "₹0.00"

  @doc "Formats Money amount only (no ₹ symbol), for PDF rows."
  def fmt_amount(%Money{} = m), do: to_string(m.amount)
  def fmt_amount(_), do: "0.00"
end
