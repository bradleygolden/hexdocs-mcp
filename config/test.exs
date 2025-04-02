import Config

config :hexdocs_mcp, HexdocsMcp.Repo,
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :logger, level: :warning
