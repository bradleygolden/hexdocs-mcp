defmodule HexdocsMcp.EmbeddingsTest do
  use HexdocsMcp.DataCase, async: true

  import Ecto.Query
  import ExUnit.CaptureLog
  import Mox

  alias HexdocsMcp.Embeddings
  alias HexdocsMcp.Embeddings.Embedding

  @default_model "nomic-embed-text"
  @default_version "latest"

  setup :verify_on_exit!
  setup :setup_test_environment
  setup :setup_ollama_mock

  defp setup_test_environment(context \\ %{}) do
    test_data_path = Path.join(System.tmp_dir!(), "hexdocs_mcp_test")
    Application.put_env(:hexdocs_mcp, :data_path, test_data_path)
    test_package = "test_package"
    chunks_dir = Path.join([test_data_path, test_package, "chunks"])
    File.rm_rf(test_data_path)
    File.mkdir_p!(chunks_dir)
    create_test_chunks(chunks_dir, test_package)

    Map.merge(context, %{
      test_package: test_package,
      chunks_dir: chunks_dir,
      test_data_path: test_data_path
    })
  end

  defp create_test_chunks(chunks_dir, package) do
    for i <- 1..3 do
      chunk_file = Path.join(chunks_dir, "chunk_#{i}.json")

      chunk_content = %{
        "text" => "Sample text for chunk #{i}",
        "metadata" => %{
          "package" => package,
          "source_file" => "test_file_#{i}.ex",
          "source_type" => "docs",
          "start_byte" => i * 100,
          "end_byte" => i * 100 + 99
        }
      }

      File.write!(chunk_file, Jason.encode!(chunk_content))
    end
  end

  defp setup_ollama_mock(context) do
    HexdocsMcp.MockOllama
    |> stub(:init, fn _ -> %{mock: true} end)
    |> stub(:embed, fn _client, opts ->
      embedding = List.duplicate(0.1, 384)

      {:ok,
       %{
         "model" => Keyword.get(opts, :model),
         "embeddings" => [embedding]
       }}
    end)

    context
  end

  describe "generate/2" do
    test "generates embeddings for all chunks in a package", %{test_package: package} do
      {:ok, count} = Embeddings.generate(package, @default_version, @default_model)

      assert count == 3
      embeddings = Repo.all(from e in Embedding, where: e.package == ^package)
      assert length(embeddings) == 3

      for embedding <- embeddings do
        assert embedding.package == package
        assert embedding.version == "latest"
        assert embedding.source_file =~ "test_file_"
        assert embedding.source_type == "docs"
        assert embedding.text =~ "Sample text for chunk"
        assert not is_nil(embedding.embedding)
      end
    end

    test "generates embeddings with specific version", %{test_package: package} do
      version = "1.0.0"
      {:ok, count} = Embeddings.generate(package, version, @default_model)

      assert count == 3

      embeddings =
        Repo.all(from e in Embedding, where: e.package == ^package and e.version == ^version)

      assert length(embeddings) == 3

      for embedding <- embeddings do
        assert embedding.version == version
      end
    end

    test "generates embeddings with custom model", %{test_package: package} do
      test_pid = self()
      custom_model = "all-minilm"

      expect(HexdocsMcp.MockOllama, :embed, 3, fn _client, opts ->
        send(test_pid, {:model_used, Keyword.get(opts, :model)})
        embedding = List.duplicate(0.1, 384)
        {:ok, %{"model" => Keyword.get(opts, :model), "embeddings" => [embedding]}}
      end)

      {:ok, count} = Embeddings.generate(package, @default_version, custom_model)

      assert count == 3
      assert_received {:model_used, ^custom_model}
    end

    test "reports progress with callback", %{test_package: package} do
      test_pid = self()

      progress_callback = fn processed, total, stage ->
        send(test_pid, {:progress, processed, total, stage})
        %{processing: 0, saving: 0}
      end

      {:ok, _count} =
        Embeddings.generate(package, @default_version, @default_model,
          progress_callback: progress_callback
        )

      assert_received {:progress, _, _, :processing}
      assert_received {:progress, _, _, :saving}
    end

    test "handles errors in chunk processing", %{test_package: package, chunks_dir: chunks_dir} do
      invalid_chunk = Path.join(chunks_dir, "invalid.json")
      File.write!(invalid_chunk, "invalid json")

      logs =
        capture_log(fn ->
          {:ok, count} = Embeddings.generate(package, @default_version, @default_model)
          assert count == 3
        end)

      assert logs =~ "Error processing"
      embeddings = Repo.all(from e in Embedding, where: e.package == ^package)
      assert length(embeddings) == 3
    end

    test "handles embedding generation errors" do
      %{test_package: package} = setup_test_environment()

      HexdocsMcp.MockOllama
      |> expect(:init, fn _ -> %{mock: true} end)
      |> expect(:embed, 3, fn _client, opts ->
        case opts[:input] do
          "Sample text for chunk 2" ->
            {:error, %{reason: "Embedding failed for this chunk"}}

          _ ->
            embedding = List.duplicate(0.1, 384)
            {:ok, %{"model" => opts[:model], "embeddings" => [embedding]}}
        end
      end)

      logs =
        capture_log(fn ->
          {:ok, count} = Embeddings.generate(package, @default_version, @default_model)
          assert count == 2
        end)

      assert logs =~ "Error processing"
      embeddings = Repo.all(from e in Embedding, where: e.package == ^package)
      assert length(embeddings) == 2
    end

    test "handles empty changesets" do
      test_data_path = Path.join(System.tmp_dir!(), "hexdocs_mcp_test")
      empty_package = "empty_package"
      empty_chunks_dir = Path.join([test_data_path, empty_package, "chunks"])
      File.mkdir_p!(empty_chunks_dir)

      {:ok, count} = Embeddings.generate(empty_package, @default_version, @default_model)
      assert count == 0

      embeddings = Repo.all(from e in Embedding, where: e.package == ^empty_package)
      assert Enum.empty?(embeddings)
    end
  end

  describe "embeddings_exist?/2" do
    test "returns true when embeddings exist for package and version", %{test_package: package} do
      # Create an embedding first
      create_test_embedding(package, @default_version)

      # Check if it exists
      assert Embeddings.embeddings_exist?(package, @default_version) == true
    end

    test "returns false when no embeddings exist for package", %{test_package: package} do
      # Ensure no embeddings for this package
      Repo.delete_all(from e in Embedding, where: e.package == ^package)

      # Check if it exists
      assert Embeddings.embeddings_exist?(package, @default_version) == false
    end

    test "returns false when embeddings exist for package but different version", %{
      test_package: package
    } do
      # Create an embedding with a specific version
      other_version = "1.2.3"
      create_test_embedding(package, other_version)

      # Check if default version exists (it should not)
      assert Embeddings.embeddings_exist?(package, @default_version) == false
    end

    test "handles nil version by using 'latest'", %{test_package: package} do
      # Create an embedding with the default version
      create_test_embedding(package, @default_version)

      # Check with nil version (should convert to "latest")
      assert Embeddings.embeddings_exist?(package, nil) == true
    end
  end

  describe "delete_embeddings/2" do
    test "deletes all embeddings for a package and version", %{test_package: package} do
      # Create multiple embeddings
      create_test_embedding(package, @default_version)
      create_test_embedding(package, @default_version)
      create_test_embedding(package, "1.2.3")

      # Verify we have the expected counts
      default_query =
        from e in Embedding, where: e.package == ^package and e.version == ^@default_version

      other_query = from e in Embedding, where: e.package == ^package and e.version == "1.2.3"

      assert Repo.aggregate(default_query, :count, :id) == 2
      assert Repo.aggregate(other_query, :count, :id) == 1

      # Delete only the default version embeddings
      {:ok, count} = Embeddings.delete_embeddings(package, @default_version)

      # Verify the result
      assert count == 2
      assert Repo.aggregate(default_query, :count, :id) == 0
      assert Repo.aggregate(other_query, :count, :id) == 1
    end

    test "handles nil version by using 'latest'", %{test_package: package} do
      # Create an embedding with the default version
      create_test_embedding(package, @default_version)

      # Delete with nil version (should convert to "latest")
      {:ok, count} = Embeddings.delete_embeddings(package, nil)

      # Verify the result
      assert count == 1

      default_query =
        from e in Embedding, where: e.package == ^package and e.version == ^@default_version

      assert Repo.aggregate(default_query, :count, :id) == 0
    end

    test "returns 0 count when no embeddings match criteria", %{test_package: package} do
      # Create an embedding with a different version
      create_test_embedding(package, "1.2.3")

      # Try to delete a non-existent version
      {:ok, count} = Embeddings.delete_embeddings(package, @default_version)

      # Verify the result
      assert count == 0

      # Original embedding should still exist
      other_query = from e in Embedding, where: e.package == ^package and e.version == "1.2.3"
      assert Repo.aggregate(other_query, :count, :id) == 1
    end
  end

  describe "search/3" do
    setup :create_embeddings_for_search

    test "searches for similar text using default options", %{test_package: package} do
      setup_search_mock()
      query = "Test search query"

      results = Embeddings.search(query, package, @default_version, @default_model)

      assert length(results) == 3

      [first_result | _] = results
      assert Map.has_key?(first_result, :score)
      assert Map.has_key?(first_result, :metadata)
      assert Map.has_key?(first_result.metadata, :id)
      assert Map.has_key?(first_result.metadata, :package)
      assert Map.has_key?(first_result.metadata, :version)
      assert Map.has_key?(first_result.metadata, :source_file)
      assert Map.has_key?(first_result.metadata, :text_snippet)
    end

    test "searches for similar text with specific version", %{test_package: package} do
      setup_search_mock()
      query = "Test search query"
      version = "1.0.0"

      create_test_embedding(package, version)

      results = Embeddings.search(query, package, version, @default_model)

      assert length(results) > 0

      for result <- results do
        assert result.metadata.version == version
      end
    end

    test "searches with custom model", %{test_package: package} do
      test_pid = self()
      custom_model = "all-minilm"

      HexdocsMcp.MockOllama
      |> expect(:init, fn _ -> %{mock: true} end)
      |> expect(:embed, fn _client, opts ->
        send(test_pid, {:model_used, Keyword.get(opts, :model)})
        embedding = List.duplicate(0.1, 384)
        {:ok, %{"model" => opts[:model], "embeddings" => [embedding]}}
      end)

      Embeddings.search("test query", package, @default_version, custom_model)

      assert_received {:model_used, ^custom_model}
    end

    test "limits results based on top_k option", %{test_package: package} do
      setup_search_mock()
      query = "Test search query"
      top_k = 2

      results = Embeddings.search(query, package, @default_version, @default_model, top_k: top_k)

      assert length(results) == top_k
    end

    test "reports search progress with callback", %{test_package: package} do
      setup_search_mock()
      test_pid = self()

      progress_callback = fn processed, total, stage ->
        send(test_pid, {:search_progress, processed, total, stage})
        %{generating: 0, searching: 0}
      end

      Embeddings.search("test query", package, @default_version, @default_model,
        progress_callback: progress_callback
      )

      assert_received {:search_progress, _, _, :generating}
      assert_received {:search_progress, _, _, :searching}
    end

    test "handles error in generating query embedding", %{test_package: package} do
      HexdocsMcp.MockOllama
      |> expect(:init, fn _ -> %{mock: true} end)
      |> expect(:embed, fn _client, _opts ->
        {:error, %{reason: "Failed to generate embedding"}}
      end)

      logs =
        capture_log(fn ->
          results = Embeddings.search("error query", package, @default_version, @default_model)
          assert Enum.empty?(results)
        end)

      assert logs =~ "Error generating query embedding"
    end

    test "handles empty result when no embeddings match", %{test_package: package} do
      Repo.delete_all(Embedding)

      setup_search_mock()
      results = Embeddings.search("no matches", package, @default_version, @default_model)

      assert Enum.empty?(results)
    end
  end

  defp create_embeddings_for_search(context) do
    %{test_package: package} = context

    {:ok, _} = Embeddings.generate(package, @default_version, @default_model)

    context
  end

  defp create_test_embedding(package, version) do
    embedding_vector = List.duplicate(0.1, 384)
    rand_id = :rand.uniform(10000) 

    embedding_data = %{
      package: package,
      version: version,
      source_file: "test_file_#{rand_id}.ex",
      source_type: "docs",
      start_byte: 100,
      end_byte: 200,
      text_snippet: "Test snippet #{rand_id}...",
      text: "Test embedding with specific version #{rand_id}",
      embedding: SqliteVec.Float32.new(embedding_vector)
    }

    %Embedding{}
    |> Embedding.changeset(embedding_data)
    |> Repo.insert!()
  end

  defp setup_search_mock do
    HexdocsMcp.MockOllama
    |> expect(:init, fn _ -> %{mock: true} end)
    |> expect(:embed, fn _client, _opts ->
      embedding = List.duplicate(0.1, 384)
      {:ok, %{"embeddings" => [embedding]}}
    end)
  end
end
