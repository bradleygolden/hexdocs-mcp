defmodule HexdocsMcp.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias HexdocsMcp.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import HexdocsMcp.DataCase
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(HexdocsMcp.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(HexdocsMcp.Repo, {:shared, self()})
    end

    HexdocsMcp.SqlSandbox.setup()

    :ok
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.
  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
