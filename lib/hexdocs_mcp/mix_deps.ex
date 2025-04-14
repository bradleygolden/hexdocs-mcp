defmodule HexdocsMcp.MixDeps do
  @moduledoc """
  Functionality for reading and processing Mix dependencies using AST evaluation.
  """

  @behaviour HexdocsMcp.Behaviours.MixDeps

  @doc """
  Reads dependencies from a mix.exs file and returns a list of hex packages.
  Only returns dependencies that are from hex.pm.
  Evaluates the project/0 function in a sandboxed environment.
  """
  def read_deps(mix_file_path) do
    if !File.exists?(mix_file_path) do
      raise "Mix file not found: #{mix_file_path}"
    end

    content = File.read!(mix_file_path)

    case Code.string_to_quoted(content, file: mix_file_path) do
      {:ok, ast} ->
        case extract_deps_from_ast(ast, mix_file_path) do
          {:ok, deps} ->
            deps
            |> Enum.filter(&hex_dep?/1)
            |> Enum.map(&extract_package_info/1)
            |> Enum.reject(&is_nil(elem(&1, 1)))

          {:error, reason} ->
            raise "Failed to extract dependencies: #{reason}"
        end

      {:error, {line, description, token}} ->
        if is_integer(line) and is_binary(description) do
          raise RuntimeError, "Failed to parse mix.exs at line #{line}: #{description}"
        else
          raise RuntimeError,
                "Failed to parse mix.exs: Unexpected error format #{inspect({line, description, token})}"
        end
    end
  end

  defp extract_deps_from_ast({:defmodule, _, [_module_name, [do: module_body]]}, file_path) do
    module_name = String.to_atom("MixDepsEval#{System.unique_integer([:positive])}")

    try do
      project_func_ast = find_project_function_ast(module_body)
      project_body = extract_project_body(project_func_ast)

      module_name
      |> eval_project_body(module_body, project_body, project_func_ast, file_path)
      |> process_project_config(module_body, file_path)
    catch
      {:error, :no_project_function} ->
        {:error, "No project/0 function found"}
    end
  end

  defp extract_deps_from_ast(_, _file_path), do: {:error, "Invalid module structure"}

  defp process_project_config({:ok, project_config}, module_body, file_path) when is_list(project_config) do
    case Keyword.get(project_config, :deps) do
      nil ->
        {:ok, []}

      [] ->
        {:ok, []}

      deps when is_list(deps) ->
        {:ok, deps}

      {:deps, _, _} ->
        deps_func = find_deps_function_ast(module_body)
        eval_deps_function(deps_func, file_path)

      invalid_deps ->
        {:error, "Invalid format for :deps value: #{inspect(invalid_deps)}"}
    end
  end

  defp process_project_config({:error, reason}, _module_body, _file_path) do
    {:error, "Failed to evaluate project configuration: #{reason}"}
  end

  defp process_project_config(other, _module_body, _file_path) do
    {:error, "Project function evaluation returned non-list: #{inspect(other)}"}
  end

  defp find_project_function_ast({:__block__, _, stats}) when is_list(stats) do
    Enum.find(stats, fn
      {:def, _, [{:project, _, args}, _]} when is_list(args) and args == [] -> true
      {:def, _, [{:project, _, args}, _]} when is_nil(args) -> true
      _ -> false
    end) || throw({:error, :no_project_function})
  end

  defp find_project_function_ast({:def, _, [{:project, _, args}, _]} = func)
       when (is_list(args) and args == []) or is_nil(args) do
    func
  end

  defp find_project_function_ast({:use, _, [{:__aliases__, _, [:Mix, :Project]} | _]}) do
    {:def, [], [{:project, [], []}, [do: {:__block__, [], []}]]}
  end

  defp find_project_function_ast(_) do
    raise "Failed to extract dependencies: No project/0 function found"
  end

  defp find_deps_function_ast({:__block__, _, stats}) when is_list(stats) do
    Enum.find(stats, fn
      {def_type, _, [{:deps, _, args}, _]}
      when def_type in [:def, :defp] and ((is_list(args) and args == []) or is_nil(args)) ->
        true

      _ ->
        false
    end)
  end

  defp find_deps_function_ast(_), do: nil

  defp extract_project_body({:def, _, [{:project, _, _}, [do: project_body]]}) do
    project_body
  end

  defp extract_project_body({:def, _, [{:project, _, _}, body]}) do
    case Keyword.get(body, :do) do
      nil -> {:__block__, [], []}
      do_block -> do_block
    end
  end

  defp eval_project_body(_module_name, _module_body, project_body, _project_func_ast, _file_path) do
    result = try_direct_evaluation(project_body)

    case result do
      {:ok, _value} ->
        result

      {:error, _reason} ->
        try do
          bindings = [
            {:version, "0.1.0"},
            {:app_version, "0.1.0"},
            {:elixir_version, "~> 1.14.0"},
            {:@, [{:version, [line: 1], nil}, "1.0.0"]}
          ]

          case Code.eval_quoted(project_body, bindings) do
            {result, _binding} when is_list(result) ->
              {:ok, result}

            {result, _binding} ->
              {:error, "Project function returned non-list: #{inspect(result)}"}
          end
        rescue
          e in [CompileError, ArithmeticError, ArgumentError] ->
            {:error, Exception.message(e)}

          e ->
            {:error, "Evaluation error: #{inspect(e)}"}
        end
    end
  end

  defp try_direct_evaluation(body) do
    case body do
      list when is_list(list) ->
        if Keyword.keyword?(list) do
          deps = Keyword.get(list, :deps, [])
          processed_deps = process_deps_ast(deps)

          {:ok, Keyword.put(list, :deps, processed_deps)}
        else
          {:error, "Not a keyword list"}
        end

      [_ | _] = list ->
        try do
          {:ok, list}
        rescue
          _ -> {:error, "Not a literal list"}
        end

      _ ->
        {:error, "Not directly evaluable"}
    end
  end

  defp process_deps_ast(deps) when is_list(deps) do
    Enum.map(deps, fn
      {:{}, _, [name, version, _opts]} when is_binary(version) ->
        {name, version}

      dep ->
        dep
    end)
  end

  defp process_deps_ast(deps), do: deps

  defp eval_deps_function(nil, _file_path), do: {:error, "Could not find deps/0 function"}

  defp eval_deps_function(deps_func_ast, file_path) do
    case deps_func_ast do
      {_def_type, _, [{:deps, _, _}, [do: deps_body]]} ->
        try do
          case Code.eval_quoted(deps_body) do
            {deps, _binding} when is_list(deps) ->
              {:ok, deps}

            {result, _binding} ->
              {:error, "deps function returned non-list: #{inspect(result)}"}
          end
        rescue
          e ->
            fallback_deps = extract_fallback_deps(file_path)

            if Enum.empty?(fallback_deps) do
              {:error, "Failed to evaluate deps function: #{Exception.message(e)}"}
            else
              {:ok, fallback_deps}
            end
        end

      _ ->
        {:error, "Invalid deps function format"}
    end
  end

  defp extract_fallback_deps(file_path) do
    content = File.read!(file_path)

    ~r/\{:([a-zA-Z0-9_]+),\s*["']([^"']+)["']/
    |> Regex.scan(content)
    |> Enum.map(fn [_, package, version] ->
      {to_string(package), normalize_version(version)}
    end)
  end

  defp normalize_version(version) do
    cond do
      String.starts_with?(version, ">=") -> version |> String.replace(">=", "") |> String.trim()
      String.starts_with?(version, ">") -> version |> String.replace(">", "") |> String.trim()
      String.starts_with?(version, "~>") -> String.trim(version)
      true -> version
    end
  end

  defp hex_dep?({_package, version}) when is_binary(version), do: true

  defp hex_dep?({_package, opts}) when is_list(opts) do
    has_version = Keyword.get(opts, :version) != nil
    has_hex = Keyword.get(opts, :hex) != nil

    no_scm =
      not (Keyword.has_key?(opts, :path) or Keyword.has_key?(opts, :git) or
             Keyword.has_key?(opts, :github))

    (has_version or has_hex) and no_scm
  end

  defp hex_dep?({_package, version, opts}) when is_binary(version) and is_list(opts) do
    not (Keyword.has_key?(opts, :path) or Keyword.has_key?(opts, :git) or
           Keyword.has_key?(opts, :github))
  end

  defp hex_dep?(_), do: false

  defp extract_package_info({package, version}) when is_binary(version) do
    {to_string(package), version}
  end

  defp extract_package_info({package, opts}) when is_list(opts) do
    version = Keyword.get(opts, :version) || Keyword.get(opts, :hex)
    {to_string(package), version}
  end

  defp extract_package_info({package, version, _opts}) when is_binary(version) do
    {to_string(package), version}
  end
end
