# Script for populating the database.
#
# Run with: mix run priv/repo/seeds.exs

alias Tiago.{Auth, Organizations, Accounting}

# Create a default admin user
IO.puts("Creating default admin user...")
{:ok, admin} = Auth.register_user(%{
  email: "admin@tiago.dev",
  name: "Admin",
  password: "admin12345"
})
IO.puts("  ✓ User: #{admin.email}")

# Create a demo organization
IO.puts("\nCreating demo organization...")
{:ok, org} = Organizations.create_organization(%{name: "Demo Trading Co."}, admin.id)
IO.puts("  ✓ Org: #{org.name} (admin: #{admin.email})")

# Setup default accounts for the org
IO.puts("\nSetting up default accounts...")
results = Accounting.setup_default_accounts(org.id)

Enum.each(results, fn
  {:ok, account} ->
    IO.puts("  ✓ #{account.name} (#{account.account_type}/#{account.sub_type})")
  {:error, changeset} ->
    IO.puts("  ✗ Error: #{inspect(changeset.errors)}")
end)

IO.puts("\n✅ Done! Login with: admin@tiago.dev / admin12345")
