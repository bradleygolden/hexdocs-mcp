defmodule HexdocsMcp.HexSearch do
  @moduledoc """
  Functions for searching packages on Hex.pm using their API.
  """

  @behaviour HexdocsMcp.Behaviours.HexSearch

  @hex_api_base "https://hex.pm/api"

  @doc """
  Searches for packages on Hex.pm or gets info for a specific package/version.

  ## Options
    * `:sort` - Sort order for results. Can be "downloads", "recent", or "name". Defaults to "downloads".
    * `:limit` - Maximum number of results to return. Defaults to 10.
    * `:page` - Page number for pagination. Defaults to 1.
    * `:package` - Optional specific package name to get info for
    * `:version` - Optional specific version (only used with :package)
  """
  def search_packages(query, opts \\ []) do
    package = Keyword.get(opts, :package)
    version = Keyword.get(opts, :version)

    cond do
      # If package and version specified, get specific version info
      package && version ->
        get_package_version_info(package, version)

      # If only package specified, search within package versions
      package ->
        search_package_versions(package, query, opts)

      # Otherwise do general package search
      true ->
        search_all_packages(query, opts)
    end
  end

  defp search_all_packages(query, opts) do
    sort = Keyword.get(opts, :sort, "downloads")
    limit = Keyword.get(opts, :limit, 10)
    page = Keyword.get(opts, :page, 1)

    sort_param =
      case sort do
        "downloads" -> "total_downloads"
        "recent" -> "recent_downloads"
        "name" -> "name"
        _ -> "total_downloads"
      end

    url = "#{@hex_api_base}/packages"

    params = %{
      "search" => query,
      "sort" => sort_param,
      "page" => page
    }

    case Req.get(url, params: params) do
      {:ok, %{status: 200, body: packages}} ->
        results =
          packages
          |> Enum.take(limit)
          |> Enum.map(&format_package_result/1)

        {:ok, results}

      {:ok, %{status: status_code, body: body}} ->
        {:error, "Failed to search packages: HTTP #{status_code} - #{inspect(body)}"}

      {:error, reason} ->
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end

  defp search_package_versions(package_name, query, opts) do
    limit = Keyword.get(opts, :limit, 10)

    url = "#{@hex_api_base}/packages/#{package_name}"

    case Req.get(url) do
      {:ok, %{status: 200, body: package_info}} ->
        # Filter releases based on query (in version string or has_docs)
        filtered_releases =
          package_info["releases"]
          |> Enum.filter(fn release ->
            version_str = release["version"]

            String.contains?(String.downcase(version_str), String.downcase(query)) ||
              (query == "docs" && release["has_docs"] == true)
          end)
          |> Enum.take(limit)
          |> Enum.map(fn release ->
            format_version_result(package_info, release)
          end)

        {:ok, filtered_releases}

      {:ok, %{status: 404}} ->
        {:error, "Package '#{package_name}' not found"}

      {:ok, %{status: status_code, body: body}} ->
        {:error, "Failed to get package info: HTTP #{status_code} - #{inspect(body)}"}

      {:error, reason} ->
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end

  defp get_package_version_info(package_name, version) do
    url = "#{@hex_api_base}/packages/#{package_name}"

    case Req.get(url) do
      {:ok, %{status: 200, body: package_info}} ->
        release =
          Enum.find(package_info["releases"], fn r ->
            r["version"] == version
          end)

        if release do
          {:ok, [format_version_result(package_info, release)]}
        else
          {:error, "Version '#{version}' not found for package '#{package_name}'"}
        end

      {:ok, %{status: 404}} ->
        {:error, "Package '#{package_name}' not found"}

      {:ok, %{status: status_code, body: body}} ->
        {:error, "Failed to get package info: HTTP #{status_code} - #{inspect(body)}"}

      {:error, reason} ->
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end

  defp format_package_result(package) do
    %{
      name: package["name"],
      description: Map.get(package["meta"], "description", ""),
      downloads: %{
        all: get_in(package, ["downloads", "all"]) || 0,
        recent: get_in(package, ["downloads", "recent"]) || 0
      },
      latest_version: package["latest_stable_version"] || package["latest_version"],
      html_url: package["html_url"],
      docs_url: package["docs_html_url"],
      inserted_at: package["inserted_at"],
      updated_at: package["updated_at"]
    }
  end

  defp format_version_result(package_info, release) do
    %{
      name: package_info["name"],
      version: release["version"],
      description: Map.get(package_info["meta"], "description", ""),
      has_docs: release["has_docs"],
      inserted_at: release["inserted_at"],
      url: release["url"],
      package_url: package_info["html_url"],
      docs_url: if(release["has_docs"], do: "https://hexdocs.pm/#{package_info["name"]}/#{release["version"]}")
    }
  end
end
