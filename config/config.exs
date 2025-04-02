import Config

config :logger, :console,
  level: :info,
  format: "$time $metadata[$level] $message\n",
  metadata: [:module, :function]

config :hexdocs_mcp, ecto_repos: [HexdocsMcp.Repo], pool_size: 5

import_config "#{config_env()}.exs"
