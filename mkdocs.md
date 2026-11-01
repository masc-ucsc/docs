# Documentation build tools

`pyproject.toml` declares the Python dependencies actually used by the site;
`uv.lock` pins their complete resolution. `.python-version` selects Python
3.15.2. Use uv 0.13.6 or newer when provisioning that interpreter. The site
uses Zensical 0.0.74 with its modern theme, PyMdown Extensions 12.3, Markdown
3.11.2 and Pygments 2.21.0. MkDocs and Material are no longer dependencies.

Zensical reads the existing `mkdocs.yml`, including the custom Pyrope
SuperFences formatter. Keeping YAML avoids changing the content or page URLs;
the modern theme supplies the layout, with small reading refinements in
`docs/stylesheets/reference.css`. See the
[official migration guide](https://zensical.org/docs/compatibility/mkdocs/migration/)
for supported settings and command differences.

## Build and update

```sh
make setup                       # install the checked-in lock
make build                       # build site/ using that environment
make serve                       # preview at localhost:8000
make upgrade                     # resolve current stable Python packages
make build                       # validate the new resolution
```

Review and commit both dependency declarations and `uv.lock` when requirements
change; ordinary builds use `--locked` and never silently upgrade. For direct
Zensical commands, use `PYTHONPATH=. uv run --locked zensical ...`, or pass
options through Make, e.g. `make serve ZENSICAL_ARGS="--dev-addr 127.0.0.1:8001"`.
Set `site_dir` in `mkdocs.yml` to change the output directory; Zensical does not
support MkDocs' `--site-dir` argument.

The Pyrope highlighter uses the owning grammar repository's `npm ci` toolchain,
not an independently upgraded Tree-sitter CLI. That keeps parser/tool compatibility
under the grammar's control. Builds call the native executable from that npm
package directly, avoiding a Node launcher for every fence. The highlighter
selects `source.pyrope` from that grammar directory; it avoids `--grammar-path`,
which forces recompilation for every snippet in the current CLI.

## Browser dependencies

- Zensical's native Mermaid integration uses the standard SuperFences formatter.
  `overrides/main.html` loads Mermaid 12.2.0 before Zensical's bundle, avoiding
  its older lazy-load fallback and duplicate initialization. No Mermaid Python
  plugin or Mermaid CLI is required.
- MathJax 4.1.3 is pinned in `mkdocs.yml`. Its v4 URL no longer has an `es5/`
  component. `docs/javascripts/config.js` waits for startup before registering
  instant-navigation typesetting.
- The obsolete polyfill loader and unused redirects/minify/Markdown-extras
  packages are removed. Zensical provides the configured search integration.

Check the official package registries when updating these pins, then check
math and diagrams on initial load and after instant navigation. CDN scripts
still require network access when browsing the site.

## Deployment

CI installs the lock, builds with `make build`, and publishes the existing
`gh-pages` branch. To publish manually, explicitly run:

```sh
make build
uv run --locked ghp-import --no-jekyll --push --force --no-history --branch=gh-pages ./site
```

Zensical has no `gh-deploy` command; the explicit `ghp-import` invocation matches
CI and replaces the generated branch history. A local build does not publish
anything. The workflow pins current action releases, uv and Node LTS
independently of the Python dependency lock.
