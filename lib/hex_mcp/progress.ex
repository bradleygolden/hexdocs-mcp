defmodule HexMcp.Progress do
  @moduledoc """
  Utilities for displaying progress in command-line applications.
  """

  # Import ANSI colors and formatting functions
  import IO.ANSI,
    only: [
      green: 0,
      yellow: 0,
      reset: 0,
      bright: 0,
      cyan: 0,
      # Added red for errors
      red: 0
    ]

  @doc ~S"""
  Displays a message, executes a function, and updates the message upon completion.

  ## Options

  * `:success_message` - Text appended after the original message on success (default: "[✓]")
  * `:failure_message` - Text appended after the original message on failure (default: "[✗]")

  ## Examples

      HexMcp.Progress.with_spinner("Processing files", fn ->
        :timer.sleep(2000)
        {:ok, "Done!"}
      end)
      # Output initially: Processing files...
      # Output finally: Processing files [✓]

      HexMcp.Progress.with_spinner("Downloading", fn ->
        :timer.sleep(1000)
        raise "Network Error"
      end, failure_message: "[Failed]")
      # Output initially: Downloading...
      # Output finally: Downloading [Failed]
  """
  def with_spinner(message, func, opts \\ []) do
    success_indicator = Keyword.get(opts, :success_message, "[#{green()}✓#{reset()}]")
    failure_indicator = Keyword.get(opts, :failure_message, "[#{red()}✗#{reset()}]")
    initial_message = "#{bright()}#{message}...#{reset()}"

    # Print initial message without newline
    IO.write(initial_message)

    try do
      result = func.()
      # Clear line and print success message
      clear_line = "\r\e[2K"
      IO.write(clear_line <> "#{bright()}#{message}#{reset()} #{success_indicator}\n")
      result
    catch
      kind, reason ->
        # Clear line and print failure message
        clear_line = "\r\e[2K"
        IO.write(clear_line <> "#{bright()}#{message}#{reset()} #{failure_indicator}\n")
        # Re-raise the original error
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  @doc """
  Displays a progress bar for a given total count.

  Returns a function that should be called with the current count.

  ## Examples

      progress = HexMcp.Progress.progress_bar("Copying files", 100)
      Enum.each(1..100, fn i ->
        :timer.sleep(50)  # Do some work
        progress.(i)
      end)
  """
  def progress_bar(message, total) do
    # Store the last update time in process dictionary
    # to limit update rate
    Process.put(:last_progress_update, 0)
    # Store the last percentage to avoid redrawing when not needed
    Process.put(:last_progress_percentage, -1)
    # Store the last displayed count to maintain consistency
    Process.put(:last_displayed_count, 0)

    # Bar configuration
    # Characters for the bar itself
    bar_length = 20

    # Simple progress bar that avoids flashing by limiting updates
    fn count ->
      now = System.monotonic_time(:millisecond)
      last_update = Process.get(:last_progress_update, 0)

      # Calculate percentage
      percentage = trunc(count / total * 100)
      last_percentage = Process.get(:last_progress_percentage, -1)

      # Ensure count never decreases - this prevents "jumping backward"
      last_displayed_count = Process.get(:last_displayed_count, 0)
      display_count = max(count, last_displayed_count)

      # Only update if:
      # 1. It's been at least 250ms since last update, and count increased, or
      # 2. This is the final update (100%), or
      # 3. Percentage changed significantly (e.g., by 5%)
      # Increased interval to reduce noise
      update_interval_ms = 250
      # Update only on larger percentage jumps
      percentage_change_threshold = 5

      if count >= total ||
           (now - last_update >= update_interval_ms && count > last_displayed_count) ||
           abs(percentage - last_percentage) >= percentage_change_threshold do
        # Calculate the number of bar segments to fill
        filled_length = trunc(bar_length * display_count / total)

        # Create the bar
        bar =
          String.duplicate("█", filled_length) <>
            String.duplicate("░", bar_length - filled_length)

        # Format the message and numbers with colors
        percent_str = String.pad_leading("#{percentage}%", 4)
        count_str = String.pad_leading("#{display_count}", String.length("#{total}"))

        # Enhanced progress bar with color and visual elements
        # Use \r\e[2K to clear the line before writing to prevent flicker
        IO.write(
          # Clear line first
          "\r\e[2K" <>
            "#{bright()}#{message}#{reset()}: " <>
            "#{cyan()}#{bar}#{reset()} " <>
            "#{yellow()}#{percent_str}#{reset()} " <>
            "(#{bright()}#{count_str}#{reset()}/#{total})"
          # Removed extra padding as clear line handles overwriting
        )

        # If we're done, add a completion message on a new line
        if count >= total do
          IO.write(
            "\n#{green()}✓ #{bright()}#{message}#{reset()} #{green()}completed#{reset()}\n"
          )
        end

        # Store the last update time, percentage and count
        Process.put(:last_progress_update, now)
        Process.put(:last_progress_percentage, percentage)
        Process.put(:last_displayed_count, display_count)
      end

      count
    end
  end
end
