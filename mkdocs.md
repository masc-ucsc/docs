# Documentation build tools

`pyproject.toml` declares the Python dependencies actually used by the site;
`uv.lock` pins their complete resolution. `.python-version` selects Python
3.15.2. Use uv 0.13.6 or newer when provisioning that interpreter. MkDocs
1.6.1 remains its current stable release; the refreshed stack uses Material
9.8.0, PyMdown Extensions 12.3, Markdown 3.11.2 and Pygments 2.21.0.

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
MkDocs commands, use `PYTHONPATH=. uv run --locked mkdocs ...`. The Pyrope
highlighter uses the owning grammar repository's `npm ci` toolchain, not an
independently upgraded Tree-sitter CLI. That keeps parser/tool compatibility
under the grammar's control. Builds call the native executable from that npm
package directly, avoiding a Node launcher for every fence. The highlighter selects `source.pyrope` from that
grammar directory; it avoids `--grammar-path`, which forces recompilation for
every snippet in the current CLI.

## Browser dependencies

- Material's native Mermaid integration uses the standard SuperFences formatter.
  `overrides/main.html` loads Mermaid 12.2.0 before Material's bundle, avoiding
  its older lazy-load fallback and duplicate initialization. No Mermaid Python
  plugin or Mermaid CLI is required.
- MathJax 4.1.3 is pinned in `mkdocs.yml`. Its v4 URL no longer has an `es5/`
  component. `docs/javascripts/config.js` waits for startup before registering
  instant-navigation typesetting.
- The obsolete polyfill loader and unused redirects/minify/Markdown-extras
  packages are removed. The site enables only the search plugin.

Check the official package registries when updating these pins, then check
math and diagrams on initial load and after instant navigation. CDN scripts
still require network access when browsing the site.

## Deployment

CI installs the lock, builds with `make build`, and publishes the existing
`gh-pages` branch. To publish manually, explicitly run:

```sh
PYTHONPATH=. uv run --locked mkdocs gh-deploy --force
```

A local build does not publish anything. The workflow pins current action
releases, uv and Node LTS independently of the Python dependency lock.
