defmodule HexdocsMcp.Docs do
  @moduledoc false
  @behaviour HexdocsMcp.Behaviours.Docs

  alias HexdocsMcp.Behaviours.Docs

  @impl Docs
  def fetch(package, version) do
    actual_version = resolve_version(package, version)
    docs_base = Path.join(HexdocsMcp.Config.data_path(), "docs")
    package_dir = Path.join(docs_base, "#{package}-#{actual_version}")

    if File.exists?(package_dir) and File.dir?(package_dir) do
      normalized_path = String.replace(package_dir, "\\", "/")
      output = "Docs already fetched: #{normalized_path}\n"
      {output, 0}
    else
      File.mkdir_p!(docs_base)

      case download_and_extract_docs(package, actual_version, package_dir) do
        :ok ->
          normalized_path = String.replace(package_dir, "\\", "/")
          output = "Docs fetched: #{normalized_path}\n"
          {output, 0}

        {:error, reason} ->
          raise "Failed to fetch docs: #{reason}"
      end
    end
  end

  defp resolve_version(package, nil), do: get_latest_version!(package)
  defp resolve_version(package, "latest"), do: get_latest_version!(package)
  defp resolve_version(_package, version), do: version

  defp get_latest_version!(package) do
    case get_latest_version(package) do
      {:ok, version} -> version
      {:error, reason} -> raise reason
    end
  end

  defp download_and_extract_docs(package, version, target_dir) do
    url = "https://repo.hex.pm/docs/#{package}-#{version}.tar.gz"
    tarball_path = Path.join(System.tmp_dir!(), "#{package}-#{version}-docs.tar.gz")

    with {:download, {:ok, %{status: 200}}} <- {:download, Req.get(url, into: File.stream!(tarball_path))},
         {:extract, :ok} <- {:extract, extract_tarball(tarball_path, target_dir)} do
      File.rm(tarball_path)
      :ok
    else
      {:download, {:ok, %{status: 404}}} ->
        {:error, "Package documentation not found (404)"}

      {:download, {:ok, %{status: status}}} ->
        {:error, "Failed to download docs (HTTP #{status})"}

      {:download, {:error, reason}} ->
        {:error, "Download failed: #{inspect(reason)}"}

      {:extract, {:error, reason}} ->
        File.rm_rf!(tarball_path)
        {:error, "Failed to extract docs: #{inspect(reason)}"}
    end
  end

  defp extract_tarball(tarball_path, target_dir) do
    File.mkdir_p!(target_dir)

    cwd_path = String.replace(target_dir, "\\", "/")

    case :erl_tar.extract(String.to_charlist(tarball_path), [
           {:cwd, String.to_charlist(cwd_path)},
           :compressed
         ]) do
      :ok ->
        files = File.ls!(target_dir)
        html_count = Enum.count(files, &String.ends_with?(&1, ".html"))

        if html_count > 0 do
          :ok
        else
          {:error, "No HTML files found after extraction. Found files: #{inspect(Enum.take(files, 10))}"}
        end

      error ->
        error
    end
  end

  @impl Docs
  def get_latest_version(package) do
    url = "https://hex.pm/api/packages/#{package}"

    case Req.get(url) do
      {:ok, %{status: 200, body: body}} ->
        versions =
          for release <- body["releases"],
              version = Version.parse!(release["version"]),
              version.pre == [] do
            version
          end

        case versions do
          [] -> {:error, "No stable versions found for #{package}"}
          _ -> {:ok, to_string(Enum.max(versions, Version))}
        end

      {:ok, %{status: status_code}} ->
        {:error, "Failed to fetch package information: HTTP #{status_code}"}

      {:error, reason} ->
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end
end
