import Config

config :hexdocs_mcp, HexdocsMcp.Repo,
  database: ":memory:",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :logger, level: :warning
