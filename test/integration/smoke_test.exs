defmodule HexdocsMcp.SmokeTest do
  @moduledoc """
  Smoke tests for verifying basic RAG functionality.
  These tests use actual Ollama when available.
  """
  use HexdocsMcp.IntegrationCase

  alias HexdocsMcp.Embeddings
  alias HexdocsMcp.Embeddings.Embedding
  alias HexdocsMcp.Repo

  @moduletag :integration

  @test_model "nomic-embed-text"
  @smoke_test_package "hexdocs_mcp_smoke_test"

  setup do
    HexdocsMcp.IntegrationCase.setup_integration_environment()

    ollama_available = check_ollama_available()

    if ollama_available do
      %{ollama_available: true}
    else
      %{skip: "Ollama not available for smoke tests"}
    end
  end

  setup tags do
    if tags[:skip] do
      {:skip, tags[:skip]}
    else
      :ok
    end
  end

  describe "basic RAG functionality" do
    test "can generate embeddings and search for content" do
      test_docs = [
        %{
          text: "Elixir is a dynamic, functional language designed for building maintainable and scalable applications.",
          file: "elixir_intro.html"
        },
        %{
          text: "GenServer is a behavior module for implementing stateful server processes in Elixir.",
          file: "genserver.html"
        },
        %{
          text: "Phoenix LiveView enables rich, real-time user experiences with server-rendered HTML.",
          file: "liveview.html"
        }
      ]

      for %{text: text, file: file} <- test_docs do
        create_test_embedding(text, file)
      end

      search_tests = [
        {"what is Elixir?", ["Elixir", "functional", "language"]},
        {"GenServer behavior", ["GenServer", "behavior", "processes"]},
        {"LiveView real-time", ["LiveView", "real-time", "HTML"]}
      ]

      for {query, expected_keywords} <- search_tests do
        results = Embeddings.search(query, @smoke_test_package, "latest", @test_model, top_k: 2)

        assert length(results) > 0, "Should find results for query: #{query}"

        # Check that results contain expected keywords
        all_text = Enum.map_join(results, " ", & &1.metadata.text)

        found_keywords = Enum.filter(expected_keywords, &String.contains?(all_text, &1))

        assert length(found_keywords) > 0,
               "Results should contain at least one keyword from: #{inspect(expected_keywords)}"
      end
    end

    test "search relevance ranking works correctly" do
      docs = [
        %{
          text: "GenServer callbacks: handle_call, handle_cast, and handle_info are the main callbacks.",
          file: "genserver_callbacks.html",
          relevance: :high
        },
        %{
          text: "Supervisors work with GenServer processes to build fault-tolerant applications.",
          file: "supervisor_genserver.html",
          relevance: :medium
        },
        %{
          text: "Elixir processes are lightweight and isolated from each other.",
          file: "processes.html",
          relevance: :low
        }
      ]

      for %{text: text, file: file} <- docs do
        create_test_embedding(text, file)
      end

      results =
        Embeddings.search(
          "GenServer callbacks implementation",
          @smoke_test_package,
          "latest",
          @test_model,
          top_k: 3
        )

      assert length(results) >= 2, "Should find multiple results"

      top_result = List.first(results)

      assert String.contains?(top_result.metadata.text, "handle_call") ||
               String.contains?(top_result.metadata.text, "handle_cast") ||
               String.contains?(top_result.metadata.text, "GenServer"),
             "Top result should be highly relevant to GenServer callbacks"
    end
  end

  # Helper functions

  defp check_ollama_available do
    client = Ollama.init()

    case Ollama.list_models(client) do
      {:ok, _models} ->
        case Ollama.show_model(client, name: @test_model) do
          {:ok, _} ->
            true

          _ ->
            case Ollama.pull_model(client, name: @test_model) do
              {:ok, _} -> true
              _ -> false
            end
        end

      _ ->
        false
    end
  rescue
    _ -> false
  end

  defp create_test_embedding(text, file) do
    {:ok, %{"embeddings" => [embedding_vector]}} =
      Ollama.embed(Ollama.init(), model: @test_model, input: text)

    content_hash = Embeddings.content_hash(text)

    %Embedding{}
    |> Embedding.changeset(%{
      package: @smoke_test_package,
      version: "latest",
      source_file: file,
      source_type: "test",
      text: text,
      text_snippet: String.slice(text, 0, 100),
      content_hash: content_hash,
      embedding: SqliteVec.Float32.new(embedding_vector),
      url: "https://example.com/#{file}"
    })
    |> Repo.insert!()
  end
end
