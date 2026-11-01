# Maintenance, provenance and documentation migration

This appendix supports review and maintenance of the draft. It is not a
methodology chapter or an instruction to delete files immediately.

## 1. Reviewed baseline

The draft describes LiveHD revision
[`f60e2ecc2c155c53b03fcb3a0350118e0586a87d`](https://github.com/masc-ucsc/livehd/tree/f60e2ecc2c155c53b03fcb3a0350118e0586a87d),
reviewed on 2026-11-01. The pre-existing local change was documentation in
`docs/placer.html`; no algorithm changes were made for this draft. Selected
policy defaults were cross-checked with `lhd list options` and the source.

The baseline differs from older local narratives in several important ways:

- The graph simplifier is aegraph, with a consumer-specific extraction cost.
- Fused synthesis defaults to coarse partitioning even when the optimizer is
  ABC. Register-to-register overlap merging is not bounded by the ordinary
  predicted-AIG threshold.
- Synthesis specialization, register merging, observability sweeping and clock
  gating are enabled. Clock-gate insertion also requires a suitable Liberty
  ICG cell and eligible register groups.
- Native LLVM objects are the default simulator backend.
- Placement is opt-in; legroute is an additional opt-in, not its default
  terminal legalizer.
- Compile-cache invalidation must remain body-sensitive where callers consume
  exported bodies. The old unconditional claim that a body-only edit can
  invalidate only its own unit is not an implementation contract.

## 2. Implementation evidence map

These are the entry points to inspect when an algorithm changes. Detailed
source references are kept here so the methodology chapters can stay focused
on rationale, constraints and dataflow.

| Topic | Reviewed source / detailed reference |
|---|---|
| Defaults and effective dispatch | [option registry](https://github.com/masc-ucsc/livehd/blob/f60e2ecc2c155c53b03fcb3a0350118e0586a87d/lhd/lhd.hpp), [synthesis driver](https://github.com/masc-ucsc/livehd/blob/f60e2ecc2c155c53b03fcb3a0350118e0586a87d/lhd/lhd_kernel_synth.cpp) |
| Graph schedule and structural legality | [compile driver](https://github.com/masc-ucsc/livehd/blob/f60e2ecc2c155c53b03fcb3a0350118e0586a87d/lhd/lhd_kernel_compile.cpp), [scheduled graph passes](https://github.com/masc-ucsc/livehd/blob/f60e2ecc2c155c53b03fcb3a0350118e0586a87d/lhd/lhd_kernel_common.cpp) |
| Acyclic rewriting and extraction | [aegraph reference](https://github.com/masc-ucsc/livehd/blob/main/pass/aegraph/README.md) |
| Cone profiles | [color registration and profile dispatch](https://github.com/masc-ucsc/livehd/blob/f60e2ecc2c155c53b03fcb3a0350118e0586a87d/pass/color/pass_color.cpp) |
| Shared preparation and backend seam | [synthesis reference](https://github.com/masc-ucsc/livehd/blob/main/pass/synth/README.md) |
| ABC recipes and budgets | [backend](https://github.com/masc-ucsc/livehd/blob/f60e2ecc2c155c53b03fcb3a0350118e0586a87d/pass/abc/abc_backend.cpp), [detailed reference](https://github.com/masc-ucsc/livehd/blob/main/pass/abc/README.md) |
| Compile reuse | [cache implementation](https://github.com/masc-ucsc/livehd/blob/f60e2ecc2c155c53b03fcb3a0350118e0586a87d/lhd/lhd_compile_cache.cpp) |
| Region reuse | [structural authorization and artifact handling](https://github.com/masc-ucsc/livehd/blob/f60e2ecc2c155c53b03fcb3a0350118e0586a87d/pass/synth/region_cache.cpp) |
| Placement, repair and physical reuse | [physical reference](https://github.com/masc-ucsc/livehd/blob/main/pass/place/README.md), synthesis driver above for effective stage gates |
| Simulator scheduling | [simulation reference](https://github.com/masc-ucsc/livehd/blob/main/inou/cgen/README.md) |
| Formal semantics | [formal guide](../livehd/07-formal.md) |

Pinned links identify this review's source; `main` links lead to living detail.
Some component README defaults lag the fused driver's overrides, so consult
both before changing this baseline. A pass's standalone default does not
necessarily describe `lhd synth`.

## 3. Local-document retirement assessment

Paths below are relative to the **LiveHD repository**, not this docs repository.
“Retire” means the concept is covered by this draft and/or the existing guide;
it does not promise preservation of every command, figure or implementation
detail. No source document has been deleted by this migration draft.

| Local document | Recommendation | Conceptual replacement / material to preserve |
|---|---|---|
| `docs/synthesis.html` | **Retire after accepting this draft and retargeting links.** | [Regions](02-regions.md), [mapping](03-synthesis.md) and [reuse](05-incremental.md) cover the shared flow. Optional uSyn-specific detail stays in its dedicated reference; implementation contracts stay in `pass/synth/README.md`. |
| `docs/synth_abc.html` | **Retire after accepting this draft and retargeting links.** | [Mapping](03-synthesis.md) covers Boolean alternatives, covering, budgets and boundary refinement. Exact recipes and architecture-trial details already have a home in `pass/abc/README.md`. |
| `docs/passes.html` | **Retire after accepting this draft and retargeting links.** | [Overview](index.md), [normalization](01-normalization.md), [execution](06-execution-verification.md), existing [usage](../livehd/02-usage.md) and [pass guide](../livehd/11-pass.md). Do not carry over stale C++-only simulation or optimizer defaults. |
| `docs/opt_loop_incr.md` | **Partial overlap; keep until operational material is separated.** | [Reuse](05-incremental.md) replaces the algorithm discussion. Queue items, measurement rules and diagnostics are not reproduced; move still-current work to the task hub or owning README before retiring this file. Some old invalidation claims are explicitly superseded. |
| `docs/placer.html` | **Keep as the detailed/experimental reference for now.** | [Physical flow](04-physical.md) covers default concepts, but not its option inventory, phase matrix, technology examples or legroute description. A default-only reference cannot replace that experimental material. |
| `docs/synth_usyn.html` | **Keep, or move later to a clearly labeled research section.** | Its endpoint selection, care sets, residual optimization and DOMINO methods are not part of this default-flow draft. A sentence naming the alternate backend does not replace them. |
| `docs/placement_regularity.html` | **Keep.** | Contains advisory hierarchy metadata, fixtures and measurements. These are not default-flow methodology and are not replaced here. |
| `docs/simopt.md` | **Partial overlap; keep its operational/evidence role.** | [Execution](06-execution-verification.md) covers scheduling concepts. Profiling, tuning protocol, negative experiments and reproduction commands remain distinct. |
| `docs/opt_loop_synth.md` | **Keep or consolidate into current tasks separately.** | The new mapping chapter covers algorithms; experiment acceptance rules, harness requirements and work queues are not migrated. Existing [synthesis guide](../livehd/08-synth.md) also covers the edit/LEC/QoR loop, but not the full record. |
| `docs/opt_loop_incr_log.md` | **Keep/archive as evidence.** | A measurement and decision history is not superseded by methodology. |
| `docs/current_opt_loop_incr.html` | **Keep as a generated evaluation artifact, or relocate separately.** | Its measurements are intentionally absent from this draft. |
| `docs/synth_plots.html` | **Keep as evaluation, or relocate separately.** | Cost/runtime plots are not algorithm documentation and are not replaced. |
| `docs/examples.md` | **Keep or curate into recipes separately.** | Design-specific commands and external benchmark workflows go beyond the [usage guide](../livehd/02-usage.md). |
| `docs/sample_prompt_cleanup_pyrope.md` | **Keep as an agent workflow.** | A behavior-preserving source-cleanup procedure is not a flow-algorithm chapter. |
| `docs/CONTRIBUTING.md` | **Keep pending a policy-specific consolidation.** | Overlap with the [GitHub guide](../livehd/12-github.md) does not make contribution policy an algorithm-document duplicate. |
| `docs/CODE_OF_CONDUCT.md` | **Keep.** | Community policy is outside this migration. |
| `docs/PULL_REQUEST_TEMPLATE.md` | **Keep pending a template-specific cleanup.** | Repository workflow metadata is outside this migration. |

The `docs/divergence/` subtree is also retained: it contains semantic
counterexamples and evidence, not redundant methodology prose.

The first three retirements need link maintenance. Known consumers include
`docs/synth_usyn.html` (including its `[S §…]` / `[A §…]` section citations),
`docs/placer.html` and `pass/synth/README.md`, plus links among the retiring
pages. Retarget the section citations as well as URLs. Publish the replacement
before removing public destinations, or leave small redirects when preserving
old URLs matters. Re-scan inbound references at deletion time.

## 4. Division of responsibility

- `docs/lhd/`: the implemented default algorithm and conditional default flows,
  with references and explicit limits.
- `docs/livehd/`: IR semantics, CLI/formal contracts and developer principles.
- `docs/pyrope/`: the language contract.
- LiveHD component READMEs: implementation, options, diagnostics and tests.
- LiveHD task pages: proposed or unfinished algorithms; a successful experiment
  is not sufficient to promote a feature into the default chapter.
- Evaluation artifacts: measured results, provenance and reproduction data.

When a default algorithm changes, update the relevant chapter, its scope table
and this provenance. Keep numerical evaluation outside the methodology and
cite primary sources for external algorithms. This draft deliberately leaves
the existing LiveHD/Pyrope contract chapters intact.
