defmodule Mix.Tasks.Hex.Docs.Mcp do
  @shortdoc "Quickly search hexdocs using MCP. (use `--help` for more info)"
  @moduledoc @shortdoc

  use Mix.Task

  @requirements ["app.config", "app.start"]

  def run(args) do
    Application.ensure_all_started(:hexdocs_mcp)
    HexdocsMcp.CLI.main(args)
  end
end
