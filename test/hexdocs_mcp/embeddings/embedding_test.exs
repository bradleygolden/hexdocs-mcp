defmodule HexdocsMcp.Embeddings.EmbeddingTest do
  use HexdocsMcp.DataCase, async: true

  alias HexdocsMcp.Embeddings
  alias HexdocsMcp.Embeddings.Embedding

  describe "schema" do
    test "changeset/2 creates valid changeset with required fields" do
      embedding = SqliteVec.Float32.new([1.0, 2.0, 3.0, 4.0])
      text = "Phoenix is a web framework for the Elixir programming language."
      content_hash = Embeddings.content_hash(text)

      attrs = %{
        package: "phoenix",
        version: "1.6.0",
        source_file: "guides/introduction/overview.md",
        text: text,
        content_hash: content_hash,
        embedding: embedding
      }

      changeset = Embedding.changeset(%Embedding{}, attrs)
      assert changeset.valid?
    end

    test "validates presence of required fields" do
      changeset = Embedding.changeset(%Embedding{}, %{})
      refute changeset.valid?

      errors = errors_on(changeset)
      assert errors[:package]
      assert errors[:version]
      assert errors[:source_file]
      assert errors[:text]
      assert errors[:content_hash]
      assert errors[:embedding]
    end
  end
end
