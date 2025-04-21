defmodule HexdocsMcp.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    ensure_sqlite_vec_available()

    children = [
      {HexdocsMcp.Repo, load_extensions: [sqlite_vec_extension_path()], database: HexdocsMcp.Config.database()}
    ]

    opts = [strategy: :one_for_one, name: HexdocsMcp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp ensure_sqlite_vec_available do
    version = SqliteVec.Downloader.default_version()
    output_dir = sqlite_vec_dir(version)
    File.mkdir_p!(output_dir)

    case SqliteVec.download(output_dir, version) do
      :skip -> :ok
      {:ok, _, []} -> :ok
      {:ok, _, failed_files} -> raise "Failed to download: #{Enum.join(failed_files, ", ")}"
      {:error, message} -> raise message
    end
  end

  defp sqlite_vec_extension_path do
    version = SqliteVec.Downloader.default_version()
    Path.join(sqlite_vec_dir(version), "vec0")
  end

  defp sqlite_vec_dir(version) do
    Path.join([HexdocsMcp.Config.data_path(), "sqlite_vec", version])
  end
end
