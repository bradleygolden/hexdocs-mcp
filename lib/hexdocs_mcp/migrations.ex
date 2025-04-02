defmodule HexdocsMcp.Migrations do
  @moduledoc """
  Shared migrations that can be used in regular migrations and tests.

  This provides a consistent way to create database structure both during regular
  migrations and in test environments.
  """

  @doc """
  Creates the embeddings table.

  ## Options
    * `:prefix` - The prefix to run the migrations in
  """
  def create_embeddings_table(opts \\ []) do
    prefix = opts[:prefix]
    create_opts = if prefix, do: ", prefix: #{inspect(prefix)}", else: ""

    [
      """
      CREATE TABLE IF NOT EXISTS embeddings(
        id INTEGER PRIMARY KEY,
        package TEXT NOT NULL,
        version TEXT NOT NULL,
        source_file TEXT NOT NULL,
        source_type TEXT,
        start_byte INTEGER,
        end_byte INTEGER,
        text_snippet TEXT,
        text TEXT NOT NULL,
        embedding FLOAT[384] NOT NULL,
        inserted_at TIMESTAMP,
        updated_at TIMESTAMP,
        UNIQUE(package, version, source_file, text_snippet)
      )#{create_opts};
      """,
      "CREATE INDEX IF NOT EXISTS idx_embeddings_package_version ON embeddings(package, version)#{create_opts};"
    ]
  end

  @doc """
  Drops the embeddings table.

  ## Options
    * `:prefix` - The prefix to run the migrations in
  """
  def drop_embeddings_table(opts \\ []) do
    prefix = opts[:prefix]
    drop_opts = if prefix, do: ", prefix: #{inspect(prefix)}", else: ""

    ["DROP TABLE IF EXISTS embeddings#{drop_opts};"]
  end
end
