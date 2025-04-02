import Config

# Configure logger
config :logger, :console,
  level: :info,
  format: "$time $metadata[$level] $message\n",
  metadata: [:module, :function]

# Ecto SQLite configuration
data_path = System.get_env("HEXDOCS_MCP_PATH") || Path.join(System.user_home(), ".hexdocs_mcp")
File.mkdir_p!(data_path)

config :hexdocs_mcp, HexdocsMcp.Repo,
  database: Path.join(data_path, "hexdocs_mcp.db"),
  pool_size: 5

config :hexdocs_mcp, ecto_repos: [HexdocsMcp.Repo]

# MCP server configuration
config :hexdocs_mcp,
  default_embedding_model: "nomic-embed-text",
  data_path: data_path

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
