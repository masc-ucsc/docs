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
$ ./bazel-bin/lhd/lhd help compile
```

The design rationale is documented in the LiveHD repo under
`docs/contracts/future_cli.md`.

## Commands

The split rule: commands that ingest source are language-qualified; commands
that operate on IR are language-agnostic. The language word is optional — it
is inferred from the file extension (`.prp` vs `.v`/`.sv`).

| Command | Purpose |
|---------|---------|
| `lhd compile [verilog\|pyrope] SRCS/IR...` | the single source→IR→netlist action (frontend + synth fused; sources and/or `ln:`/`lg:` inputs) |
| `lhd lec --impl S --ref S` | logic equivalence check between two designs (also spelled `lhd formal lec`) |
| `lhd formal verify DESIGN [SIDECARS.prp...]` | prove the design's `assert`/`assume` obligations by BMC + induction (per-assert verdict table) |
| `lhd sim SRCS...` | compile and run the design's `test` blocks (simulation driver) |
| `lhd pass <sub> ...` | run one pass over IR (`abc`, `color`, `partition`, `semdiff`, `formal`, ...) |
| `lhd tool cat\|grep\|diff\|tree ...` | unified `ln:`/`lg:` inspector |
| `lhd scan FILES.prp...` | report each Pyrope file's `import` strings (dependency discovery) |
| `lhd pyrope fmt\|lsp` | Pyrope formatter / language server over stdio (JSON-RPC) |
| `lhd list steps\|recipes\|emit-kinds\|error-classes\|options [REGEX]` | discovery (JSON when piped; `options` prints human text on a terminal) |
| `lhd describe <command\|recipe:NAME\|emit-kind\|pass.flag>` | self-documentation (JSON output; `pass.flag` shows one option's full help) |
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
| `--diag-fmt auto\|jsonl\|pretty` | rendering of the stdout result envelope and the stderr diagnostics; `auto` (default) = `pretty` on a terminal, `jsonl` when piped/captured (agents, CI) |

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

Or as separate steps with the `lg:` container in between (`compile` is the
single action; an `lg:`-only input skips the frontend):

```sh
$ lhd compile foo.v --top foo --emit-dir lg:foo_lgs/
$ lhd compile lg:foo_lgs/ --recipe O1 --emit verilog:foo.gen.v
```

The Verilog frontend has three readers, selected with
`--reader slang|yosys-slang|yosys-verilog` (default `slang`):

* `slang` — the direct `inou.slang` SV→LNAST front-end (the default); the
  design becomes LNAST and joins the Pyrope flow.
* `yosys-verilog` — Yosys' native Verilog frontend, into LGraphs.
* `yosys-slang` — Yosys with the slang.so plugin (SystemVerilog), into LGraphs.

Because Verilog `` `include `` + `+incdir` can read files that are not on the
command line, the Verilog frontend supports `--depfile PATH` to write a
Make-syntax dependency file for build systems.

## Pyrope compilation

```sh
$ lhd compile bar.prp --emit verilog:bar.gen.v
```

A `.prp` file can define several functions; compiling with `--emit-dir ln:`
emits one LNAST unit per elaborated unit into an `ln:` directory. Files related by `import`
ride along as pre-elaborated `ln:` inputs. The canonical per-file → top flow:

```sh
# per pyrope file, in parallel (no imports)
$ lhd compile f1.prp --emit-dir ln:f1_lns/ --emit-dir lg:f1_lgs/

# a file importing f1: its pre-elaborated ln: rides along
$ lhd compile f2.prp ln:f1_lns/ --emit-dir ln:f2_lns/ --emit-dir lg:f2_lgs/

# top target: aggregate ln: units into ONE library, then synth
$ lhd compile ln:f1_lns/ ln:f2_lns/ --top foo --emit-dir lg:top_lgs/
$ lhd compile lg:top_lgs/ --recipe O1 --emit-dir lg:top_opt_lgs/ --emit verilog:top.v
```

To discover the import relationships without elaborating (Pyrope `import`
arguments are comptime string literals, so the list is exact):

```sh
$ lhd scan f1.prp f2.prp     # imports reported in the result's "scan" member
```

## Source maps

Verilog source maps emitted by codegen are ECMA-426 compliant. Enable them with
`cgen.srcmap=1`; the generated `.v` and source-map sidecar can be loaded by
standard source-map tools.

