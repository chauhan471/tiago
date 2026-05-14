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

  @doc "Returns formatted label for party type."
  def party_type_label(:customer), do: "Customer"
  def party_type_label(:supplier), do: "Supplier"
  def party_type_label(:both_customer_and_supplier), do: "Customer & Supplier"
  def party_type_label(_), do: "Party"

  @doc "Returns Tailwind classes for party type badges."
  def party_type_badge_class(:customer), do: "bg-blue-100 text-blue-800"
  def party_type_badge_class(:supplier), do: "bg-green-100 text-green-800"
  def party_type_badge_class(:both_customer_and_supplier), do: "bg-purple-100 text-purple-800"
  def party_type_badge_class(_), do: "bg-gray-100 text-gray-800"
end
