defmodule HexdocsMcp.MarkdownTest do
  use ExUnit.Case

  alias HexdocsMcp.Markdown

  describe "from_html/1" do
    test "removes sidebar navigation elements" do
      html = """
      <html>
        <body>
          <nav id="sidebar" class="sidebar">
            <div class="sidebar-header">Sidebar content</div>
            <ul class="sidebar-list-nav">
              <li>Item 1</li>
              <li>Item 2</li>
            </ul>
          </nav>
          <main class="content">
            <h1>Main Content</h1>
            <p>This is the actual documentation content.</p>
          </main>
        </body>
      </html>
      """

      result = Markdown.from_html(html)

      assert result =~ "Main Content"
      assert result =~ "This is the actual documentation content"

      refute result =~ "Sidebar content"
      refute result =~ "Item 1"
      refute result =~ "Item 2"
    end

    test "removes module listing navigation sections" do
      html = """
      <html>
        <body>
          <main class="content">
            <h1>API Reference</h1>
            <section class="details-list">
              <div class="summary-row">
                <a href="Module1.html">Module1</a>
              </div>
              <div class="summary-row">
                <a href="Module2.html">Module2</a>
              </div>
            </section>
            <section>
              <h2>Documentation</h2>
              <p>This is the actual content.</p>
            </section>
          </main>
        </body>
      </html>
      """

      result = Markdown.from_html(html)

      assert result =~ "API Reference"
      assert result =~ "Documentation"
      assert result =~ "This is the actual content"

      refute result =~ "Module1"
      refute result =~ "Module2"
    end

    test "extracts main content area when available" do
      html = """
      <html>
        <body>
          <div class="sidebar">Navigation here</div>
          <main class="content">
            <h1>Main Documentation</h1>
            <p>Important content here.</p>
          </main>
          <footer>Footer content</footer>
        </body>
      </html>
      """

      result = Markdown.from_html(html)

      assert result =~ "Main Documentation"
      assert result =~ "Important content here"

      refute result =~ "Navigation here"
      refute result =~ "Footer content"
    end

    test "preserves content when it's the primary focus" do
      html = """
      <html>
        <body>
          <main class="content">
            <article>
              <h1>Module Documentation</h1>
              <p>This module provides functionality for...</p>
              <h2>Functions</h2>
              <ul>
                <li>function1/2 - Does something</li>
                <li>function2/3 - Does something else</li>
              </ul>
            </article>
          </main>
        </body>
      </html>
      """

      result = Markdown.from_html(html)

      assert result =~ "Module Documentation"
      assert result =~ "This module provides functionality"
      assert result =~ "Functions"
      assert result =~ "function1/2"
      assert result =~ "function2/3"
    end
  end
end