```sh
# Generate Verilog with source maps.
$ lhd compile inou/prp/tests/equiv/mod_varargs_csa.prp --emit-dir verilog:tmp --set cgen.srcmap=1

# Visualize the mapping.
# Open https://evanw.github.io/source-map-visualization/
# Upload the tmp/mod_varargs_csa.blk_add__u8.v* files.
```

## Linking libraries (Pyrope + a Verilog black box)

A design can mix leaves from different frontends. `import("lg:NAME")` pulls a
*compiled* LGraph (from a previous Pyrope or Verilog/yosys run) into a Pyrope
module as a black box — instantiated by name, body resolved at link time.
`compile` then **assembles** several `lg:`/`ln:` inputs, starting from
`--top`, into one new `lg:` library you can synthesize.

The lg: name is the full graph name: a Verilog module keeps its name (`inv`), a
Pyrope unit is `file.entity` (`adder.adder`).

Cut-and-paste from the LiveHD root (writes Verilog to `./tmp`); this is exactly
the flow exercised by `lhd/tests/lhd_usage_merge_test.sh`:

```sh
$ bazel build //lhd:lhd

# 1. a Verilog leaf -> lg: (through yosys; the default reader is now slang, so
#    request the yosys frontend explicitly for this black-box leaf)
$ ./bazel-bin/lhd/lhd compile lhd/tests/merge_demo/inv.v --top inv --reader yosys-verilog --emit-dir lg:tmp/inv_lg/

# 2. a Pyrope leaf -> lg:
$ ./bazel-bin/lhd/lhd compile lhd/tests/merge_demo/adder.prp --emit-dir lg:tmp/adder_lg/

# 3. a top Pyrope that imports BOTH (a yosys black box + a Pyrope module) -> ln:
#    (elaborated only; the lg: imports stay unresolved until the link step)
$ ./bazel-bin/lhd/lhd compile lhd/tests/merge_demo/top.prp --emit-dir ln:tmp/top_ln/

# 4. LINK: merge the two lg: libraries and lower the top against them -> a new lg:
$ ./bazel-bin/lhd/lhd compile --top top lg:tmp/inv_lg/ lg:tmp/adder_lg/ ln:tmp/top_ln/ --emit-dir lg:tmp/merged_lg/

# 5. synthesize the assembled library -> Verilog
$ ./bazel-bin/lhd/lhd compile lg:tmp/merged_lg/ --emit verilog:tmp/top.v
```

`tmp/top.v` holds three modules — `inv`, `adder.adder`, and `top.top` — with
`top` instantiating the other two (`y = (-x) + 1`). Because gids are a
deterministic hash of the graph name, a name shared across libraries keeps the
same gid, so the merge is conflict-free.

## Recipes

A recipe is the named pass chain between the frontend and the terminal
`--emit` — defined as data, not `|>` strings:

| Recipe | Passes | Description |
|--------|--------|-------------|
| `O0` | (frontend lowering only) | no graph optimization; `ln:` inputs still run `pass.upass` + tolg |
| `O1` | `pass.cprop` | constant/copy propagation (default) |
| `O2` | `pass.cprop`, `pass.bitwidth` | cprop + bitwidth inference |

`--set pass.flag=value` overrides one knob without forking the recipe, e.g.
`--set cgen.srcmap=1`. A typo'd pass or flag is a usage error (never a silent
no-op). Introspect with:

```sh
$ lhd list recipes
$ lhd describe recipe:O2
$ lhd list options             # every --set/--config pass.flag, with defaults
$ lhd list options 'cgen\..*'  # regex-filtered
$ lhd describe upass.toln      # one option, full help text
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

`lhd lec` (also spelled `lhd formal lec`) proves two designs equivalent; each
side can be a `verilog:`/`pyrope:` file or an `ln:`/`lg:` directory (a bare
`.v`/`.sv`/`.prp` path infers its kind):

```sh
$ lhd lec --impl foo.gen.v --ref foo.v --top foo
```

The default backend is the in-process cvc5 SMT engine (bottom-up hierarchical:
each module def is proven leaves-first and proven children collapse into their
parents); `--set lec.solver=lgyosys` routes through `inou/yosys/lgcheck`
instead, and `--set lec.engine=bmc|ind` picks a single engine over the default
ind+bmc portfolio. On a refutation with `--workdir`, the counterexample is
also written as a self-contained Pyrope testbench (`lecfail.prp`) plus a VCD
so the divergence can be replayed and visualized. A non-equivalent pair exits
non-zero with `error.class = equiv_fail`; an inconclusive solve is a warning
(exit 0) unless `--set lec.strict=true`.

## Formal verification (assert / assume)

`lhd formal verify` proves ONE design's `assert` / `assert_always` / `assume`
obligations by bounded model checking from reset, on the same engine LEC uses.
Each obligation is checked per cycle as its own solver query; every proven
fact immediately prunes the search for the rest, and a timeout costs one
obligation at one cycle — the run reports a per-assert verdict table, not a
single verdict:

```sh
$ lhd formal verify cnt.prp cnt.verify.prp --top cnt --set formal.bound=10
formal verify: 'cnt.cnt' REFUTED (...)
  assert at cnt.prp:5: PROVEN (inductive — every cycle of every bound)
  assert at cnt.prp:6 "counter hit 5": REFUTED at cycle 7
    counterexample inputs: cyc0: enable=0, reset=1 | ... | cyc6: enable=1, reset=0
  assume at cnt.verify.prp:4 [cnt.quiet]: in force (environment constraint)
