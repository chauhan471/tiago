defmodule Tiago.Import.GstrParser do
  @moduledoc "Parser for GSTR1/GSTR2B data — org-scoped."

  require Logger
  alias Tiago.{Accounting, Parties}
  alias Tiago.Import.DateParser

  def process_gstr1_json(org_id, json_data) do
    receivable = ensure_account!(org_id, :receivable)
    sales = ensure_account!(org_id, :sales)
    gst_output = ensure_account!(org_id, :gst_output)

    results =
      Map.get(json_data, "b2b", [])
      |> Enum.flat_map(fn %{"ctin" => gstn, "inv" => invoices} ->
        {:ok, party} = Parties.get_or_create_party_by_gstn(org_id, gstn, %{type: :customer})
        Enum.map(invoices, &create_sales_journal(org_id, &1, party, receivable, sales, gst_output))
      end)

    count_results(results)
  end

  def process_gstr2b_json(org_id, json_data) do
    payable = ensure_account!(org_id, :payable)
    purchases = ensure_account!(org_id, :purchases)
    gst_input = ensure_account!(org_id, :gst_input)

    results =
      Map.get(json_data, "b2b", [])
      |> Enum.flat_map(fn %{"ctin" => gstn, "inv" => invoices} ->
        {:ok, party} = Parties.get_or_create_party_by_gstn(org_id, gstn, %{type: :supplier})
        Enum.map(invoices, &create_purchase_journal(org_id, &1, party, payable, purchases, gst_input))
      end)

    count_results(results)
  end

  defp create_sales_journal(org_id, invoice, party, receivable, sales, gst_output) do
    with {:ok, date} <- DateParser.parse_date(invoice["idt"]),
         {:ok, total_value} <- parse_money(invoice["val"]) do
      {taxable_value, total_gst} = calculate_tax_from_items(Map.get(invoice, "itms", []))
      inum = invoice["inum"]

      Accounting.create_journal(org_id,
        %{date: date, description: "Sales Invoice #{inum}", reference_type: :invoice, reference_number: inum, party_id: party.id},
        [
          %{account_id: receivable.id, entry_type: :debit, amount: total_value, description: "Sales #{inum}"},
          %{account_id: sales.id, entry_type: :credit, amount: taxable_value, description: "Revenue #{inum}"},
          %{account_id: gst_output.id, entry_type: :credit, amount: total_gst, description: "GST Output #{inum}"}
        ]
      )
    else
      error -> Logger.error("Sales journal failed: #{inspect(error)}"); error
    end
  end

  defp create_purchase_journal(org_id, invoice, party, payable, purchases, gst_input) do
    with {:ok, date} <- DateParser.parse_date(invoice["idt"]),
         {:ok, total_value} <- parse_money(invoice["val"]) do
      {taxable_value, total_gst} = calculate_tax_from_items(Map.get(invoice, "itms", []))
      inum = invoice["inum"]

      Accounting.create_journal(org_id,
        %{date: date, description: "Purchase Invoice #{inum}", reference_type: :invoice, reference_number: inum, party_id: party.id},
        [
          %{account_id: purchases.id, entry_type: :debit, amount: taxable_value, description: "Purchase #{inum}"},
          %{account_id: gst_input.id, entry_type: :debit, amount: total_gst, description: "GST Input #{inum}"},
          %{account_id: payable.id, entry_type: :credit, amount: total_value, description: "Payable #{inum}"}
        ]
      )
    else
      error -> Logger.error("Purchase journal failed: #{inspect(error)}"); error
    end
  end

  defp calculate_tax_from_items(items) do
    Enum.reduce(items, {Money.new!(:INR, 0), Money.new!(:INR, 0)}, fn item, {txval_acc, gst_acc} ->
      det = Map.get(item, "itm_det", %{})
      txval = get_num(det, "txval", 0)
      tax = get_num(det, "iamt", 0) + get_num(det, "camt", 0) + get_num(det, "samt", 0)
      {Money.add!(txval_acc, Money.new!(:INR, to_string(txval))), Money.add!(gst_acc, Money.new!(:INR, to_string(tax)))}
    end)
  end

  defp get_num(map, key, default) do
    case Map.get(map, key) do
      v when is_number(v) -> v
      _ -> default
    end
  end

  defp parse_money(v) when is_number(v), do: {:ok, Money.new!(:INR, to_string(v))}
  defp parse_money(_), do: {:error, "invalid amount"}

  defp ensure_account!(org_id, sub_type) do
    case Accounting.get_account_by_sub_type(org_id, sub_type) do
      nil ->
        Accounting.setup_default_accounts(org_id)
        Accounting.get_account_by_sub_type(org_id, sub_type)
      account -> account
    end
  end

  defp count_results(results) do
    {ok, errors} = Enum.split_with(results, &match?({:ok, _}, &1))
    {:ok, %{journals_created: length(ok), errors: length(errors)}}
  end
end
