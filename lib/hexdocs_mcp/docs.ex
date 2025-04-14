defmodule HexdocsMcp.Docs do
  @moduledoc false
  def fetch(package, version) do
    # Convert package and version to strings to ensure they're binaries
    package_str = to_string(package)
    version_str = if version, do: to_string(version), else: "latest"
    
    args =
      if version_str == "latest",
        do: ["hex.docs", "fetch", package_str],
        else: ["hex.docs", "fetch", package_str, version_str]

    result = System.cmd("mix", args, stderr_to_stdout: true)

    case result do
      {output, 0} -> {output, 0}
      {output, _} -> raise "Failed to fetch docs: \n#{output}"
    end
  end
end
