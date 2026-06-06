# Usage

This is a high level description of how to use LiveHD.

## The lhd driver

LiveHD is driven by a single command line binary called `lhd`. It replaces the
legacy interactive shell (`lgshell`) and its `|>` pipeline syntax, which were
removed from the tree. `lhd` is a *stateless kernel*: one invocation runs one
step — `(declared inputs, config) -> (declared outputs, exit code)` — which
makes it directly callable from build systems (Make, Ninja, Bazel) and by
coding agents.

Two invariants are properties of the binary, not flags:

* **Deterministic**: output bytes are a pure function of the inputs. The
  reported `run_id` is a content hash of (tool version + command + resolved
  config + input bytes), never wall-clock/random. If a timestamp must be
  embedded it comes from the `SOURCE_DATE_EPOCH` convention.
* **Hermetic**: a source file the frontend cannot find within its declared
  inputs is a `missing_file` error, never a silent reach into the filesystem.

To build and get started:

```sh
$ bazel build //lhd:lhd
$ ./bazel-bin/lhd/lhd help
$ ./bazel-bin/lhd/lhd help synth
```

The design rationale is documented in the LiveHD repo under
`docs/contracts/future_cli.md`.

## Commands

The split rule: commands that ingest source are language-qualified; commands
that operate on IR are language-agnostic. The language word is optional — it
is inferred from the file extension (`.prp` vs `.v`/`.sv`).

| Command | Purpose |
|---------|---------|
| `lhd elaborate [verilog\|pyrope] SRCS...` | frontend: source → IR |
| `lhd synth IR...` | transform / optimize / codegen over IR inputs |
| `lhd compile [verilog\|pyrope] SRCS...` | fused elaborate + synth (one action, one exit code) |
| `lhd check` | logic equivalence check (LEC) between two designs |
| `lhd scan FILES.prp...` | report each Pyrope file's `import` strings (dependency discovery) |
| `lhd lsp` | Pyrope language server over stdio (JSON-RPC) |
| `lhd list steps\|recipes\|emit-kinds\|error-classes` | discovery (JSON output) |
| `lhd describe <command\|recipe:NAME\|emit-kind>` | self-documentation (JSON output) |
| `lhd version` / `lhd help [command]` | meta |

Shared arguments honored by the execution commands:

| Argument | Meaning |
|----------|---------|
| `--emit KIND:PATH` | declared single-file typed output (`verilog:` only) |
| `--emit-dir KIND:DIR/` | declared directory output (`ln:`, `lg:`, `pyrope:`, `lnast-dump:`) |
| `--top <name>` | top module/function |
| `--config lhd.toml` | pass-flag defaults from a config file (see below) |
| `--result-json PATH` | structured result object (JSON) to a file (else stdout) |
| `--workdir DIR` | scratch + ephemeral lgdb; never a global cache |
| `-j`/`--jobs N` | intra-action parallelism |
| `-q`/`--quiet`, `--verbose` | stderr verbosity; never pollutes the stdout protocol |

## Typed inputs and outputs (kinds)

Every input/output is a typed slot `KIND:PATH`. The main IR kinds:

| Kind | Contents |
|------|----------|
| `ln:` | the design's LNAST units — an `hhds::Forest` save directory (`forest.txt` + binary tree bodies) plus a `manifest.json` unit index. Alias: `lnast:` |
| `lg:` | the design's LGraphs — an `hhds::GraphLibrary` save directory (`library.txt` + binary graph bodies). Aliases: `design:`, `lgraph:` |
| `verilog:` | Verilog source. As `--emit`, a deterministic name-sorted concatenation of the per-module `inou.cgen.verilog` output |
| `pyrope:` | Pyrope source. As `--emit-dir`, a per-unit `.prp` re-emission via `pass.prp_writer` (needs `ln:`/pyrope inputs) |
| `lnast-dump:` | round-trippable textual LNAST dump (the `Lnast::dump` text form), one `<unit>.lnast` per unit. A debug/test observable; the binary interchange form is `ln:` |

Because a design always holds *many* units/graphs, `ln:`/`lg:`/`pyrope:` are
directory containers (`--emit-dir` only). `--emit verilog:PATH` is the one
single-file output. `ln:`/`lg:` inputs are given positionally.

## Verilog compilation

One shot — elaborate, optimize, and emit Verilog:

```sh
$ lhd compile foo.v --top foo --recipe O2 --emit verilog:foo.gen.v
```

Or as separate steps with the `lg:` container in between:

```sh
$ lhd elaborate foo.v --top foo --emit-dir lg:foo_lgs/
$ lhd synth lg:foo_lgs/ --recipe O1 --emit verilog:foo.gen.v
```

The Verilog frontend has three readers, selected with
`--reader yosys-verilog|yosys-slang|slang` (default `yosys-slang`):

* `yosys-verilog` — Yosys' native Verilog frontend, into LGraphs.
* `yosys-slang` — Yosys with the slang.so plugin (SystemVerilog), into LGraphs.
* `slang` — the direct `inou.slang` SV→LNAST front-end; the design becomes
  LNAST units and the rest of the flow is the Pyrope one.

Because Verilog `` `include `` + `+incdir` can read files that are not on the
command line, the Verilog frontend supports `--depfile PATH` to write a
Make-syntax dependency file for build systems.

## Pyrope compilation

```sh
$ lhd compile bar.prp --emit verilog:bar.gen.v
```

A `.prp` file can define several functions; `elaborate pyrope` emits one LNAST
unit per elaborated unit into an `ln:` directory. Files related by `import`
ride along as pre-elaborated `ln:` inputs. The canonical per-file → top flow:

```sh
# per pyrope file, in parallel (no imports)
$ lhd elaborate f1.prp --emit-dir ln:f1_lns/ --emit-dir lg:f1_lgs/

