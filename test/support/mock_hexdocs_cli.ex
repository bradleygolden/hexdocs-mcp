defmodule HexdocsMcp.MockHexdocsCli do
  @moduledoc """
  Mock implementation of the Hexdocs CLI for testing.
  """

  @behaviour HexdocsMcp.Behaviours.Docs

  alias HexdocsMcp.Fixtures

  @impl HexdocsMcp.Behaviours.Docs
  def fetch(package, version) do
    hex_docs_path = Path.join([System.tmp_dir!(), "docs", "hexpm", package, version])
    File.mkdir_p!(hex_docs_path)
    File.write!(Path.join([hex_docs_path, Fixtures.html_filename()]), Fixtures.html())

    {"""
     Docs fetched to #{hex_docs_path}
     """, 0}
  end
end
