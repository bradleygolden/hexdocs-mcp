defmodule HexdocsMcp.CLI.WatchTest do
  @moduledoc false

  use ExUnit.Case, async: false

  import ExUnit.CaptureIO
  import Mox

  alias HexdocsMcp.CLI.Watch

  setup :verify_on_exit!

  setup do
    if pid = Process.whereis(HexdocsMcp.MixLockWatcher) do
      Process.exit(pid, :normal)
      :timer.sleep(10)
    end

    on_exit(fn ->
      if pid = Process.whereis(HexdocsMcp.MixLockWatcher) do
        Process.exit(pid, :normal)
        :timer.sleep(10)
      end
    end)

    :ok
  end

  describe "main/1" do
    test "shows usage when no command is provided" do
      output = capture_io(fn -> Watch.main([]) end)
      assert output =~ "Usage:"
      assert output =~ "Commands:"
      assert output =~ "enable"
      assert output =~ "disable"
      assert output =~ "status"
    end

    test "enable command works when watcher not running" do
      output = capture_io(fn -> Watch.main(["enable"]) end)
      assert output =~ "Starting mix.lock watcher"
      assert output =~ "Watcher started successfully"
    end

    test "enable command works when watcher already running" do
      {:ok, _pid} = HexdocsMcp.MixLockWatcher.start_link(enabled: false)

      output = capture_io(fn -> Watch.main(["enable"]) end)
      assert output =~ "Watcher enabled"
    end

    test "disable command works" do
      {:ok, _pid} = HexdocsMcp.MixLockWatcher.start_link(enabled: true)

      output = capture_io(fn -> Watch.main(["disable"]) end)
      assert output =~ "Watcher disabled"
    end

    test "status command shows correct info" do
      tmp_dir = Path.join(System.tmp_dir!(), "hexdocs_mcp_watch_test_#{:rand.uniform(1000)}")
      File.mkdir_p!(tmp_dir)
      test_file = Path.join(tmp_dir, "mix.exs")
      File.write!(test_file, "")

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      {:ok, _pid} = HexdocsMcp.MixLockWatcher.start_link(enabled: true)
      :ok = HexdocsMcp.MixLockWatcher.add_project(test_file)

      output = capture_io(fn -> Watch.main(["status"]) end)
      assert output =~ "Status: enabled"
      assert output =~ "Poll interval:"
      assert output =~ "Watched projects:"
      assert output =~ test_file
    end

    test "now command triggers check" do
      {:ok, _pid} = HexdocsMcp.MixLockWatcher.start_link(enabled: true)

      output = capture_io(fn -> Watch.main(["now"]) end)
      assert output =~ "Checking for changes now"
      assert output =~ "Check triggered"
    end

    test "add command adds project" do
      tmp_dir = Path.join(System.tmp_dir!(), "hexdocs_mcp_watch_test_#{:rand.uniform(1000)}")
      File.mkdir_p!(tmp_dir)
      test_file = Path.join(tmp_dir, "mix.exs")
      File.write!(test_file, "")

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      {:ok, _pid} = HexdocsMcp.MixLockWatcher.start_link(enabled: true)

      output = capture_io(fn -> Watch.main(["add", test_file]) end)
      assert output =~ "Added project: #{test_file}"
    end

    test "remove command removes project" do
      tmp_dir = Path.join(System.tmp_dir!(), "hexdocs_mcp_watch_test_#{:rand.uniform(1000)}")
      File.mkdir_p!(tmp_dir)
      test_file = Path.join(tmp_dir, "mix.exs")
      File.write!(test_file, "")

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      {:ok, _pid} = HexdocsMcp.MixLockWatcher.start_link(enabled: true)
      :ok = HexdocsMcp.MixLockWatcher.add_project(test_file)

      output = capture_io(fn -> Watch.main(["remove", test_file]) end)
      assert output =~ "Removed project: #{test_file}"
    end
  end
end
