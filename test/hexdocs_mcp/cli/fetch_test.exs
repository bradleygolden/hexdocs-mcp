defmodule HexdocsMcp.CLI.FetchTest do
  use HexdocsMcp.DataCase, async: false

  import Mox

  alias HexdocsMcp.CLI.Fetch
  alias HexdocsMcp.Embeddings
  alias HexdocsMcp.MockDocs

  setup :verify_on_exit!

  setup do
    system_command = HexdocsMcp.Config.system_command()
    [package: package(), version: "1.0.0", system_command: system_command]
  end

  test "fetching with package and version", %{package: package, version: version} do
    capture_io(fn ->
      assert :ok = Fetch.main([package, version])
    end)

    assert_markdown_files_generated(package, version)
    assert_chunks_generated(package, version)
    assert_embeddings_generated(package, version)
  end

  test "fetching with package only (latest version)", %{package: package} do
    version = "latest"

    capture_io(fn ->
      assert :ok = Fetch.main([package])
    end)

    assert_markdown_files_generated(package, version)
    assert_chunks_generated(package, version)
    assert_embeddings_generated(package, version)
  end

  test "fetching when embeddings already exist", %{package: package, version: version} do
    capture_io(fn ->
      assert :ok = Fetch.main([package, version])
    end)

    output =
      capture_io(fn ->
        assert :ok = Fetch.main([package, version])
      end)

    assert output =~ "already exist"
    assert output =~ "--force"
  end

  test "fetching with force flag when embeddings exist", %{package: package, version: version} do
    capture_io(fn ->
      assert :ok = Fetch.main([package, version])
    end)

    initial_count = count_embeddings(package, version)
    assert initial_count > 0

    output =
      capture_io(fn ->
        assert :ok = Fetch.main([package, version, "--force"])
      end)

    assert output =~ "Removed #{initial_count} existing embeddings"

    assert_markdown_files_generated(package, version)
    assert_chunks_generated(package, version)
    assert_embeddings_generated(package, version)

    assert count_embeddings(package, version) == initial_count
  end

  test "fetching with custom model", %{package: package, version: version} do
    custom_model = "all-minilm"

    output =
      capture_io(fn ->
        assert :ok = Fetch.main([package, version, "--model", custom_model])
      end)

    assert output =~ "using #{custom_model}"

    assert_markdown_files_generated(package, version)
    assert_chunks_generated(package, version)
    assert_embeddings_generated(package, version)
  end

  test "fetching with help flag", %{system_command: system_command} do
    output =
      capture_io(fn ->
        assert :ok = Fetch.main(["--help"])
      end)

    assert output =~ "Usage: #{system_command} fetch PACKAGE [VERSION]"
    assert output =~ "Arguments:"
    assert output =~ "PACKAGE"
    assert output =~ "VERSION"
    assert output =~ "Options:"
    assert output =~ "--model"
    assert output =~ "--force"
    assert output =~ "Examples:"
  end

  test "fetching with invalid package name" do
    package = "invalid/package"

    expect(MockDocs, :fetch, fn ^package, _ ->
      raise "Failed to fetch docs"
    end)

    capture_io(:stderr, fn ->
      assert {:error, message} = Fetch.main([])
      assert message =~ "Invalid arguments: missing package name"
    end)

    capture_io(:stderr, fn ->
      assert {:error, message} = Fetch.main(["--model", "test"])
      assert message =~ "Invalid arguments: missing package name"
    end)

    capture_io(fn ->
      assert_raise RuntimeError, "Failed to fetch docs", fn ->
        Fetch.main([package])
      end
    end)
  end

  test "fetching when docs fetch fails", %{package: package, version: version} do
    expect(MockDocs, :fetch, fn ^package, ^version ->
      raise "Failed to fetch docs"
    end)

    capture_io(fn ->
      assert_raise RuntimeError, "Failed to fetch docs", fn ->
        Fetch.main([package, version])
      end
    end)

    refute Embeddings.embeddings_exist?(package, version)
  end

  defp assert_markdown_files_generated(package, version) do
    package_path = Path.join([HexdocsMcp.Config.data_path(), package])

    filename =
      package_path
      |> File.ls!()
      |> Enum.find(fn filename -> filename == version <> ".md" end)
      |> String.split(".md")
      |> List.first()

    assert filename == version
  end

  defp assert_chunks_generated(package, _version) do
    chunk_filename = html_filename() |> String.split(".html") |> List.first()

    chunk_file =
      Path.join([
        HexdocsMcp.Config.data_path(),
        package,
        "chunks",
        chunk_filename <> "_chunk_0.json"
      ])

    assert File.exists?(chunk_file)
    assert {:ok, _} = chunk_file |> File.read!() |> JSON.decode()
  end

  defp assert_embeddings_generated(package, version) do
    assert Embeddings.embeddings_exist?(package, version)
  end

  defp count_embeddings(package, version) do
    query =
      from e in HexdocsMcp.Embeddings.Embedding,
        where: e.package == ^package and e.version == ^version,
        select: count(e.id)

    HexdocsMcp.Repo.one(query)
  end
end
