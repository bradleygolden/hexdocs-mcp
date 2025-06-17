defmodule HexdocsMcp.Embeddings do
  @moduledoc """
  Functions for generating embeddings from markdown chunks using Ollama.
  """

  @behaviour HexdocsMcp.Behaviours.Embeddings

  import Ecto.Query
  import SqliteVec.Ecto.Query

  alias HexdocsMcp.Behaviours.Embeddings
  alias HexdocsMcp.Embeddings.Embedding
  alias HexdocsMcp.Ollama
  alias HexdocsMcp.Repo

  require Logger

  @default_top_k 3
  @batch_size 10
  @max_concurrency 4
  @timeout 30_000
  @snippet_length 100

  @doc """
  Generates a SHA-256 hash for the given text content.

  Returns a lowercase hex-encoded string representation of the hash.
  """
  @spec content_hash(String.t()) :: String.t()
  def content_hash(text) when is_binary(text) do
    :sha256 |> :crypto.hash(text) |> Base.encode16(case: :lower)
  end

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
  @impl Embeddings
  def generate(package, version, model, opts \\ []) do
    progress_callback = opts[:progress_callback]
    force? = opts[:force] || false

    check_model_available(model)

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
        {0, [], 0, 0},
        fn {batch, _idx}, {count, changesets, processed, reused} ->
          process_batch(
            batch,
            {count, changesets, processed, reused},
            client,
            model,
            total_chunks,
            progress_callback,
            force?
          )
        end
      )
      |> then(fn {count, changesets, processed, reused} ->
        updated_changesets =
          Enum.map(changesets, fn changeset ->
            Ecto.Changeset.put_change(changeset, :version, default_version)
          end)

        {count, updated_changesets, processed, reused}
      end)

    {count, changesets, _, reused} = result

    if total_chunks > 0 && count == 0 && reused == 0 do
      {:error, "Failed to generate embeddings. Please check that Ollama is running and accessible."}
    else
      persist_changesets(changesets, count, reused, progress_callback)
    end
  end

  defp process_batch(batch, {count, changesets, processed, reused}, client, model, total, callback, force?) do
    batch_results =
      batch
      |> Task.async_stream(
        &process_chunk_file(&1, client, model, force?),
        max_concurrency: @max_concurrency,
        timeout: @timeout
      )
      |> Enum.to_list()

    {new_changesets, new_count, reused_count} = extract_successful_changesets(batch_results)
    new_processed = processed + length(batch)

    if callback, do: callback.(new_processed, total, :processing)

    {count + new_count, changesets ++ new_changesets, new_processed, reused + reused_count}
  end

  defp process_chunk_file(chunk_file, client, model, force?) do
    with {:ok, chunk_json} <- File.read(chunk_file),
         {:ok, chunk_data} <- Jason.decode(chunk_json) do
      text = chunk_data["text"]
      metadata = chunk_data["metadata"]
      content_hash = metadata["content_hash"]

      version = metadata["version"] || "latest"
      package = metadata["package"]

      if force? do
        generate_new_embedding(text, metadata, content_hash, client, model, chunk_file)
      else
        process_existing_embedding(text, metadata, content_hash, package, version, client, model, chunk_file)
      end
    else
      error ->
        Logger.error("Error processing #{chunk_file}: #{inspect(error)}")
        {:error, error}
    end
  end

  defp process_existing_embedding(text, metadata, content_hash, package, version, client, model, chunk_file) do
    existing_embedding = find_existing_embedding(package, version, content_hash)

    if existing_embedding do
      {:ok, :reused, update_existing_embedding_changeset(existing_embedding, metadata)}
    else
      process_embedding_with_hash(text, metadata, content_hash, package, client, model, chunk_file)
    end
  end

  defp process_embedding_with_hash(text, metadata, content_hash, package, client, model, chunk_file) do
    existing_hash = find_embedding_with_hash(package, content_hash)

    if existing_hash do
      {:ok, :reused, copy_embedding_changeset(existing_hash, text, metadata, content_hash)}
    else
      generate_new_embedding(text, metadata, content_hash, client, model, chunk_file)
    end
  end

  defp generate_new_embedding(text, metadata, content_hash, client, model, chunk_file) do
    case Ollama.embed(client, model: model, input: text) do
      {:ok, response} ->
        embedding = extract_embedding(response, chunk_file)

        if embedding do
          Logger.debug("Generated embedding with #{length(embedding)} dimensions for #{chunk_file}")
          {:ok, :new, create_embedding_changeset(text, metadata, embedding, content_hash)}
        else
          Logger.error("No embedding extracted from response for #{chunk_file}")
          {:error, :no_embedding}
        end

      {:error, %Req.TransportError{reason: :econnrefused}} = error ->
        Logger.error("Ollama connection refused for #{chunk_file}. Is Ollama running on http://localhost:11434?")
        {:error, error}

      error ->
        Logger.error("Error processing #{chunk_file}: #{inspect(error)}")
        {:error, error}
    end
  end

  defp find_existing_embedding(package, version, content_hash) do
    if is_nil(package) or is_nil(content_hash) do
      nil
    else
      query =
        from e in Embedding,
          where:
            e.package == ^package and
              e.version == ^version and
              e.content_hash == ^content_hash,
          limit: 1

      Repo.one(query)
    end
  end

  defp update_existing_embedding_changeset(embedding, metadata) do
    changes = %{
      source_file: metadata["source_file"],
      source_type: metadata["source_type"],
      start_byte: metadata["start_byte"],
      end_byte: metadata["end_byte"],
      version: metadata["version"] || "latest"
    }

    Embedding.changeset(embedding, changes)
  end

  defp find_embedding_with_hash(package, content_hash) do
    if is_nil(package) or is_nil(content_hash) do
      nil
    else
      query =
        from e in Embedding,
          where:
            e.package == ^package and
              e.content_hash == ^content_hash,
          limit: 1

      Repo.one(query)
    end
  end

  defp copy_embedding_changeset(existing, text, metadata, content_hash) do
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
      content_hash: content_hash,
      url: metadata["url"],
      embedding: existing.embedding
    })
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

  defp create_embedding_changeset(text, metadata, embedding, content_hash) do
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
      content_hash: content_hash,
      url: metadata["url"],
      embedding: SqliteVec.Float32.new(embedding)
    })
  end

  defp extract_successful_changesets(batch_results) do
    Enum.reduce(batch_results, {[], 0, 0}, fn
      {:ok, {:ok, :new, changeset}}, {acc_changesets, new_count, reused_count} ->
        {[changeset | acc_changesets], new_count + 1, reused_count}

      {:ok, {:ok, :reused, changeset}}, {acc_changesets, new_count, reused_count} ->
        {[changeset | acc_changesets], new_count, reused_count + 1}

      _, acc ->
        acc
    end)
  end

  defp persist_changesets(changesets, _count, reused, callback) do
    if Enum.empty?(changesets) do
      {:ok, {0, 0, 0}}
    else
      case do_persist_changesets(changesets, callback) do
        {:ok, _} ->
          total = length(changesets)
          {:ok, {total, total - reused, reused}}

        {:error, reason} ->
          Logger.error("Failed to persist changesets: #{inspect(reason)}")
          {:error, "Failed to save embeddings: #{inspect(reason)}"}
      end
    end
  end

  defp do_persist_changesets(changesets, callback) do
    Repo.transaction(fn ->
      changesets
      |> Enum.with_index(1)
      |> Enum.each(&insert_and_callback(&1, length(changesets), callback))

      if callback, do: callback.(length(changesets), length(changesets), :saving)
    end)
  end

  defp insert_and_callback({changeset, idx}, total, callback) do
    case Repo.insert(changeset, on_conflict: :replace_all) do
      {:ok, _} ->
        if callback && rem(idx, 10) == 0, do: callback.(idx, total, :saving)

      {:error, %{errors: errors}} ->
        Logger.error("Failed to insert embedding at index #{idx}")
        Logger.error("Changeset errors: #{inspect(errors)}")

        embedding_errors = Keyword.get(errors, :embedding, [])

        if embedding_errors != [] do
          Logger.error("Embedding validation error. This might be due to dimension mismatch.")
          Logger.error("Try regenerating all embeddings with --force flag.")
        end

        raise "Failed to insert embedding: #{inspect(errors)}"
    end
  rescue
    e in Exqlite.Error ->
      if String.contains?(e.message, "dimension") do
        Logger.error("Dimension mismatch detected: #{e.message}")
        Logger.error("The model is generating embeddings with different dimensions than stored in the database.")
        Logger.error("Please regenerate all embeddings using --force flag.")
        raise "Embedding dimension mismatch. Use --force to regenerate all embeddings."
      else
        raise e
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
    * `all_versions` - (Optional) Include all versions in search, defaults to false
  """
  def search(query, package, version, model, opts \\ []) do
    top_k = opts[:top_k] || @default_top_k
    progress_callback = opts[:progress_callback]
    all_versions = opts[:all_versions] || false

    client = Ollama.init()

    if progress_callback, do: progress_callback.(0, 2, :generating)

    case generate_query_embedding(client, query, model) do
      {:ok, query_vector} when not is_nil(query_vector) ->
        if progress_callback, do: progress_callback.(1, 2, :generating)
        if progress_callback, do: progress_callback.(0, 1, :searching)

        results = search_with_vector(query_vector, package, version, top_k, all_versions)

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

  defp search_with_vector(query_vector, package, version, top_k, all_versions) do
    base_query = build_base_query(package, version)
    v = SqliteVec.Float32.new(query_vector)

    if not all_versions and is_nil(version) do
      initial_limit = top_k * 10

      raw_results =
        Repo.all(
          from e in base_query,
            order_by: vec_distance_L2(e.embedding, vec_f32(v)),
            select: %{
              id: e.id,
              package: e.package,
              version: e.version,
              source_file: e.source_file,
              text: e.text,
              text_snippet: e.text_snippet,
              url: e.url,
              score: vec_distance_L2(e.embedding, vec_f32(v))
            },
            limit: ^initial_limit
        )

      formatted_results = format_results(raw_results)

      formatted_results
      |> HexdocsMcp.Version.filter_latest_versions()
      |> Enum.take(top_k)
    else
      results =
        Repo.all(
          from e in base_query,
            order_by: vec_distance_L2(e.embedding, vec_f32(v)),
            select: %{
              id: e.id,
              package: e.package,
              version: e.version,
              source_file: e.source_file,
              text: e.text,
              text_snippet: e.text_snippet,
              url: e.url,
              score: vec_distance_L2(e.embedding, vec_f32(v))
            },
            limit: ^top_k
        )

      format_results(results)
    end
  end

  defp build_base_query(nil, _), do: from(e in Embedding)

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
          text_snippet: result.text_snippet,
          text: result.text,
          url: result.url
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
  @impl Embeddings
  def embeddings_exist?(package, version) do
    version = version || "latest"

    query =
      from e in Embedding,
        select: count(e.id),
        limit: 1

    query =
      if package do
        from e in query,
          where: e.package == ^package and e.version == ^version
      else
        query
      end

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
  @impl Embeddings
  def delete_embeddings(package, version) do
    version = version || "latest"

    query =
      if package do
        from e in Embedding,
          where: e.package == ^package and e.version == ^version
      end

    if query do
      {count, _} = Repo.delete_all(query)
      {:ok, count}
    else
      {:ok, 0}
    end
  end

  defp check_model_available(model) do
    if model == "mxbai-embed-large" do
      try do
        client = Ollama.init()

        case Ollama.embed(client, model: model, input: "test") do
          {:ok, _response} ->
            :ok

          {:error, error} ->
            error_string = inspect(error)

            if String.contains?(error_string, "HTTPError") and
                 (String.contains?(error_string, "404") or String.contains?(error_string, "Not Found")) do
              Logger.error("")
              Logger.error("🚨 Model '#{model}' not found!")
              Logger.error("")
              Logger.error("To use the default embedding model, please run:")
              Logger.error("  ollama pull #{model}")
              Logger.error("")
              Logger.error("This will download the recommended embedding model (~670MB)")
              Logger.error("")
              raise "Required model '#{model}' not available in Ollama"
            else
              Logger.error("Error checking model availability: #{inspect(error)}")
              :ok
            end
        end
      rescue
        error ->
          Logger.error("Failed to connect to Ollama: #{inspect(error)}")
          Logger.error("Please ensure Ollama is running and accessible at http://localhost:11434")
          raise "Could not connect to Ollama server"
      end
    end
  end
end
