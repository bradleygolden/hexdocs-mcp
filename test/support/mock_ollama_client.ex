defmodule HexdocsMcp.MockOllamaClient do
  @moduledoc """
  Mock implementation of the Ollama client for testing.
  This allows us to test the Embeddings module without making actual Ollama API calls.
  """

  @behaviour HexdocsMcp.Behaviours.Ollama

  @impl true
  def init(_opts \\ []) do
    test_pid = Process.get(:test_pid)
    %{mock: true, test_pid: test_pid}
  end

  @impl true
  def embed(%{mock: true, test_pid: test_pid}, opts) do
    model = Keyword.get(opts, :model)
    input = Keyword.get(opts, :input)

    embedding_size =
      case model do
        "nomic-embed-text" -> 1024
        "mxbai-embed-large" -> 1024
        "all-minilm" -> 1024
        "all-minilm:l6-v2" -> 1024
        "test-model" -> 1024
        _ -> 1024
      end

    embedding =
      if is_list(input) do
        Enum.map(input, fn _ -> List.duplicate(0.1, embedding_size) end)
      else
        [List.duplicate(0.1, embedding_size)]
      end

    if test_pid && Process.get(:track_model_usage) do
      send(test_pid, {:model_used, model})
    end

    {:ok,
     %{
       "model" => model,
       "embeddings" => embedding
     }}
  end
end
