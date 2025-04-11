defmodule HexdocsMcp.MockOllamaClient do
  @moduledoc """
  Mock implementation of the Ollama client for testing.
  This allows us to test the Embeddings module without making actual Ollama API calls.
  """

  @behaviour HexdocsMcp.Behaviours.Ollama

  @impl true
  def init(_opts \\ []) do
    # Track the test process so we can send messages back
    test_pid = Process.get(:test_pid)
    %{mock: true, test_pid: test_pid}
  end

  @impl true
  def embed(%{mock: true, test_pid: test_pid}, opts) do
    model = Keyword.get(opts, :model)
    input = Keyword.get(opts, :input)

    embedding_size =
      case model do
        "nomic-embed-text" -> 384
        _ -> 128
      end

    embedding =
      case is_list(input) do
        true ->
          Enum.map(input, fn _ -> List.duplicate(0.1, embedding_size) end)

        false ->
          [List.duplicate(0.1, embedding_size)]
      end

    # Track model usage if a test_pid is provided
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
