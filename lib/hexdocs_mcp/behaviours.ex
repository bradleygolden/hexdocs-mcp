defmodule HexdocsMcp.Behaviours.CLI.Fetch do
  @moduledoc false
  @callback main(list) :: :ok | :error
end

defmodule HexdocsMcp.Behaviours.CLI.Search do
  @moduledoc false
  @callback main(list) :: :ok | :error
end

defmodule HexdocsMcp.Behaviours.Docs do
  @moduledoc false
  @callback fetch(String.t(), String.t() | nil) :: {String.t(), non_neg_integer()}
end

defmodule HexdocsMcp.Behaviours.Embeddings do
  @moduledoc """
  Behaviour for the Embeddings module - used primarily for mocking in tests
  """

  @callback generate(
              package :: String.t(),
              version :: String.t() | nil,
              model :: String.t(),
              opts :: Keyword.t()
            ) ::
              {:ok, term()}

  @callback embeddings_exist?(package :: String.t(), version :: String.t() | nil) :: boolean()
  @callback delete_embeddings(package :: String.t(), version :: String.t() | nil) ::
              {:ok, non_neg_integer()}
end

defmodule HexdocsMcp.Behaviours.Ollama do
  @moduledoc false
  @callback init(opts :: term()) :: map()
  @callback embed(client :: map(), opts :: keyword()) :: {:ok, map()} | {:error, term()}
end
