defmodule HexdocsMcp.CLITest do
  use HexdocsMcp.DataCase, async: true

  import Mox

  alias HexdocsMcp.CLI
  alias HexdocsMcp.Embeddings.Embedding

  setup :verify_on_exit!

  setup do
    system_command = HexdocsMcp.Config.system_command()
    [system_command: system_command]
  end

  test "no arguments shows usage", %{system_command: system_command} do
    assert capture_io(fn ->
             CLI.main([])
           end) =~ "Usage: #{system_command} COMMAND [options]"
  end

  test "invalid command shows usage", %{system_command: system_command} do
    assert capture_io(fn ->
             CLI.main(["invalid"])
           end) =~ "Usage: #{system_command} COMMAND [options]"
  end

  test "fetch initializes the database" do
    expect(HexdocsMcp.MockFetch, :main, fn _ -> :ok end)

    capture_io(fn ->
      CLI.main(["fetch", "test"])
      assert Repo.all(Embedding)
    end)
  end

  test "search initializes the database" do
    expect(HexdocsMcp.MockSearch, :main, fn _ -> :ok end)

    capture_io(fn ->
      CLI.main(["search"])
      assert Repo.all(Embedding)
    end)
  end
end
