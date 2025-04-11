defmodule HexdocsMcp.Ollama do
  @behaviour HexdocsMcp.Behaviours.Ollama

  @impl true
  def init(opts \\ []), do: impl().init(opts)

  @impl true
  def embed(client, opts), do: impl().embed(client, opts)

  defp impl, do: HexdocsMcp.Config.ollama_client()
end
