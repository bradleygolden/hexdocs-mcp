defmodule HexdocsMcp.Embeddings.Embedding do
  @moduledoc """
  Schema for storing document embeddings using SQLiteVec.
  """
  use Ecto.Schema

  import Ecto.Changeset

  schema "embeddings" do
    field(:package, :string)
    field(:version, :string)
    field(:source_file, :string)
    field(:source_type, :string)
    field(:start_byte, :integer)
    field(:end_byte, :integer)
    field(:text_snippet, :string)
    field(:text, :string)
    field(:content_hash, :string)
    field(:url, :string)
    field(:embedding, SqliteVec.Ecto.Float32)

    timestamps()
  end

  @required_fields [:package, :version, :source_file, :text, :embedding, :content_hash]
  @optional_fields [:source_type, :start_byte, :end_byte, :text_snippet, :url]

  def changeset(embedding, attrs) do
    embedding
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:package, min: 1)
    |> validate_length(:version, min: 1)
    |> validate_length(:source_file, min: 1)
    |> unique_constraint([:package, :version, :source_file, :text_snippet])
  end
end
