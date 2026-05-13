defmodule Tiago.Accounting.Account do
  @moduledoc "Schema for Chart of Accounts, scoped to an organization."

  use Ecto.Schema
  import Ecto.Changeset

  @account_types [:asset, :liability, :equity, :revenue, :expense]
  @sub_types [:bank, :cash, :receivable, :payable, :purchases, :sales, :gst_input, :gst_output]

  schema "accounts" do
    field :name, :string
    field :account_type, Ecto.Enum, values: @account_types
    field :sub_type, Ecto.Enum, values: @sub_types
    field :current_balance, Money.Ecto.Composite.Type
    field :is_default, :boolean, default: false

    belongs_to :organization, Tiago.Organizations.Organization

    timestamps(type: :utc_datetime)
  end

  def changeset(account, attrs) do
    account
    |> cast(attrs, [:name, :account_type, :sub_type, :current_balance, :is_default, :organization_id])
    |> validate_required([:name, :account_type, :sub_type, :organization_id])
    |> put_default_balance()
    |> foreign_key_constraint(:organization_id)
  end

  defp put_default_balance(changeset) do
    if get_field(changeset, :current_balance) do
      changeset
    else
      put_change(changeset, :current_balance, Money.new!(:INR, 0))
    end
  end

  def account_types, do: @account_types
  def sub_types, do: @sub_types
end
