defmodule HexMcp.Application do
  @moduledoc false
  use Application

  @doc false
  def start(_type, _args) do
    children = [
      HexMcp.Repo
    ]

    # Initialize vector functions in SQLite after the repo starts
    :timer.apply_after(1000, HexMcp.Vector, :register_vector_functions, [])
    
    opts = [strategy: :one_for_one, name: HexMcp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end