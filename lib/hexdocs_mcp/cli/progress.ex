defmodule HexdocsMcp.CLI.Progress do
  @moduledoc """
  Utilities for displaying progress indicators in command-line interfaces.
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

  # Spinner animation frames
  @spinner_frames ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

  @doc ~S"""
  Displays a message, executes a function, and updates the message upon completion.

  ## Options

  * `:success_message` - Text appended after the original message on success (default: "[✓]")
  * `:failure_message` - Text appended after the original message on failure (default: "[✗]")

  ## Examples

      HexdocsMcp.CLI.Progress.with_spinner("Processing files", fn ->
        :timer.sleep(2000)
        {:ok, "Done!"}
      end)
      # Output initially: Processing files...
      # Output finally: Processing files [✓]

      HexdocsMcp.CLI.Progress.with_spinner("Downloading", fn ->
        :timer.sleep(1000)
        raise "Network Error"
      end, failure_message: "[Failed]")
      # Output initially: Downloading...
      # Output finally: Downloading [Failed]
  """
  def with_spinner(message, func, opts \\ []) do
    success_indicator = Keyword.get(opts, :success_message, "#{green()}✓#{reset()}")
    failure_indicator = Keyword.get(opts, :failure_message, "[#{red()}✗#{reset()}]")
    initial_message = "#{bright()}#{message}...#{reset()}"

    # Print initial message without newline
    IO.write(initial_message)

    try do
      result = func.()
      # Clear line and print success message
      clear_line = "\r\e[2K"
      IO.write(clear_line <> "#{success_indicator} #{bright()}#{message}#{reset()}\n")
      result
    catch
      kind, reason ->
        # Clear line and print failure message
        clear_line = "\r\e[2K"
        IO.write(clear_line <> "#{failure_indicator} #{bright()}#{message}#{reset()}\n")
        # Re-raise the original error
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  @doc """
  Displays a progress bar for a given total count.

  Returns a function that should be called with the current count.

  ## Examples

      progress = HexdocsMcp.CLI.Progress.progress_bar("Copying files", 100)
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
          IO.write("\n#{green()}✓#{reset()} #{bright()}#{message}#{reset()} completed\n")
        end

        # Store the last update time, percentage and count
        Process.put(:last_progress_update, now)
        Process.put(:last_progress_percentage, percentage)
        Process.put(:last_displayed_count, display_count)
      end

      count
    end
  end

  @doc """
  Creates a single-line workflow with animated spinner and checkmarks.

  Returns a tuple of two functions:
  - start_stage(stage_name) - Start a new stage with animated spinner
  - complete_workflow() - Complete the workflow with final checkmark

  ## Example

      {next_stage, complete} = HexdocsMcp.CLI.Progress.workflow(["Fetching", "Converting", "Processing"])
      
      next_stage.("Fetching")
      # do fetching work...
      
      next_stage.("Converting")
      # do conversion work...
      
      next_stage.("Processing")
      # do processing work...
      
      complete.()
  """
  def workflow(stages) do
    # Store state in process dictionary
    Process.put(:workflow_stages, stages)
    Process.put(:workflow_completed_stages, [])
    Process.put(:workflow_current_stage, nil)
    Process.put(:workflow_spinner_pid, nil)

    # Function to start a new stage
    start_stage = fn stage_name ->
      # Stop current spinner if it exists
      if pid = Process.get(:workflow_spinner_pid) do
        Process.exit(pid, :normal)
        Process.put(:workflow_spinner_pid, nil)
      end

      # Mark previous stage as completed if exists
      if current = Process.get(:workflow_current_stage) do
        completed = Process.get(:workflow_completed_stages, [])
        Process.put(:workflow_completed_stages, [current | completed])
      end

      # Set current stage
      Process.put(:workflow_current_stage, stage_name)

      # Start spinner for current stage
      pid = spawn_link(fn -> animate_spinner(stage_name) end)
      Process.put(:workflow_spinner_pid, pid)

      # Update display
      render_workflow_line()
    end

    # Function to complete the workflow
    complete_workflow = fn ->
      # Stop spinner
      if pid = Process.get(:workflow_spinner_pid) do
        Process.exit(pid, :normal)
        Process.put(:workflow_spinner_pid, nil)
      end

      # Mark all stages as complete
      if current = Process.get(:workflow_current_stage) do
        completed = Process.get(:workflow_completed_stages, [])
        Process.put(:workflow_completed_stages, [current | completed])
      end

      # Render final line with checkmark
      render_workflow_line(true)
    end

    {start_stage, complete_workflow}
  end

  # Private function to animate the spinner
  defp animate_spinner(stage_name) do
    Enum.reduce(Stream.cycle(@spinner_frames), 0, fn frame, i ->
      # Update spinner frame every 80ms
      :timer.sleep(80)

      # Render the workflow line with current spinner frame
      render_workflow_line(false, frame)

      # Check if we should exit
      if Process.get(:workflow_current_stage) != stage_name do
        throw(:exit)
      end

      i + 1
    end)
  catch
    :exit -> :ok
  end

  # Render the workflow line
  defp render_workflow_line(completed \\ false, spinner_frame \\ nil) do
    stages = Process.get(:workflow_stages, [])
    completed_stages = Process.get(:workflow_completed_stages, [])
    current_stage = Process.get(:workflow_current_stage)

    # Clear the line
    IO.write("\r\e[2K")

    # Build the workflow line
    line =
      Enum.map_join(stages, " → ", fn stage ->
        cond do
          stage in completed_stages ->
            "#{green()}✓#{reset()} #{stage}"

          stage == current_stage and not completed ->
            if spinner_frame,
              do: "#{cyan()}#{spinner_frame}#{reset()} #{stage}",
              else: "  #{stage}"

          true ->
            "  #{stage}"
        end
      end)

    # Add final checkmark if completed
    final_line =
      if completed do
        "#{line} #{green()}✓#{reset()}"
      else
        line
      end

    # Write the line
    IO.write(final_line)

    # Add newline if completed
    if completed do
      IO.write("\n")
    end
  end
end
