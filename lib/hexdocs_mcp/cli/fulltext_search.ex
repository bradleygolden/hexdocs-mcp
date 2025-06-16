defmodule HexdocsMcp.CLI.FulltextSearch do
  @moduledoc """
  CLI interface for full-text search on HexDocs.
  """

  alias HexdocsMcp.CLI.Utils
  alias HexdocsMcp.Config

  @usage """
  Usage: [SYSTEM_COMMAND] fulltext_search [PACKAGE] [VERSION] [options]

  Performs full-text search on HexDocs documentation using Typesense.

  Arguments:
    PACKAGE    - Optional package name to search within
    VERSION    - Optional version (only with PACKAGE)

  Options:
    --query QUERY    - Search query (required) - supports Typesense syntax
    --limit LIMIT    - Maximum number of results (default: 10, max: 100)
    --help, -h       - Show this help

  Query Syntax:
    Basic search:     GenServer
    Exact phrase:     "handle_call function"
    AND operator:     Phoenix AND LiveView
    OR operator:      Phoenix OR Plug
    Exclude terms:    Phoenix -test

  Examples:
    [SYSTEM_COMMAND] fulltext_search --query "GenServer"
    [SYSTEM_COMMAND] fulltext_search phoenix --query "channels"
    [SYSTEM_COMMAND] fulltext_search phoenix 1.7.0 --query "LiveView"
  """

  defmodule Context do
    @moduledoc false
    @enforce_keys [:query]
    defstruct query: nil,
              package: nil,
              version: nil,
              limit: 10,
              help?: false
  end

  def main(args) do
    case parse(args) do
      {:ok, %Context{help?: true}} ->
        Utils.output_info(usage())

      {:ok, context} ->
        search(context)
    end
  end

  def usage do
    String.replace(@usage, "[SYSTEM_COMMAND]", Config.system_command())
  end

  defp search(%Context{query: query, package: package, version: version, limit: limit}) do
    search_desc =
      cond do
        package && version -> "in #{package} v#{version}"
        package -> "in #{package}"
        true -> "in all packages"
      end

    Utils.output_info("Searching HexDocs #{search_desc} for \"#{query}\"...")

    opts = [package: package, version: version, limit: limit]

    fulltext_search = Config.fulltext_search_module()

    case fulltext_search.search(query, opts) do
      {:ok, [], _search_info} ->
        Utils.output_info("No results found for \"#{query}\"")

      {:ok, results, search_info} ->
        Utils.output_info("#{Utils.check()} Found #{search_info.total_found} results (showing #{length(results)}):\n")
        display_results(results)

      {:error, reason} ->
        Utils.output_error("Search failed: #{reason}")
    end
  end

  defp display_results(results) do
    Enum.each(results, fn result ->
      Utils.output_info("#{IO.ANSI.bright()}#{result.title}#{IO.ANSI.reset()}")
      Utils.output_info("  Package: #{result.package}")
      Utils.output_info("  Type: #{result.type}")

      if result.snippet != "" do
        # Clean up the snippet - remove <mark> tags but keep the text
        snippet =
          result.snippet
          |> String.replace("<mark>", IO.ANSI.bright())
          |> String.replace("</mark>", IO.ANSI.reset())
          |> String.trim()

        Utils.output_info("  Match: #{snippet}")
      end

      Utils.output_info("  URL: #{result.url}")
      Utils.output_info("")
    end)
  end

  defp parse(args) do
    {opts, remaining_args} =
      OptionParser.parse!(args,
        aliases: [
          q: :query,
          l: :limit,
          h: :help
        ],
        strict: [
          query: :string,
          limit: :integer,
          help: :boolean
        ]
      )

    {package, version} = Utils.parse_package_args(remaining_args)

    if opts[:query] do
      {:ok,
       %Context{
         query: opts[:query],
         package: package,
         version: version,
         limit: opts[:limit] || 10,
         help?: opts[:help] || false
       }}
    else
      {:ok, %Context{query: nil, help?: true}}
    end
  end
end
