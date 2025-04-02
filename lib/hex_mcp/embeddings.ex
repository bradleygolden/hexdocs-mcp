defmodule HexMcp.Embeddings do
  @moduledoc """
  Functions for generating embeddings from markdown chunks using Ollama.
  """

  require Logger
  alias Jason
  alias HexMcp.Repo
  alias HexMcp.Schema.Embedding

  @doc """
  Generate embeddings for all chunks in a package and store them in SQLite.

  ## Parameters
    * `package` - The name of the package
    * `version` - (Optional) The version of the package, defaults to "latest"
    * `model` - (Optional) The Ollama model to use, defaults to "nomic-embed-text"
  """
  def generate_embeddings(package, version \\ nil, model \\ "nomic-embed-text") do
    version_str = version || "latest"
    chunks_dir = Path.join([".hex_mcp", package, "chunks"])

    # Get all JSON chunk files
    chunk_files = Path.wildcard(Path.join(chunks_dir, "*.json"))

    client = Ollama.init()

    total_chunks = length(chunk_files)

    # Show initial progress message
    Mix.shell().info("Generating embeddings for #{total_chunks} chunks...")

    # Process files in batches with progress indicators
    HexMcp.Progress.with_spinner("Preparing embeddings", fn ->
      # Initialize the progress function at the top level
      progress_fn = HexMcp.Progress.progress_bar("Processing embeddings", total_chunks)
      Process.put(:embedding_progress_fn, progress_fn)
      # Initial update
      progress_fn.(0)

      chunk_files
      # Process in batches of 10 files
      |> Enum.chunk_every(10)
      |> Enum.reduce({0, [], 0}, fn batch, {successful_count, changesets, processed_count} ->
        # Get the current progress function from process dictionary
        progress_fn = Process.get(:embedding_progress_fn)

        # Create progress function if it doesn't exist yet (this should never happen now)
        if is_nil(progress_fn) do
          progress_fn = HexMcp.Progress.progress_bar("Processing embeddings", total_chunks)
          Process.put(:embedding_progress_fn, progress_fn)
          # Initial update
          progress_fn.(0)
        end

        # Update progress less frequently
        if rem(processed_count, 20) == 0 do
          progress_fn.(processed_count)
        end

        # Process each batch
        batch_results =
          Task.async_stream(
            batch,
            fn chunk_file ->
              with {:ok, chunk_json} <- File.read(chunk_file),
                   {:ok, chunk_data} <- Jason.decode(chunk_json),
                   text = chunk_data["text"],
                   metadata = chunk_data["metadata"],
                   {:ok, response} <- Ollama.embed(client, model: model, input: text) do
                # Extract the embedding from the response
                Logger.debug("Ollama response for #{chunk_file}: #{inspect(response)}")

                embedding =
                  case response["embeddings"] do
                    nil ->
                      Logger.error("No embeddings in response for #{chunk_file}")
                      nil

                    [first_embedding | _] ->
                      # The API returns an array with a single embedding array
                      first_embedding

                    _ ->
                      Logger.error("Unexpected embeddings format in response for #{chunk_file}")
                      nil
                  end

                if embedding do
                  # Create text snippet
                  text_snippet =
                    if String.length(text) > 100 do
                      String.slice(text, 0, 100) <> "..."
                    else
                      text
                    end

                  # Create embedding record changeset
                  changeset =
                    Embedding.changeset(%Embedding{}, %{
                      package: metadata["package"],
                      version: metadata["version"] || "latest",
                      source_file: metadata["source_file"],
                      source_type: metadata["source_type"],
                      start_byte: metadata["start_byte"],
                      end_byte: metadata["end_byte"],
                      text_snippet: text_snippet,
                      text: text,
                      vector: HexMcp.Vector.encode_vector(embedding)
                    })

                  {:ok, changeset}
                else
                  {:error, :no_embedding}
                end
              else
                error ->
                  Logger.error("Error processing #{chunk_file}: #{inspect(error)}")
                  {:error, error}
              end
            end,
            max_concurrency: 4,
            timeout: 30_000
          )
          |> Enum.to_list()

        # Extract successful changesets and update count
        {new_changesets, new_count} =
          batch_results
          |> Enum.reduce({[], 0}, fn
            {:ok, {:ok, changeset}}, {acc_changesets, acc_count} ->
              {[changeset | acc_changesets], acc_count + 1}

            _, acc ->
              acc
          end)

        # Update progress after batch
        # Calculate actual count of items processed (even failed ones)
        new_processed_count = processed_count + length(batch)

        # Progress function has built-in update limiting now
        # so we can call it more frequently without causing flashing
        progress_fn = Process.get(:embedding_progress_fn)

        if !is_nil(progress_fn) do
          progress_fn.(new_processed_count)
        end

        # Combine with existing results
        {successful_count + new_count, changesets ++ new_changesets, new_processed_count}
      end)
      |> then(fn {count, changesets, total_processed} ->
        # Make sure to show final progress
        progress_fn = Process.get(:embedding_progress_fn)

        if !is_nil(progress_fn) do
          progress_fn.(total_processed)
          Process.delete(:embedding_progress_fn)
        end

        {count, changesets}
      end)
    end)
    |> then(fn {count, changesets} ->
      # Insert all changesets in one batch transaction for better performance
      if length(changesets) > 0 do
        HexMcp.Progress.with_spinner(
          "Inserting #{length(changesets)} embeddings into SQLite database...",
          fn ->
            # Use a transaction for better performance and consistency
            Repo.transaction(fn ->
              progress_fn = HexMcp.Progress.progress_bar("Saving embeddings", length(changesets))

              # The progress function now handles update frequency internally
              changesets
              |> Enum.with_index(1)
              |> Enum.each(fn {changeset, idx} ->
                Repo.insert!(changeset)
                # Call the progress function more frequently - it will throttle itself
                if rem(idx, 10) == 0, do: progress_fn.(idx)
              end)

              # Final update to show 100%
              progress_fn.(length(changesets))
            end)
          end
        )
      end

      Mix.shell().info(
        "Successfully generated and stored #{count} embeddings for #{package} #{version_str}"
      )

      {:ok, count}
    end)
  end

  @doc """
  Search for similar text in embeddings using SQLite.

  ## Parameters
    * `query` - The search query
    * `package` - The name of the package to search in
    * `version` - (Optional) The version of the package, defaults to "latest"
    * `model` - (Optional) The Ollama model to use, defaults to "nomic-embed-text"
    * `top_k` - (Optional) Number of results to return, defaults to 3
    * `use_sqlite` - (Optional) Whether to use SQLite for search, defaults to true
  """
  def search(
        query,
        package,
        version \\ nil,
        model \\ "nomic-embed-text",
        top_k \\ 3,
        use_sqlite \\ true
      ) do
    if use_sqlite do
      search_sqlite(query, package, version, model, top_k)
    else
      search_json_files(query, package, version, model, top_k)
    end
  end

  # Search using SQLite vector database
  defp search_sqlite(query, package, version, model, top_k) do
    Mix.shell().info("Searching for \"#{query}\" in SQLite database...")

    client =
      HexMcp.Progress.with_spinner("Initializing Ollama client", fn ->
        Ollama.init()
      end)

    # Generate query embedding with progress indicator
    embedding_result =
      HexMcp.Progress.with_spinner("Generating query embedding", fn ->
        case Ollama.embed(client, model: model, input: query) do
          {:ok, query_response} ->
            query_embedding =
              case query_response do
                %{"embedding" => embedding} ->
                  embedding

                %{"embeddings" => [embedding | _]} ->
                  embedding

                _ ->
                  Logger.error("Unexpected response format: #{inspect(query_response)}")
                  nil
              end

            {:ok, query_embedding}

          error ->
            Logger.error("Error generating query embedding: #{inspect(error)}")
            {:error, error}
        end
      end)

    case embedding_result do
      {:ok, query_vector} when not is_nil(query_vector) ->
        # Use optimized query builder to get embeddings
        embeddings = HexMcp.Vector.query_embeddings_optimized(package, version) |> Repo.all()

        total_embeddings = length(embeddings)
        Mix.shell().info("Found #{total_embeddings} embeddings to search through")

        # Create progress agent
        {:ok, progress_agent} = Agent.start_link(fn -> 0 end)
        # Create progress function
        progress_fn =
          HexMcp.Progress.progress_bar("Computing similarity scores", total_embeddings)

        # Start similarity calculation
        results =
          HexMcp.Progress.with_spinner("Calculating similarity scores", fn ->
            # Process in batches for better memory usage
            embeddings_with_similarity =
              embeddings
              # Use Stream to avoid rebuilding a large list in memory
              |> Stream.with_index(1)
              |> Task.async_stream(
                fn {embedding, idx} ->
                  vector = HexMcp.Vector.decode_vector(embedding.vector)
                  similarity = cosine_similarity(query_vector, vector)

                  # Increment progress counter
                  Agent.update(progress_agent, fn count -> count + 1 end)

                  # The progress_fn now limits updates internally to avoid flashing
                  # So we can call it more frequently without causing issues
                  if rem(idx, 25) == 0 do
                    count = Agent.get(progress_agent, fn count -> count end)
                    progress_fn.(count)
                  end

                  Map.put(embedding, :similarity, similarity)
                end,
                # Adjust based on your system
                max_concurrency: 4,
                # Longer timeout for larger datasets
                timeout: 30_000
              )
              |> Stream.map(fn {:ok, result} -> result end)
              |> Enum.sort_by(fn %{similarity: score} -> score end, :desc)

            # Clean up the progress agent
            Agent.stop(progress_agent)

            # Return the top k results with similarity scores
            embeddings_with_similarity
            |> Enum.take(top_k)
            |> Enum.map(fn embedding ->
              %{
                score: embedding.similarity,
                metadata: %{
                  id: embedding.id,
                  package: embedding.package,
                  version: embedding.version,
                  source_file: embedding.source_file,
                  text_snippet: embedding.text_snippet
                }
              }
            end)
          end)

        results

      {:ok, nil} ->
        Mix.shell().error("Could not generate query embedding")
        []

      {:error, error} ->
        Logger.error("Error processing query embedding: #{inspect(error)}")
        []
    end
  end

  # Original JSON file-based search implementation - kept for backward compatibility
  defp search_json_files(query, package, _version, model, top_k) do
    embeddings_dir = Path.join([".hex_mcp", package, "embeddings"])

    # Load saved embeddings
    embeddings_path = Path.join(embeddings_dir, "embeddings.json")
    metadata_path = Path.join(embeddings_dir, "metadata.json")

    with {:ok, embeddings_json} <- File.read(embeddings_path),
         {:ok, embeddings} <- Jason.decode(embeddings_json),
         {:ok, metadata_json} <- File.read(metadata_path),
         {:ok, metadata} <- Jason.decode(metadata_json) do
      client = Ollama.init()
      # Generate query embedding
      case Ollama.embed(client, model: model, input: query) do
        {:ok, query_response} ->
          query_embedding = query_response["embedding"]

          # Calculate cosine similarities and sort results
          results =
            embeddings
            |> Enum.zip(metadata)
            |> Enum.map(fn {embedding, meta} ->
              similarity = cosine_similarity(query_embedding, embedding)
              %{score: similarity, metadata: atomize_keys(meta)}
            end)
            |> Enum.sort_by(fn %{score: score} -> score end, :desc)
            |> Enum.take(top_k)

          results

        error ->
          Logger.error("Error generating query embedding: #{inspect(error)}")
          []
      end
    else
      error ->
        Logger.error("Error searching embeddings: #{inspect(error)}")
        []
    end
  end

  # Helper function to calculate cosine similarity between two vectors
  defp cosine_similarity(vec1, vec2) do
    dot_product = Enum.zip(vec1, vec2) |> Enum.reduce(0, fn {a, b}, sum -> sum + a * b end)

    # Calculate magnitudes
    mag1 = :math.sqrt(Enum.reduce(vec1, 0, fn x, sum -> sum + x * x end))
    mag2 = :math.sqrt(Enum.reduce(vec2, 0, fn x, sum -> sum + x * x end))

    case mag1 * mag2 do
      # Match both positive and negative zero to avoid division by zero
      +0.0 -> 0
      -0.0 -> 0
      product -> dot_product / product
    end
  end

  # Helper function to convert string keys to atoms
  defp atomize_keys(map) do
    Map.new(map, fn {k, v} -> {String.to_atom(k), v} end)
  end
end
