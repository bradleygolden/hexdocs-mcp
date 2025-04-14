import Config

data_path =
  System.get_env("HEXDOCS_MCP_PATH") || Path.join(System.user_home(), ".hexdocs_mcp")

database_path = Path.join(data_path, "hexdocs_mcp.db")

project_paths = System.get_env("HEXDOCS_MCP_MIX_PROJECT_PATHS")

system_command = if System.get_env("__BURRITO") == 1, do: "hexdocs_mcp", else: "mix hex.docs.mcp"

if config_env() in [:dev, :prod] do
  log_path = Path.join(data_path, "logs")

  config :hexdocs_mcp, HexdocsMcp.Repo, database: database_path
  config :hexdocs_mcp, HexdocsMcp.Repo, database: database_path

  config :hexdocs_mcp,
    data_path: data_path,
    default_embedding_model: System.get_env("HEXDOCS_MCP_DEFAULT_EMBEDDING_MODEL", "nomic-embed-text"),
    system_command: system_command,
    project_paths: project_paths,
    watch_enabled: System.get_env("HEXDOCS_MCP_WATCH_ENABLED") in ["true", "1"],
    watch_poll_interval:
      (case System.get_env("HEXDOCS_MCP_WATCH_INTERVAL") do
         nil ->
           60_000

         value ->
           case Integer.parse(value) do
             {interval, _} when interval > 0 -> interval
             _ -> 60_000
           end
       end)

  File.mkdir_p!(log_path)

  config :logger, :console,
    level: :info,
    format: "$time $metadata[$level] $message\n",
    metadata: [:module, :function, :line, :pid]

  config :logger, :default_handler,
    config: [
      file: log_path |> Path.join("hexdocs_mcp.log") |> String.to_charlist(),
      filesync_repeat_interval: 5000,
      file_check: 5000,
      # 10MB
      max_no_bytes: 10_000_000,
      max_no_files: 5,
      compress_on_rotate: true
    ],
    formatter:
      {Logger.Formatter, format: "$time $metadata[$level] $message\n", metadata: [:module, :function, :line, :pid]}

  config :logger,
    level: :info,
    handle_otp_reports: true,
    handle_sasl_reports: true
end

if config_env() == :test do
  config :hexdocs_mcp,
    data_path: Path.join(System.tmp_dir!(), "hexdocs_mcp_test"),
    default_embedding_model: "test-model",
    system_command: "mix hex.docs.mcp",
    project_paths: project_paths,
    watch_enabled: false
end
