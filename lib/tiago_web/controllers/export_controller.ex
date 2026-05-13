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
    case PdfGenerator.generate(html, page_size: "A4", shell_params: ["--orientation", "Portrait", "--margin-top", "0", "--margin-bottom", "0", "--margin-left", "0", "--margin-right", "0"]) do
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
    entry_count = length(ledger.entries)

    rows = ledger.entries
    |> Enum.with_index(1)
    |> Enum.map_join("", fn {e, idx} ->
      bg = if rem(idx, 2) == 0, do: "background:#f9fafb;", else: ""
      debit_val = if Money.positive?(e.debit), do: fmt_amount(e.debit), else: ""
      credit_val = if Money.positive?(e.credit), do: fmt_amount(e.credit), else: ""
      """
      <tr style="#{bg}">
        <td style="padding:7px 10px;border-bottom:1px solid #e5e7eb;font-size:11px;color:#6b7280">#{idx}</td>
        <td style="padding:7px 10px;border-bottom:1px solid #e5e7eb;font-size:11px">#{fmt_date(e.date)}</td>
        <td style="padding:7px 10px;border-bottom:1px solid #e5e7eb;font-size:11px">#{e.description}</td>
        <td style="padding:7px 10px;border-bottom:1px solid #e5e7eb;font-size:11px;color:#6b7280">#{e.reference_number || ""}</td>
        <td style="padding:7px 10px;border-bottom:1px solid #e5e7eb;font-size:11px;text-align:right;font-family:'Courier New',monospace">#{debit_val}</td>
        <td style="padding:7px 10px;border-bottom:1px solid #e5e7eb;font-size:11px;text-align:right;font-family:'Courier New',monospace">#{credit_val}</td>
        <td style="padding:7px 10px;border-bottom:1px solid #e5e7eb;font-size:11px;text-align:right;font-family:'Courier New',monospace;font-weight:600">#{fmt_amount(e.balance)}</td>
      </tr>
      """
    end)

    gstn_line = if org_gstn, do: "<div style='font-size:11px;color:#6b7280;margin-top:2px'>GSTN: #{org_gstn}</div>", else: ""
    balance_label = if Money.positive?(ledger.closing_balance) || Money.zero?(ledger.closing_balance), do: "Dr", else: "Cr"

    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Helvetica Neue', Arial, sans-serif; color: #1f2937; }
        @page { margin: 0; }
      </style>
    </head>
    <body>
      <!-- Letterpad Container -->
      <div style="min-height:100vh;padding:0">

        <!-- Header Band -->
        <div style="background:linear-gradient(135deg, #1e3a5f 0%, #2563eb 100%);color:white;padding:30px 40px 25px">
          <div style="display:flex;justify-content:space-between;align-items:flex-start">
            <div>
              <div style="font-size:22px;font-weight:700;letter-spacing:0.5px">#{org_name}</div>
              #{gstn_line |> String.replace("color:#6b7280", "color:rgba(255,255,255,0.7)")}
            </div>
            <div style="text-align:right">
              <div style="font-size:10px;color:rgba(255,255,255,0.7);text-transform:uppercase;letter-spacing:1px">Ledger Statement</div>
              <div style="font-size:11px;margin-top:4px;color:rgba(255,255,255,0.85)">Generated: #{today}</div>
            </div>
          </div>
        </div>

        <!-- Party Info Bar -->
        <div style="background:#f0f4ff;border-bottom:2px solid #2563eb;padding:16px 40px;display:flex;justify-content:space-between;align-items:center">
          <div>
            <div style="font-size:10px;color:#6b7280;text-transform:uppercase;letter-spacing:0.5px">#{party_type_label}</div>
            <div style="font-size:16px;font-weight:700;color:#1e3a5f;margin-top:2px">#{party.name}</div>
          </div>
          <div style="text-align:right">
            <div style="font-size:10px;color:#6b7280;text-transform:uppercase;letter-spacing:0.5px">Entries</div>
            <div style="font-size:16px;font-weight:700;color:#1e3a5f;margin-top:2px">#{entry_count}</div>
          </div>
        </div>

        <!-- Ledger Table -->
        <div style="padding:20px 40px 0">
          <table style="width:100%;border-collapse:collapse">
            <thead>
              <tr style="background:#1e3a5f">
                <th style="padding:8px 10px;text-align:left;font-size:9px;color:white;text-transform:uppercase;letter-spacing:0.5px;font-weight:600;width:30px">#</th>
                <th style="padding:8px 10px;text-align:left;font-size:9px;color:white;text-transform:uppercase;letter-spacing:0.5px;font-weight:600;width:85px">Date</th>
                <th style="padding:8px 10px;text-align:left;font-size:9px;color:white;text-transform:uppercase;letter-spacing:0.5px;font-weight:600">Description</th>
                <th style="padding:8px 10px;text-align:left;font-size:9px;color:white;text-transform:uppercase;letter-spacing:0.5px;font-weight:600;width:80px">Ref</th>
                <th style="padding:8px 10px;text-align:right;font-size:9px;color:white;text-transform:uppercase;letter-spacing:0.5px;font-weight:600;width:90px">Debit</th>
                <th style="padding:8px 10px;text-align:right;font-size:9px;color:white;text-transform:uppercase;letter-spacing:0.5px;font-weight:600;width:90px">Credit</th>
                <th style="padding:8px 10px;text-align:right;font-size:9px;color:white;text-transform:uppercase;letter-spacing:0.5px;font-weight:600;width:100px">Balance</th>
              </tr>
            </thead>
            <tbody>
              #{rows}
            </tbody>
          </table>
        </div>

        <!-- Totals Section -->
        <div style="padding:0 40px;margin-top:4px">
          <table style="width:100%;border-collapse:collapse">
            <tr style="background:#1e3a5f">
              <td style="padding:10px;font-size:11px;color:white;font-weight:700" colspan="4">TOTALS</td>
              <td style="padding:10px;font-size:11px;color:white;font-weight:700;text-align:right;font-family:'Courier New',monospace;width:90px">₹ #{fmt_amount(ledger.total_debit)}</td>
              <td style="padding:10px;font-size:11px;color:white;font-weight:700;text-align:right;font-family:'Courier New',monospace;width:90px">₹ #{fmt_amount(ledger.total_credit)}</td>
              <td style="padding:10px;font-size:11px;color:white;font-weight:700;text-align:right;font-family:'Courier New',monospace;width:100px">₹ #{fmt_amount(ledger.closing_balance)}</td>
            </tr>
          </table>
        </div>

        <!-- Closing Balance Highlight -->
        <div style="padding:20px 40px 0">
          <div style="display:inline-block;background:#f0fdf4;border:1px solid #86efac;border-radius:6px;padding:12px 24px">
            <span style="font-size:10px;color:#6b7280;text-transform:uppercase;letter-spacing:0.5px">Closing Balance</span>
            <span style="font-size:18px;font-weight:700;color:#166534;margin-left:16px">₹ #{fmt_amount(ledger.closing_balance)}</span>
            <span style="font-size:11px;color:#6b7280;margin-left:4px">#{balance_label}</span>
          </div>
        </div>

        <!-- Footer -->
        <div style="padding:30px 40px 20px;margin-top:30px;border-top:1px solid #e5e7eb;display:flex;justify-content:space-between;align-items:center">
          <div style="font-size:9px;color:#9ca3af">This is a computer-generated document and does not require a signature.</div>
          <div style="font-size:9px;color:#9ca3af">Powered by Tiago</div>
        </div>

      </div>
    </body>
    </html>
    """
  end
end
