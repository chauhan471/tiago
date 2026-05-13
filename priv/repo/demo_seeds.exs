# Demo data seed for Demo Trading Co.
# Run with: mix run priv/repo/demo_seeds.exs

alias Tiago.{Repo, Parties, Accounting}
alias Tiago.Parties.PartyGstn

# Get the demo org (id=1)
org_id = 1

IO.puts("📦 Seeding demo data for org_id=#{org_id}...\n")

# ── Customers ──
IO.puts("Creating customers...")

customers = [
  %{name: "Sharma Electronics Pvt Ltd", type: :customer, gstn: "07AABCS1234A1Z5"},
  %{name: "Gupta Textiles", type: :customer, gstn: "09AABCG5678B1Z3"},
  %{name: "Mehta Pharma Distributors", type: :customer, gstn: "24AABCM9012C1Z1"},
  %{name: "Patel Hardware Store", type: :customer, gstn: "27AABCP3456D1Z9"},
  %{name: "Singh Auto Parts", type: :customer, gstn: "03AABCS7890E1Z7"}
]

customer_records = Enum.map(customers, fn c ->
  {:ok, party} = Parties.create_party(org_id, %{name: c.name, type: c.type})
  {:ok, _gstn} = Parties.add_gstn_to_party(party.id, c.gstn)
  IO.puts("  ✓ #{party.name} (#{c.gstn})")
  party
end)

# ── Suppliers ──
IO.puts("\nCreating suppliers...")

suppliers = [
  %{name: "Reliance Industries Ltd", type: :supplier, gstn: "27AAACR5055K1Z2"},
  %{name: "Tata Steel Trading Co", type: :supplier, gstn: "33AAACT1234F1Z8"},
  %{name: "Agarwal Packaging Solutions", type: :supplier, gstn: "06AAACA5678G1Z6"},
  %{name: "Kumar Raw Materials", type: :supplier, gstn: "08AAACK9012H1Z4"},
  %{name: "Jain Logistics Services", type: :supplier, gstn: "29AAACJ3456I1Z2"}
]

supplier_records = Enum.map(suppliers, fn s ->
  {:ok, party} = Parties.create_party(org_id, %{name: s.name, type: s.type})
  {:ok, _gstn} = Parties.add_gstn_to_party(party.id, s.gstn)
  IO.puts("  ✓ #{party.name} (#{s.gstn})")
  party
end)

# ── Get accounts ──
bank = Accounting.get_account_by_sub_type(org_id, :bank)
receivable = Accounting.get_account_by_sub_type(org_id, :receivable)
payable = Accounting.get_account_by_sub_type(org_id, :payable)
sales = Accounting.get_account_by_sub_type(org_id, :sales)
purchases = Accounting.get_account_by_sub_type(org_id, :purchases)
gst_output = Accounting.get_account_by_sub_type(org_id, :gst_output)
gst_input = Accounting.get_account_by_sub_type(org_id, :gst_input)

# ── Sales Invoices (to customers) ──
IO.puts("\nCreating sales invoices...")

sales_invoices = [
  {Enum.at(customer_records, 0), ~D[2025-04-05], "INV-001", 50000, 9000},
  {Enum.at(customer_records, 0), ~D[2025-05-12], "INV-007", 35000, 6300},
  {Enum.at(customer_records, 1), ~D[2025-04-10], "INV-002", 120000, 21600},
  {Enum.at(customer_records, 2), ~D[2025-04-18], "INV-003", 75000, 13500},
  {Enum.at(customer_records, 2), ~D[2025-06-01], "INV-010", 42000, 7560},
  {Enum.at(customer_records, 3), ~D[2025-05-02], "INV-005", 28000, 5040},
  {Enum.at(customer_records, 4), ~D[2025-05-20], "INV-008", 95000, 17100},
  {Enum.at(customer_records, 4), ~D[2025-06-15], "INV-012", 62000, 11160}
]

Enum.each(sales_invoices, fn {customer, date, inv_no, taxable, gst} ->
  total = taxable + gst
  {:ok, _} = Accounting.create_journal(org_id,
    %{date: date, description: "Sales Invoice #{inv_no} - #{customer.name}",
      reference_type: :invoice, reference_number: inv_no, party_id: customer.id},
    [
      %{account_id: receivable.id, entry_type: :debit, amount: Money.new!(:INR, total), description: "Receivable #{inv_no}"},
      %{account_id: sales.id, entry_type: :credit, amount: Money.new!(:INR, taxable), description: "Sales #{inv_no}"},
      %{account_id: gst_output.id, entry_type: :credit, amount: Money.new!(:INR, gst), description: "GST Output #{inv_no}"}
    ]
  )
  IO.puts("  ✓ #{inv_no} → #{customer.name}: ₹#{total} (taxable: ₹#{taxable}, GST: ₹#{gst})")
end)

# ── Purchase Invoices (from suppliers) ──
IO.puts("\nCreating purchase invoices...")

purchase_invoices = [
  {Enum.at(supplier_records, 0), ~D[2025-04-03], "PUR-001", 200000, 36000},
  {Enum.at(supplier_records, 0), ~D[2025-05-15], "PUR-006", 150000, 27000},
  {Enum.at(supplier_records, 1), ~D[2025-04-08], "PUR-002", 85000, 15300},
  {Enum.at(supplier_records, 2), ~D[2025-04-22], "PUR-003", 32000, 5760},
  {Enum.at(supplier_records, 3), ~D[2025-05-05], "PUR-004", 60000, 10800},
  {Enum.at(supplier_records, 3), ~D[2025-06-10], "PUR-008", 45000, 8100},
  {Enum.at(supplier_records, 4), ~D[2025-05-25], "PUR-007", 18000, 3240}
]

