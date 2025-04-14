import Config

data_path =
  System.get_env("HEXDOCS_MCP_PATH") || Path.join(System.user_home(), ".hexdocs_mcp")

database_path = Path.join(data_path, "hexdocs_mcp.db")

project_paths = System.get_env("HEXDOCS_MCP_MIX_PROJECT_PATHS")

system_command = if System.get_env("__BURRITO") == 1, do: "hexdocs_mcp", else: "mix hex.docs.mcp"

if config_env() in [:dev, :prod] do
  config :hexdocs_mcp, HexdocsMcp.Repo, database: database_path
  config :hexdocs_mcp, HexdocsMcp.Repo, database: database_path

  config :hexdocs_mcp,
    data_path: data_path,
    default_embedding_model: System.get_env("HEXDOCS_MCP_DEFAULT_EMBEDDING_MODEL", "nomic-embed-text"),
    system_command: system_command,
    project_paths: project_paths
end

if config_env() == :test do
  config :hexdocs_mcp,
    data_path: Path.join(System.tmp_dir!(), "hexdocs_mcp_test"),
    default_embedding_model: "test-model",
    system_command: "mix hex.docs.mcp",
    project_paths: project_paths
end
