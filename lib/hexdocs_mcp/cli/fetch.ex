defmodule HexdocsMcp.CLI.Fetch do
  @moduledoc """
  Functions for fetching and processing Hex documentation.
  """

  alias HexdocsMcp.CLI.Progress
  alias HexdocsMcp.CLI.Utils
  alias HexdocsMcp.Markdown

  @usage """
    Usage: [SYSTEM_COMMAND] fetch PACKAGE [VERSION] [options]

    Fetches Hex docs for a package, converts to markdown, creates chunks, and generates embeddings.

    Arguments:
      PACKAGE    - Hex package name to fetch (required)
      VERSION    - Package version (optional, defaults to latest)

    Options:
      --model MODEL    - Ollama model to use for embeddings (default: nomic-embed-text)
      --force          - Force re-fetch even if embeddings already exist
      --help, -h       - Show this help

    Process:
      1. Checks if embeddings exist (skips remaining steps unless --force is used)
      2. Downloads docs using mix hex.docs
      3. Converts HTML to markdown
      4. Creates semantic chunks
      5. Generates embeddings

    Examples:
      [SYSTEM_COMMAND] fetch phoenix              # Process latest version of phoenix
      [SYSTEM_COMMAND] fetch phoenix 1.7.0        # Process specific version
      [SYSTEM_COMMAND] fetch phoenix --model all-minilm   # Use custom model
  """

  defmodule Context do
    @moduledoc false
    @enforce_keys [:package, :version, :model, :force?, :help?, :embeddings_module]
    defstruct package: nil,
              version: nil,
              model: nil,
              force?: false,
              help?: false,
              embeddings_module: nil
  end

  def main(args) do
    case parse(args) do
      {:ok, %Context{help?: true}} ->
        Utils.output_info(usage())

      {:ok, context} ->
        process_docs(context)

      {:error, message} ->
        Utils.output_error(message)
    end
  end

  def usage do
    String.replace(@usage, "[SYSTEM_COMMAND]", HexdocsMcp.Config.system_command())
  end

  defp process_docs(%Context{force?: false} = context) do
    %Context{package: package, version: version, embeddings_module: embeddings_module} = context

    if embeddings_module.embeddings_exist?(package, version) do
      Utils.output_info("#{Utils.check()} Embeddings for #{package} #{version} already exist, skipping fetch.")

      Utils.output_info("  Use --force to re-fetch and update embeddings.")

      :ok
    else
      do_process_docs(context)
    end
  end

  defp process_docs(%Context{force?: true} = context) do
    %Context{package: package, version: version, embeddings_module: embeddings_module} = context

    if embeddings_module.embeddings_exist?(package, version) do
      {:ok, count} = embeddings_module.delete_embeddings(package, version)

      Utils.output_info("#{Utils.check()} Removed #{count} existing embeddings for #{package} #{version || "latest"}.")
    end

    do_process_docs(context)
  end

  defp do_process_docs(context) do
    %Context{package: package, version: version, model: model} = context
    ensure_markdown_dir!(package)

    Utils.output_info("Fetching documentation for #{package}#{if version, do: " #{version}", else: ""}...")

    docs_path = execute_docs_fetch_quietly(package, version)
    verify_docs_path!(docs_path)

    html_files = find_html_files(docs_path)
    verify_html_files!(html_files, docs_path)

    output_file = create_markdown_file(package, version)

    Utils.output_info("Converting #{length(html_files)} HTML files to markdown...")
    convert_html_files_to_markdown(html_files, output_file)

    chunks_dir = prepare_chunks_dir(package)

    Utils.output_info("Creating semantic text chunks...")
    chunk_count = create_text_chunks(output_file, chunks_dir, package, version)

    Utils.output_info("Generating embeddings using #{model}...")

    {:ok, embed_count} =
      HexdocsMcp.generate_embeddings(
        package,
        version,
        model,
        progress_callback: create_embedding_progress_callback()
      )

    Utils.output_info("#{Utils.check()} Processing completed:")
    Utils.output_info("  • Docs location: #{docs_path}")
    Utils.output_info("  • Markdown file: #{output_file}")
    Utils.output_info("  • Created #{chunk_count} chunks in: #{chunks_dir}")
    Utils.output_info("  • Generated #{embed_count} embeddings")

    :ok
  end

  defp execute_docs_fetch_quietly(package, version) do
    {output, 0} = execute_hex_docs_fetch(package, version)
    parse_docs_path(output, package, version)
  end

  defp execute_hex_docs_fetch(package, version) do
    HexdocsMcp.Config.docs_module().fetch(package, version)
  end

  defp verify_docs_path!(docs_path) do
    if !File.dir?(docs_path), do: raise("Docs directory not found: #{docs_path}")
  end

  defp verify_html_files!(html_files, docs_path) do
    if Enum.empty?(html_files), do: raise("No HTML files found in docs directory: #{docs_path}")
  end

  defp parse_docs_path(output, package, version) do
    docs_path = extract_docs_path_from_output(output)
    docs_path || find_default_docs_path(package, version, output)
  end

  defp extract_docs_path_from_output(output) do
    output
    |> String.split("\n")
    |> Enum.find_value(&extract_path_from_line/1)
  end

  defp extract_path_from_line(line) do
    cond do
      Regex.match?(~r/Docs fetched to (.+)/, line) ->
        [_, path] = Regex.run(~r/Docs fetched to (.+)/, line)
        path

      Regex.match?(~r/Docs already fetched: (.+)/, line) ->
        [_, path] = Regex.run(~r/Docs already fetched: (.+)/, line)
        path

      Regex.match?(~r/Docs fetched: (.+)/, line) ->
        [_, path] = Regex.run(~r/Docs fetched: (.+)/, line)
        path

      true ->
        nil
    end
  end

  defp find_default_docs_path(package, version, output) do
    Utils.output_info("Could not parse docs path from output: \n#{output}")
    docs_base = Path.join(HexdocsMcp.Config.data_path(), "docs")

    if version do
      Path.join([docs_base, "hexpm", package, version])
    else
      find_latest_version_path(docs_base, package)
    end
  end

  defp find_latest_version_path(docs_base, package) do
    package_path = Path.join([docs_base, "hexpm", package])

    package_path
    |> File.ls!()
    |> Enum.filter(&version_directory?(&1, docs_base, package))
    |> Enum.sort_by(&parse_version/1)
    |> List.last()
    |> build_version_path(docs_base, package)
  end

  defp version_directory?(dir, docs_base, package) do
    path = Path.join([docs_base, "hexpm", package, dir])
    File.dir?(path) && String.match?(dir, ~r/\d+\.\d+\.\d+.*/)
  end

  defp parse_version(dir) do
    case Version.parse(dir) do
      {:ok, version} -> version
      :error -> Version.parse!("0.0.0")
    end
  end

  defp build_version_path(latest_version, docs_base, package) do
    Path.join([docs_base, "hexpm", package, latest_version])
  end

  defp ensure_markdown_dir!(package) do
    data_path = HexdocsMcp.Config.data_path()
    File.mkdir_p!(Path.join(data_path, package))
  end

  defp prepare_chunks_dir(package) do
    data_path = HexdocsMcp.Config.data_path()
    chunks_dir = Path.join([data_path, package, "chunks"])
    File.mkdir_p!(chunks_dir)
    chunks_dir
  end

  defp create_markdown_file(package, version) do
    data_path = HexdocsMcp.Config.data_path()
    version_str = if version, do: version, else: "latest"
    Path.join([data_path, package, "#{version_str}.md"])
  end

  defp find_html_files(docs_path) do
    Path.wildcard(Path.join(docs_path, "**/*.html"))
  end

  defp convert_html_files_to_markdown(html_files, output_file) do
    File.open!(output_file, [:write, :utf8], &write_markdown_content(&1, html_files))
  end

  defp write_markdown_content(file, html_files) do
    Enum.each(html_files, fn html_file ->
      html_content = File.read!(html_file)
      relative_path = Path.relative_to(html_file, HexdocsMcp.Config.data_path())

      IO.write(file, "---\n\n")
      IO.write(file, "# #{relative_path}\n\n")
      IO.write(file, Markdown.from_html(html_content))
      IO.write(file, "\n\n---\n\n")
    end)
  end

  defp create_text_chunks(markdown_file, output_dir, package, version) do
    markdown_file
    |> File.read!()
    |> String.split(~r/^---$/m, trim: true)
    |> process_file_chunks(output_dir, package, version)
    |> Enum.count()
  end

  defp process_file_chunks(file_chunks, output_dir, package, version) do
    file_chunks
    |> Enum.with_index()
    |> Enum.flat_map(&process_file_chunk(&1, output_dir, package, version))
  end

  defp process_file_chunk({file_chunk, idx}, output_dir, package, version) do
    file_path = extract_file_path(file_chunk, idx)

    if skip_chunk?(file_chunk, file_path) do
      []
    else
      clean_path = sanitize_path(file_path)
      metadata = build_chunk_metadata(package, version, file_path)

      file_chunk
      |> chunk_text()
      |> create_chunk_files(clean_path, output_dir, metadata)
    end
  end

  defp extract_file_path(file_chunk, idx) do
    case Regex.run(~r/# ([^\n]+)/, file_chunk) do
      [_, path] -> path
      _ -> "Unknown-#{idx}"
    end
  end

  defp skip_chunk?(file_chunk, file_path) do
    String.trim(file_chunk) == "" or
      String.starts_with?(file_path, "Unknown") or
      Path.basename(file_path) in ["404.html", "search.html"]
  end

  defp sanitize_path(file_path) do
    file_path
    |> Path.basename()
    |> Path.rootname()
    |> String.replace(~r/[^\w\d\.-]/, "_")
  end

  defp chunk_text(text) do
    TextChunker.split(text, chunk_size: 2000, chunk_overlap: 200, format: :markdown)
  end

  defp build_chunk_metadata(package, version, file_path) do
    %{
      package: package,
      version: version || "latest",
      source_file: file_path,
      source_type: "hexdocs"
    }
  end

  defp create_chunk_files(chunks, clean_path, output_dir, metadata) do
    chunks
    |> Enum.with_index()
    |> Enum.map(&create_chunk_file(&1, clean_path, output_dir, metadata))
    |> Enum.reject(&is_nil/1)
  end

  defp create_chunk_file({chunk, chunk_idx}, clean_path, output_dir, metadata) do
    if String.length(chunk.text) < 50 do
      nil
    else
      chunk_filename = "#{clean_path}_chunk_#{chunk_idx}.json"
      chunk_path = Path.join(output_dir, chunk_filename)

      extended_metadata =
        Map.merge(metadata, %{
          start_byte: chunk.start_byte,
          end_byte: chunk.end_byte
        })

      chunk_data = %{
        "text" => chunk.text,
        "metadata" => extended_metadata
      }

      chunk_json = Jason.encode!(chunk_data, pretty: true)
      File.write!(chunk_path, chunk_json)

      chunk
    end
  end

  defp create_embedding_progress_callback do
    fn current, total, step ->
      step = step || :processing
      progress_fn = get_progress_fn_for_step(step, total)
      progress_fn.(current)
    end
  end

  defp get_progress_fn_for_step(step, total) do
    case step do
      :processing -> get_or_create_processing_progress_fn(total)
      :saving -> get_or_create_saving_progress_fn(total)
      _ -> get_default_progress_fn(total)
    end
  end

  defp get_or_create_processing_progress_fn(total) do
    case Process.get(:processing_progress_fn) do
      nil ->
        fn_with_total = Progress.progress_bar("Processing embeddings", total)
        Process.put(:processing_progress_fn, fn_with_total)
        fn_with_total

      existing ->
        existing
    end
  end

  defp get_or_create_saving_progress_fn(total) do
    case Process.get(:saving_progress_fn) do
      nil ->
        fn_with_total = Progress.progress_bar("Saving embeddings", total)
        Process.put(:saving_progress_fn, fn_with_total)
        fn_with_total

      existing ->
        existing
    end
  end

  defp get_default_progress_fn(total) do
    Process.get(
      :processing_progress_fn,
      Progress.progress_bar("Processing embeddings", total)
    )
  end

  defp parse(args) do
    {opts, args} =
      OptionParser.parse!(args,
        aliases: [
          m: :model,
          f: :force,
          h: :help
        ],
        strict: [
          model: :string,
          force: :boolean,
          help: :boolean
        ]
      )

    {package, version} = Utils.parse_package_args(args)
    help? = opts[:help] || false

    if not help? and !package do
      {:error, "Invalid arguments: missing package name"}
    else
      {:ok,
       %Context{
         package: package,
         version: version || "latest",
         model: opts[:model] || HexdocsMcp.Config.default_embedding_model(),
         force?: opts[:force] || false,
         help?: help?,
         embeddings_module: HexdocsMcp.Config.embeddings_module()
       }}
    end
  end
end
