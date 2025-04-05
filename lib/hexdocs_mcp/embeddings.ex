defmodule HexdocsMcp.EmbeddingsBehaviour do
  @moduledoc """
  Behaviour for the Embeddings module - used primarily for mocking in tests
  """
  
  @callback embeddings_exist?(package :: String.t(), version :: String.t() | nil) :: boolean()
  @callback delete_embeddings(package :: String.t(), version :: String.t() | nil) :: 
              {:ok, non_neg_integer()}
end

defmodule HexdocsMcp.Embeddings do
  @moduledoc """
  Functions for generating embeddings from markdown chunks using Ollama.
  """
  
  @behaviour HexdocsMcp.EmbeddingsBehaviour

  require Logger
  alias Jason
  alias HexdocsMcp.Repo
  alias HexdocsMcp.Embeddings.Embedding
  alias HexdocsMcp.Ollama

  import SqliteVec.Ecto.Query
  import Ecto.Query

  @default_top_k 3
  @batch_size 10
  @max_concurrency 4
  @timeout 30_000
  @snippet_length 100

  @doc """
  Generate embeddings for all chunks in a package and store them in SQLite.

  ## Parameters
    * `package` - The name of the package
    * `version` - The version of the package or "latest"
    * `model` - The Ollama model to use, "nomic-embed-text" is recommended
    * `progress_callback` - (Optional) Function called with progress updates

  ## Returns
    * `{:ok, count}` - The number of embeddings generated
  """
  def generate(package, version, model, opts \\ []) do
    progress_callback = opts[:progress_callback]

    data_path = HexdocsMcp.Config.data_path()
    chunks_dir = Path.join([data_path, package, "chunks"])
    default_version = version || "latest"

    chunk_files = Path.wildcard(Path.join(chunks_dir, "*.json"))
    total_chunks = length(chunk_files)

    client = Ollama.init()

    result =
      chunk_files
      |> Stream.chunk_every(@batch_size)
      |> Stream.with_index()
      |> Enum.reduce(
        {0, [], 0},
        fn {batch, _idx}, {count, changesets, processed} ->
          process_batch(
            batch,
            {count, changesets, processed},
            client,
            model,
            total_chunks,
            progress_callback
          )
        end
      )
      |> then(fn {count, changesets, processed} ->
        updated_changesets =
          Enum.map(changesets, fn changeset ->
            Ecto.Changeset.put_change(changeset, :version, default_version)
          end)

        {count, updated_changesets, processed}
      end)

    {count, updated_changesets, _} = result
    persist_changesets(updated_changesets, count, progress_callback)
  end

  defp process_batch(batch, {count, changesets, processed}, client, model, total, callback) do
    batch_results =
      Task.async_stream(
        batch,
        &process_chunk_file(&1, client, model),
        max_concurrency: @max_concurrency,
        timeout: @timeout
      )
      |> Enum.to_list()

    {new_changesets, new_count} = extract_successful_changesets(batch_results)
    new_processed = processed + length(batch)

    if callback, do: callback.(new_processed, total, :processing)

    {count + new_count, changesets ++ new_changesets, new_processed}
  end

  defp process_chunk_file(chunk_file, client, model) do
    with {:ok, chunk_json} <- File.read(chunk_file),
         {:ok, chunk_data} <- Jason.decode(chunk_json),
         text = chunk_data["text"],
         metadata = chunk_data["metadata"],
         {:ok, response} <- Ollama.embed(client, model: model, input: text),
         embedding <- extract_embedding(response, chunk_file) do
      if embedding do
        {:ok, create_embedding_changeset(text, metadata, embedding)}
      else
        {:error, :no_embedding}
      end
    else
      error ->
        Logger.error("Error processing #{chunk_file}: #{inspect(error)}")
        {:error, error}
    end
  end

  defp extract_embedding(response, chunk_file) do
    case response["embeddings"] do
      nil ->
        Logger.error("No embeddings in response for #{chunk_file}")
        nil

      [first_embedding | _] ->
        first_embedding

      _ ->
        Logger.error("Unexpected embeddings format in response for #{chunk_file}")
        nil
    end
  end

  defp create_embedding_changeset(text, metadata, embedding) do
    text_snippet =
      if String.length(text) > @snippet_length,
        do: String.slice(text, 0, @snippet_length) <> "...",
        else: text

    Embedding.changeset(%Embedding{}, %{
      package: metadata["package"],
      version: metadata["version"] || "latest",
      source_file: metadata["source_file"],
      source_type: metadata["source_type"],
      start_byte: metadata["start_byte"],
      end_byte: metadata["end_byte"],
      text_snippet: text_snippet,
      text: text,
      embedding: SqliteVec.Float32.new(embedding)
    })
  end

  defp extract_successful_changesets(batch_results) do
    Enum.reduce(batch_results, {[], 0}, fn
      {:ok, {:ok, changeset}}, {acc_changesets, acc_count} ->
        {[changeset | acc_changesets], acc_count + 1}

      _, acc ->
        acc
    end)
  end

  defp persist_changesets(changesets, count, callback) do
    if Enum.empty?(changesets) do
      {:ok, count}
    else
      Repo.transaction(fn ->
        changesets
        |> Enum.with_index(1)
        |> Enum.each(fn {changeset, idx} ->
          Repo.insert!(changeset, on_conflict: :replace_all)

          if callback && rem(idx, 10) == 0, do: callback.(idx, length(changesets), :saving)
        end)

        if callback, do: callback.(length(changesets), length(changesets), :saving)
      end)

      {:ok, count}
    end
  end

  @doc """
  Search for similar text in embeddings using SQLite.

  ## Parameters
    * `query` - The search query
    * `package` - The name of the package to search in
    * `version` - The version of the package or "latest"
    * `model` - The Ollama model to use, "nomic-embed-text" is recommended
    * `top_k` - (Optional) Number of results to return, defaults to 3
    * `progress_callback` - (Optional) Function called with progress updates
  """
  def search(query, package, version, model, opts \\ []) do
    top_k = opts[:top_k] || @default_top_k
    progress_callback = opts[:progress_callback]

    client = Ollama.init()

    if progress_callback, do: progress_callback.(0, 2, :generating)

    case generate_query_embedding(client, query, model) do
      {:ok, query_vector} when not is_nil(query_vector) ->
        if progress_callback, do: progress_callback.(1, 2, :generating)
        if progress_callback, do: progress_callback.(0, 1, :searching)

        results = search_with_vector(query_vector, package, version, top_k)

        if progress_callback, do: progress_callback.(1, 1, :searching)
        results

      _ ->
        []
    end
  end

  defp generate_query_embedding(client, query, model) do
    case Ollama.embed(client, model: model, input: query) do
      {:ok, response} ->
        embedding =
          case response do
            %{"embedding" => emb} ->
              emb

            %{"embeddings" => [emb | _]} ->
              emb

            _ ->
              Logger.error("Unexpected response format: #{inspect(response)}")
              nil
          end

        {:ok, embedding}

      error ->
        Logger.error("Error generating query embedding: #{inspect(error)}")
        {:error, error}
    end
  end

  defp search_with_vector(
         query_vector,
         package,
         version,
         top_k
       ) do
    base_query = build_base_query(package, version)
    v = SqliteVec.Float32.new(query_vector)

    results =
      Repo.all(
        from e in base_query,
          order_by: vec_distance_L2(e.embedding, vec_f32(v)),
          select: %{
            id: e.id,
            package: e.package,
            version: e.version,
            source_file: e.source_file,
            text_snippet: e.text_snippet,
            score: vec_distance_L2(e.embedding, vec_f32(v))
          },
          limit: ^top_k
      )

    format_results(results)
  end

  defp build_base_query(package, nil) do
    from e in Embedding, where: e.package == ^package
  end

  defp build_base_query(package, version) do
    from e in Embedding, where: e.package == ^package and e.version == ^version
  end

  defp format_results(results) do
    Enum.map(results, fn result ->
      %{
        score: result.score,
        metadata: %{
          id: result.id,
          package: result.package,
          version: result.version,
          source_file: result.source_file,
          text_snippet: result.text_snippet
        }
      }
    end)
  end

  @doc """
  Check if embeddings exist for a package and version.

  ## Parameters
    * `package` - The name of the package
    * `version` - The version of the package or "latest"

  ## Returns
    * `true` - Embeddings exist
    * `false` - No embeddings exist
  """
  @impl HexdocsMcp.EmbeddingsBehaviour
  def embeddings_exist?(package, version) do
    version = version || "latest"

    query =
      from e in Embedding,
        where: e.package == ^package and e.version == ^version,
        select: count(e.id),
        limit: 1

    Repo.one(query) > 0
  end

  @doc """
  Delete all embeddings for a package and version.

  ## Parameters
    * `package` - The name of the package
    * `version` - The version of the package or "latest"

  ## Returns
    * `{:ok, count}` - The number of embeddings deleted
  """
  @impl HexdocsMcp.EmbeddingsBehaviour
  def delete_embeddings(package, version) do
    version = version || "latest"

    query =
      from e in Embedding,
        where: e.package == ^package and e.version == ^version

    {count, _} = Repo.delete_all(query)
    {:ok, count}
  end
end
