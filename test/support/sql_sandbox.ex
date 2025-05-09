defmodule HexdocsMcp.SqlSandbox do
  @moduledoc """
  Setup for SQLite in-memory database for tests.
  """

  alias HexdocsMcp.Migrations
  alias HexdocsMcp.Repo

  require Logger

  @doc """
  Create all tables needed for testing directly using shared migration SQL.
  """
  def setup do
    # Enable SQLite extensions for vector operations
    {:ok, conn} = Exqlite.Basic.open(Repo.config()[:database])
    :ok = Exqlite.Basic.enable_load_extension(conn)
    Exqlite.Basic.load_extension(conn, SqliteVec.path())

    Logger.debug("Setting up test database tables...")

    # Use the shared migrations module to create tables
    Enum.each(Migrations.create_embeddings_table(), fn sql -> Repo.query!(sql) end)
    Migrations.update_embeddings_table()
    :ok
  end
end
