defmodule HexdocsMcp.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    download_sqlite_vec()

    children = [
      {HexdocsMcp.Repo,
       load_extensions: [SqliteVec.path()], database: HexdocsMcp.Config.database()}
    ]

    opts = [strategy: :one_for_one, name: HexdocsMcp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp download_sqlite_vec() do
    version = SqliteVec.Downloader.default_version()

    output_dir =
      :hexdocs_mcp
      |> :code.priv_dir()
      |> Path.join(version)
      |> tap(&File.mkdir_p!/1)

    case SqliteVec.download(output_dir, version) do
      :skip ->
        :ok

      {:ok, _successful_files, []} ->
        :ok

      {:ok, _successful_files, failed_files} ->
        message = "failed to download: " <> Enum.join(failed_files, ", ")
        raise(message)

      {:error, message} ->
        raise(message)
    end
  end
end
