defmodule HexdocsMcp.Application do
  @moduledoc false
  use Application

  @doc false
  def start(_type, _args) do
    children = [
      {HexdocsMcp.Repo,
       load_extensions: [SqliteVec.path()], database: HexdocsMcp.Config.database()}
    ]

    opts = [strategy: :one_for_one, name: HexdocsMcp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
