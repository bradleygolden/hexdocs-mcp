import Config

# Python configuration
config :pythonx, :uv_init,
  pyproject_toml: """
  [project]
  name = "hex_mcp"
  version = "0.0.0"
  requires-python = "==3.13.*"
  dependencies = [
    "ollama~=0.4.7"
  ]
  """

# Configure logger
config :logger, :console,
  level: :info,
  format: "$time $metadata[$level] $message\n",
  metadata: [:module, :function]

# Ecto SQLite configuration
config :hex_mcp, HexMcp.Repo,
  database: "priv/hex_mcp/hex_mcp.db",
  pool_size: 5

config :hex_mcp, ecto_repos: [HexMcp.Repo]
