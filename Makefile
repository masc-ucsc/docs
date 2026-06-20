.PHONY: all site build serve clean check-pyrope-tools

PYROPE_TREE_SITTER_GRAMMAR ?= $(abspath ../tree-sitter-pyrope)
PYROPE_TREE_SITTER_CLI ?= $(PYROPE_TREE_SITTER_GRAMMAR)/node_modules/.bin/tree-sitter

export PYTHONPATH := .
export PYROPE_TREE_SITTER_GRAMMAR
export PYROPE_TREE_SITTER_CLI

all: site

site build: check-pyrope-tools
	mkdocs build

serve: check-pyrope-tools
	mkdocs serve

clean:
	rm -rf site

check-pyrope-tools:
	@test -f "$(PYROPE_TREE_SITTER_GRAMMAR)/tree-sitter.json" || \
		(echo "Missing tree-sitter-pyrope grammar: $(PYROPE_TREE_SITTER_GRAMMAR)" >&2; exit 1)
	@test -x "$(PYROPE_TREE_SITTER_CLI)" || \
		(echo "Missing tree-sitter CLI: $(PYROPE_TREE_SITTER_CLI)" >&2; \
		 echo "Run: npm ci --prefix $(PYROPE_TREE_SITTER_GRAMMAR)" >&2; exit 1)
