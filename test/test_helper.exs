ExUnit.start(exclude: [:integration])
Ecto.Adapters.SQL.Sandbox.mode(HexdocsMcp.Repo, :manual)

# Mock definitions
Mox.defmock(HexdocsMcp.MockOllama, for: HexdocsMcp.Behaviours.Ollama)
Mox.defmock(HexdocsMcp.MockEmbeddings, for: HexdocsMcp.Behaviours.Embeddings)
Mox.defmock(HexdocsMcp.MockFetchDocs, for: HexdocsMcp.Behaviours.CLI.FetchDocs)
Mox.defmock(HexdocsMcp.MockSemanticSearch, for: HexdocsMcp.Behaviours.CLI.SemanticSearch)
Mox.defmock(HexdocsMcp.MockDocs, for: HexdocsMcp.Behaviours.Docs)
Mox.defmock(HexdocsMcp.MockMixDeps, for: HexdocsMcp.Behaviours.MixDeps)
Mox.defmock(HexdocsMcp.MockHexSearch, for: HexdocsMcp.Behaviours.HexSearch)
Mox.defmock(HexdocsMcp.MockFulltextSearch, for: HexdocsMcp.Behaviours.FulltextSearch)

# Set default mocks for testing
Application.put_env(:hexdocs_mcp, :ollama_client, HexdocsMcp.MockOllama)
Application.put_env(:hexdocs_mcp, :embeddings_module, HexdocsMcp.Embeddings)
Application.put_env(:hexdocs_mcp, :cli_module, HexdocsMcp.CLI)
Application.put_env(:hexdocs_mcp, :fetch_docs_module, HexdocsMcp.MockFetchDocs)
Application.put_env(:hexdocs_mcp, :search_module, HexdocsMcp.MockSemanticSearch)
Application.put_env(:hexdocs_mcp, :docs_module, HexdocsMcp.MockDocs)
Application.put_env(:hexdocs_mcp, :mix_deps_module, HexdocsMcp.MockMixDeps)
Application.put_env(:hexdocs_mcp, :hex_search_module, HexdocsMcp.MockHexSearch)
Application.put_env(:hexdocs_mcp, :fulltext_search_module, HexdocsMcp.MockFulltextSearch)
