defmodule HexdocsMcp.Behaviours.CLI.FetchDocs do
  @moduledoc false
  @callback main(list) :: :ok | :error
end

defmodule HexdocsMcp.Behaviours.CLI.SemanticSearch do
  @moduledoc false
  @callback main(list) :: :ok | :error
end

defmodule HexdocsMcp.Behaviours.Docs do
  @moduledoc false
  @callback fetch(String.t(), String.t() | nil) :: {String.t(), non_neg_integer()}
  @callback get_latest_version(String.t()) :: {:ok, String.t()} | {:error, String.t()}
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

  @callback embeddings_exist?(package :: String.t() | nil, version :: String.t() | nil) :: boolean()
  @callback delete_embeddings(package :: String.t() | nil, version :: String.t() | nil) ::
              {:ok, non_neg_integer()}
end

defmodule HexdocsMcp.Behaviours.Ollama do
  @moduledoc false
  @callback init(opts :: term()) :: map()
  @callback embed(client :: map(), opts :: keyword()) :: {:ok, map()} | {:error, term()}
end

defmodule HexdocsMcp.Behaviours.MixDeps do
  @moduledoc false
  @callback read_deps(String.t()) :: [{String.t(), String.t() | nil}]
end

defmodule HexdocsMcp.Behaviours.HexSearch do
  @moduledoc false
  @callback search_packages(query :: String.t(), opts :: Keyword.t()) ::
              {:ok, list(map())} | {:error, String.t()}
end

defmodule HexdocsMcp.Behaviours.FulltextSearch do
  @moduledoc false
  @callback search(query :: String.t(), opts :: Keyword.t()) ::
              {:ok, list(map()), map()} | {:error, String.t()}
end
