defmodule HexdocsMcp.Fixtures do
  def package() do
    "fake_test_package"
  end

  def html_filename() do
    "api-reference.html"
  end

  def html() do
    """
    <!DOCTYPE html>
    <html>
      <head>
        <title>FakeTestPackage v1.0.0 — Documentation</title>
        <meta charset="utf-8">
      </head>
      <body>
        <div class="content">
          <div class="main">
            <h1>FakeTestPackage</h1>

            <section id="moduledoc" class="docstring">
              <p>A test package that demonstrates various documentation elements.</p>
            </section>

            <section id="summary" class="details-list">
              <h2>Summary</h2>
              <div class="summary">
                <div class="summary-row">
                  <div class="summary-signature">
                    <a href="#function/2">function(arg1, arg2)</a>
                  </div>
                  <div class="summary-synopsis">
                    A test function that does something interesting.
                  </div>
                </div>
              </div>
            </section>

            <section id="functions" class="details-list">
              <h2>Functions</h2>
              <section class="detail">
                <div class="detail-header">
                  <a href="#function/2" class="detail-link">
                    <span class="icon-link"></span>
                  </a>
                  <span class="signature">function(arg1, arg2)</span>
                </div>
                <div class="docstring">
                  <p>A test function that does something interesting.</p>
                  <h4>Parameters</h4>
                  <ul>
                    <li><code>arg1</code> - The first argument</li>
                    <li><code>arg2</code> - The second argument</li>
                  </ul>
                  <h4>Examples</h4>
                  <pre><code>iex> function("test", 123)
    :ok</code></pre>
                </div>
              </section>
            </section>
          </div>
        </div>
      </body>
    </html>
    """
  end
end