Enum.each(purchase_invoices, fn {supplier, date, inv_no, taxable, gst} ->
  total = taxable + gst
  {:ok, _} = Accounting.create_journal(org_id,
    %{date: date, description: "Purchase Invoice #{inv_no} - #{supplier.name}",
      reference_type: :invoice, reference_number: inv_no, party_id: supplier.id},
    [
      %{account_id: purchases.id, entry_type: :debit, amount: Money.new!(:INR, taxable), description: "Purchase #{inv_no}"},
      %{account_id: gst_input.id, entry_type: :debit, amount: Money.new!(:INR, gst), description: "GST Input #{inv_no}"},
      %{account_id: payable.id, entry_type: :credit, amount: Money.new!(:INR, total), description: "Payable #{inv_no}"}
    ]
  )
  IO.puts("  ✓ #{inv_no} ← #{supplier.name}: ₹#{total} (taxable: ₹#{taxable}, GST: ₹#{gst})")
end)

# ── Payments Received (from customers) ──
IO.puts("\nCreating payments received...")

payments_received = [
  {Enum.at(customer_records, 0), ~D[2025-04-25], "REC-001", 59000},
  {Enum.at(customer_records, 1), ~D[2025-05-10], "REC-002", 100000},
  {Enum.at(customer_records, 2), ~D[2025-05-20], "REC-003", 88500},
  {Enum.at(customer_records, 4), ~D[2025-06-05], "REC-004", 50000}
]

Enum.each(payments_received, fn {customer, date, ref, amount} ->
  {:ok, _} = Accounting.create_journal(org_id,
    %{date: date, description: "Payment received from #{customer.name}",
      reference_type: :payment, reference_number: ref, party_id: customer.id},
    [
      %{account_id: bank.id, entry_type: :debit, amount: Money.new!(:INR, amount), description: "Bank Receipt #{ref}"},
      %{account_id: receivable.id, entry_type: :credit, amount: Money.new!(:INR, amount), description: "Receipt #{ref}"}
    ]
  )
  IO.puts("  ✓ #{ref} ← #{customer.name}: ₹#{amount}")
end)

# ── Payments Made (to suppliers) ──
IO.puts("\nCreating payments made...")

payments_made = [
  {Enum.at(supplier_records, 0), ~D[2025-05-01], "PAY-001", 236000},
  {Enum.at(supplier_records, 1), ~D[2025-05-15], "PAY-002", 100300},
  {Enum.at(supplier_records, 2), ~D[2025-05-28], "PAY-003", 37760},
  {Enum.at(supplier_records, 4), ~D[2025-06-12], "PAY-004", 21240}
]

Enum.each(payments_made, fn {supplier, date, ref, amount} ->
  {:ok, _} = Accounting.create_journal(org_id,
    %{date: date, description: "Payment to #{supplier.name}",
      reference_type: :payment, reference_number: ref, party_id: supplier.id},
    [
      %{account_id: payable.id, entry_type: :debit, amount: Money.new!(:INR, amount), description: "Payment #{ref}"},
      %{account_id: bank.id, entry_type: :credit, amount: Money.new!(:INR, amount), description: "Bank Payment #{ref}"}
    ]
  )
  IO.puts("  ✓ #{ref} → #{supplier.name}: ₹#{amount}")
end)

# ── Credit Note ──
IO.puts("\nCreating credit/debit notes...")

customer_cn = Enum.at(customer_records, 1)
{:ok, _} = Accounting.create_journal(org_id,
  %{date: ~D[2025-05-18], description: "Credit Note CN-001 - Sales return from #{customer_cn.name}",
    reference_type: :credit_note, reference_number: "CN-001", party_id: customer_cn.id},
  [
    %{account_id: sales.id, entry_type: :debit, amount: Money.new!(:INR, 10000), description: "Sales return CN-001"},
    %{account_id: gst_output.id, entry_type: :debit, amount: Money.new!(:INR, 1800), description: "GST reversal CN-001"},
    %{account_id: receivable.id, entry_type: :credit, amount: Money.new!(:INR, 11800), description: "Receivable adjustment CN-001"}
  ]
)
IO.puts("  ✓ CN-001 ← #{customer_cn.name}: ₹11,800 (sales return)")

supplier_dn = Enum.at(supplier_records, 2)
{:ok, _} = Accounting.create_journal(org_id,
  %{date: ~D[2025-06-02], description: "Debit Note DN-001 - Purchase return to #{supplier_dn.name}",
    reference_type: :debit_note, reference_number: "DN-001", party_id: supplier_dn.id},
  [
    %{account_id: payable.id, entry_type: :debit, amount: Money.new!(:INR, 5000), description: "Payable adjustment DN-001"},
    %{account_id: purchases.id, entry_type: :credit, amount: Money.new!(:INR, 4237), description: "Purchase return DN-001"},
    %{account_id: gst_input.id, entry_type: :credit, amount: Money.new!(:INR, 763), description: "GST reversal DN-001"}
  ]
)
IO.puts("  ✓ DN-001 → #{supplier_dn.name}: ₹5,000 (purchase return)")

# ── Summary ──
IO.puts("\n" <> String.duplicate("─", 50))
IO.puts("✅ Demo data seeded!")
IO.puts("   5 customers, 5 suppliers")
IO.puts("   8 sales invoices, 7 purchase invoices")
IO.puts("   4 payments received, 4 payments made")
IO.puts("   1 credit note, 1 debit note")
IO.puts("   = 25 journal entries total")
IO.puts(String.duplicate("─", 50))
