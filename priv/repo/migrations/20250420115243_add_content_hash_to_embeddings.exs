defmodule HexdocsMcp.Repo.Migrations.AddContentHashToEmbeddings do
  use Ecto.Migration

  def up do
    alter table(:embeddings) do
      add_if_not_exists :content_hash, :text, null: false
    end

    create_if_not_exists index(:embeddings, [:package, :version, :content_hash], name: :idx_embeddings_content_hash)
  end

  def down do
    :ok
  end
end
