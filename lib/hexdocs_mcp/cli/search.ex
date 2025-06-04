defmodule HexdocsMcp.CLI.Search do
  @moduledoc """
  Functions for searching through Hex documentation using embeddings.
  """

  alias HexdocsMcp.CLI.Progress
  alias HexdocsMcp.CLI.Utils

  @usage """
  Usage: [SYSTEM_COMMAND] search [PACKAGE] [options]

  Searches in package documentation using semantic embeddings.

  Arguments:
    PACKAGE    - Hex package name to search in (optional, searches all packages if not provided)

  Options:
    --query QUERY       - Search query (required)
    --model MODEL       - Ollama model to use for search (default: nomic-embed-text)
    --limit LIMIT       - Maximum number of results to return (default: 3)
    --version VERSION   - Search only in specific version
    --all-versions      - Include results from all indexed versions (default: latest only)
    --help, -h          - Show this help

  Process:
    1. Looks up existing embeddings for the package(s)
    2. Performs semantic search using the query
    3. By default, returns results only from the latest version of each package
    4. Returns the most relevant results

  Examples:
    [SYSTEM_COMMAND] search --query "how to create channels" # Search latest versions of all packages
    [SYSTEM_COMMAND] search phoenix --query "how to create channels" # Search latest version of phoenix
    [SYSTEM_COMMAND] search phoenix --query "configuration options" --version 1.7.0 # Search specific version
    [SYSTEM_COMMAND] search phoenix --query "configuration options" --all-versions # Search all versions
    [SYSTEM_COMMAND] search phoenix --query "configuration options" --limit 10 # Return more results
  """

  defmodule Context do
    @moduledoc false
    @enforce_keys [:query, :model, :help?]
    defstruct query: nil,
              package: nil,
              version: nil,
              model: nil,
              limit: 3,
              all_versions: false,
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
    String.replace(@usage, "[SYSTEM_COMMAND]", HexdocsMcp.Config.system_command())
  end

  defp search(%Context{} = context) do
    %Context{
      query: query,
      package: package,
      version: version,
      model: model,
      limit: limit,
      all_versions: all_versions
    } = context

    package_info =
      cond do
        version -> "#{package || "all packages"} version #{version}"
        all_versions -> "#{package || "all packages"} (all versions)"
        true -> "#{package || "all packages"} (latest versions only)"
      end

    Utils.output_info("Searching for \"#{query}\" in #{package_info}...")

    progress_callback = create_search_progress_callback()
    results = perform_search(query, package, version, model, limit, all_versions, progress_callback)
    display_search_results(results, package, version)
    results
  end

  defp create_search_progress_callback do
    fn current, total, step ->
      step = step || :computing

      if step == :computing do
        progress_fn = get_or_create_progress_fn(total)
        progress_fn.(current)
      end
    end
  end

  defp get_or_create_progress_fn(total) do
    case Process.get(:search_progress_fn) do
      nil ->
        fn_with_correct_total = Progress.progress_bar("Computing similarity scores", total)
        Process.put(:search_progress_fn, fn_with_correct_total)
        fn_with_correct_total

      existing_fn ->
        existing_fn
    end
  end

  defp perform_search(query, package, version, model, limit, all_versions, progress_callback) do
    HexdocsMcp.search_embeddings(
      query,
      package,
      version,
      model,
      top_k: limit,
      all_versions: all_versions,
      progress_callback: progress_callback
    )
  end

  defp display_search_results([], package, version) do
    fetch_cmd =
      if package do
        cmd = "[SYSTEM_COMMAND] fetch #{package} #{version}"
        cmd = String.replace(cmd, "[SYSTEM_COMMAND]", HexdocsMcp.Config.system_command())
        "\n  #{cmd}"
      else
        ""
      end

    Utils.output_info("No results found.")

    if package do
      Utils.output_info("Make sure you've generated embeddings for this package first by running:#{fetch_cmd}")
    else
      Utils.output_info("Try searching for a specific package or generate embeddings for packages first.")
    end
  end

  defp display_search_results(results, _package, _version) do
    Utils.output_info("#{Utils.check()} Found #{length(results)} results:")

    Enum.each(results, fn %{score: score, metadata: metadata} ->
      formatted_score = "~.3f" |> :io_lib.format([score]) |> IO.iodata_to_binary()

      Utils.output_info("\n#{IO.ANSI.bright()}Result (score: #{formatted_score})#{IO.ANSI.reset()}")

      Utils.output_info("  Package: #{metadata.package}")
      Utils.output_info("  Version: #{metadata.version}")
      Utils.output_info("  File: #{metadata.source_file}")

      if metadata.url, do: Utils.output_info("  URL: #{metadata.url}")

      Utils.output_info("  Text: #{metadata.text}")
    end)
  end

  defp parse(args) do
    {opts, args} =
      OptionParser.parse!(args,
        aliases: [
          q: :query,
          m: :model,
          l: :limit,
          h: :help,
          v: :version
        ],
        strict: [
          query: :string,
          model: :string,
          limit: :integer,
          version: :string,
          all_versions: :boolean,
          help: :boolean
        ]
      )

    {package, position_version} = Utils.parse_package_args(args)
    version = opts[:version] || position_version

    {:ok,
     %Context{
       query: opts[:query],
       package: package,
       version: version,
       model: opts[:model] || HexdocsMcp.Config.default_embedding_model(),
       limit: opts[:limit] || 3,
       all_versions: opts[:all_versions] || false,
       help?: opts[:help] || false
     }}
  end
end
