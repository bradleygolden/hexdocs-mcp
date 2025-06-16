defmodule HexdocsMcp.CLI.FetchDocsTest do
  use HexdocsMcp.DataCase, async: false

  import Mox

  alias HexdocsMcp.CLI.FetchDocs
  alias HexdocsMcp.Embeddings
  alias HexdocsMcp.Fixtures
  alias HexdocsMcp.MockDocs

  setup :verify_on_exit!

  setup do
    system_command = HexdocsMcp.Config.system_command()
    [package: package(), version: "1.0.0", system_command: system_command]
  end

  test "fetching with package and version", %{package: package, version: version} do
    capture_io(fn ->
      assert :ok = FetchDocs.main([package, version])
    end)

    assert_markdown_files_generated(package, version)
    assert_chunks_generated(package, version)
    assert_embeddings_generated(package, version)
  end

  test "fetching with package only (latest version)", %{package: package} do
    version = "latest"

    capture_io(fn ->
      assert :ok = FetchDocs.main([package])
    end)

    assert_markdown_files_generated(package, version)
    assert_chunks_generated(package, version)
    assert_embeddings_generated(package, version)
  end

  test "fetching when embeddings already exist", %{package: package, version: version} do
    capture_io(fn ->
      assert :ok = FetchDocs.main([package, version])
    end)

    output =
      capture_io(fn ->
        assert :ok = FetchDocs.main([package, version])
      end)

    assert output =~ "already exist"
    assert output =~ "--force"
  end

  test "fetching with force flag when embeddings exist", %{package: package, version: version} do
    capture_io(fn ->
      assert :ok = FetchDocs.main([package, version])
    end)

    initial_count = count_embeddings(package, version)
    assert initial_count > 0

    output =
      capture_io(fn ->
        assert :ok = FetchDocs.main([package, version, "--force"])
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
        assert :ok = FetchDocs.main([package, version, "--model", custom_model])
      end)

    assert output =~ "using #{custom_model}"

    assert_markdown_files_generated(package, version)
    assert_chunks_generated(package, version)
    assert_embeddings_generated(package, version)
  end

  test "fetching with help flag", %{system_command: system_command} do
    output =
      capture_io(fn ->
        assert :ok = FetchDocs.main(["--help"])
      end)

    assert output =~ "Usage: #{system_command} fetch_docs PACKAGE [VERSION]"
    assert output =~ "Arguments:"
    assert output =~ "PACKAGE"
    assert output =~ "VERSION"
    assert output =~ "Options:"
    assert output =~ "--model"
    assert output =~ "--force"
    assert output =~ "--project"
    assert output =~ "Examples:"
  end

  test "fetching with invalid package name" do
    package = "invalid/package"

    expect(MockDocs, :fetch, fn ^package, _ ->
      raise "Failed to fetch docs"
    end)

    capture_io(:stderr, fn ->
      assert {:error, message} = FetchDocs.main([])
      assert message =~ "Invalid arguments: must specify either PACKAGE or --project PATH"
    end)

    capture_io(:stderr, fn ->
      assert {:error, message} = FetchDocs.main(["--model", "test"])
      assert message =~ "Invalid arguments: must specify either PACKAGE or --project PATH"
    end)

    capture_io(fn ->
      assert_raise RuntimeError, "Failed to fetch docs", fn ->
        FetchDocs.main([package])
      end
    end)
  end

  test "fetching when docs fetch fails", %{package: package, version: version} do
    expect(MockDocs, :fetch, fn ^package, ^version ->
      raise "Failed to fetch docs"
    end)

    capture_io(fn ->
      assert_raise RuntimeError, "Failed to fetch docs", fn ->
        FetchDocs.main([package, version])
      end
    end)

    refute Embeddings.embeddings_exist?(package, version)
  end

  test "fetching latest after a new release" do
    package = package()
    old_version = "1.0.0"
    new_version = "1.1.0"

    capture_io(fn ->
      assert :ok = FetchDocs.main([package, old_version])
    end)

    assert_embeddings_generated(package, old_version)

    expect(MockDocs, :get_latest_version, fn ^package ->
      {:ok, new_version}
    end)

    expect(MockDocs, :fetch, fn ^package, ^new_version ->
      hex_docs_path = Path.join([System.tmp_dir!(), "docs", "hexpm", package, new_version])
      File.mkdir_p!(hex_docs_path)
      File.write!(Path.join([hex_docs_path, Fixtures.html_filename()]), Fixtures.html())
      {"Docs fetched to #{hex_docs_path}", 0}
    end)

    capture_io(fn ->
      assert :ok = FetchDocs.main([package])
    end)

    assert_embeddings_generated(package, new_version)
  end

  test "fetching latest when API fails falls back to hex docs fetch", %{package: package} do
    expect(MockDocs, :get_latest_version, fn ^package ->
      {:error, "Failed to fetch package information: HTTP 404"}
    end)

    expect(MockDocs, :fetch, fn ^package, "latest" ->
      hex_docs_path = Path.join([System.tmp_dir!(), "docs", "hexpm", package, "1.2.3"])
      File.mkdir_p!(hex_docs_path)
      File.write!(Path.join([hex_docs_path, Fixtures.html_filename()]), Fixtures.html())
      {"Docs fetched to #{hex_docs_path}", 0}
    end)

    output =
      capture_io(fn ->
        assert :ok = FetchDocs.main([package])
      end)

    assert output =~ "Could not determine latest version"
    assert output =~ "Fetching docs anyway"
    assert_embeddings_generated(package, "1.2.3")
  end

  test "fetching latest when API fails and version extraction fails", %{package: package} do
    expect(MockDocs, :get_latest_version, fn ^package ->
      {:error, "Network timeout"}
    end)

    expect(MockDocs, :fetch, fn ^package, "latest" ->
      hex_docs_path = Path.join([System.tmp_dir!(), "invalid", "path", "structure"])
      File.mkdir_p!(hex_docs_path)
      File.write!(Path.join([hex_docs_path, Fixtures.html_filename()]), Fixtures.html())
      {"Docs fetched to #{hex_docs_path}", 0}
    end)

    output =
      capture_io(fn ->
        assert :ok = FetchDocs.main([package])
      end)

    assert output =~ "Could not determine latest version"
    assert output =~ "Fetching docs anyway"
    assert Embeddings.embeddings_exist?(package, "latest")
  end

  test "fetching latest with force flag when embeddings exist", %{package: package} do
    capture_io(fn ->
      assert :ok = FetchDocs.main([package, "1.0.0"])
    end)

    initial_count = count_embeddings(package, "1.0.0")
    assert initial_count > 0

    expect(MockDocs, :get_latest_version, fn ^package ->
      {:ok, "1.0.0"}
    end)

    expect(MockDocs, :fetch, fn ^package, "1.0.0" ->
      hex_docs_path = Path.join([System.tmp_dir!(), "docs", "hexpm", package, "1.0.0"])
      File.mkdir_p!(hex_docs_path)
      File.write!(Path.join([hex_docs_path, Fixtures.html_filename()]), Fixtures.html())
      {"Docs fetched to #{hex_docs_path}", 0}
    end)

    output =
      capture_io(fn ->
        assert :ok = FetchDocs.main([package, "--force"])
      end)

    assert output =~ "Latest version of #{package} is 1.0.0"
    assert output =~ "Removed #{initial_count} existing embeddings"
    assert_embeddings_generated(package, "1.0.0")
  end

  defp assert_markdown_files_generated(package, version) do
    package_path = Path.join([HexdocsMcp.Config.data_path(), package])

    expected_version = if version == "latest", do: "1.0.0", else: version

    filename =
      package_path
      |> File.ls!()
      |> Enum.find(fn filename -> filename == expected_version <> ".md" end)
      |> String.split(".md")
      |> List.first()

    assert filename == expected_version
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
    expected_version = if version == "latest", do: "1.0.0", else: version
    assert Embeddings.embeddings_exist?(package, expected_version)
  end

  defp count_embeddings(package, version) do
    query =
      from e in HexdocsMcp.Embeddings.Embedding,
        where: e.package == ^package and e.version == ^version,
        select: count(e.id)

    HexdocsMcp.Repo.one(query)
  end
end
