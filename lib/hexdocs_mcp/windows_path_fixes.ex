defmodule HexdocsMcp.WindowsPathFixes do
  @moduledoc """
  Custom build step for Burrito that fixes Windows path issues.
  This module is used in the burrito build pipeline to ensure that
  Windows path separators are handled correctly.
  """

  require Logger

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
    # This is particularly important for the bootfile path
    Map.update(context, :build_env, %{}, fn env ->
      Map.put(env, "BURRITO_WINDOWS_PATH_FIX", "true")
    end)
  end
end
