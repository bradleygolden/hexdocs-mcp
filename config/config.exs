import Config

config :logger, :console,
  level: :info,
  format: "$time $metadata[$level] $message\n",
  metadata: [:module, :function]

config :hexdocs_mcp, ecto_repos: [HexdocsMcp.Repo], pool_size: 5

# Set essential configurations directly in config.exs
data_path = System.get_env("HEXDOCS_MCP_PATH") || Path.join(System.user_home(), ".hexdocs_mcp")

config :hexdocs_mcp,
  data_path: data_path,
  default_embedding_model:
    System.get_env("HEXDOCS_MCP_DEFAULT_EMBEDDING_MODEL") || "nomic-embed-text"

config :hexdocs_mcp, HexdocsMcp.Repo, database: Path.join(data_path, "hexdocs_mcp.db")

# Create data directory
try do
  File.mkdir_p!(data_path)
rescue
  _ -> :ok
end

import_config "#{config_env()}.exs"
