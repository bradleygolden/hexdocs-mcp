defmodule HexdocsMcp.Markdown do
  @moduledoc false
  def from_html(html) do
    html
    |> preprocess_content()
    |> convert_to_markdown()
  end

  defp preprocess_content(content) do
    content
    |> prep_document()
    |> Floki.parse_document!()
    |> extract_main_content()
    |> Floki.filter_out(:comment)
    |> remove_non_content_tags()
    |> remove_nav_elements()
  end

  defp extract_main_content(document) do
    main_content = Floki.find(document, "main.content, #content, .content-inner, article, [role='main']")

    case main_content do
      [] -> Floki.find(document, "body")
      content -> content
    end
  end

  defp prep_document(content) do
    if html_document?(content), do: content, else: wrap_fragment(content)
  end

  defp html_document?(content) do
    content
    |> String.downcase()
    |> String.contains?(["<html", "<body", "<head"])
  end

  defp wrap_fragment(fragment), do: "<html><body>#{fragment}</body></html>"

  @non_content_tags [
    "aside",
    "audio",
    "base",
    "button",
    "datalist",
    "embed",
    "form",
    "iframe",
    "input",
    "keygen",
    "nav",
    "noscript",
    "object",
    "output",
    "script",
    "select",
    "source",
    "style",
    "svg",
    "template",
    "textarea",
    "track",
    "video"
  ]

  defp remove_non_content_tags(document) do
    Enum.reduce(@non_content_tags, document, &Floki.filter_out(&2, &1))
  end

  @navigation_classes [
    "footer",
    "menu",
    "nav",
    "sidebar",
    "aside",
    "sidebar-list",
    "sidebar-list-nav",
    "section-nav",
    "api-reference-list",
    "module-list"
  ]

  @navigation_ids [
    "sidebar",
    "sidebar-menu",
    "sidebar-list",
    "sidebar-list-nav",
    "module-index",
    "api-reference",
    "navigation",
    "nav-menu"
  ]

  defp remove_nav_elements(document) do
    Floki.find_and_update(document, "*", &process_nav_element/1)
  end

  defp process_nav_element({tag, attrs} = element) when is_list(attrs) do
    cond do
      should_delete_by_class?(attrs) && tag != "body" -> :delete
      should_delete_by_id?(attrs) && tag != "body" -> :delete
      should_delete_module_listing?(tag, attrs) -> :delete
      true -> element
    end
  end

  defp process_nav_element(element), do: element

  defp should_delete_by_class?(attrs) do
    case List.keyfind(attrs, "class", 0) do
      {"class", class} -> contains_nav_class?(class)
      _ -> false
    end
  end

  defp should_delete_by_id?(attrs) do
    case List.keyfind(attrs, "id", 0) do
      {"id", id} -> id in @navigation_ids
      _ -> false
    end
  end

  defp should_delete_module_listing?(tag, attrs) do
    # Remove module listing sections that appear on API reference pages
    # Only when they're specifically module lists, not when they're part of actual documentation
    case {tag, List.keyfind(attrs, "class", 0), List.keyfind(attrs, "id", 0)} do
      {"section", {"class", "details-list"}, {"id", "modules"}} ->
        true

      {"section", {"class", "details-list"}, {"id", "types"}} ->
        false

      {"section", {"class", "details-list"}, {"id", "summary"}} ->
        false

      {"section", {"class", class}, _} when tag == "section" ->
        String.contains?(class, "module-list") || String.contains?(class, "api-reference-list")

      {"div", {"class", class}, _} ->
        String.contains?(class, "module-list")

      _ ->
        false
    end
  end

  defp contains_nav_class?(class) do
    class_list = String.split(class, " ")
    Enum.any?(@navigation_classes, &Enum.member?(class_list, &1))
  end

  defp convert_to_markdown(document) do
    document
    |> process_node()
    |> String.trim()
  end

  defp process_node(document) when is_list(document) do
    Enum.map_join(document, "", &process_node/1)
  end

  defp process_node({tag, _, children} = _node) when tag in ["h1", "h2", "h3", "h4", "h5", "h6"] do
    level = String.to_integer(String.last(tag))
    heading_marker = String.duplicate("#", level)
    newline() <> heading_marker <> " " <> process_children(children) <> newline()
  end

  defp process_node({"p", _, children}), do: process_children(children) <> newline(2)

  defp process_node({"ul", _, children}), do: process_ul_list(children)

  defp process_node({"ol", _, children}), do: process_ol_list(children)

  defp process_node({"details", _, children}), do: process_children(children) <> newline()

  defp process_node({"summary", _, children}), do: "**#{process_children(children)}**" <> newline()

  defp process_node({"pre", _, [{"code", [{"class", classes}], children}]}), do: process_code_block(classes, children)

  defp process_node({"pre", _, children}), do: process_code_block(children)

  defp process_node({"blockquote", _, children}), do: newline() <> "> #{process_children(children)}" <> newline()

  defp process_node({"table", _, children}), do: process_table(children)

  defp process_node({"strong", _, children}), do: "**#{process_children(children)}**"

  defp process_node({"b", _, children}), do: "**#{process_children(children)}**"

  defp process_node({"em", _, children}), do: "*#{process_children(children)}*"

  defp process_node({"i", _, children}), do: "*#{process_children(children)}*"

  defp process_node({"u", _, children}), do: "<u>#{process_children(children)}</u>"

  defp process_node({"del", _, children}), do: "~~#{process_children(children)}~~"

  defp process_node({"sup", _, children}), do: "<sup>#{process_children(children)}</sup>"

  defp process_node({"sub", _, children}), do: "<sub>#{process_children(children)}</sub>"

  defp process_node({"code", _, children}), do: "`#{process_children(children)}`"

  defp process_node({"a", attrs, children}), do: process_href(attrs, children)

  defp process_node({"img", [{"src", src}, {"alt", alt}], _}), do: "![#{alt}](#{src})"

  defp process_node({"caption", _, children}), do: "| " <> process_children(children) <> " |" <> newline()

  defp process_node({"figcaption", _, children}), do: "**#{process_children(children)}**"

  defp process_node({"br", _, _}), do: newline(2)

  defp process_node({"hr", _, _}), do: newline() <> newline() <> "---" <> newline(2)

  defp process_node({"section", _, children}), do: newline() <> "#{process_children(children)}" <> newline()

  defp process_node({"article", _, children}), do: newline() <> "#{process_children(children)}" <> newline()

  defp process_node({"picture", _, children}) do
    with {"img", attrs, _} <- Enum.find(children, fn {tag, _, _} -> tag == "img" end),
         %{"alt" => alt, "src" => src} <- Map.new(attrs) do
      "![#{alt}](#{src})"
    end
  end

  defp process_node({"div", _, children}), do: "#{process_children(children)}" <> newline()

  defp process_node({_, _, children}), do: process_children(children)

  defp process_node(text) when is_binary(text), do: String.trim(text)

  defp process_href(attrs, children) do
    case Enum.find(attrs, fn {attr, _} -> attr == "href" end) do
      {"href", url} ->
        case process_children(children) do
          "" -> "[#{url}](#{url})"
          children -> "[#{children}](#{url})"
        end

      _ ->
        process_children(children)
    end
  end

  defp process_code_block(children) do
    newline() <> "```\n#{process_children(children)}\n```" <> newline()
  end

  defp process_code_block(classes, children) do
    language = detect_language(classes)
    newline() <> "```#{language}\n#{process_children(children)}\n```" <> newline()
  end

  defp detect_language(classes) do
    case Regex.run(~r/language-(\w+)/, classes) do
      [_, lang] -> lang
      _ -> ""
    end
  end

  defp process_ul_list(children) when is_list(children) do
    newline() <> Enum.map_join(children, "\n", &process_list_item/1) <> newline()
  end

  defp process_ol_list(children) when is_list(children) do
    ol_list =
      children
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {child, index} ->
        process_ordered_list_item(child, index + 1)
      end)

    newline() <> ol_list <> newline()
  end

  defp process_list_item({"li", _, children}), do: "- " <> process_children(children)

  defp process_list_item(other), do: process_node(other)

  defp process_ordered_list_item({"li", _, children}, index), do: "#{index}. " <> process_children(children)

  defp process_ordered_list_item(other, _index), do: process_node(other)

  defp process_table(children) do
    table =
      children
      |> extract_rows()
      |> process_table_rows()

    newline() <> table <> newline()
  end

  defp extract_rows(children) do
    rows =
      Enum.find(children, fn
        {"tbody", _, _} -> true
        _ -> false
      end)

    case rows do
      {"tbody", _, rows} -> rows
      _ -> children
    end
  end

  defp process_table_rows(rows) do
    rows
    |> Enum.with_index()
    |> Enum.map_join("\n", fn {row, index} ->
      row_str = process_table_row(row)

      if index == 0 do
        row_str <> newline() <> header_separator(row)
      else
        row_str
      end
    end)
  end

  defp process_table_row({"tr", _attrs, cells}) when is_list(cells) and length(cells) > 0 do
    {_, attrs, _} = List.first(cells)
    colspan = get_colspan(attrs)

    processed_cells =
      if colspan >= 1 do
        {_, _, content} = List.first(cells)
        cell_content = process_children(content)
        spans = Enum.map_join(1..colspan, " | ", &process_table_cell/1)
        cell_content <> spans
      else
        Enum.map_join(cells, " | ", &process_table_cell/1)
      end

    "| " <> processed_cells <> " |"
  end

  defp process_table_row(_), do: ""

  defp process_table_cell({_, attrs, content}) do
    cell_content = process_children(content)
    indent = get_indent(attrs)
    String.duplicate("&ensp;", indent) <> cell_content
  end

  defp process_table_cell(_), do: ""

  defp get_colspan(attrs) do
    case Enum.find(attrs, fn {attr, _} -> attr == "colspan" end) do
      {"colspan", value} -> String.to_integer(value)
      _ -> 0
    end
  end

  defp get_indent(attrs) do
    case Enum.find(attrs, fn {attr, _} -> attr == "style" end) do
      {"style", style} ->
        case Regex.run(~r/padding-left:(\d+\.\d+)em;/, style) do
          [_, indent] ->
            indent |> String.to_float() |> ceil()

          _ ->
            0
        end

      _ ->
        0
    end
  end

  defp header_separator({"thead", _, [{"tr", _, cells}]}), do: header_separator({"tr", [], cells})

  defp header_separator({"colgroup", _, cols}) do
    separator =
      Enum.map_join(cols, " | ", fn _ -> "---" end)

    "| " <> separator <> " |"
  end

  defp header_separator({"tr", _, cells}) do
    {_, attrs, _} = List.first(cells)
    colspan = get_colspan(attrs)

    separator =
      if colspan >= 1 do
        Enum.map_join(1..colspan, " | ", fn _ -> "---" end)
      else
        Enum.map_join(cells, " | ", fn _ -> "---" end)
      end

    "| " <> separator <> " |"
  end

  defp process_children(children) do
    children
    |> Enum.map_join(" ", &process_node/1)
    |> String.trim()
  end

  defp newline, do: "\n"

  defp newline(count), do: String.duplicate("\n", count)
end
