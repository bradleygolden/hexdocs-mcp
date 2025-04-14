import Config

config :hexdocs_mcp, ecto_repos: [HexdocsMcp.Repo], pool_size: 5

config :logger, :console,
  level: :info,
  format: "$time $metadata[$level] $message\n",
  metadata: [:module, :function]

import_config "#{config_env()}.exs"
