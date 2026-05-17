defmodule Tiago.Repo.Migrations.CreateBankStatements do
  use Ecto.Migration

  def change do
    create table(:bank_statements) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :party_id, references(:parties, on_delete: :nilify_all)
      add :counter_account_id, references(:accounts, on_delete: :nilify_all)
      add :raw_data, :map
      add :is_processed, :boolean, default: false, null: false
      add :date, :date
      add :description, :string
      add :payment_reference, :string
      add :debit, :money_with_currency
      add :credit, :money_with_currency

      timestamps()
    end

    create index(:bank_statements, [:account_id])
    create index(:bank_statements, [:party_id])
    create index(:bank_statements, [:counter_account_id])
  end
end
