defmodule Tiago.Repo.Migrations.CreateAccountingTables do
  use Ecto.Migration

  def change do
    # Accounts (Chart of Accounts, org-scoped)
    create table(:accounts) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :account_type, :string, null: false
      add :sub_type, :string, null: false
      add :current_balance, :money_with_currency
      add :is_default, :boolean, default: false
      timestamps(type: :utc_datetime)
    end

    create index(:accounts, [:organization_id])
    create index(:accounts, [:organization_id, :sub_type])

    # Parties (org-scoped)
    create table(:parties) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :type, :string, null: false
      add :notes, :text
      timestamps(type: :utc_datetime)
    end

    create index(:parties, [:organization_id])
    create index(:parties, [:organization_id, :type])

    # Party GSTNs
    create table(:party_gstns) do
      add :party_id, references(:parties, on_delete: :delete_all), null: false
      add :gstn, :string, null: false
      add :state_name, :string
      timestamps(type: :utc_datetime)
    end

    create unique_index(:party_gstns, [:gstn])
    create index(:party_gstns, [:party_id])

    # Journals (org-scoped)
    create table(:journals) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :party_id, references(:parties, on_delete: :nilify_all)
      add :date, :date, null: false
      timestamps(type: :utc_datetime)
    end

    create index(:journals, [:organization_id])
    create index(:journals, [:party_id])
    create index(:journals, [:date])

    # Journal Entries
    create table(:journal_entries) do
      add :journal_id, references(:journals, on_delete: :delete_all), null: false
      add :account_id, references(:accounts, on_delete: :restrict), null: false
      add :entry_type, :string, null: false
      add :amount, :money_with_currency, null: false
      add :date, :date, null: false
      add :description, :string
      add :transaction_type, :string
      add :reference_number, :string
      timestamps(type: :utc_datetime)
    end

    create index(:journal_entries, [:journal_id])
    create index(:journal_entries, [:account_id])

    create unique_index(:journal_entries, [:account_id, :date, :amount, :reference_number],
             where:
               "transaction_type IN ('invoice', 'credit_note', 'debit_note') AND reference_number IS NOT NULL",
             name: :journal_entries_unique_invoice_idx
           )

    create unique_index(
             :journal_entries,
             [:account_id, :date, :amount, :description, "coalesce(reference_number, '')"],
             where: "transaction_type = 'payment' AND description IS NOT NULL",
             name: :journal_entries_unique_payment_idx
           )

    # Shared Ledger Links
    create table(:shared_ledger_links) do
      add :party_id, references(:parties, on_delete: :delete_all), null: false
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :created_by_id, references(:users, on_delete: :nilify_all)
      add :token, :string, null: false
      add :label, :string
      add :expires_at, :utc_datetime
      add :active, :boolean, default: true
      timestamps(type: :utc_datetime)
    end

    create unique_index(:shared_ledger_links, [:token])
    create index(:shared_ledger_links, [:party_id])
    create index(:shared_ledger_links, [:organization_id])
  end
end
