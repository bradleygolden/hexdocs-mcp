defmodule HexdocsMcp.CLI.HexSearch do
  @moduledoc """
  CLI interface for searching packages on Hex.pm.
  """

  alias HexdocsMcp.CLI.Utils
  alias HexdocsMcp.Config

  @usage """
  Usage: [SYSTEM_COMMAND] hex_search [PACKAGE] [VERSION] [options]

  Searches for packages on Hex.pm by name or description.

  Arguments:
    PACKAGE    - Optional package name to search within its versions
    VERSION    - Optional version (only with PACKAGE)

  Options:
    --query QUERY    - Search query (required)
    --sort SORT      - Sort results by: downloads (default), recent, or name
    --limit LIMIT    - Maximum number of results (default: 10)
    --help, -h       - Show this help

  Examples:
    [SYSTEM_COMMAND] hex_search --query "authentication"
    [SYSTEM_COMMAND] hex_search --query "phoenix" --sort recent
    [SYSTEM_COMMAND] hex_search phoenix --query "1.7"
    [SYSTEM_COMMAND] hex_search phoenix 1.7.0 --query "info"
  """

  defmodule Context do
    @moduledoc false
    @enforce_keys [:query]
    defstruct query: nil,
              package: nil,
              version: nil,
              sort: "downloads",
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

  defp search(%Context{query: query, package: package, version: version, sort: sort, limit: limit}) do
    search_desc =
      cond do
        package && version -> "package #{package} version #{version}"
        package -> "package #{package} versions"
        true -> "packages"
      end

    Utils.output_info("Searching Hex.pm #{search_desc} matching \"#{query}\"...")

    opts = [sort: sort, limit: limit, package: package, version: version]

    hex_search = Config.hex_search_module()

    case hex_search.search_packages(query, opts) do
      {:ok, []} ->
        Utils.output_info("No results found matching \"#{query}\"")

      {:ok, results} ->
        Utils.output_info("#{Utils.check()} Found #{length(results)} results:\n")
        display_results(results)

      {:error, reason} ->
        Utils.output_error("Search failed: #{reason}")
    end
  end

  defp display_results(results) do
    Enum.each(results, fn result ->
      # Check if it's a version result or package result
      if Map.has_key?(result, :version) do
        display_version_result(result)
      else
        display_package_result(result)
      end
    end)
  end

  defp display_package_result(package) do
    Utils.output_info("#{IO.ANSI.bright()}#{package.name}#{IO.ANSI.reset()} (v#{package.latest_version})")

    if package.description != "" do
      Utils.output_info("  #{package.description}")
    end

    Utils.output_info(
      "  Downloads: #{format_number(package.downloads.all)} total, #{format_number(package.downloads.recent)} recent"
    )

    if Map.get(package, :docs_url) do
      Utils.output_info("  Docs: #{package.docs_url}")
    end

    Utils.output_info("  Hex: #{package.html_url}")
    Utils.output_info("")
  end

  defp display_version_result(result) do
    Utils.output_info("#{IO.ANSI.bright()}#{result.name} v#{result.version}#{IO.ANSI.reset()}")

    if result.description != "" do
      Utils.output_info("  #{result.description}")
    end

    Utils.output_info("  Has docs: #{result.has_docs}")
    Utils.output_info("  Released: #{result.inserted_at}")

    if Map.get(result, :docs_url) do
      Utils.output_info("  Docs: #{result.docs_url}")
    end

    Utils.output_info("  API: #{result.url}")
    Utils.output_info("")
  end

  defp format_number(n) when n >= 1_000_000_000 do
    "#{Float.round(n / 1_000_000_000, 1)}B"
  end

  defp format_number(n) when n >= 1_000_000 do
    "#{Float.round(n / 1_000_000, 1)}M"
  end

  defp format_number(n) when n >= 1_000 do
    "#{Float.round(n / 1_000, 1)}K"
  end

  defp format_number(n), do: "#{n}"

  defp parse(args) do
    {opts, remaining_args} =
      OptionParser.parse!(args,
        aliases: [
          q: :query,
          s: :sort,
          l: :limit,
          h: :help
        ],
        strict: [
          query: :string,
          sort: :string,
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
         sort: opts[:sort] || "downloads",
         limit: opts[:limit] || 10,
         help?: opts[:help] || false
       }}
    else
      {:ok, %Context{query: nil, help?: true}}
    end
  end
end
