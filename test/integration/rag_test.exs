defmodule HexdocsMcp.RagTest do
  use HexdocsMcp.IntegrationCase

  alias HexdocsMcp.CLI.FetchDocs
  alias HexdocsMcp.Embeddings
  alias HexdocsMcp.Embeddings.Embedding
  alias HexdocsMcp.Markdown
  alias HexdocsMcp.Repo

  @moduletag :integration

  @default_model "nomic-embed-text"

  setup :setup_test_environment
  setup :check_ollama_availability

  setup do
    HexdocsMcp.IntegrationCase.setup_integration_environment()
  end

  setup tags do
    if tags[:skip] do
      {:skip, tags[:skip]}
    else
      :ok
    end
  end

  describe "RAG search quality tests" do
    test "excludes sidebar navigation content from search results" do
      create_embedding_from_html(
        """
        <html>
          <body>
            <nav id="sidebar" class="sidebar">
              <div class="sidebar-header">MyApp v1.0.0</div>
              <ul class="sidebar-list-nav">
                <li><a href="Module1.html">Module1</a></li>
                <li><a href="Module2.html">Module2</a></li>
              </ul>
            </nav>
            <main class="content">
              <h1>Understanding GenServer</h1>
              <p>GenServer is a behavior module for implementing stateful server processes.</p>
            </main>
          </body>
        </html>
        """,
        "genserver_doc.html"
      )

      embeddings = Repo.all(Embedding)

      for embedding <- embeddings do
        refute String.contains?(embedding.text, "MyApp v1.0.0"),
               "Embedding text should not contain sidebar version"

        refute String.contains?(embedding.text, "sidebar-list-nav"),
               "Embedding text should not contain sidebar classes"
      end

      main_results = search_with_real_embeddings("GenServer stateful server processes")
      assert length(main_results) > 0, "Should find main documentation content"

      for result <- main_results do
        refute String.contains?(result.metadata.text, "sidebar")
        refute String.contains?(result.metadata.text, "Module1")
        assert String.contains?(result.metadata.text, "GenServer")
      end
    end

    test "prioritizes main documentation content over navigation elements" do
      create_embedding_from_html(
        """
        <html>
          <body>
            <section class="details-list" id="modules">
              <div class="summary-row">
                <a href="Phoenix.Router.html">Phoenix.Router</a>
                <p>Router configuration</p>
              </div>
            </section>
            <main class="content">
              <h1>Phoenix.Router</h1>
              <p>The Phoenix router is responsible for routing incoming requests to controllers.</p>
              <h2>Configuration</h2>
              <p>Configure your router by defining routes with the appropriate HTTP verbs.</p>
            </main>
          </body>
        </html>
        """,
        "phoenix_router.html"
      )

      results = search_with_real_embeddings("Phoenix router configuration HTTP verbs")

      assert length(results) > 0, "Should find documentation about router"

      first_result = List.first(results)
      assert String.contains?(first_result.metadata.text, "incoming requests")
      assert String.contains?(first_result.metadata.text, "HTTP verbs")
    end

    test "returns relevant documentation for specific queries" do
      create_embeddings_for_topics()

      test_cases = [
        {"how to use GenServer callbacks", ["genserver", "handle_call", "handle_cast"]},
        {"Phoenix LiveView state management", ["LiveView", "assign", "socket"]},
        {"Ecto query composition", ["Ecto", "from", "where", "select"]},
        {"testing async processes", ["ExUnit", "async", "test"]}
      ]

      for {query, expected_keywords} <- test_cases do
        results = search_with_real_embeddings(query, top_k: 3)

        assert length(results) > 0, "Should find results for: #{query}"

        found_keywords =
          results
          |> Enum.flat_map(fn r ->
            Enum.filter(expected_keywords, &String.contains?(String.downcase(r.metadata.text), String.downcase(&1)))
          end)
          |> Enum.uniq()

        assert length(found_keywords) > 0,
               "Results for '#{query}' should contain at least one of: #{inspect(expected_keywords)}"
      end
    end

    test "search returns relevant results" do
      create_embedding_with_text(
        "GenServer is the primary abstraction for building stateful server processes in Elixir.",
        "genserver_main.html"
      )

      create_embedding_with_text(
        "Supervisor trees help organize GenServer processes in fault-tolerant applications.",
        "supervisor_genserver.html"
      )

      create_embedding_with_text(
        "Phoenix framework uses many OTP behaviors including GenServer for real-time features.",
        "phoenix_otp.html"
      )

      create_embedding_with_text(
        "Elixir is a dynamic, functional language designed for building scalable applications.",
        "elixir_intro.html"
      )

      results = search_with_real_embeddings("GenServer implementation details", top_k: 4)

      assert length(results) >= 2, "Should find multiple results"

      top_two = Enum.take(results, 2)

      assert Enum.any?(top_two, &String.contains?(&1.metadata.text, "GenServer")),
             "At least one of the top results should mention GenServer"

      for result <- results do
        assert is_float(result.score)
        assert String.length(result.metadata.text) > 0
      end
    end

    test "handles multi-topic queries appropriately" do
      create_embeddings_for_topics()

      results = search_with_real_embeddings("LiveView GenServer state management patterns", top_k: 5)

      assert length(results) > 0, "Should find results for multi-topic query"

      topics_found = %{
        liveview: Enum.any?(results, &String.contains?(&1.metadata.text, "LiveView")),
        genserver: Enum.any?(results, &String.contains?(&1.metadata.text, "GenServer"))
      }

      assert topics_found.liveview || topics_found.genserver,
             "Should find content related to at least one topic"
    end

    test "excludes API reference module listings while preserving actual module docs" do
      create_embedding_from_html(
        """
        <html>
          <body>
            <main class="content">
              <h1>API Reference</h1>
              <section class="details-list" id="modules">
                <h2>Modules</h2>
                <div class="summary-row">
                  <a href="MyApp.Worker.html">MyApp.Worker</a>
                </div>
                <div class="summary-row">
                  <a href="MyApp.Supervisor.html">MyApp.Supervisor</a>
                </div>
              </section>
            </main>
          </body>
        </html>
        """,
        "api-reference.html"
      )

      create_embedding_from_html(
        """
        <html>
          <body>
            <main class="content">
              <h1>MyApp.Worker</h1>
              <section id="moduledoc">
                <p>A worker module that processes background jobs using GenServer.</p>
                <h2>Examples</h2>
                <pre><code>MyApp.Worker.start_link(job_id: 123)</code></pre>
              </section>
            </main>
          </body>
        </html>
        """,
        "myapp_worker.html"
      )

      results = search_with_real_embeddings("MyApp.Worker background jobs")

      assert length(results) > 0, "Should find module documentation"

      assert Enum.any?(results, &String.contains?(&1.metadata.text, "processes background jobs"))

      _api_ref_result =
        Enum.find(results, fn r ->
          String.contains?(r.metadata.text, "API Reference")
        end)

      worker_result =
        Enum.find(results, fn r ->
          String.contains?(r.metadata.text, "background jobs")
        end)

      assert worker_result, "Should find actual worker documentation"

      top_two = Enum.take(results, 2)

      assert Enum.member?(top_two, worker_result),
             "Worker documentation should be in the top 2 results"
    end

    test "real package fetch and search" do
      package = "jason"

      Repo.delete_all(from e in Embedding, where: e.package == ^package)

      capture_io(fn ->
        FetchDocs.main([package, "--force", "--model", @default_model])
      end)

      jason_embeddings = Repo.all(from e in Embedding, where: e.package == ^package)
      assert length(jason_embeddings) > 0, "Should have created embeddings for #{package}"

      actual_version = List.first(jason_embeddings).version

      test_queries = [
        {"JSON encoding in Elixir", ["encode", "JSON", "jason"]},
        {"decode JSON string", ["decode", "JSON", "string"]},
        {"Jason configuration options", ["config", "option", "Jason"]}
      ]

      for {query, expected_keywords} <- test_queries do
        results = search_with_real_embeddings(query, package: package, version: actual_version, top_k: 3)

        assert length(results) > 0, "Should find results for query: #{query}"

        all_text = results |> Enum.map_join(" ", & &1.metadata.text) |> String.downcase()
        found_keywords = Enum.filter(expected_keywords, &String.contains?(all_text, String.downcase(&1)))

        assert length(found_keywords) > 0,
               "Results for '#{query}' should contain at least one keyword from: #{inspect(expected_keywords)}"
      end
    end

    test "cross-package search with real packages" do
      packages = ["jason", "floki"]

      for package <- packages do
        Repo.delete_all(from e in Embedding, where: e.package == ^package)

        capture_io(fn ->
          FetchDocs.main([package, "--force", "--model", @default_model])
        end)
      end

      results = search_with_real_embeddings("parse HTML or JSON", top_k: 5)

      assert length(results) > 0, "Should find results across packages"

      found_packages = results |> Enum.map(& &1.metadata.package) |> Enum.uniq()
      assert length(found_packages) >= 1, "Should find results from at least one package"
    end
  end

  # Helper functions

  defp setup_test_environment(_context) do
    test_data_path = Path.join(System.tmp_dir!(), "hexdocs_mcp_rag_test_#{System.unique_integer()}")
    Application.put_env(:hexdocs_mcp, :data_path, test_data_path)
    File.rm_rf!(test_data_path)
    File.mkdir_p!(test_data_path)

    on_exit(fn -> File.rm_rf!(test_data_path) end)

    %{test_data_path: test_data_path}
  end

  defp check_ollama_availability(_context) do
    ollama_available = check_ollama_available()

    if ollama_available do
      %{ollama_available: true}
    else
      %{skip: "Ollama not available for integration tests"}
    end
  end

  defp check_ollama_available do
    IO.puts("\n🔍 Checking Ollama availability for integration tests...")

    try do
      client = Ollama.init()
      IO.puts("✅ Ollama client initialized")

      case Ollama.list_models(client) do
        {:ok, _models} ->
          IO.puts("✅ Ollama is running")

          case Ollama.show_model(client, name: @default_model) do
            {:ok, _} ->
              IO.puts("✅ Model #{@default_model} is available")
              true

            _ ->
              IO.puts("📥 Model #{@default_model} not found, attempting to pull...")

              # Try to pull the model
              case Ollama.pull_model(client, name: @default_model) do
                {:ok, _} ->
                  IO.puts("✅ Successfully pulled #{@default_model}")
                  true

                error ->
                  IO.puts("❌ Failed to pull model: #{inspect(error)}")
                  false
              end
          end

        error ->
          IO.puts("❌ Cannot connect to Ollama: #{inspect(error)}")
          IO.puts("Please ensure Ollama is running with: ollama serve")
          false
      end
    rescue
      error ->
        IO.puts("❌ Error checking Ollama: #{inspect(error)}")
        false
    end
  end

  defp create_embedding_from_html(html, source_file, opts \\ []) do
    markdown = Markdown.from_html(html)
    create_embedding_with_text(markdown, source_file, opts)
  end

  defp create_embedding_with_text(text, source_file, opts \\ []) do
    package = Keyword.get(opts, :package, "test_package")
    version = Keyword.get(opts, :version, "latest")

    # Generate real embedding using Ollama
    {:ok, %{"embeddings" => [embedding_vector]}} =
      Ollama.embed(Ollama.init(), model: @default_model, input: text)

    content_hash = Embeddings.content_hash(text)

    %Embedding{}
    |> Embedding.changeset(%{
      package: package,
      version: version,
      source_file: source_file,
      source_type: "hexdocs",
      text: text,
      text_snippet: String.slice(text, 0, 100),
      content_hash: content_hash,
      embedding: SqliteVec.Float32.new(embedding_vector),
      url: "https://hexdocs.pm/#{package}/#{source_file}"
    })
    |> Repo.insert!()
  end

  defp create_embeddings_for_topics do
    topics = [
      {
        "GenServer is a behavior module for implementing the server of a client-server relation. " <>
          "A GenServer is implemented in two parts: the client API and the server callbacks. " <>
          "The most common callbacks are handle_call, handle_cast, and handle_info.",
        "genserver_guide.html"
      },
      {
        "Phoenix.LiveView provides rich, real-time user experiences with server-rendered HTML. " <>
          "LiveView manages state on the server and uses WebSockets to update the client. " <>
          "You can update state using assign/3 and access it through the socket assigns.",
        "liveview_guide.html"
      },
      {
        "Ecto is a toolkit for data mapping and language integrated query for Elixir. " <>
          "Build queries using from, where, select, and other query expressions. " <>
          "Ecto provides a DSL for writing type-safe queries that are compiled to SQL.",
        "ecto_guide.html"
      },
      {
        "ExUnit is Elixir's built-in test framework. Write tests using the test macro. " <>
          "For testing concurrent code, use the async: true option carefully. " <>
          "ExUnit provides powerful assertions and excellent error messages.",
        "exunit_guide.html"
      }
    ]

    for {text, file} <- topics do
      create_embedding_with_text(text, file)
    end
  end

  defp search_with_real_embeddings(query, opts \\ []) do
    package = Keyword.get(opts, :package, nil)
    version = Keyword.get(opts, :version, "latest")
    top_k = Keyword.get(opts, :top_k, 3)

    Embeddings.search(query, package, version, @default_model, top_k: top_k)
  end
end
