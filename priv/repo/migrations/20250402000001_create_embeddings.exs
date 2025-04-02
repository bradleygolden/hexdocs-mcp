defmodule HexMcp.Repo.Migrations.CreateEmbeddings do
  use Ecto.Migration

  def change do
    create table(:embeddings) do
      add :package, :string, null: false
      add :version, :string, null: false
      add :source_file, :string, null: false
      add :source_type, :string
      add :start_byte, :integer
      add :end_byte, :integer
      add :text_snippet, :text
      add :text, :text, null: false
      add :vector, :binary, null: false

      timestamps()
    end

    # Create indexes for better query performance
    create index(:embeddings, [:package, :version])
    create index(:embeddings, [:package])
    create index(:embeddings, [:source_file])
    
    # Create covering index for common search queries to improve performance
    create index(:embeddings, [:package, :version, :source_file, :text_snippet])
  end
end