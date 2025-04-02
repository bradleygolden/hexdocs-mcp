defmodule HexdocsMcp.Repo do
  use Ecto.Repo,
    otp_app: :hexdocs_mcp,
    adapter: Ecto.Adapters.SQLite3
end
