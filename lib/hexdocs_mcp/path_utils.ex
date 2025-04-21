defmodule HexdocsMcp.PathUtils do
  @moduledoc """
  Path utilities for handling cross-platform path issues.
  """

  @doc """
  Normalizes paths to ensure they use the correct path separators for the platform.
  This is particularly important for Windows, which needs backslashes instead of forward slashes.
  """
  def normalize_path(path) do
    case :os.type() do
      {:win32, _} -> String.replace(path, "/", "\\")
      _ -> path
    end
  end

  @doc """
  Returns the path to the ERTS bin directory, ensuring proper path separators.
  """
  def erts_bin_dir(path) do
    normalize_path(Path.join(path, "bin"))
  end

  @doc """
  Returns the path to the bootfile, ensuring proper path separators.
  """
  def bootfile_path(path) do
    normalize_path(Path.join(path, "bin/start.boot"))
  end
end
