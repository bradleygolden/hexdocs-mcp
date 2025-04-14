defmodule HexdocsMcp.CLI.Watch do
  @moduledoc """
  Command-line interface for controlling the mix.lock file watcher.
  """

  @behaviour HexdocsMcp.Behaviours.CLI.Watch

  alias HexdocsMcp.CLI.Utils

  @usage """
  Usage: [SYSTEM_COMMAND] watch COMMAND

  Commands:
    enable       - Enable the mix.lock watcher
    disable      - Disable the mix.lock watcher
    status       - Show watcher status and watched projects
    now          - Trigger an immediate check for changes
    add PATH     - Add a project to watch (provide absolute path to mix.exs)
    remove PATH  - Remove a project from the watch list

  Environment Variables:
    HEXDOCS_MCP_WATCH_ENABLED  - Set to "true" or "1" to enable watching at startup
    HEXDOCS_MCP_WATCH_INTERVAL - Polling interval in milliseconds (default: 60000)
  """

  @doc """
  Main entry point for the watch command.
  """
  def main(args) do
    case args do
      ["enable" | _] -> enable_watcher()
      ["disable" | _] -> disable_watcher()
      ["status" | _] -> show_status()
      ["now" | _] -> check_now()
      ["add", path | _] -> add_project(path)
      ["remove", path | _] -> remove_project(path)
      _ -> show_usage()
    end
  end

  defp enable_watcher do
    case Process.whereis(HexdocsMcp.MixLockWatcher) do
      nil ->
        Utils.output_info("Starting mix.lock watcher...")
        {:ok, _} = HexdocsMcp.MixLockWatcher.start_link(enabled: true)
        Utils.output_info("#{Utils.check()} Watcher started successfully.")

      pid when is_pid(pid) ->
        HexdocsMcp.MixLockWatcher.set_enabled(true)
        Utils.output_info("#{Utils.check()} Watcher enabled.")
    end
  end

  defp disable_watcher do
    case Process.whereis(HexdocsMcp.MixLockWatcher) do
      nil ->
        Utils.output_info("Watcher is not running.")

      pid when is_pid(pid) ->
        HexdocsMcp.MixLockWatcher.set_enabled(false)
        Utils.output_info("#{Utils.check()} Watcher disabled.")
    end
  end

  defp show_status do
    # Check the persisted state file
    state_file = Path.join([HexdocsMcp.Config.data_path(), "watcher", "watcher_state.json"])

    if File.exists?(state_file) do
      try do
        state =
          state_file
          |> File.read!()
          |> Jason.decode!()

        enabled = Map.get(state, "enabled", false)
        project_paths = Map.get(state, "project_paths", [])

        Utils.output_info("Watcher configuration:")
        Utils.output_info("  • Status: #{if enabled, do: "enabled", else: "disabled"} (will apply on startup)")
        Utils.output_info("  • Poll interval: #{HexdocsMcp.Config.watch_poll_interval()}ms")

        show_watched_projects(project_paths)

        Utils.output_info("\nNote: The watcher runs only while the application is running.")
        Utils.output_info("To have it run continuously, you need to start the application and keep it running.")
      rescue
        e ->
          Utils.output_error("Error reading watcher state: #{Exception.message(e)}")
          Utils.output_info("Watcher status: not configured")
      end
    else
      Utils.output_info("Watcher status: not configured")
      Utils.output_info("Use 'watch enable' to enable the watcher.")
    end
  end

  defp check_now do
    case Process.whereis(HexdocsMcp.MixLockWatcher) do
      nil ->
        # Try to start the watcher first
        {:ok, _} = HexdocsMcp.MixLockWatcher.start_link()
        Utils.output_info("Watcher started. Checking for changes now...")
        HexdocsMcp.MixLockWatcher.check_now()
        Utils.output_info("#{Utils.check()} Check triggered.")

      pid when is_pid(pid) ->
        Utils.output_info("Checking for changes now...")
        HexdocsMcp.MixLockWatcher.check_now()
        Utils.output_info("#{Utils.check()} Check triggered.")
    end
  end

  defp add_project(path) do
    case Process.whereis(HexdocsMcp.MixLockWatcher) do
      nil ->
        # Start the watcher automatically
        {:ok, _} = HexdocsMcp.MixLockWatcher.start_link(enabled: true)
        Utils.output_info("Watcher started automatically.")

        case HexdocsMcp.MixLockWatcher.add_project(path) do
          :ok -> Utils.output_info("#{Utils.check()} Added project: #{path}")
          {:error, reason} -> Utils.output_error("Error: #{reason}")
        end

      pid when is_pid(pid) ->
        case HexdocsMcp.MixLockWatcher.add_project(path) do
          :ok -> Utils.output_info("#{Utils.check()} Added project: #{path}")
          {:error, reason} -> Utils.output_error("Error: #{reason}")
        end
    end
  end

  defp remove_project(path) do
    case Process.whereis(HexdocsMcp.MixLockWatcher) do
      nil ->
        # Start the watcher automatically
        {:ok, _} = HexdocsMcp.MixLockWatcher.start_link()
        Utils.output_info("Watcher started automatically.")

        case HexdocsMcp.MixLockWatcher.remove_project(path) do
          :ok -> Utils.output_info("#{Utils.check()} Removed project: #{path}")
          {:error, reason} -> Utils.output_error("Error: #{reason}")
        end

      pid when is_pid(pid) ->
        case HexdocsMcp.MixLockWatcher.remove_project(path) do
          :ok -> Utils.output_info("#{Utils.check()} Removed project: #{path}")
          {:error, reason} -> Utils.output_error("Error: #{reason}")
        end
    end
  end

  defp show_watched_projects(projects) do
    Utils.output_info("Watched projects:")

    if Enum.empty?(projects) do
      Utils.output_info("  No projects being watched")
    else
      Enum.each(projects, fn path -> Utils.output_info("  #{path}") end)
    end
  end

  defp show_usage do
    Utils.output_info(String.replace(@usage, "[SYSTEM_COMMAND]", HexdocsMcp.Config.system_command()))
  end
end
