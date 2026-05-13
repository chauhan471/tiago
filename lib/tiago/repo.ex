defmodule Tiago.Repo do
  use Ecto.Repo,
    otp_app: :tiago,
    adapter: Ecto.Adapters.Postgres
end
