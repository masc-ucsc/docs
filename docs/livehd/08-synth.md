# Synthesis and timing

`lhd synth` is the one-shot synthesis flow: compile, form regions, map and
analyze timing. The default mapper is ABC; `synth.mapper=usyn` selects native
synthesis. Shared preparation and reconstruction live in `pass/synth`.

```sh
lhd synth dut.prp --top top.m --set synth.liberty=cells.lib \
  --workdir W --stats --emit-dir verilog:mapped/
```

Reports and mapped intermediates are under `W/synth/`. The same Liberty library
feeds mapping and static timing. `lhd.incremental` controls reuse under the
working directory. Placement is off by default; `synth.place=true` enables the
physical flow with the required LEF inputs. Experimental `legroute.local`
remains opt-in and is not the default legalizer.

See the [synthesis methodology](../lhd/03-synthesis.md) and
[physical-flow chapter](../lhd/04-physical.md) for the algorithms, assumptions
and experimental boundaries. Individual `lhd pass color|abc|opentimer` commands
remain useful for inspecting intermediates and choosing a custom decomposition.

For source optimization, use a proof gate before accepting a timing result:
compare the edited source to the previously accepted version, then measure
both with the same mapping, library and timing constraints. A sampled or
bounded result is not an unbounded equivalence proof.

## The loop, one iteration

```bash
# 1. compile the edited source (must pass)
lhd compile dut.prp --top top.m --emit-dir lg:G --workdir W

# 2. the gate: edited vs the PREVIOUSLY ACCEPTED source (cycle-accurate)
lhd lec --impl dut.prp --ref accepted/dut.prp --top top.m --workdir W \
  --set formal.effort=proof
#    require PROVEN-full; inspect the verdict, not only exit 0

# 3. the score: map and time the compiled graph with one cell library
lhd synth lg:G --top top.m --set synth.liberty=cells.lib \
  --emit-dir lg:NET --workdir W --stats
#    -> W/synth/ reports, including mapping QoR and OpenTimer timing
```

Notes that keep the loop sound and fast:

- The gate is **cycle-accurate**: retiming and
  latency-changing edits are off-limits. Chained equivalence (each edit vs the
  previous accepted version) is cheap: the `--workdir` `formal_cache.json`
  verdict cache and semdiff structural matching can reuse unchanged modules
  when their inputs, settings and build salts still match.
- Netlist-vs-source LEC (mapped netlist against its `pass partition` twin with
  `pass liberty gensim` cell models) is an **lhd-bug catcher that runs in the
  test suite**, not in the loop — it validates the compiler, not the edit.
- Everything is machine-readable: `--result-json` envelopes carry
  `status`/`error.class`, the `"qor"` member carries the score, and a
  `REFUTED-cex` result leaves `lecfail.json` with a source-located root cut the agent can react
  to.

## Block-scoped synthesis attributes (Pyrope)

A code block can be its own synthesis partition region, with its own ABC
options:

```pyrope
mod m(a:u8, b:u8, c:u8, s:u1) -> (x:u8@[0], y:u8@[0]) {
  x = (a & b) | (c ^ a)
  {::[abc='strash; &get -n; &dch -f; &nf {D}; &put', color=2]
    mut t = b & c
    if s { t = a | b }
    y = t ^ c
  }
}
```

- Every LGraph node generated from statements inside the block gets node color
  2; `pass.abc` maps each color region as its own module (`m__c2`), so the
  block is an isolated mapping/QoR/LEC unit.
- `abc='…'` is the region's verbatim ABC flow override (the same vocabulary as
  `--set pass.abc.flow`). **Single-quote it** — a double-quoted Pyrope string
  would interpolate `{D}`. It lands in the graph's `coloring_info` JSON as
  `region_opts["2"].flow`, which `pass.abc` reads; a CLI
  `--set pass.abc.region_opts` wins over it.
- `color=` takes a positive integer (two blocks with the same id form one
  region group), a string label (same label anywhere in the file ⇒ same
  region), or can be omitted (a fresh id is auto-allocated).
- The attribute is **semantics-free by construction**: the annotated source is
  LEC-PROVEN identical to the stripped source (guarded by
  `//lhd/tests:lhd_block_attr_test`). Unknown attribute names or malformed
  values are hard compile errors — a mistyped hint never silently no-ops.
- Source-seeded colors survive a later `lhd pass color <alg>` run: the
  algorithm keeps seeded nodes and allocates its own region ids above the
  seeded ones (`coloring_info` carries `algorithm:"block-attr"` /
  `seeded:true`).

## The two timing oracles

**Phase 1 — ABC post-map QoR** (`qor.json`, `"kind":"abc-map"`): after each
region's flow, pass.abc reads back gates / Liberty area / critical arrival
(`Abc_NtkDelayTrace`) plus the worst-arrival region output, source-attributed
via the srcid carry-through. Per-region only: paths crossing region or
blackbox boundaries are invisible here. Free with every mapping run.

**Phase 2 — OpenTimer STA** (`timing.json`, `"kind":"sta"`): real
arrival-time analysis of ONE tech-mapped module (`--top` a region module, or
a whole-design flat module — see below). Flops and memories are path
boundaries (their outputs arrive at 0), so flop-to-flop segments are scored;
`min period ≈ max_delay` up to setup/clock terms. Endpoints resolve to the
pre-synthesis `file:line` through the gates' srcid, giving the agent concrete
edit targets. Optional `.sdc` (`create_clock -period`, `set_input_delay`, …)
and `.spef` refine it.

**Whole-design timing without region boundaries**: `lhd pass color flat` +
`lhd pass abc` flattens the instance hierarchy (`pass.abc.flatten=auto` fires
on the flat coloring) and maps the whole design as ONE netlist module named
after the top — a drop-in replacement for the original def, with no
cross-module bus-packing glue. `lhd pass opentimer --top <top>` then times
the entire design in its default single-module mode, catching every
cross-module path the per-region ABC estimate is blind to.

## What the agent can and cannot move

The effect of a source change depends on the mapper, constraints and region
boundaries. Measure it rather than assuming that a source-level rewrite will
survive optimization. Useful candidates include:

- **Strength reduction ABC cannot see**: `div`/`mod` are blackboxed (never
  mapped, invisible to timing); replacing a constant division with a
  reciprocal multiply-shift makes the cone mappable at all — and the LEC gate
  proves the transform (cvc5 handles the bit-vector equivalence).
- **Region control**: isolate the hot cone into its own block region and give
  it a deeper flow (`&dc4`, `resyn2`, a binding `&nf -D` target) without
  paying that effort design-wide.
- **Bit-width discipline**: narrower operands shrink every downstream cone —
  the QoR's `critical_src` points at the code to narrow.
- Retiming/pipelining is out of scope until transaction-level equivalence
  (4f-fluid-lec) lands; `dretime` was removed from the default seq flow for
  exactly this reason (it also destroys register-name correspondence and
  din-cone attribution).

See the source references for [ABC](https://github.com/masc-ucsc/livehd/blob/master/pass/abc/README.md),
[native synthesis](https://github.com/masc-ucsc/livehd/blob/master/pass/usyn/README.md)
and [OpenTimer](https://github.com/masc-ucsc/livehd/blob/master/pass/opentimer/README.md)
for options and report formats.
