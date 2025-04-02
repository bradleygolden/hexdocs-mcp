defmodule HexdocsMcp.OllamaBehaviour do
  @callback init(opts :: term()) :: map()
  @callback embed(client :: map(), opts :: keyword()) :: {:ok, map()} | {:error, term()}
end

defmodule HexdocsMcp.Ollama do
  @behaviour HexdocsMcp.OllamaBehaviour

  @impl true
  def init(opts \\ []), do: impl().init(opts)

  @impl true
  def embed(client, opts), do: impl().embed(client, opts)

  defp impl, do: Application.get_env(:hexdocs_mcp, :ollama_client, Ollama)
end
