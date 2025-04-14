defmodule HexdocsMcp.CLI.Utils do
  @moduledoc """
  Utility functions shared across CLI modules.
  """

  @doc """
  Display a checkmark symbol with ANSI color.
  """
  def check do
    "#{IO.ANSI.green()}✓#{IO.ANSI.reset()}"
  end

  @doc """
  Output information to the console.
  Works with both Mix.shell() and IO for standalone executables.
  """
  def output_info(message) do
    if Code.ensure_loaded?(Mix) && function_exported?(Mix, :shell, 0) do
      Mix.shell().info(message)
    else
      IO.puts(message)
    end
  end

  @doc """
  Raise an error in Mix context or output error and exit in standalone context.
  """
  def output_error(message) do
    if Code.ensure_loaded?(Mix) && function_exported?(Mix, :raise, 1) do
      Mix.Shell.IO.error(message)
    else
      IO.puts(:stderr, "Error: #{message}")
      System.halt(1)
    end

    {:error, message}
  end

  @doc """
  Parse package and version arguments for CLI commands.

  Returns a tuple {package, version} where:
  - package is the package name or nil if not provided
  - version is the version or nil if not provided
  """
  def parse_package_args([package]) when is_binary(package), do: {package, nil}

  def parse_package_args([package, version]) when is_binary(package) and is_binary(version), do: {package, version}

  def parse_package_args(_), do: {nil, nil}
end
