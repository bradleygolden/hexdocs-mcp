ExUnit.start(exclude: [:integration])
Ecto.Adapters.SQL.Sandbox.mode(HexdocsMcp.Repo, :manual)

# Mock definitions
Mox.defmock(HexdocsMcp.MockOllama, for: HexdocsMcp.Behaviours.Ollama)
Mox.defmock(HexdocsMcp.MockEmbeddings, for: HexdocsMcp.Behaviours.Embeddings)
Mox.defmock(HexdocsMcp.MockFetch, for: HexdocsMcp.Behaviours.CLI.Fetch)
Mox.defmock(HexdocsMcp.MockSearch, for: HexdocsMcp.Behaviours.CLI.Search)
Mox.defmock(HexdocsMcp.MockDocs, for: HexdocsMcp.Behaviours.Docs)
Mox.defmock(HexdocsMcp.MockMixDeps, for: HexdocsMcp.Behaviours.MixDeps)

# Set default mocks for testing
Application.put_env(:hexdocs_mcp, :ollama_client, HexdocsMcp.MockOllama)
Application.put_env(:hexdocs_mcp, :embeddings_module, HexdocsMcp.Embeddings)
Application.put_env(:hexdocs_mcp, :cli_module, HexdocsMcp.CLI)
Application.put_env(:hexdocs_mcp, :fetch_module, HexdocsMcp.MockFetch)
Application.put_env(:hexdocs_mcp, :search_module, HexdocsMcp.MockSearch)
Application.put_env(:hexdocs_mcp, :docs_module, HexdocsMcp.MockDocs)
Application.put_env(:hexdocs_mcp, :mix_deps_module, HexdocsMcp.MockMixDeps)
