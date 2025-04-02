defmodule HexdocsMcp.Repo.Migrations.CreateEmbeddingsTable do
  use Ecto.Migration
  alias HexdocsMcp.Migrations

  def up do
    # Using the shared migrations module to create tables
    Migrations.create_embeddings_table()
    |> Enum.each(fn sql -> execute(sql) end)
  end

  def down do
    # Using the shared migrations module to drop tables
    Migrations.drop_embeddings_table()
    |> Enum.each(fn sql -> execute(sql) end)
  end
end
