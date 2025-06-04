defmodule HexdocsMcp.IntegrationCase do
  @moduledoc """
  Test case template for integration tests that need to use real implementations
  instead of mocks.

  This configures the application to use real implementations for the modules
  needed by integration tests, and provides isolation by storing/restoring
  the original configuration.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use HexdocsMcp.DataCase, async: false

      import ExUnit.CaptureIO
    end
  end

  def setup_integration_environment(_context \\ nil) do
    original_config = %{
      ollama_client: Application.get_env(:hexdocs_mcp, :ollama_client),
      docs_module: Application.get_env(:hexdocs_mcp, :docs_module),
      mix_deps_module: Application.get_env(:hexdocs_mcp, :mix_deps_module)
    }

    Application.put_env(:hexdocs_mcp, :ollama_client, Ollama)
    Application.put_env(:hexdocs_mcp, :docs_module, HexdocsMcp.Docs)
    Application.put_env(:hexdocs_mcp, :mix_deps_module, HexdocsMcp.MixDeps)

    on_exit(fn ->
      Application.put_env(:hexdocs_mcp, :ollama_client, original_config.ollama_client)
      Application.put_env(:hexdocs_mcp, :docs_module, original_config.docs_module)
      Application.put_env(:hexdocs_mcp, :mix_deps_module, original_config.mix_deps_module)
    end)

    :ok
  end
end
