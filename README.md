# LiveHD and Pyrope documentation

The rendered documentation is at https://masc-ucsc.github.io/docs/.

## Local build

Install [uv](https://docs.astral.sh/uv/getting-started/installation/) 0.13.6
or newer, Node.js (current LTS), npm and a C compiler for Tree-sitter.
On macOS, `brew install uv node` installs the package tools; use
`brew upgrade uv node` if they are already installed.

The Pyrope grammar is maintained in the sibling `../tree-sitter-pyrope`
repository. Install its locked tools, then build:

```sh
npm ci --prefix ../tree-sitter-pyrope
make setup
make build
make serve
```

`uv` provisions the Python version in `.python-version` and installs the exact
`uv.lock` dependency set into `.venv`. Local builds and CI use that same lock;
no global Python packages are required. `make serve` previews edits at
http://127.0.0.1:8000/. Override `PYROPE_TREE_SITTER_GRAMMAR` and
`PYROPE_TREE_SITTER_CLI` for a different grammar checkout.

See [tool maintenance](mkdocs.md) for upgrades, rendering dependencies and the
separate deployment command.
