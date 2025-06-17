defmodule HexdocsMcp.Repo.Migrations.UpgradeEmbeddingDimensions do
  use Ecto.Migration

  def up do
    execute "DROP TABLE IF EXISTS embeddings;"
    
    execute """
    CREATE TABLE embeddings(
      id INTEGER PRIMARY KEY,
      package TEXT NOT NULL,
      version TEXT NOT NULL,
      source_file TEXT NOT NULL,
      source_type TEXT,
      start_byte INTEGER,
      end_byte INTEGER,
      url TEXT,
      text_snippet TEXT,
      text TEXT NOT NULL,
      content_hash TEXT NOT NULL,
      embedding FLOAT[1024] NOT NULL,
      inserted_at TIMESTAMP,
      updated_at TIMESTAMP,
      UNIQUE(package, version, source_file, text_snippet)
    );
    """
    
    execute "CREATE INDEX idx_embeddings_package_version ON embeddings(package, version);"
    execute "CREATE INDEX idx_embeddings_content_hash ON embeddings(package, version, content_hash);"
  end

  def down do
    execute "DROP TABLE IF EXISTS embeddings;"
    
    execute """
    CREATE TABLE embeddings(
      id INTEGER PRIMARY KEY,
      package TEXT NOT NULL,
      version TEXT NOT NULL,
      source_file TEXT NOT NULL,
      source_type TEXT,
      start_byte INTEGER,
      end_byte INTEGER,
      url TEXT,
      text_snippet TEXT,
      text TEXT NOT NULL,
      content_hash TEXT NOT NULL,
      embedding FLOAT[384] NOT NULL,
      inserted_at TIMESTAMP,
      updated_at TIMESTAMP,
      UNIQUE(package, version, source_file, text_snippet)
    );
    """
    
    execute "CREATE INDEX idx_embeddings_package_version ON embeddings(package, version);"
    execute "CREATE INDEX idx_embeddings_content_hash ON embeddings(package, version, content_hash);"
  end
end