defmodule HexdocsMcp.WindowsPathFixes do
  @moduledoc """
  Custom build step for Burrito that fixes Windows path issues.
  This module is used in the burrito build pipeline to ensure that
  Windows path separators are handled correctly.
  """

  require Logger
  alias HexdocsMcp.WindowsPathConverter

  @doc """
  Entry point for the build step. It receives the Burrito context
  and returns the modified context.
  """
  def execute(context) do
    os_type = get_target_os(context)

    if os_type == :windows do
      Logger.info("Applying Windows path fixes for target '#{context.release.name}'")
      fix_windows_paths(context)
    else
      # Not a Windows build, pass through
      context
    end
  end

  defp get_target_os(%{burrito: %{target: target}}) do
    case Keyword.get(target, :os) do
      :windows -> :windows
      _ -> :other
    end
  end

  defp get_target_os(_), do: :other

  defp fix_windows_paths(context) do
    # Create a modified version of the context that ensures Windows path compatibility
    context = Map.update(context, :build_env, %{}, fn env ->
      env
      |> Map.put("BURRITO_WINDOWS_PATH_FIX", "true")
      # Ensure other Windows-specific environment variables are set
      |> Map.put("BURRITO_FORCE_WINDOWS_PATHS", "true")
    end)

    # For Windows, make sure the boot scripts have the correct path separators
    # Check if we're on a Unix-like OS (this will be true for macOS and Linux)
    case :os.type() do
      {:unix, _} ->
        # We're cross-compiling from a Unix system to Windows
        Logger.info("Cross-compiling to Windows from Unix-like system - applying boot script path fixes")

        # Fix paths in the build directory for Windows
        if release_path = Map.get(context, :work_dir) do
          release_path = Path.join(release_path, context.release.path)

          Logger.info("Fixing paths in build directory: #{release_path}")

          # Fix paths in the bin directory (contains start scripts)
          bin_dir = Path.join(release_path, "bin")
          if File.dir?(bin_dir) do
            Logger.info("Processing bin directory: #{bin_dir}")

            # Process .bat files to ensure paths are properly quoted
            bat_files = Path.wildcard(Path.join(bin_dir, "*.bat"))
            Enum.each(bat_files, fn bat_file ->
              Logger.info("Fixing and quoting paths in .bat file: #{bat_file}")
              fix_bat_file_paths(bat_file)
            end)

            # Process the start.boot file specially if it exists
            boot_files = Path.wildcard(Path.join([release_path, "**", "*.{boot,script}"]))

            if Enum.empty?(boot_files) do
              Logger.warning("No boot files found to process")
            else
              Enum.each(boot_files, fn boot_file ->
                Logger.info("Fixing paths in boot file: #{boot_file}")
                WindowsPathConverter.convert_file_paths_to_windows(boot_file)
              end)
            end
          end

          # Fix any other directories that may contain Windows paths
          config_files = Path.wildcard(Path.join([release_path, "**", "*.config"]))
          Enum.each(config_files, fn config_file ->
            Logger.info("Fixing paths in config file: #{config_file}")
            WindowsPathConverter.convert_file_paths_to_windows(config_file)
          end)
        else
          Logger.warning("Release path not found in context, skipping path fixes")
        end
      _ ->
        # Not on Unix system, no path fixes needed
        Logger.info("Not cross-compiling from Unix system - skipping boot script path fixes")
    end

    # Return the modified context
    context
  end

  # Add a new function to fix .bat files specifically
  defp fix_bat_file_paths(bat_file) do
    case File.read(bat_file) do
      {:ok, content} ->
        # Fix paths and also ensure they are properly quoted
        # Quote %RELEASE_ROOT%\bin\start and other similar patterns
        new_content = Regex.replace(~r/%([A-Za-z_]+)%\\bin\\start/, content, fn _, var ->
          "\"%\\1%\\bin\\start\""
        end)

        # Quote %ERTS_DIR%\bin\erl.exe and other similar patterns
        new_content = Regex.replace(~r/%([A-Za-z_]+)%\\([^%\s]+)/, new_content, fn _, var, path ->
          "\"%\\1%\\#{path}\""
        end)

        # Write back the modified content if changes were made
        if new_content != content do
          File.write!(bat_file, new_content)
          Logger.info("Fixed and quoted paths in .bat file: #{bat_file}")
        else
          Logger.info("No path quoting needed in .bat file: #{bat_file}")
        end
        :ok

      {:error, reason} ->
        Logger.error("Error reading .bat file for path quoting: #{bat_file}, reason: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
