defmodule Evo.Repo do
  use Ecto.Repo,
    otp_app: :evo,
    adapter: Ecto.Adapters.SQLite3
end
