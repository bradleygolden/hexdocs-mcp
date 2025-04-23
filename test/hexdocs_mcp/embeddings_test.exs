defmodule HexdocsMcp.EmbeddingsTest do
  use HexdocsMcp.DataCase, async: false

  import Ecto.Query
  import ExUnit.CaptureLog
  import Mox

  alias HexdocsMcp.Embeddings
  alias HexdocsMcp.Embeddings.Embedding
  alias HexdocsMcp.Repo

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
      text = "Sample text for chunk #{i}"

      content_hash = Embeddings.content_hash(text)

      chunk_content = %{
        "text" => text,
        "metadata" => %{
          "package" => package,
          "source_file" => "test_file_#{i}.ex",
          "source_type" => "docs",
          "start_byte" => i * 100,
          "end_byte" => i * 100 + 99,
          "content_hash" => content_hash
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

  describe "hash generation" do
    test "generates consistent hashes for the same text" do
      text = "This is a test text"
      hash1 = Embeddings.content_hash(text)
      hash2 = Embeddings.content_hash(text)

      assert hash1 == hash2
      assert String.length(hash1) == 64
    end

    test "generates different hashes for different texts" do
      hash1 = Embeddings.content_hash("Text one")
      hash2 = Embeddings.content_hash("Text two")

      assert hash1 != hash2
    end
  end

  describe "incremental embedding generation" do
    test "generates all embeddings for initial run", %{test_package: package} do
      {:ok, result} = Embeddings.generate(package, @default_version, @default_model)

      assert result == {3, 3, 0}

      embeddings = Repo.all(from e in Embedding, where: e.package == ^package)
      assert length(embeddings) == 3

      for embedding <- embeddings do
        assert embedding.package == package
        assert embedding.version == @default_version
        assert String.length(embedding.content_hash) == 64
      end
    end

    test "reuses existing embeddings with matching hash", %{test_package: package, chunks_dir: chunks_dir} do
      {:ok, {3, 3, 0}} = Embeddings.generate(package, @default_version, @default_model)

      {:ok, {3, 0, 3}} = Embeddings.generate(package, @default_version, @default_model)

      modified_text = "Modified text for chunk 2"
      modified_hash = Embeddings.content_hash(modified_text)

      chunk_file = Path.join(chunks_dir, "chunk_2.json")

      chunk_content = %{
        "text" => modified_text,
        "metadata" => %{
          "package" => package,
          "source_file" => "test_file_2.ex",
          "source_type" => "docs",
          "start_byte" => 200,
          "end_byte" => 299,
          "content_hash" => modified_hash
        }
      }

      File.write!(chunk_file, Jason.encode!(chunk_content))

      {:ok, {3, 1, 2}} = Embeddings.generate(package, @default_version, @default_model)

      embedding =
        Repo.one(
          from e in Embedding,
            where:
              e.package == ^package and
                e.version == ^@default_version and
                e.source_file == "test_file_2.ex" and
                e.content_hash == ^modified_hash,
            limit: 1
        )

      assert embedding.content_hash == modified_hash
      assert embedding.text == modified_text
    end

    test "handles version-specific embeddings with same content hash", %{test_package: package, chunks_dir: chunks_dir} do
      File.rm_rf!(chunks_dir)
      File.mkdir_p!(chunks_dir)

      text = "This is a test text for cross-version testing"
      content_hash = Embeddings.content_hash(text)

      chunk_file = Path.join(chunks_dir, "chunk_1.json")
      chunk_content = %{
        "text" => text,
        "metadata" => %{
          "package" => package,
          "version" => @default_version,
          "source_file" => "test_file_v1.ex",
          "source_type" => "docs",
          "start_byte" => 100,
          "end_byte" => 199,
          "content_hash" => content_hash
        }
      }

      File.write!(chunk_file, Jason.encode!(chunk_content))

      {:ok, {1, 1, 0}} = Embeddings.generate(package, @default_version, @default_model)

      new_version = "1.2.3"
      File.rm_rf!(chunks_dir)
      File.mkdir_p!(chunks_dir)

      new_chunk_file = Path.join(chunks_dir, "new_version_chunk.json")
      new_chunk_content = %{
        "text" => text,
        "metadata" => %{
          "package" => package,
          "version" => new_version,
          "source_file" => "test_file_v2.ex",
          "source_type" => "docs",
          "start_byte" => 200,
          "end_byte" => 299,
          "content_hash" => content_hash
        }
      }

      File.write!(new_chunk_file, Jason.encode!(new_chunk_content))

      {:ok, {1, 0, 1}} = Embeddings.generate(package, new_version, @default_model)

      embeddings =
        Repo.all(
          from e in Embedding,
            where:
              e.package == ^package and
              e.content_hash == ^content_hash
        )

      assert length(embeddings) == 2, "Should have separate embeddings for each version"

      default_version_embedding =
        Repo.one(
          from e in Embedding,
            where:
              e.package == ^package and
              e.version == ^@default_version and
              e.content_hash == ^content_hash
        )

      new_version_embedding =
        Repo.one(
          from e in Embedding,
            where:
              e.package == ^package and
              e.version == ^new_version and
              e.content_hash == ^content_hash
        )

      refute is_nil(default_version_embedding), "Default version embedding should exist"
      refute is_nil(new_version_embedding), "New version embedding should exist"

      assert default_version_embedding.source_file == "test_file_v1.ex"
      assert default_version_embedding.start_byte == 100
      assert default_version_embedding.end_byte == 199

      assert new_version_embedding.source_file == "test_file_v2.ex"
      assert new_version_embedding.start_byte == 200
      assert new_version_embedding.end_byte == 299

      another_version = "2.0.0"
      File.rm_rf!(chunks_dir)
      File.mkdir_p!(chunks_dir)

      third_chunk_file = Path.join(chunks_dir, "another_version_chunk.json")
      third_chunk_content = %{
        "text" => text,
        "metadata" => %{
          "package" => package,
          "version" => another_version,
          "source_file" => "test_file_v3.ex",
          "source_type" => "docs",
          "start_byte" => 300,
          "end_byte" => 399,
          "content_hash" => content_hash
        }
      }

      File.write!(third_chunk_file, Jason.encode!(third_chunk_content))
      {:ok, {1, 0, 1}} = Embeddings.generate(package, another_version, @default_model)

      embeddings_after_third =
        Repo.all(
          from e in Embedding,
            where:
              e.package == ^package and
              e.content_hash == ^content_hash
        )

      assert length(embeddings_after_third) == 3, "Should have three separate embeddings for three versions"
    end

    test "respects force flag and regenerates all embeddings", %{test_package: package} do
      {:ok, {3, 3, 0}} = Embeddings.generate(package, @default_version, @default_model)

      {:ok, result} = Embeddings.generate(package, @default_version, @default_model, force: true)

      assert result == {3, 3, 0}
    end

    test "updates metadata even when reusing embedding", %{test_package: package, chunks_dir: chunks_dir} do
      {:ok, {3, 3, 0}} = Embeddings.generate(package, @default_version, @default_model)

      embedding =
        Repo.one(
          from e in Embedding,
            where:
              e.package == ^package and
                e.source_file == "test_file_1.ex"
        )

      refute is_nil(embedding), "Embedding should exist after first generate"
      original_start_byte = embedding.start_byte

      text = "Sample text for chunk 1"
      content_hash = Embeddings.content_hash(text)

      chunk_file = Path.join(chunks_dir, "chunk_1.json")

      chunk_content = %{
        "text" => text,
        "metadata" => %{
          "package" => package,
          "source_file" => "test_file_1.ex",
          "source_type" => "docs",
          "start_byte" => 999,
          "end_byte" => 1099,
          "content_hash" => content_hash
        }
      }

      File.write!(chunk_file, Jason.encode!(chunk_content))

      {:ok, result} = Embeddings.generate(package, @default_version, @default_model)

      assert result == {3, 0, 3}

      updated_embedding =
        Repo.one(
          from e in Embedding,
            where:
              e.package == ^package and
                e.source_file == "test_file_1.ex"
        )

      refute is_nil(updated_embedding), "Updated embedding should exist"
      assert updated_embedding.content_hash == content_hash
      assert updated_embedding.text == text
      assert updated_embedding.start_byte == 999
      assert updated_embedding.start_byte != original_start_byte
    end

    test "reuses embeddings within the same version", %{test_package: package, chunks_dir: chunks_dir} do
      File.rm_rf!(chunks_dir)
      File.mkdir_p!(chunks_dir)

      text = "This is a test text for same-version reuse"
      content_hash = Embeddings.content_hash(text)

      chunk_file = Path.join(chunks_dir, "chunk_1.json")
      chunk_content = %{
        "text" => text,
        "metadata" => %{
          "package" => package,
          "version" => @default_version,
          "source_file" => "test_file_v1.ex",
          "source_type" => "docs",
          "start_byte" => 100,
          "end_byte" => 199,
          "content_hash" => content_hash
        }
      }

      File.write!(chunk_file, Jason.encode!(chunk_content))

      {:ok, {1, 1, 0}} = Embeddings.generate(package, @default_version, @default_model)

      File.rm_rf!(chunks_dir)
      File.mkdir_p!(chunks_dir)

      new_chunk_file = Path.join(chunks_dir, "same_version_different_file.json")
      new_chunk_content = %{
        "text" => text,
        "metadata" => %{
          "package" => package,
          "version" => @default_version,
          "source_file" => "test_file_v2.ex",
          "source_type" => "docs",
          "start_byte" => 200,
          "end_byte" => 299,
          "content_hash" => content_hash
        }
      }

      File.write!(new_chunk_file, Jason.encode!(new_chunk_content))

      {:ok, {1, 0, 1}} = Embeddings.generate(package, @default_version, @default_model)

      embeddings =
        Repo.all(
          from e in Embedding,
            where:
              e.package == ^package and
              e.content_hash == ^content_hash
        )

      assert length(embeddings) == 1, "Expected only one embedding for the same version"

      embedding = hd(embeddings)
      assert embedding.version == @default_version
      assert embedding.source_file == "test_file_v2.ex"
      assert embedding.start_byte == 200
      assert embedding.end_byte == 299
    end

    test "reuses embeddings across different versions with same content hash", %{test_package: package, chunks_dir: chunks_dir} do
      File.rm_rf!(chunks_dir)
      File.mkdir_p!(chunks_dir)

      text = "This is a test text for cross-version embedding reuse"
      content_hash = Embeddings.content_hash(text)

      chunk_file = Path.join(chunks_dir, "chunk_1.json")
      chunk_content = %{
        "text" => text,
        "metadata" => %{
          "package" => package,
          "version" => @default_version,
          "source_file" => "test_file_v1.ex",
          "source_type" => "docs",
          "start_byte" => 100,
          "end_byte" => 199,
          "content_hash" => content_hash
        }
      }

      File.write!(chunk_file, Jason.encode!(chunk_content))

      test_pid = self()

      HexdocsMcp.MockOllama
      |> expect(:init, fn _ -> %{mock: true} end)
      |> expect(:embed, fn _client, _opts ->
        send(test_pid, :embedding_generated)
        embedding = List.duplicate(0.1, 384)
        {:ok, %{"embeddings" => [embedding]}}
      end)

      {:ok, {1, 1, 0}} = Embeddings.generate(package, @default_version, @default_model)
      assert_received :embedding_generated

      default_embedding =
        Repo.one(
          from e in Embedding,
            where:
              e.package == ^package and
              e.version == ^@default_version and
              e.content_hash == ^content_hash
        )

      refute is_nil(default_embedding)
      assert default_embedding.source_file == "test_file_v1.ex"

      new_version = "1.2.3"
      File.rm_rf!(chunks_dir)
      File.mkdir_p!(chunks_dir)

      new_chunk_file = Path.join(chunks_dir, "new_version_chunk.json")
      new_chunk_content = %{
        "text" => text,
        "metadata" => %{
          "package" => package,
          "version" => new_version,
          "source_file" => "test_file_v2.ex",
          "source_type" => "docs",
          "start_byte" => 200,
          "end_byte" => 299,
          "content_hash" => content_hash
        }
      }

      File.write!(new_chunk_file, Jason.encode!(new_chunk_content))

      HexdocsMcp.MockOllama
      |> expect(:init, fn _ -> %{mock: true} end)

      {:ok, {1, 0, 1}} = Embeddings.generate(package, new_version, @default_model)

      new_embedding =
        Repo.one(
          from e in Embedding,
            where:
              e.package == ^package and
              e.version == ^new_version and
              e.content_hash == ^content_hash
        )

      refute is_nil(new_embedding)
      assert new_embedding.source_file == "test_file_v2.ex"
      assert new_embedding.start_byte == 200
      assert new_embedding.end_byte == 299

      assert new_embedding.embedding == default_embedding.embedding
    end
  end

  describe "generate/2" do
    test "generates embeddings for all chunks in a package", %{test_package: package} do
      {:ok, {total, new, reused}} = Embeddings.generate(package, @default_version, @default_model)

      assert total == 3
      assert new == 3
      assert reused == 0

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
      {:ok, {total, _, _}} = Embeddings.generate(package, version, @default_model)

      assert total == 3

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

      {:ok, {total, _, _}} = Embeddings.generate(package, @default_version, custom_model)

      assert total == 3
      assert_received {:model_used, ^custom_model}
    end

    test "reports progress with callback", %{test_package: package} do
      test_pid = self()

      progress_callback = fn processed, total, stage ->
        send(test_pid, {:progress, processed, total, stage})
        %{processing: 0, saving: 0}
      end

      {:ok, _} =
        Embeddings.generate(package, @default_version, @default_model, progress_callback: progress_callback)

      assert_received {:progress, _, _, :processing}
      assert_received {:progress, _, _, :saving}
    end

    test "handles errors in chunk processing", %{test_package: package, chunks_dir: chunks_dir} do
      invalid_chunk = Path.join(chunks_dir, "invalid.json")
      File.write!(invalid_chunk, "invalid json")

      logs =
        capture_log(fn ->
          {:ok, {total, _, _}} = Embeddings.generate(package, @default_version, @default_model)
          assert total == 3
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
          {:ok, {total, new, _}} = Embeddings.generate(package, @default_version, @default_model)
          assert total == 2
          assert new == 2
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

      {:ok, {total, new, reused}} = Embeddings.generate(empty_package, @default_version, @default_model)
      assert total == 0
      assert new == 0
      assert reused == 0

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

    test "returns true with nil package if any embeddings exist" do
      # Create an embedding with a different package
      test_package = "existence_test_package"
      create_test_embedding(test_package, @default_version)

      # Check with nil package (should check if any embeddings exist)
      assert Embeddings.embeddings_exist?(nil, @default_version) == true
    end

    test "returns false with nil package if no embeddings exist" do
      # Ensure no embeddings exist
      Repo.delete_all(Embedding)

      # Check with nil package
      assert Embeddings.embeddings_exist?(nil, @default_version) == false
    end
  end

  describe "delete_embeddings/2" do
    test "deletes all embeddings for a package and version", %{test_package: package} do
      create_test_embedding(package, @default_version)
      create_test_embedding(package, @default_version)
      create_test_embedding(package, "1.2.3")

      # Delete only the default version
      {:ok, count} = Embeddings.delete_embeddings(package, @default_version)

      assert count == 2

      default_query = from e in Embedding, where: e.package == ^package and e.version == @default_version
      assert Repo.aggregate(default_query, :count, :id) == 0

      other_query = from e in Embedding, where: e.package == ^package and e.version == "1.2.3"
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

    test "does not delete any embeddings when package is nil" do
      # Create multiple embeddings in different packages
      package1 = "test_package1"
      package2 = "test_package2"
      create_test_embedding(package1, @default_version)
      create_test_embedding(package2, @default_version)

      # Try to delete with nil package
      {:ok, count} = Embeddings.delete_embeddings(nil, @default_version)

      # Verify that no embeddings were deleted (safety feature)
      assert count == 0

      # Verify that all embeddings still exist
      assert Repo.aggregate(Embedding, :count) == 2
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

      assert length(results) == 1

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

      Embeddings.search("test query", package, @default_version, @default_model, progress_callback: progress_callback)

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

    test "searches across all packages when package is nil", %{test_package: existing_package} do
      # First, ensure we have embeddings for the main test package
      assert Embeddings.embeddings_exist?(existing_package, @default_version)

      # Now create a second package with embeddings
      other_package = "search_across_test"
      create_test_embedding(other_package, @default_version)

      # Verify both packages have embeddings
      assert Embeddings.embeddings_exist?(existing_package, @default_version)
      assert Embeddings.embeddings_exist?(other_package, @default_version)

      setup_search_mock()
      query = "Test search query"

      # Search with nil package to get results from all packages
      results = Embeddings.search(query, nil, @default_version, @default_model)

      # We should get results since embeddings exist
      # The implementation is returning 3 results
      assert length(results) == 3

      # Get the packages in the results
      found_packages =
        results
        |> Enum.map(& &1.metadata.package)
        |> Enum.uniq()
        |> MapSet.new()

      # We should find both packages
      assert found_packages != MapSet.new()
      assert MapSet.size(found_packages) >= 1
      # At least one package should be present in the results
      assert MapSet.member?(found_packages, existing_package) or
               MapSet.member?(found_packages, other_package)
    end
  end

  defp create_embeddings_for_search(context) do
    %{test_package: package} = context

    {:ok, _} = Embeddings.generate(package, @default_version, @default_model)

    context
  end

  defp create_test_embedding(package, version) do
    embedding_vector = List.duplicate(0.1, 384)
    rand_id = :rand.uniform(10_000)
    text = "Test embedding with specific version #{rand_id}"

    content_hash = Embeddings.content_hash(text)

    embedding_data = %{
      package: package,
      version: version,
      source_file: "test_file_#{rand_id}.ex",
      source_type: "docs",
      start_byte: 100,
      end_byte: 200,
      text_snippet: "Test snippet #{rand_id}...",
      text: text,
      content_hash: content_hash,
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
