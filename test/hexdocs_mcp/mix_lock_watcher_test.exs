defmodule HexdocsMcp.MixLockWatcherTest do
  @moduledoc false

  use ExUnit.Case, async: false

  import Mox

  alias HexdocsMcp.MixLockWatcher

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    if pid = Process.whereis(MixLockWatcher) do
      Process.exit(pid, :kill)
      :timer.sleep(10)
    end

    state_file = Path.join([HexdocsMcp.Config.data_path(), "watcher", "watcher_state.json"])
    File.rm(state_file)

    tmp_dir = Path.join(System.tmp_dir!(), "hexdocs_mcp_watcher_test_#{:rand.uniform(1000)}")
    File.mkdir_p!(tmp_dir)

    mix_exs_path = Path.join(tmp_dir, "mix.exs")
    mix_lock_path = Path.join(tmp_dir, "mix.lock")

    File.write!(mix_exs_path, """
    defmodule TestMixProject do
      use Mix.Project

      def project do
        [
          app: :test_app,
          version: "0.1.0",
          deps: [
            {:phoenix, "~> 1.7.0"},
            {:ecto, "~> 3.10"}
          ]
        ]
      end
    end
    """)

    File.write!(mix_lock_path, """
    %{
      "phoenix": {:hex, :phoenix, "1.7.2", "test", "hexpm"},
      "ecto": {:hex, :ecto, "3.10.1", "test", "hexpm"}
    }
    """)

    Mox.stub(HexdocsMcp.MockMixDeps, :read_deps, fn _path ->
      [
        {"phoenix", "~> 1.7.0"},
        {"ecto", "~> 3.10"}
      ]
    end)

    on_exit(fn ->
      File.rm_rf!(tmp_dir)
    end)

    %{
      tmp_dir: tmp_dir,
      mix_exs_path: mix_exs_path,
      mix_lock_path: mix_lock_path
    }
  end

  describe "start_link/1" do
    test "starts the watcher with the correct configuration" do
      {:ok, pid} = MixLockWatcher.start_link(poll_interval: 100, enabled: false, project_paths: [])

      assert is_pid(pid)
      assert Process.alive?(pid)

      state = :sys.get_state(pid)
      assert state.poll_interval == 100
      assert state.enabled == false
      assert is_list(state.project_paths)
      assert is_map(state.lock_states)
    end
  end

  describe "get_projects/0" do
    test "returns empty list when no projects being watched" do
      {:ok, _pid} = MixLockWatcher.start_link(poll_interval: 100, enabled: false, project_paths: [])

      assert MixLockWatcher.get_projects() == []
    end
  end

  describe "add_project/1 and remove_project/1" do
    test "adds and removes a project from the watch list", %{mix_exs_path: mix_exs_path} do
      {:ok, _pid} = MixLockWatcher.start_link(poll_interval: 100, enabled: false, project_paths: [])

      assert :ok = MixLockWatcher.add_project(mix_exs_path)
      assert MixLockWatcher.get_projects() == [mix_exs_path]

      assert :ok = MixLockWatcher.remove_project(mix_exs_path)
      assert MixLockWatcher.get_projects() == []
    end

    test "returns error when adding non-existent project" do
      {:ok, _pid} = MixLockWatcher.start_link(poll_interval: 100, enabled: false, project_paths: [])

      assert {:error, _} = MixLockWatcher.add_project("/this/path/does/not/exist.exs")
    end

    test "returns error when removing project that isn't being watched", %{mix_exs_path: mix_exs_path} do
      {:ok, _pid} = MixLockWatcher.start_link(poll_interval: 100, enabled: false, project_paths: [])

      assert {:error, _} = MixLockWatcher.remove_project(mix_exs_path)
    end
  end

  describe "set_enabled/1" do
    test "enables and disables the watcher" do
      {:ok, pid} = MixLockWatcher.start_link(poll_interval: 100, enabled: false, project_paths: [])

      assert :ok = MixLockWatcher.set_enabled(true)
      assert :sys.get_state(pid).enabled == true

      assert :ok = MixLockWatcher.set_enabled(false)
      assert :sys.get_state(pid).enabled == false
    end
  end

  describe "check_now/0" do
    test "triggers an immediate check" do
      {:ok, _pid} = MixLockWatcher.start_link(poll_interval: 1000, enabled: true, project_paths: [])

      # We can't easily test the actual behavior, but we can ensure it doesn't crash
      assert MixLockWatcher.check_now() == :ok
    end
  end

  describe "detecting changes" do
    test "detects changes to mix.lock file", %{mix_exs_path: mix_exs_path, mix_lock_path: mix_lock_path} do
      Mox.stub(HexdocsMcp.MockEmbeddings, :embeddings_exist?, fn _, _ -> false end)
      Mox.stub(HexdocsMcp.MockDocs, :fetch, fn _, _ -> {"/test/docs", 0} end)

      parent = self()
      ref = make_ref()

      Mox.expect(HexdocsMcp.MockMixLockWatcher, :process_changed_project, fn path ->
        send(parent, {:project_processed, ref, path})
        :ok
      end)

      Application.put_env(:hexdocs_mcp, :mix_lock_watcher_module, HexdocsMcp.MockMixLockWatcher)

      on_exit(fn ->
        Application.delete_env(:hexdocs_mcp, :mix_lock_watcher_module)
      end)

      {:ok, _pid} = MixLockWatcher.start_link(poll_interval: 100, enabled: true, project_paths: [])
      assert :ok = MixLockWatcher.add_project(mix_exs_path)

      :timer.sleep(150)

      File.write!(mix_lock_path, """
      %{
        "phoenix": {:hex, :phoenix, "1.7.3", "updated_hash", "hexpm"},
        "ecto": {:hex, :ecto, "3.10.1", "test", "hexpm"}
      }
      """)

      MixLockWatcher.check_now()

      assert_receive {:project_processed, ^ref, ^mix_exs_path}, 500
    end
  end
end
