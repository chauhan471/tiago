defmodule Tiago.Import.BankStatement do
  @moduledoc "Schema for a single bank statement row imported from a file."

  use Ecto.Schema
  import Ecto.Changeset

  schema "bank_statements" do
    field :raw_data, :map
    field :is_processed, :boolean, default: false
    field :date, :date
    field :description, :string
    field :payment_reference, :string
    field :debit, Money.Ecto.Composite.Type
    field :credit, Money.Ecto.Composite.Type

    belongs_to :account, Tiago.Accounting.Account
    belongs_to :party, Tiago.Parties.Party
    belongs_to :counter_account, Tiago.Accounting.Account

    timestamps()
  end

  def changeset(bank_statement, attrs) do
    bank_statement
    |> cast(attrs, [:account_id, :party_id, :counter_account_id, :raw_data, :is_processed, :date, :description, :payment_reference, :debit, :credit])
    |> validate_required([:account_id, :is_processed])
  end
end