# a file importing f1: its pre-elaborated ln: rides along
$ lhd elaborate f2.prp ln:f1_lns/ --emit-dir ln:f2_lns/ --emit-dir lg:f2_lgs/

# top target: aggregate ln: units into ONE library, then synth
$ lhd elaborate ln:f1_lns/ ln:f2_lns/ --top foo --emit-dir lg:top_lgs/
$ lhd synth lg:top_lgs/ --recipe O1 --emit-dir lg:top_opt_lgs/ --emit verilog:top.v
```

To discover the import relationships without elaborating (Pyrope `import`
arguments are comptime string literals, so the list is exact):

```sh
$ lhd scan f1.prp f2.prp     # imports reported in the result's "scan" member
```

## Recipes

A recipe is the named pass chain between the frontend and the terminal
`--emit` — defined as data, not `|>` strings:

| Recipe | Passes | Description |
|--------|--------|-------------|
| `O0` | (frontend lowering only) | no graph optimization; `ln:` inputs still run `pass.upass` + tolg |
| `O1` | `pass.cprop` | constant/copy propagation (default) |
| `O2` | `pass.cprop`, `pass.bitwidth` | cprop + bitwidth inference |

`--set pass.flag=value` overrides one knob without forking the recipe, e.g.
`--set cprop.verbose=true`. Introspect with:

```sh
$ lhd list recipes
$ lhd describe recipe:O2
```

The result records the *expanded* recipe (the passes+flags that actually ran),
so an artifact is self-describing even if a recipe is later redefined.

## Configuration: lhd.toml

`--config lhd.toml` provides pass-flag defaults as a declared input file. It
is a strict TOML *subset*: `#` comments, pass tables (`[upass]`, `[cprop]`,
`[bitwidth]`), and `key = value` entries with quoted strings, booleans, or
integers. The top level takes only `recipe`. Anything else is a `config`
error — a typo'd pass table errors rather than silently no-oping.

```toml
recipe = "O2"

[upass]
constprop = true
verifier  = false
```

File entries are defaults: explicit `--set`/`--recipe` always win, and the
`recipe` key is ignored by commands with no recipe slot, so one `lhd.toml` can
serve every step of a flow. The config is folded in before `run_id` hashing,
so a config file and the equivalent explicit flags hash identically.

```sh
$ lhd describe config    # prints the lhd.toml schema
```

## Equivalence checking (LEC)

`lhd check` runs a logic equivalence check (via `inou/yosys/lgcheck`) between
an implementation and a reference; each side can be a `verilog:` file or a
`lg:` directory:

```sh
$ lhd check --impl verilog:foo.gen.v --ref verilog:foo.v --impl-top foo --ref-top foo
```

A non-equivalent pair exits non-zero with `error.class = equiv_fail`.

## Inspecting the IRs

Textual LNAST dump (round-trips through `Lnast::read`):

```sh
$ lhd elaborate bar.prp --emit-dir lnast-dump:dump_dir/
```

From `elaborate` the dump is post-parse; from `synth`/`compile` it is
post-upass. The `ln:`/`lg:` directories themselves are the binary interchange
forms (`hhds::Forest::save` / `hhds::GraphLibrary::save`).

## Results, exit codes, and error classes

A step's success is *only* the process exit code: `0` = pass, non-zero = fail.
The structured result (one JSON object, to `--result-json PATH` or stdout)
carries the detail: command, status, `run_id`, inputs, outputs, the expanded
recipe steps, and on failure an `error` block:

| error.class | Meaning |
|---------------|------------------------------------------------|
| `usage` | invalid CLI usage or unsupported argument |
| `syntax` | input file has syntax errors |
| `internal` | LiveHD bug or unhandled case |
| `equiv_fail` | equivalence check failed |
| `signal` | process killed by signal (segfault, abort) |
| `timeout` | step exceeded time limit |
| `missing_file`| required file or path does not exist |
| `config` | missing or invalid configuration |
| `dependency` | required external tool or prior artifact absent |
| `unsupported` | requested feature is known but not implemented |

`lhd` emits nothing on stdout except the selected protocol — no banners, no
echoed commands, no raw pass logs. Per-step raw logs land under
`--workdir/logs/`.

## Pyrope language server

`lhd lsp` serves the Pyrope LSP (JSON-RPC over stdio) for `.prp` files:
real-time compile diagnostics (syntax, name, type, bit-width) in any editor.
The `scripts/prplsp` wrapper picks the right `lhd` binary (in-checkout build
when inside a livehd checkout, `$PATH` otherwise) — point your editor at that.

## Bazel integration

A thin Starlark ruleset ships in the LiveHD repo (`//tools:lhd.bzl`) so a
BUILD file can run LiveHD as a hermetic action:

```python
load("//tools:lhd.bzl", "lhd_verilog")

lhd_verilog(
    name    = "foo_net",
    top     = "foo",
    srcs    = ["foo.v", "bar.v"],
    incdirs = ["rtl/inc"],
    recipe  = "O2",
    out     = "foo.gen.v",     # also writes foo.d (depfile) + foo.result.json
)
```

## Low level directed build

To compile an individual pass:

```sh
$ bazel build -c dbg //pass/cprop:pass_cprop
$ bazel build -c dbg //inou/yosys:all
```
