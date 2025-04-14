defmodule HexdocsMcp.MixDepsTest do
  use ExUnit.Case, async: false

  alias HexdocsMcp.MixDeps

  describe "read_deps/1" do
    setup do
      tmp_dir =
        Path.join(System.tmp_dir!(), "hexdocs_mcp_test_#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp_dir)
      on_exit(fn -> File.rm_rf!(tmp_dir) end)
      {:ok, tmp_dir: tmp_dir}
    end

    test "raises error when file doesn't exist" do
      assert_raise RuntimeError, "Mix file not found: nonexistent.exs", fn ->
        MixDeps.read_deps("nonexistent.exs")
      end
    end

    test "parses hex dependencies from mix.exs", %{tmp_dir: tmp_dir} do
      path =
        setup_test_mix_file(tmp_dir, """
        defmodule TestProject do
          use Mix.Project

          def project do
            [
              app: :test_app,
              version: "0.1.0",
              deps: [
                {:phoenix, "~> 1.7.0"},
                {:ecto, "~> 3.10"},
                {:local_dep, path: "../local"},
                {:git_dep, git: "https://github.com/user/repo"},
                {:hex_dep_with_opts, version: "1.0.0"},
                {:hex_dep_explicit, hex: "1.2.3"},
                {:hex_dep_with_requirement, "~> 2.0.0", hex: "hexpm"}
              ]
            ]
          end
        end
        """)

      deps = MixDeps.read_deps(path)

      assert deps == [
               {"phoenix", "~> 1.7.0"},
               {"ecto", "~> 3.10"},
               {"hex_dep_with_opts", "1.0.0"},
               {"hex_dep_explicit", "1.2.3"},
               {"hex_dep_with_requirement", "~> 2.0.0"}
             ]
    end

    test "handles no project function", %{tmp_dir: tmp_dir} do
      path =
        setup_test_mix_file(tmp_dir, """
        defmodule TestProject do
          use Mix.Project
        end
        """)

      assert_raise RuntimeError, fn ->
        MixDeps.read_deps(path)
      end
    end

    test "handles no deps in project", %{tmp_dir: tmp_dir} do
      path =
        setup_test_mix_file(tmp_dir, """
        defmodule TestProject do
          use Mix.Project

          def project do
            [
              app: :test_app,
              version: "0.1.0"
            ]
          end
        end
        """)

      assert MixDeps.read_deps(path) == []
    end

    test "handles empty deps list", %{tmp_dir: tmp_dir} do
      path =
        setup_test_mix_file(tmp_dir, """
        defmodule TestProject do
          use Mix.Project

          def project do
            [
              app: :test_app,
              version: "0.1.0",
              deps: []
            ]
          end
        end
        """)

      assert MixDeps.read_deps(path) == []
    end

    test "ignores non-hex dependencies", %{tmp_dir: tmp_dir} do
      path =
        setup_test_mix_file(tmp_dir, """
        defmodule TestProject do
          use Mix.Project

          def project do
            [
              app: :test_app,
              version: "0.1.0",
              deps: [
                {:local_dep, path: "../local"},
                {:git_dep, git: "https://github.com/user/repo"}
              ]
            ]
          end
        end
        """)

      assert MixDeps.read_deps(path) == []
    end

    test "handles invalid syntax", %{tmp_dir: tmp_dir} do
      path =
        setup_test_mix_file(tmp_dir, """
        defmodule TestProject do
          use Mix.Project

          def project do
            [
              app: :test_app,
              version: "0.1.0",
              deps: [
                {:invalid_dep,
            ]
          end
        end
        """)

      assert catch_error(MixDeps.read_deps(path))
    end

    test "handles deps with module attributes", %{tmp_dir: tmp_dir} do
      path =
        setup_test_mix_file(tmp_dir, """
        defmodule TestProject do
          use Mix.Project

          @version "1.0.0"

          def project do
            [
              app: :test_app,
              version: @version,
              deps: [
                {:phoenix, @version},
                {:ecto, "~> 3.0"}
              ]
            ]
          end
        end
        """)

      deps = MixDeps.read_deps(path)

      assert {"ecto", "~> 3.0"} in deps
    end
  end

  defp setup_test_mix_file(tmp_dir, content) do
    path = Path.join(tmp_dir, "test_mix.exs")
    File.write!(path, content)
    path
  end
end
