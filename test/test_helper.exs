ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(HexdocsMcp.Repo, :manual)

# Mock definitions
Mox.defmock(HexdocsMcp.MockOllama, for: HexdocsMcp.OllamaBehaviour)
Mox.defmock(HexdocsMcp.MockEmbeddings, for: HexdocsMcp.EmbeddingsBehaviour)
Mox.defmock(HexdocsMcp.MockCLI, for: HexdocsMcp.CLIBehaviour)

# Set default mocks for testing
Application.put_env(:hexdocs_mcp, :ollama_client, HexdocsMcp.MockOllama)
Application.put_env(:hexdocs_mcp, :embeddings_module, HexdocsMcp.Embeddings)
Application.put_env(:hexdocs_mcp, :cli_module, HexdocsMcp.CLI)
