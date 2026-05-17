defmodule Tiago.Parties do
  @moduledoc "Parties context — org-scoped party management."

  import Ecto.Query, warn: false
  alias Tiago.Repo
  alias Tiago.Parties.{Party, PartyGstn}

  def list_parties(org_id, opts \\ []) do
    Party
    |> where([p], p.organization_id == ^org_id)
    |> apply_filters(opts)
    |> order_by([p], desc: p.id)
    |> preload(:party_gstns)
    |> Repo.all()
  end

  defp apply_filters(q, []), do: q
  defp apply_filters(q, [{:type, t} | r]), do: q |> where([p], p.type == ^t) |> apply_filters(r)

  defp apply_filters(q, [{:search, s} | r]),
    do: q |> where([p], ilike(p.name, ^"%#{s}%")) |> apply_filters(r)

  defp apply_filters(q, [_ | r]), do: apply_filters(q, r)

  def get_party!(id), do: Party |> Repo.get!(id) |> Repo.preload(:party_gstns)
  
  def get_party(id) do
    case Repo.get(Party, id) do
      nil -> nil
      party -> Repo.preload(party, :party_gstns)
    end
  end

  def create_party(org_id, attrs) do
    # Convert all keys to strings to safely avoid mixed keys issues
    attrs_with_org = 
      attrs
      |> Enum.into(%{}, fn {k, v} -> {to_string(k), v} end)
      |> Map.put("organization_id", org_id)

    %Party{}
    |> Party.changeset(attrs_with_org)
    |> Repo.insert()
  end

  def update_party(%Party{} = party, attrs) do
    party
    |> Party.changeset(attrs)
    |> Repo.update()
  end

  def delete_party(%Party{} = party), do: Repo.delete(party)

  def add_gstn_to_party(party_id, gstn) do
    %PartyGstn{}
    |> PartyGstn.changeset(%{party_id: party_id, gstn: gstn})
    |> Repo.insert()
  end

  def get_party_gstn!(id), do: Repo.get!(PartyGstn, id)

  def update_party_gstn(%PartyGstn{} = party_gstn, attrs) do
    party_gstn
    |> PartyGstn.changeset(attrs)
    |> Repo.update()
  end

  def delete_party_gstn(%PartyGstn{} = party_gstn), do: Repo.delete(party_gstn)

  def find_party_by_gstn(org_id, gstn) do
    from(p in Party,
      join: pg in assoc(p, :party_gstns),
      where: pg.gstn == ^gstn and p.organization_id == ^org_id,
      preload: [party_gstns: pg]
    )
    |> Repo.one()
  end

  def get_or_create_party_by_gstn(org_id, gstn, attrs) do
    case find_party_by_gstn(org_id, gstn) do
      nil ->
        name = Map.get(attrs, :name) || Map.get(attrs, "name", gstn)
        type = Map.get(attrs, :type) || Map.get(attrs, "type", :supplier)

        Repo.transaction(fn ->
          {:ok, party} = create_party(org_id, %{name: name, type: type})
          {:ok, _} = add_gstn_to_party(party.id, gstn)
          Repo.preload(party, :party_gstns)
        end)

      party ->
        {:ok, party}
    end
  end

  def list_parties_by_name_like(org_id, pattern) do
    from(p in Party,
      where: p.organization_id == ^org_id and ilike(p.name, ^"%#{pattern}%"),
      preload: :party_gstns
    )
    |> Repo.all()
  end

  def merge_parties(source_id, target_id, org_id) do
    if to_string(source_id) == to_string(target_id) do
      {:error, "Cannot merge a party into itself."}
    else
      source = get_party!(source_id)
      target = get_party!(target_id)

      if source.organization_id != org_id or target.organization_id != org_id do
        {:error, "Both parties must belong to your organization."}
      else
        Repo.transaction(fn ->
          # Dynamically introspect all tables with foreign keys to parties.id
          query = """
          SELECT tc.table_name, kcu.column_name
          FROM information_schema.table_constraints AS tc
          JOIN information_schema.key_column_usage AS kcu ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
          JOIN information_schema.constraint_column_usage AS ccu ON ccu.constraint_name = tc.constraint_name AND ccu.table_schema = tc.table_schema
          WHERE tc.constraint_type = 'FOREIGN KEY' AND ccu.table_name = 'parties' AND ccu.column_name = 'id'
          """
          
          {:ok, %{rows: tables_to_update}} = Ecto.Adapters.SQL.query(Repo, query, [])
          
          # Move all related records to the target party
          Enum.each(tables_to_update, fn [table, column] ->
            # Warning: Table and column names from information_schema are safe, but still we quote them.
            update_sql = "UPDATE \"#{table}\" SET \"#{column}\" = $1 WHERE \"#{column}\" = $2"
            {:ok, _} = Ecto.Adapters.SQL.query(Repo, update_sql, [target.id, source.id])
          end)

          # Finally, delete the source party
          Repo.delete!(source)
          target
        end)
      end
    end
  end
end
