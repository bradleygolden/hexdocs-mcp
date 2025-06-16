defmodule HexdocsMcp.CLI.CheckEmbeddings do
  @moduledoc """
  Functions for checking if embeddings exist for a package.
  """

  @behaviour HexdocsMcp.Behaviours.CLI.CheckEmbeddings

  alias HexdocsMcp.CLI.Utils

  @usage """
    Usage: [SYSTEM_COMMAND] check_embeddings PACKAGE [VERSION]

    Checks if embeddings exist for a specific package and version.

    Arguments:
      PACKAGE    - Hex package name to check (required)
      VERSION    - Package version (optional, defaults to latest)

    Options:
      --help, -h - Show this help

    Examples:
      [SYSTEM_COMMAND] check_embeddings phoenix        # Check if embeddings exist for latest phoenix
      [SYSTEM_COMMAND] check_embeddings phoenix 1.7.0  # Check if embeddings exist for phoenix 1.7.0
  """

  def main(args) do
    case parse_args(args) do
      {:ok, {package, version}} ->
        check_embeddings(package, version)

      {:help} ->
        Utils.output_info(usage())

      {:error, message} ->
        Utils.output_error(message)
    end
  end

  defp check_embeddings(package, version) do
    embeddings_module = HexdocsMcp.Config.embeddings_module()
    version = version || "latest"

    if embeddings_module.embeddings_exist?(package, version) do
      count = get_embeddings_count(package, version)
      Utils.output_info("#{Utils.check()} Embeddings exist for #{package} #{version}")
      Utils.output_info("  Total embeddings: #{count}")
      :ok
    else
      Utils.output_info("#{Utils.cross()} No embeddings found for #{package} #{version}")
      Utils.output_info("  Run 'fetch_docs #{package} #{version}' to generate embeddings")
      :error
    end
  end

  defp get_embeddings_count(package, version) do
    alias HexdocsMcp.Repo
    alias HexdocsMcp.Embeddings.Embedding
    import Ecto.Query

    query =
      from e in Embedding,
        where: e.package == ^package and e.version == ^version,
        select: count(e.id)

    Repo.one(query) || 0
  end

  defp parse_args(args) do
    {opts, args} = OptionParser.parse!(args,
      aliases: [h: :help],
      strict: [help: :boolean]
    )

    cond do
      opts[:help] ->
        {:help}

      length(args) == 0 ->
        {:error, "Package name is required"}

      length(args) > 2 ->
        {:error, "Too many arguments"}

      true ->
        [package | rest] = args
        version = List.first(rest)
        {:ok, {package, version}}
    end
  end

  defp usage do
    String.replace(@usage, "[SYSTEM_COMMAND]", HexdocsMcp.Config.system_command())
  end
end