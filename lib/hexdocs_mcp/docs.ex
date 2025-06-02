defmodule HexdocsMcp.Docs do
  @moduledoc false
  @behaviour HexdocsMcp.Behaviours.Docs

  alias HexdocsMcp.Behaviours.Docs

  @impl Docs
  def fetch(package, version) do
    args =
      case version do
        nil -> ["hex.docs", "fetch", package]
        "latest" -> ["hex.docs", "fetch", package]
        version -> ["hex.docs", "fetch", package, version]
      end

    result = System.cmd("mix", args, stderr_to_stdout: true)

    case result do
      {output, 0} -> {output, 0}
      {output, _} -> raise "Failed to fetch docs: \n#{output}"
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
