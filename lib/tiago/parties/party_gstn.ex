defmodule Tiago.Parties.PartyGstn do
  @moduledoc "Schema for linking GSTNs to parties. Globally unique GSTN."

  use Ecto.Schema
  import Ecto.Changeset

  @state_codes %{
    "01" => "Jammu & Kashmir",
    "02" => "Himachal Pradesh",
    "03" => "Punjab",
    "04" => "Chandigarh",
    "05" => "Uttarakhand",
    "06" => "Haryana",
    "07" => "Delhi",
    "08" => "Rajasthan",
    "09" => "Uttar Pradesh",
    "10" => "Bihar",
    "11" => "Sikkim",
    "12" => "Arunachal Pradesh",
    "13" => "Nagaland",
    "14" => "Manipur",
    "15" => "Mizoram",
    "16" => "Tripura",
    "17" => "Meghalaya",
    "18" => "Assam",
    "19" => "West Bengal",
    "20" => "Jharkhand",
    "21" => "Odisha",
    "22" => "Chhattisgarh",
    "23" => "Madhya Pradesh",
    "24" => "Gujarat",
    "27" => "Maharashtra",
    "29" => "Karnataka",
    "30" => "Goa",
    "32" => "Kerala",
    "33" => "Tamil Nadu",
    "34" => "Puducherry",
    "36" => "Telangana",
    "37" => "Andhra Pradesh"
  }

  schema "party_gstns" do
    field :gstn, :string
    field :state_name, :string
    belongs_to :party, Tiago.Parties.Party
    timestamps(type: :utc_datetime)
  end

  def changeset(party_gstn, attrs) do
    party_gstn
    |> cast(attrs, [:gstn, :party_id])
    |> validate_required([:gstn, :party_id])
    |> validate_gstn_format()
    |> derive_state_name()
    |> unique_constraint(:gstn)
    |> foreign_key_constraint(:party_id)
  end

  defp validate_gstn_format(changeset) do
    case get_change(changeset, :gstn) do
      nil ->
        changeset

      gstn ->
        if String.match?(gstn, ~r/^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$/) do
          changeset
        else
          add_error(changeset, :gstn, "invalid GSTIN format")
        end
    end
  end

  defp derive_state_name(changeset) do
    case get_change(changeset, :gstn) do
      nil ->
        changeset

      gstn ->
        state_code = String.slice(gstn, 0, 2)
        put_change(changeset, :state_name, Map.get(@state_codes, state_code, "Unknown"))
    end
  end

  def state_codes, do: @state_codes
end
