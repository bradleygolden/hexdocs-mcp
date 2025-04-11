defmodule HexdocsMcp.CLI.Search do
  @moduledoc """
  Functions for searching through Hex documentation using embeddings.
  """

  alias HexdocsMcp.CLI.{Progress, Utils}

  @usage """
  Usage: [SYSTEM_COMMAND] search PACKAGE [VERSION] [options]

  Searches in package documentation using semantic embeddings.

  Arguments:
    PACKAGE    - Hex package name to search in (required)
    VERSION    - Package version (optional, defaults to latest)

  Options:
    --query QUERY    - Search query (required)
    --model MODEL    - Ollama model to use for search (default: nomic-embed-text)
    --help, -h       - Show this help

  Process:
    1. Looks up existing embeddings for the package
    2. Performs semantic search using the query
    3. Returns the most relevant results

  Examples:
    [SYSTEM_COMMAND] search phoenix --query "how to create channels" # Search all packages
    [SYSTEM_COMMAND] search phoenix 1.7.0 --query "configuration options" # Search specific version
    [SYSTEM_COMMAND] search phoenix --query "configuration options" --model all-minilm # Use custom model
  """

  defmodule Context do
    @enforce_keys [:query, :package, :version, :model, :help?]
    defstruct query: nil,
              package: nil,
              version: nil,
              model: nil,
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
    %Context{query: query, package: package, version: version, model: model} = context

    Utils.output_info("Searching for \"#{query}\" in #{package} #{version || "latest"}...")

    progress_callback = create_search_progress_callback()
    results = perform_search(query, package, version, model, progress_callback)
    display_search_results(results, package, version)
    results
  end

  defp create_search_progress_callback do
    fn current, total, step ->
      step = step || :computing

      if step == :computing do
        progress_fn =
          case Process.get(:search_progress_fn) do
            nil ->
              fn_with_correct_total = Progress.progress_bar("Computing similarity scores", total)
              Process.put(:search_progress_fn, fn_with_correct_total)
              fn_with_correct_total

            existing_fn ->
              existing_fn
          end

        progress_fn.(current)
      end
    end
  end

  defp perform_search(query, package, version, model, progress_callback) do
    HexdocsMcp.search_embeddings(
      query,
      package,
      version,
      model,
      top_k: 3,
      progress_callback: progress_callback
    )
  end

  defp display_search_results([], package, version) do
    cmd = "[SYSTEM_COMMAND] fetch #{package} #{version}"
    cmd = String.replace(cmd, "[SYSTEM_COMMAND]", HexdocsMcp.Config.system_command())

    Utils.output_info("No results found.")
    Utils.output_info("Make sure you've generated embeddings for this package first by running:")
    Utils.output_info("  #{cmd}")
  end

  defp display_search_results(results, _package, _version) do
    Utils.output_info("#{Utils.check()} Found #{length(results)} results:")

    Enum.each(results, fn %{score: score, metadata: metadata} ->
      # Format score to 3 decimal places
      formatted_score = :io_lib.format("~.3f", [score]) |> IO.iodata_to_binary()

      Utils.output_info(
        "\n#{IO.ANSI.bright()}Result (score: #{formatted_score})#{IO.ANSI.reset()}"
      )

      Utils.output_info("  File: #{metadata.source_file}")
      Utils.output_info("  Text: #{metadata.text_snippet}")
    end)
  end

  defp parse(args) do
    {opts, args} =
      OptionParser.parse!(args,
        aliases: [
          q: :query,
          m: :model,
          h: :help
        ],
        strict: [
          query: :string,
          model: :string,
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
       help?: opts[:help] || false
     }}
  end
end
