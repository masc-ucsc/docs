.PHONY: all site build serve setup upgrade clean check-pyrope-tools

UV ?= uv
MKDOCS_ARGS ?=
PYROPE_TREE_SITTER_GRAMMAR ?= $(abspath ../tree-sitter-pyrope)
PYROPE_TREE_SITTER_CLI ?= $(PYROPE_TREE_SITTER_GRAMMAR)/node_modules/tree-sitter-cli/tree-sitter

export PYTHONPATH := .
export PYROPE_TREE_SITTER_GRAMMAR
export PYROPE_TREE_SITTER_CLI

all: site

setup:
	$(UV) sync --locked

upgrade:
	$(UV) lock --upgrade
	$(UV) sync --locked

site build: check-pyrope-tools
	$(UV) run --locked mkdocs build $(MKDOCS_ARGS)

serve: check-pyrope-tools
	$(UV) run --locked mkdocs serve $(MKDOCS_ARGS)

clean:
	rm -rf site

check-pyrope-tools:
	@test -f "$(PYROPE_TREE_SITTER_GRAMMAR)/tree-sitter.json" || \
		(echo "Missing tree-sitter-pyrope grammar: $(PYROPE_TREE_SITTER_GRAMMAR)" >&2; exit 1)
	@test -x "$(PYROPE_TREE_SITTER_CLI)" || \
		(echo "Missing tree-sitter CLI: $(PYROPE_TREE_SITTER_CLI)" >&2; \
		 echo "Run: npm ci --prefix $(PYROPE_TREE_SITTER_GRAMMAR)" >&2; exit 1)
