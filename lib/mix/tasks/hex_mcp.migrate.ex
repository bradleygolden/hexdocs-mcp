defmodule Mix.Tasks.HexMcp.Migrate do
  use Mix.Task
  @shortdoc "Runs the database migrations for HexMcp"

  @requirements ["app.config", "app.start"]

  @moduledoc """
  Runs the database migrations for HexMcp.

  ## Usage

      $ mix hex_mcp.migrate
  """

  def run(_args) do
    # Ensure the repository is started
    Mix.shell().info("Starting migrations for HexMcp...")
    
    # Ensure the priv/repo/migrations directory exists
    migrations_path = Path.join(["priv", "repo", "migrations"])
    if !File.dir?(migrations_path) do
      Mix.shell().info("Creating migrations directory: #{migrations_path}")
      File.mkdir_p!(migrations_path)
    end
    
    # Run migrations
    Mix.shell().info("Running migrations...")
    Ecto.Migrator.run(HexMcp.Repo, migrations_path, :up, all: true)
    
    Mix.shell().info("Migrations completed successfully!")
  end
end