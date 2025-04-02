import Config

data_path = System.get_env("HEXDOCS_MCP_PATH") || Path.join(System.user_home(), ".hexdocs_mcp")
File.mkdir_p!(data_path)

config :hexdocs_mcp,
  data_path: data_path,
  default_embedding_model:
    System.get_env("HEXDOCS_MCP_DEFAULT_EMBEDDING_MODEL") || "nomic-embed-text"

config :hexdocs_mcp, HexdocsMcp.Repo, database: Path.join(data_path, "hexdocs_mcp.db")

if config_env() == :test do
  config :hexdocs_mcp, HexdocsMcp.Repo, database: ":memory:"
end
