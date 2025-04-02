defmodule HexMcp do
  @moduledoc """
  HexMcp converts Hex documentation to markdown files.
  
  This application provides a mix task to:
  1. Download package documentation using mix hex.docs
  2. Convert the HTML documentation to markdown
  3. Save all documentation as a single markdown file in the .hex_mcp directory
  """

  @doc """
  Hello world.

  ## Examples

      iex> HexMcp.hello()
      :world

  """
  def hello do
    :world
  end
end
