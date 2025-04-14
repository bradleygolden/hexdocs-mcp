defmodule HexdocsMcp do
  @moduledoc false
  defdelegate generate_embeddings(package, version, model, opts \\ []),
    to: HexdocsMcp.Embeddings,
    as: :generate

  defdelegate search_embeddings(query, package, version, model, opts \\ []),
    to: HexdocsMcp.Embeddings,
    as: :search
end
