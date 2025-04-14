defmodule HexdocsMcp.Docs do
  @moduledoc false
  def fetch(package, version) do
    args =
      if version == "latest",
        do: ["hex.docs", "fetch", package],
        else: ["hex.docs", "fetch", package, version]

    result = System.cmd("mix", args, stderr_to_stdout: true)

    case result do
      {output, 0} -> {output, 0}
      {output, _} -> raise "Failed to fetch docs: \n#{output}"
    end
  end
end
