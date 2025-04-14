defmodule HexdocsMcp.MixLockWatcher do
  @moduledoc """
  A GenServer that periodically polls mix.lock files for changes and triggers
  automatic fetching of project dependencies that are declared in the associated mix.exs files.
  """

  @behaviour HexdocsMcp.Behaviours.MixLockWatcher

  use GenServer

  alias HexdocsMcp.CLI.Fetch

  require Logger

  @default_poll_interval 60_000

  @state_file_name "watcher_state.json"

  # Client API

  @doc """
  Starts the mix.lock watcher process.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Manually trigger a check for mix.lock changes.
  """
  def check_now do
    case ensure_watcher_running() do
      {:ok, _pid} -> GenServer.cast(__MODULE__, :check_now)
      _ -> {:error, "Failed to start watcher"}
    end
  end

  @doc """
  Enable or disable the watcher.
  """
  def set_enabled(enabled) when is_boolean(enabled) do
    case ensure_watcher_running() do
      {:ok, _pid} ->
        GenServer.call(__MODULE__, {:set_enabled, enabled})
        save_state()

      _ ->
        {:error, "Failed to start watcher"}
    end
  end

  @doc """
  Add a project to watch.
  """
  def add_project(project_path) do
    if File.exists?(project_path) do
      case ensure_watcher_running() do
        {:ok, _pid} ->
          result = GenServer.call(__MODULE__, {:add_project, project_path})
          save_state()
          result

        _ ->
          {:error, "Failed to start watcher"}
      end
    else
      {:error, "Project file does not exist: #{project_path}"}
    end
  end

  @doc """
  Remove a project from the watch list.
  """
  def remove_project(project_path) do
    case ensure_watcher_running() do
      {:ok, _pid} ->
        result = GenServer.call(__MODULE__, {:remove_project, project_path})
        save_state()
        result

      _ ->
        {:error, "Failed to start watcher"}
    end
  end

  @doc """
  Get the list of projects being watched.
  """
  def get_projects do
    case ensure_watcher_running() do
      {:ok, _pid} -> GenServer.call(__MODULE__, :get_projects)
      _ -> []
    end
  end

  @doc """
  Check if the watcher is enabled
  """
  def enabled? do
    case ensure_watcher_running() do
      {:ok, _pid} -> GenServer.call(__MODULE__, :get_status)
      _ -> false
    end
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    poll_interval = Keyword.get(opts, :poll_interval, @default_poll_interval)

    {enabled, project_paths} =
      case {Keyword.get(opts, :enabled), Keyword.get(opts, :project_paths)} do
        {nil, nil} -> load_state()
        {enabled, nil} -> {enabled || get_env_enabled(), elem(load_state(), 1)}
        {nil, paths} -> {get_env_enabled(), paths}
        {enabled, paths} -> {enabled, paths}
      end

    if enabled, do: schedule_check(poll_interval)
    lock_states = init_lock_states(project_paths)

    state = %{
      poll_interval: poll_interval,
      enabled: enabled,
      project_paths: project_paths,
      lock_states: lock_states
    }

    save_state(state)

    {:ok, state}
  end

  @impl true
  def handle_info(:check_locks, %{enabled: false} = state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(:check_locks, state) do
    %{poll_interval: poll_interval, project_paths: project_paths, lock_states: lock_states} = state

    {updated_lock_states, changed_projects} = check_for_changes(project_paths, lock_states)

    watcher_module = HexdocsMcp.Config.mix_lock_watcher_module()
    Enum.each(changed_projects, &watcher_module.process_changed_project/1)

    schedule_check(poll_interval)

    {:noreply, %{state | lock_states: updated_lock_states}}
  end

  @impl true
  def handle_cast(:check_now, state) do
    if state.enabled do
      send(self(), :check_locks)
    end

    {:noreply, state}
  end

  @impl true
  def handle_call({:set_enabled, enabled}, _from, state) do
    if enabled && !state.enabled do
      schedule_check(state.poll_interval)
    end

    {:reply, :ok, %{state | enabled: enabled}}
  end

  @impl true
  def handle_call({:add_project, project_path}, _from, state) do
    if project_path in state.project_paths do
      {:reply, {:error, "Project already being watched"}, state}
    else
      project_paths = [project_path | state.project_paths]
      lock_states = Map.put(state.lock_states, project_path, get_lock_file_state(project_path))

      {:reply, :ok, %{state | project_paths: project_paths, lock_states: lock_states}}
    end
  end

  @impl true
  def handle_call({:remove_project, project_path}, _from, state) do
    if project_path in state.project_paths do
      project_paths = List.delete(state.project_paths, project_path)
      lock_states = Map.delete(state.lock_states, project_path)

      {:reply, :ok, %{state | project_paths: project_paths, lock_states: lock_states}}
    else
      {:reply, {:error, "Project not being watched"}, state}
    end
  end

  @impl true
  def handle_call(:get_projects, _from, state) do
    {:reply, state.project_paths, state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    {:reply, state.enabled, state}
  end

  # Private Functions

  defp schedule_check(interval) do
    Process.send_after(self(), :check_locks, interval)
  end

  defp init_lock_states(project_paths) do
    Enum.reduce(project_paths, %{}, fn path, acc ->
      Map.put(acc, path, get_lock_file_state(path))
    end)
  end

  defp check_for_changes(project_paths, lock_states) do
    Enum.reduce(project_paths, {lock_states, []}, fn path, {states_acc, changed_acc} ->
      current_state = get_lock_file_state(path)
      previous_state = Map.get(states_acc, path)

      if has_changed?(current_state, previous_state) do
        {Map.put(states_acc, path, current_state), [path | changed_acc]}
      else
        {states_acc, changed_acc}
      end
    end)
  end

  defp get_lock_file_state(mix_exs_path) do
    dir = Path.dirname(mix_exs_path)
    lock_path = Path.join(dir, "mix.lock")

    if File.exists?(lock_path) do
      case File.stat(lock_path) do
        {:ok, %{mtime: mtime, size: size}} ->
          {mtime, size}

        _ ->
          nil
      end
    end
  end

  defp has_changed?(current_state, previous_state) do
    current_state != previous_state
  end

  @impl HexdocsMcp.Behaviours.MixLockWatcher
  def process_changed_project(mix_exs_path) do
    log_info("Detected changes in mix.lock for project: #{mix_exs_path}")

    context = %Fetch.Context{
      project_path: mix_exs_path,
      model: HexdocsMcp.Config.default_embedding_model(),
      force?: false,
      help?: false,
      embeddings_module: HexdocsMcp.Config.embeddings_module()
    }

    Task.start(fn ->
      try do
        Fetch.process_project_deps(context)
      rescue
        e -> log_error("Error processing changed project: #{Exception.message(e)}")
      end
    end)

    :ok
  end

  defp get_env_enabled do
    env_var = System.get_env("HEXDOCS_MCP_WATCH_ENABLED")

    cond do
      is_nil(env_var) -> false
      env_var == "true" -> true
      env_var == "1" -> true
      true -> false
    end
  end

  # State persistence functions

  defp get_state_file do
    Path.join([HexdocsMcp.Config.data_path(), "watcher", @state_file_name])
  end

  defp ensure_watcher_running do
    case Process.whereis(__MODULE__) do
      nil ->
        {enabled, projects} = load_state()
        start_link(enabled: enabled, project_paths: projects)

      pid ->
        {:ok, pid}
    end
  end

  defp save_state do
    if pid = Process.whereis(__MODULE__) do
      state = :sys.get_state(pid)
      save_state(state)
    end
  end

  defp save_state(state) do
    state_file = get_state_file()
    dir = Path.dirname(state_file)

    serialized_state = %{
      "enabled" => state.enabled,
      "project_paths" => state.project_paths
    }

    try do
      File.mkdir_p!(dir)

      json = Jason.encode!(serialized_state)
      File.write!(state_file, json)

      Logger.debug("Saved watcher state to #{state_file}: #{json}")
      :ok
    rescue
      e ->
        Logger.error("Failed to save watcher state: #{Exception.message(e)}")
        :error
    end
  end

  defp load_state do
    state_file = get_state_file()

    if File.exists?(state_file) do
      try do
        state =
          state_file
          |> File.read!()
          |> Jason.decode!()

        enabled = Map.get(state, "enabled", false)
        project_paths = Map.get(state, "project_paths", [])

        Logger.debug("Loaded watcher state from #{state_file}: enabled=#{enabled}, projects=#{inspect(project_paths)}")

        {enabled, project_paths}
      rescue
        e ->
          Logger.error("Failed to load watcher state: #{Exception.message(e)}")
          {get_env_enabled(), []}
      end
    else
      Logger.debug("No state file found at #{state_file}, using defaults")
      {get_env_enabled(), []}
    end
  end

  defp log_info(message), do: Logger.info(message)
  defp log_error(message), do: Logger.error(message)
end
