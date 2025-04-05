defmodule HexdocsMcp.CLITest do
  use HexdocsMcp.DataCase, async: true

  import ExUnit.CaptureIO
  import Mox

  alias HexdocsMcp.CLI
  alias HexdocsMcp.Embeddings.Embedding
  
  @default_model "nomic-embed-text"
  @default_version "latest"
  
  setup :verify_on_exit!
  setup :setup_test_environment
  setup :setup_ollama_mock
  
  defp setup_test_environment(_context) do
    test_data_path = Path.join(System.tmp_dir!(), "hexdocs_mcp_test")
    Application.put_env(:hexdocs_mcp, :data_path, test_data_path)
    test_package = "test_package"
    chunks_dir = Path.join([test_data_path, test_package, "chunks"])
    File.rm_rf(test_data_path)
    File.mkdir_p!(chunks_dir)
    
    %{
      test_package: test_package,
      chunks_dir: chunks_dir,
      test_data_path: test_data_path
    }
  end
  
  defp setup_ollama_mock(_context) do
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

    :ok
  end
  
  describe "fetch_and_process_docs/4" do
    test "uses cache when embeddings exist and force is false", %{test_package: package} do
      # Create a test embedding to simulate existing embeddings
      create_test_embedding(package, @default_version)
      
      output = capture_io(fn ->
        result = CLI.fetch_and_process_docs(package, @default_version, @default_model)
        
        assert result.cached == true
        assert result.package == package
        assert result.version == @default_version
      end)
      
      assert output =~ "already exist, skipping fetch"
      assert output =~ "Use --force to re-fetch"
    end
    
    test "processes docs when embeddings don't exist", %{test_package: package} do
      # Ensure no embeddings exist
      query = from e in Embedding, where: e.package == ^package
      Repo.delete_all(query)
      
      # Create a process_docs mock by defining a module behavior
      defmodule ProcessDocsMock do
        @behaviour HexdocsMcp.CLIBehaviour
        
        @impl true
        def process_docs(package, version, _model) do
          %{
            package: package,
            version: version || "latest",
            chunks_count: 3,
            embeddings_created: true
          }
        end
      end
      
      # Temporarily override the process_docs implementation
      original_process_docs = Application.get_env(:hexdocs_mcp, :cli_module, HexdocsMcp.CLI)
      Application.put_env(:hexdocs_mcp, :cli_module, ProcessDocsMock)
      
      try do
        output = capture_io(fn ->
          result = CLI.fetch_and_process_docs(package, @default_version, @default_model)
          
          assert result.package == package
          assert result.version == @default_version
          assert result.chunks_count == 3
          assert result.embeddings_created == true
        end)
        
        refute output =~ "already exist, skipping fetch"
      after
        # Restore the original implementation
        Application.put_env(:hexdocs_mcp, :cli_module, original_process_docs)
      end
    end
    
    test "forces processing when force=true, even when embeddings exist", %{test_package: package} do
      # Create a test embedding to simulate existing embeddings
      create_test_embedding(package, @default_version)
      
      # Mock the embeddings_exist? function first - needs to be done BEFORE we call fetch_and_process_docs
      expect(HexdocsMcp.MockEmbeddings, :embeddings_exist?, fn pkg, ver -> 
        assert pkg == package
        assert ver == @default_version
        true  # Return true, embeddings exist
      end)
      
      # Mock the delete_embeddings function
      expect(HexdocsMcp.MockEmbeddings, :delete_embeddings, fn pkg, ver -> 
        assert pkg == package
        assert ver == @default_version
        {:ok, 1}  # Return 1 embedding deleted
      end)
      
      # Mock the process_docs function
      expect(HexdocsMcp.MockCLI, :process_docs, fn pkg, ver, mdl -> 
        assert pkg == package
        assert ver == @default_version
        assert mdl == @default_model
        %{
          package: package,
          version: ver || "latest",
          chunks_count: 3,
          embeddings_created: true
        }
      end)
      
      # Override the module references
      original_embeddings_module = Application.get_env(:hexdocs_mcp, :embeddings_module, HexdocsMcp.Embeddings)
      original_cli_module = Application.get_env(:hexdocs_mcp, :cli_module, HexdocsMcp.CLI)
      
      Application.put_env(:hexdocs_mcp, :embeddings_module, HexdocsMcp.MockEmbeddings)
      Application.put_env(:hexdocs_mcp, :cli_module, HexdocsMcp.MockCLI)
      
      try do
        output = capture_io(fn ->
          result = CLI.fetch_and_process_docs(package, @default_version, @default_model, force: true)
          
          assert result.package == package
          assert result.version == @default_version
          assert result.chunks_count == 3
          assert result.embeddings_created == true
        end)
        
        assert output =~ "Removed 1 existing embeddings"
      after
        # Restore the original implementations
        Application.put_env(:hexdocs_mcp, :embeddings_module, original_embeddings_module)
        Application.put_env(:hexdocs_mcp, :cli_module, original_cli_module)
      end
    end
  end
  
  defp create_test_embedding(package, version) do
    embedding_vector = List.duplicate(0.1, 384)

    embedding_data = %{
      package: package,
      version: version,
      source_file: "test_file_#{:rand.uniform(1000)}.ex",
      source_type: "docs",
      start_byte: 100,
      end_byte: 200,
      text_snippet: "Test snippet #{:rand.uniform(1000)}...",
      text: "Test embedding with specific version #{:rand.uniform(1000)}",
      embedding: SqliteVec.Float32.new(embedding_vector)
    }

    %Embedding{}
    |> Embedding.changeset(embedding_data)
    |> Repo.insert!()
  end
end