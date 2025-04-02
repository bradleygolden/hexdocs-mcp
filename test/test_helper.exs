ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(HexdocsMcp.Repo, :manual)

Mox.defmock(HexdocsMcp.MockOllama, for: HexdocsMcp.OllamaBehaviour)
Application.put_env(:hexdocs_mcp, :ollama_client, HexdocsMcp.MockOllama)
