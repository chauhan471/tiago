defmodule TiagoWeb.ExportController do
  use TiagoWeb, :controller
  alias Tiago.Ledger
  alias Tiago.Organizations
  import TiagoWeb.Helpers

  def party_ledger_csv(conn, %{"id" => id}) do
    ledger = Ledger.party_ledger(String.to_integer(id))
    header = "Date,Description,Reference,Debit,Credit,Balance\r\n"
    rows = Enum.map_join(ledger.entries, "\r\n", fn e ->
      [fmt_date(e.date), ~s("#{e.description}"), e.reference_number || "", fmt_amount(e.debit), fmt_amount(e.credit), fmt_amount(e.balance)]
      |> Enum.join(",")
    end)
    totals = "\r\n\"Totals\",,,#{fmt_amount(ledger.total_debit)},#{fmt_amount(ledger.total_credit)},#{fmt_amount(ledger.closing_balance)}"

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{ledger.party.name}_ledger.csv"))
    |> send_resp(200, header <> rows <> totals)
  end

  def party_ledger_pdf(conn, %{"id" => id}) do
    org_id = get_session(conn, :current_org_id)
    org = if org_id, do: Organizations.get_organization!(org_id), else: nil
    ledger = Ledger.party_ledger(String.to_integer(id))
    html = build_pdf_html(ledger, org)
    case PdfGenerator.generate(html, page_size: "A4", shell_params: ["--orientation", "Portrait", "--margin-top", "15", "--margin-bottom", "10", "--margin-left", "12", "--margin-right", "12"]) do
      {:ok, pdf_path} ->
        conn
        |> put_resp_content_type("application/pdf")
        |> put_resp_header("content-disposition", ~s(attachment; filename="#{ledger.party.name}_ledger.pdf"))
        |> send_file(200, pdf_path)
      {:error, reason} ->
        conn |> put_flash(:error, "PDF failed: #{inspect(reason)}") |> redirect(to: ~p"/parties/#{id}/ledger")
    end
  end

  defp build_pdf_html(ledger, org) do
    org_name = if org, do: org.name, else: "Tiago"
    org_gstn = if org && org.gstn, do: org.gstn, else: nil
    party = ledger.party
    party_type_label = if party.type == :customer, do: "Customer", else: "Supplier"
    today = Calendar.strftime(Date.utc_today(), "%d-%m-%Y")

    rows = ledger.entries
    |> Enum.with_index(1)
    |> Enum.map_join("", fn {e, idx} ->
      bg = if rem(idx, 2) == 0, do: "background:#f0f0f0;", else: ""
      debit_val = if Money.positive?(e.debit), do: fmt_amount(e.debit), else: ""
      credit_val = if Money.positive?(e.credit), do: fmt_amount(e.credit), else: ""
      """
      <tr style="#{bg}">
        <td class="c">#{idx}</td>
        <td>#{fmt_date(e.date)}</td>
        <td>#{e.description}</td>
        <td>#{e.reference_number || ""}</td>
        <td class="r mono">#{debit_val}</td>
        <td class="r mono">#{credit_val}</td>
        <td class="r mono b">#{fmt_amount(e.balance)}</td>
      </tr>
      """
    end)

    gstn_line = if org_gstn, do: "<div style='font-size:10px;color:#555'>GSTN: #{org_gstn}</div>", else: ""

    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <style>
        body { font-family: Arial, sans-serif; font-size: 11px; color: #222; margin: 0; }

        .header { border-bottom: 2px solid #000; padding-bottom: 8px; margin-bottom: 6px; overflow: hidden; }
        .header .org { font-size: 16px; font-weight: 700; }
        .header .meta { float: right; text-align: right; font-size: 10px; color: #555; }

        .party-bar { background: #f0f0f0; border: 1px solid #aaa; padding: 7px 10px; margin-bottom: 10px; overflow: hidden; }
        .party-bar .label { font-size: 9px; text-transform: uppercase; color: #666; }
        .party-bar .name { font-size: 13px; font-weight: 700; }

        table { width: 100%; border-collapse: collapse; }
        th { background: #ddd; border: 1px solid #999; padding: 5px 7px; text-align: left;
             font-size: 9px; text-transform: uppercase; font-weight: 700; }
        td { border: 1px solid #ccc; padding: 4px 7px; font-size: 10px; }
        .r { text-align: right; }
        .c { text-align: center; color: #888; }
        .b { font-weight: 700; }
        .mono { font-family: 'Courier New', monospace; }

        tfoot td { background: #ddd; border: 1px solid #999; font-weight: 700; font-size: 10px; }

        .closing { margin-top: 10px; border: 1px solid #888; padding: 6px 12px; display: inline-block; }
        .closing .lbl { font-size: 9px; text-transform: uppercase; color: #555; }
        .closing .amt { font-size: 14px; font-weight: 700; font-family: 'Courier New', monospace; margin-left: 8px; }

        .footer { margin-top: 20px; border-top: 1px solid #ccc; padding-top: 6px;
                   font-size: 8px; color: #aaa; overflow: hidden; }
        .footer .right { float: right; }
      </style>
    </head>
    <body>

      <div class="header">
        <div class="meta">LEDGER STATEMENT<br/>Date: #{today}</div>
        <div class="org">#{org_name}</div>
        #{gstn_line}
      </div>

      <div class="party-bar">
        <span class="label">#{party_type_label}: </span>
        <span class="name">#{party.name}</span>
      </div>

      <table>
        <thead>
          <tr>
            <th style="width:22px" class="c">#</th>
            <th style="width:72px">Date</th>
            <th>Description</th>
            <th style="width:68px">Ref</th>
            <th style="width:78px" class="r">Debit</th>
            <th style="width:78px" class="r">Credit</th>
            <th style="width:88px" class="r">Balance</th>
          </tr>
        </thead>
        <tbody>
          #{rows}
        </tbody>
        <tfoot>
          <tr>
            <td colspan="4" class="b">TOTALS</td>
            <td class="r mono">₹ #{fmt_amount(ledger.total_debit)}</td>
            <td class="r mono">₹ #{fmt_amount(ledger.total_credit)}</td>
            <td class="r mono">₹ #{fmt_amount(ledger.closing_balance)}</td>
          </tr>
        </tfoot>
      </table>

      <div class="closing">
        <span class="lbl">Closing Balance:</span>
        <span class="amt">₹ #{fmt_amount(ledger.closing_balance)}</span>
      </div>

      <div class="footer">
        This is a computer-generated document.
        <span class="right">Tiago</span>
      </div>

    </body>
    </html>
    """
  end
end