```

Verdict tiers, per assert: `PROVEN (inductive)` holds at every cycle of every
bound (the bounded proof plus an induction step); `PROVEN to cycle k
(bounded)` means no violation within the unrolled window only; `REFUTED at
cycle k` is a reachable violation with the per-cycle input trace that
reproduces it from reset (the run exits non-zero, `error.class =
equiv_fail`); `UNKNOWN` (solver gave up / contradictory assumes) is a loud
warning that fails only under `--set formal.strict=true`. An `assume` is an
environment constraint: it prunes the explored traces and is disclosed in the
table.

Properties can live inline in the design or in *sidecar* files as
`formal name.dotted { ... }` blocks — declarative every-cycle claims over
dotted signal paths, activated by listing the file and filtered with
`--formal <glob>`; see
[Pyrope verification](../pyrope/05-assert.md#formal-blocks) for the block
syntax. Engine knobs are shared with LEC under `--set formal.*`
(`formal.bound`, `formal.timeout` per query, `formal.phase`, `formal.reset`);
the legacy `lec.*` spellings stay accepted. The same checks also run in a don't-try-hard mode inside every
`lhd compile` (`pass.formal`): proven obligations are elided from the netlist,
refuted ones fail the build, undecided ones stay as runtime checks with a
deferral warning.

## Inspecting the IRs

Textual LNAST dump (round-trips through `Lnast::read`):

```sh
$ lhd compile bar.prp --emit-dir lnast-dump:dump_dir/
```

With `--recipe O0` the dump is close to post-parse; the default recipes show
the post-upass form. The `ln:`/`lg:` directories themselves are the binary interchange
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

### Diagnostics

Errors and warnings are also emitted as a finer JSONL stream — **one line per
diagnostic** — alongside the step result. Point it at a file with
`--emit diagnostics:PATH`. The stderr rendering follows `--diag-fmt`:
clang-style text in `pretty` mode (the default on a terminal), the same JSONL
records in `jsonl` mode (the default when stdout is piped/captured). The
machine stream is the source of truth; the human text is a rendering of it.
Diagnostics are designed to be triaged by a coding agent as much as read by a
human, which drives the schema below.

Each record is one JSON object:

| field | meaning |
|---|---|
| `severity` | `error` (compilation cannot proceed), `warning` (proceeds, likely issue), or `note` (a secondary location) |
| `code` | stable, greppable id (kebab-case, e.g. `range-fit`) — survives message rewording, so tooling branches on it instead of the prose |
| `category` | what kind of fix is needed (below) |
| `pass` | originating stage (e.g. `inou.prp`, `upass.attributes`) |
| `message` | one human-readable line, without the location |
| `span` | source location, or `null` when unknown |
| `hint` | one actionable suggestion (optional) |

`category` says *who is wrong*:

| category | meaning |
|---|---|
| `syntax` / `name` / `type` / `bitwidth` | the source — fix the Pyrope/Verilog |
| `unsupported` | valid input LiveHD cannot lower yet — rewrite around it, do not "fix" the source |
| `internal` | a LiveHD bug — reduce to a repro, do not change the source |

A run collects every diagnostic (not just the first), so all problems surface in
one compile; duplicates of the same diagnostic within a step are reported once.
The step result's `error` block summarizes the fatal diagnostic and points back
at the diagnostics file with per-severity counts. The renderer prints a
clang/rust-style block with a caret line when a span is available and degrades to
a single line — never a fabricated location — when it is not.

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
