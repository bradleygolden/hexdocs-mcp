defmodule HexdocsMcp.CLI.Search do
  @moduledoc """
  Functions for searching through Hex documentation using embeddings.
  """

  alias HexdocsMcp.CLI.Progress
  alias HexdocsMcp.CLI.Utils

  @usage """
  Usage: [SYSTEM_COMMAND] search [PACKAGE] [VERSION] [options]

  Searches in package documentation using semantic embeddings.

  Arguments:
    PACKAGE    - Hex package name to search in (optional, searches all packages if not provided)
    VERSION    - Package version (optional, defaults to latest)

  Options:
    --query QUERY    - Search query (required)
    --model MODEL    - Ollama model to use for search (default: nomic-embed-text)
    --limit LIMIT    - Maximum number of results to return (default: 3)
    --help, -h       - Show this help

  Process:
    1. Looks up existing embeddings for the package(s)
    2. Performs semantic search using the query
    3. Returns the most relevant results

  Examples:
    [SYSTEM_COMMAND] search --query "how to create channels" # Search all packages
    [SYSTEM_COMMAND] search phoenix --query "how to create channels" # Search specific package
    [SYSTEM_COMMAND] search phoenix 1.7.0 --query "configuration options" # Search specific version
    [SYSTEM_COMMAND] search phoenix --query "configuration options" --model all-minilm # Use custom model
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
    %Context{query: query, package: package, version: version, model: model, limit: limit} =
      context

    package_info = if package, do: "#{package} #{version || "latest"}", else: "all packages"
    Utils.output_info("Searching for \"#{query}\" in #{package_info}...")

    progress_callback = create_search_progress_callback()
    results = perform_search(query, package, version, model, limit, progress_callback)
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

  defp perform_search(query, package, version, model, limit, progress_callback) do
    HexdocsMcp.search_embeddings(
      query,
      package,
      version,
      model,
      top_k: limit,
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
      # Format score to 3 decimal places
      formatted_score = "~.3f" |> :io_lib.format([score]) |> IO.iodata_to_binary()

      Utils.output_info("\n#{IO.ANSI.bright()}Result (score: #{formatted_score})#{IO.ANSI.reset()}")

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
          h: :help
        ],
        strict: [
          query: :string,
          model: :string,
          limit: :integer,
          help: :boolean
        ]
      )

    {package, version} = Utils.parse_package_args(args)

    {:ok,
     %Context{
       query: opts[:query],
       package: package,
       version: version,
       model: opts[:model] || HexdocsMcp.Config.default_embedding_model(),
       limit: opts[:limit] || 3,
       help?: opts[:help] || false
     }}
  end
end
