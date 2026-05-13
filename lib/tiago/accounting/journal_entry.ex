defmodule Tiago.Accounting.JournalEntry do
  @moduledoc "Schema for journal entries (debit/credit lines)."

  use Ecto.Schema
  import Ecto.Changeset

  @entry_types [:debit, :credit]

  schema "journal_entries" do
    field :entry_type, Ecto.Enum, values: @entry_types
    field :amount, Money.Ecto.Composite.Type
    field :description, :string

    belongs_to :journal, Tiago.Accounting.Journal
    belongs_to :account, Tiago.Accounting.Account

    timestamps(type: :utc_datetime)
  end

  def changeset(journal_entry, attrs) do
    journal_entry
    |> cast(attrs, [:journal_id, :account_id, :entry_type, :amount, :description])
    |> validate_required([:journal_id, :account_id, :entry_type, :amount])
    |> validate_positive_amount()
    |> foreign_key_constraint(:journal_id)
    |> foreign_key_constraint(:account_id)
  end

  defp validate_positive_amount(changeset) do
    case get_field(changeset, :amount) do
      %Money{} = money ->
        if Money.positive?(money), do: changeset,
        else: add_error(changeset, :amount, "must be positive")
      _ -> changeset
    end
  end

  def entry_types, do: @entry_types
end
