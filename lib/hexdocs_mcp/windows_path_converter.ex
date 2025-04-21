defmodule HexdocsMcp.WindowsPathConverter do
  @moduledoc """
  Utility module to convert paths between Unix and Windows formats.
  This is used by the WindowsPathFixes module during the Burrito build process.
  """

  require Logger

  @doc """
  Converts all forward slashes in a path to backslashes for Windows compatibility.
  """
  def to_windows_path(path) when is_binary(path) do
    # Make sure we're using double backslashes to escape them properly
    String.replace(path, "/", "\\")
  end

  @doc """
  Converts all backslashes in a path to forward slashes for Unix compatibility.
  """
  def to_unix_path(path) when is_binary(path) do
    String.replace(path, "\\", "/")
  end

  @doc """
  Processes a file to convert all paths from Unix format to Windows format.
  This is useful for fixing boot scripts and other files that contain paths.
  """
  def convert_file_paths_to_windows(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        # Handle paths with drive letters (C:/path/to/file)
        new_content = Regex.replace(~r/([A-Za-z]:)(\/[^"'<>\s]*)/, content, fn _, drive, path ->
          drive <> String.replace(path, "/", "\\")
        end)

        # Handle paths that start with a forward slash but don't have a drive letter
        # This is more conservative - only match things that look like full paths
        new_content = Regex.replace(~r/(^|\s|\")(\/.+?\/.+?)(\s|\"|\n|$)/, new_content, fn _, prefix, path, suffix ->
          "#{prefix}#{String.replace(path, "/", "\\")}#{suffix}"
        end)

        # Special handling for app paths (specifically targeting bootfile paths)
        new_content = Regex.replace(~r/'((?:\/[^'\/]+)+)'/, new_content, fn _, path ->
          "'#{String.replace(path, "/", "\\")}'"
        end)

        # Special case for bootfile paths that appear with {'cannot get bootfile','path/to/file'}
        new_content = Regex.replace(~r/({'cannot get bootfile',')([^'}]+)('})/, new_content, fn _, prefix, path, suffix ->
          "#{prefix}#{String.replace(path, "/", "\\")}#{suffix}"
        end)

        # Specifically handle /bin/start.boot pattern that's causing the error
        new_content = Regex.replace(~r{/bin/start\.boot}, new_content, "\\\\bin\\\\start.boot")

        # Write back the modified content
        if new_content != content do
          File.write!(file_path, new_content)
          Logger.info("Converted paths in file: #{file_path}")
        else
          Logger.info("No path conversions needed in file: #{file_path}")
        end
        :ok

      {:error, reason} ->
        Logger.error("Error reading file for path conversion: #{file_path}, reason: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Recursively processes all files in a directory to convert paths.
  """
  def convert_directory_paths_to_windows(dir_path) do
    case File.ls(dir_path) do
      {:ok, files} ->
        Enum.each(files, fn file ->
          path = Path.join(dir_path, file)

          cond do
            File.dir?(path) ->
              convert_directory_paths_to_windows(path)

            String.ends_with?(file, [".boot", ".script", ".rel", ".config", ".bat", ".cmd"]) ->
              # These files likely contain paths that need conversion
              convert_file_paths_to_windows(path)

            true ->
              # Skip files that are unlikely to contain paths
              :ok
          end
        end)

      {:error, reason} ->
        Logger.error("Error listing directory for path conversion: #{dir_path}, reason: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
