defmodule HexMcp.Vector do
  @moduledoc """
  Functions for working with vector embeddings in SQLite
  """

  require Logger
  alias HexMcp.Repo
  alias HexMcp.Schema.Embedding

  @doc """
  Stores an embedding vector in the SQLite database.
  """
  def store_embedding(package, version, _model, text, metadata, vector) do
    # Create a binary representation of the vector
    vector_binary = encode_vector(vector)

    # Create text snippet
    text_snippet =
      if String.length(text) > 100 do
        String.slice(text, 0, 100) <> "..."
      else
        text
      end

    # Create embedding record
    %Embedding{}
    |> Embedding.changeset(%{
      package: package,
      version: version || "latest",
      source_file: metadata["source_file"],
      source_type: metadata["source_type"],
      start_byte: metadata["start_byte"],
      end_byte: metadata["end_byte"],
      text_snippet: text_snippet,
      text: text,
      vector: vector_binary
    })
    |> Repo.insert()
  end

  @doc """
  Searches for similar vectors in the database using cosine similarity.

  NOTE: This is a placeholder for potential future SQLite optimized vector search.
  The current implementation calculates similarity in Elixir code in the Embeddings module.
  """
  def search_similar(_query_vector, package, top_k \\ 3) do
    Logger.info("Using search_similar with package: #{package}, top_k: #{top_k}")

    # This is just a placeholder - actual implementation is in HexMcp.Embeddings
    # for now, since we're calculating cosine similarity in Elixir
    []
  end

  @doc """
  Encodes a vector into binary format for storage in SQLite.
  """
  def encode_vector(vector) do
    # For simplicity, we'll use :erlang.term_to_binary here
    # In a production app, you might want a more efficient encoding
    :erlang.term_to_binary(vector)
  end

  @doc """
  Decodes a binary vector back into a list of floats.
  """
  def decode_vector(binary) do
    :erlang.binary_to_term(binary)
  end

  @doc """
  Creates an optimized query for retrieving embeddings by package with minimal data.
  This function helps build queries that make optimal use of SQLite indexes.
  """
  def query_embeddings_optimized(package, version \\ nil, limit \\ 1000) do
    import Ecto.Query
    
    # Base query with covering index fields
    query = 
      from e in Embedding,
      where: e.package == ^package,
      select: %{
        id: e.id,
        package: e.package, 
        version: e.version,
        source_file: e.source_file,
        text_snippet: e.text_snippet,
        vector: e.vector
      },
      limit: ^limit
    
    # Add version filter if provided
    if version do
      from e in query, where: e.version == ^version
    else
      query
    end
  end

  @doc """
  Registers the cosine_similarity function with SQLite.
  Should be called during application startup.
  """
  def register_vector_functions do
    # We can't easily implement vector similarity directly in SQLite
    # Instead, we'll just use Elixir's implementation in the embeddings module
    # This function exists as a placeholder for future SQLite extensions
    try do
      # Add any SQLite function registrations here if needed in the future
      Logger.info("Vector functions initialized")
      :ok
    rescue
      e ->
        Logger.error("Error initializing vector functions: #{inspect(e)}")
        :error
    end
  end
end
