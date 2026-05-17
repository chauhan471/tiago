defmodule Tiago.Import.GstrParser do
  @moduledoc "Parser for GSTR1/GSTR2B data — org-scoped."

  require Logger
  alias Tiago.{Accounting, Parties}
  alias Tiago.Import.DateParser

  def process_gstr1_json(org_id, json_data) do
    receivable = ensure_account!(org_id, :receivable)
    sales = ensure_account!(org_id, :sales)
    gst_output = ensure_account!(org_id, :gst_output)

    invoice_results =
      Map.get(json_data, "b2b", [])
      |> Enum.flat_map(fn %{"ctin" => gstn, "inv" => invoices} ->
        {:ok, party} = Parties.get_or_create_party_by_gstn(org_id, gstn, %{type: :customer})

        invoices = sort_docs(invoices, "inum")
        Enum.map(
          invoices,
          &create_sales_journal(org_id, &1, party, receivable, sales, gst_output)
        )
      end)

    note_results =
      Map.get(json_data, "cdnr", [])
      |> Enum.flat_map(fn %{"ctin" => gstn, "nt" => notes} ->
        {:ok, party} = Parties.get_or_create_party_by_gstn(org_id, gstn, %{type: :customer})

        notes = sort_docs(notes, "nt_num")
        Enum.map(
          notes,
          &create_sales_note(org_id, &1, party, receivable, sales, gst_output)
        )
      end)

    count_results(invoice_results ++ note_results)
  end

  def process_gstr2b_json(org_id, json_data) do
    payable = ensure_account!(org_id, :payable)
    purchases = ensure_account!(org_id, :purchases)
    gst_input = ensure_account!(org_id, :gst_input)

    invoice_results =
      (get_in(json_data, ["data", "docdata", "b2b"]) || [])
      |> Enum.flat_map(fn %{"ctin" => gstn, "inv" => invoices} ->
        {:ok, party} = Parties.get_or_create_party_by_gstn(org_id, gstn, %{type: :supplier})

        invoices = sort_docs(invoices, "inum")
        Enum.map(
          invoices,
          &create_purchase_journal(org_id, &1, party, payable, purchases, gst_input)
        )
      end)

    note_results =
      (get_in(json_data, ["data", "docdata", "cdnr"]) || [])
      |> Enum.flat_map(fn %{"ctin" => gstn, "nt" => notes} ->
        {:ok, party} = Parties.get_or_create_party_by_gstn(org_id, gstn, %{type: :supplier})

        notes = sort_docs(notes, "nt_num")
        Enum.map(
          notes,
          &create_purchase_note(org_id, &1, party, payable, purchases, gst_input)
        )
      end)

    count_results(invoice_results ++ note_results)
  end

  defp create_sales_journal(org_id, invoice, party, receivable, sales, gst_output) do
    with {:ok, date} <- DateParser.parse_date(invoice["idt"]),
         {:ok, total_value} <- parse_money(invoice["val"]) do
      {taxable_value, total_gst} = calculate_tax_from_items(Map.get(invoice, "itms", []))
      inum = invoice["inum"]

      desc = "Sales Invoice #{inum}"
      ref = "INV-#{inum}"

      Accounting.create_journal(
        org_id,
        %{date: date, party_id: party.id},
        [
          %{
            account_id: receivable.id,
            entry_type: :debit,
            amount: total_value,
            description: desc,
            transaction_type: :invoice,
            reference_number: ref
          },
          %{
            account_id: sales.id,
            entry_type: :credit,
            amount: taxable_value,
            description: desc,
            transaction_type: :invoice,
            reference_number: ref
          },
          %{
            account_id: gst_output.id,
            entry_type: :credit,
            amount: total_gst,
            description: desc,
            transaction_type: :invoice,
            reference_number: ref
          }
        ]
      )
    else
      error ->
        Logger.error("Sales journal failed: #{inspect(error)}")
        error
    end
  end

  defp create_purchase_journal(org_id, invoice, party, payable, purchases, gst_input) do
    with {:ok, date} <- DateParser.parse_date(invoice["dt"]),
         {:ok, total_value} <- parse_money(invoice["val"]) do
      
      # GSTR-2B JSON format stores these as flat fields on the invoice object, not in an itms array
      taxable_value = to_money(get_num(invoice, "txval", 0))
      
      tax_amount = 
        get_num(invoice, "igst", 0) + 
        get_num(invoice, "cgst", 0) + 
        get_num(invoice, "sgst", 0) + 
        get_num(invoice, "cess", 0)
        
      total_gst = to_money(tax_amount)
      
      inum = invoice["inum"]

      desc = "Purchase Invoice #{inum}"
      ref = "INV-#{inum}"

      Accounting.create_journal(
        org_id,
        %{date: date, party_id: party.id},
        [
          %{
            account_id: purchases.id,
            entry_type: :debit,
            amount: taxable_value,
            description: desc,
            transaction_type: :invoice,
            reference_number: ref
          },
          %{
            account_id: gst_input.id,
            entry_type: :debit,
            amount: total_gst,
            description: desc,
            transaction_type: :invoice,
            reference_number: ref
          },
          %{
            account_id: payable.id,
            entry_type: :credit,
            amount: total_value,
            description: desc,
            transaction_type: :invoice,
            reference_number: ref
          }
        ]
      )
    else
      error ->
        Logger.error("Purchase journal failed: #{inspect(error)}")
        error
    end
  end

  defp create_sales_note(org_id, note, party, receivable, sales, gst_output) do
    with {:ok, date} <- DateParser.parse_date(note["nt_dt"]),
         {:ok, total_value} <- parse_money(note["val"]) do
      {taxable_value, total_gst} = calculate_tax_from_items(Map.get(note, "itms", []))
      nt_num = note["nt_num"]
      ntty = note["ntty"]

      is_credit_note = ntty == "C"
      desc = if is_credit_note, do: "Credit Note #{nt_num}", else: "Debit Note #{nt_num}"
      ref = if is_credit_note, do: "CN-#{nt_num}", else: "DN-#{nt_num}"
      transaction_type = if is_credit_note, do: :credit_note, else: :debit_note

      entries =
        if is_credit_note do
          [
            %{account_id: sales.id, entry_type: :debit, amount: taxable_value},
            %{account_id: gst_output.id, entry_type: :debit, amount: total_gst},
            %{account_id: receivable.id, entry_type: :credit, amount: total_value}
          ]
        else
          [
            %{account_id: receivable.id, entry_type: :debit, amount: total_value},
            %{account_id: sales.id, entry_type: :credit, amount: taxable_value},
            %{account_id: gst_output.id, entry_type: :credit, amount: total_gst}
          ]
        end

      entries = Enum.map(entries, fn e -> 
        Map.merge(e, %{
          description: desc,
          transaction_type: transaction_type,
          reference_number: ref
        })
      end)

      Accounting.create_journal(
        org_id,
        %{date: date, party_id: party.id},
        entries
      )
    else
      error ->
        Logger.error("Sales note failed: #{inspect(error)}")
        error
    end
  end

  defp create_purchase_note(org_id, note, party, payable, purchases, gst_input) do
    with {:ok, date} <- DateParser.parse_date(note["nt_dt"] || note["dt"]),
         {:ok, total_value} <- parse_money(note["val"]) do
      
      {taxable_value, total_gst} = 
        if Map.has_key?(note, "itms") do
          calculate_tax_from_items(note["itms"])
        else
          taxval = to_money(get_num(note, "txval", 0))
          tax_amount = 
            get_num(note, "igst", 0) + 
            get_num(note, "cgst", 0) + 
            get_num(note, "sgst", 0) + 
            get_num(note, "cess", 0)
          {taxval, to_money(tax_amount)}
        end

      nt_num = note["nt_num"] || note["inum"]
      ntty = note["ntty"] || note["typ"] || "C"

      is_credit_note = ntty == "C"
      desc = if is_credit_note, do: "Credit Note #{nt_num}", else: "Debit Note #{nt_num}"
      ref = if is_credit_note, do: "CN-#{nt_num}", else: "DN-#{nt_num}"
      transaction_type = if is_credit_note, do: :credit_note, else: :debit_note

      entries =
        if is_credit_note do
          [
            %{account_id: payable.id, entry_type: :debit, amount: total_value},
            %{account_id: purchases.id, entry_type: :credit, amount: taxable_value},
            %{account_id: gst_input.id, entry_type: :credit, amount: total_gst}
          ]
        else
          [
            %{account_id: purchases.id, entry_type: :debit, amount: taxable_value},
            %{account_id: gst_input.id, entry_type: :debit, amount: total_gst},
            %{account_id: payable.id, entry_type: :credit, amount: total_value}
          ]
        end

      entries = Enum.map(entries, fn e -> 
        Map.merge(e, %{
          description: desc,
          transaction_type: transaction_type,
          reference_number: ref
        })
      end)

      Accounting.create_journal(
        org_id,
        %{date: date, party_id: party.id},
        entries
      )
    else
      error ->
        Logger.error("Purchase note failed: #{inspect(error)}")
        error
    end
  end

  defp calculate_tax_from_items(items) do
    Enum.reduce(items, {to_money(0), to_money(0)}, fn item, {txval_acc, gst_acc} ->
      det = Map.get(item, "itm_det", %{})
      txval = get_num(det, "txval", 0)
      tax = get_num(det, "iamt", 0) + get_num(det, "camt", 0) + get_num(det, "samt", 0)
      {Money.add!(txval_acc, to_money(txval)), Money.add!(gst_acc, to_money(tax))}
    end)
  end

  defp get_num(map, key, default) do
    case Map.get(map, key) do
      v when is_number(v) -> v
      _ -> default
    end
  end

  defp parse_money(v) when is_number(v), do: {:ok, to_money(v)}
  defp parse_money(_), do: {:error, "invalid amount"}

  defp to_money(v) when is_float(v),
    do: Money.new!(:INR, Decimal.from_float(v) |> Decimal.round(2))

  defp to_money(v) when is_integer(v), do: Money.new!(:INR, Decimal.new(v))

  defp ensure_account!(org_id, sub_type) do
    case Accounting.get_account_by_sub_type(org_id, sub_type) do
      nil ->
        Accounting.setup_default_accounts(org_id)
        Accounting.get_account_by_sub_type(org_id, sub_type)

      account ->
        account
    end
  end

  defp sort_docs(docs, num_key) do
    Enum.sort_by(docs, fn doc ->
      date_str = doc["idt"] || doc["nt_dt"] || doc["dt"] || ""
      date_val = case DateParser.parse_date(date_str) do
        {:ok, date} -> Date.to_iso8601(date)
        _ -> date_str
      end

      val = Map.get(doc, num_key) || Map.get(doc, "inum") || ""
      {num, rest} = case Integer.parse(to_string(val)) do
        {n, r} -> {n, r}
        :error -> {0, val}
      end

      {date_val, num, rest}
    end)
  end

  defp count_results(results) do
    {ok, errors} = Enum.split_with(results, &match?({:ok, _}, &1))
    {:ok, %{journals_created: length(ok), errors: length(errors)}}
  end
end
