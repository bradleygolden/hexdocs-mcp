defmodule HexMcp.Repo do
  use Ecto.Repo,
    otp_app: :hex_mcp,
    adapter: Ecto.Adapters.SQLite3
end