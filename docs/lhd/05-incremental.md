# Incremental computation and reuse validity

## 1. Reuse is part of the algorithm

An interactive flow must retain useful work across small source changes.
Region decomposition supplies potential reuse units, but names or partition
numbers alone do not establish equivalence. A reusable result must match both
the computation and the context that produced it. This is the central link
between the incremental synthesis motivation of
[LiveSynth](80-references.md#livesynth), structural reuse in
[SMatch](80-references.md#smatch), and the current implementation.

The baseline enables persistent reuse when a named work directory is present.
One switch controls these persistent tiers. It does not mean every stage has
the same cache key, granularity or proof of compatibility.

## 2. Stage-specific identity

Conceptually, an artifact's identity is

\[
K = H(\text{input structure},\text{interfaces},\text{effective policy},
       \text{technology/context},\text{producer identity}).
\]

This expression is an inventory of dependencies, not a claim that one hash
comparison is a sufficient reuse check everywhere.

| Tier | Reused work | Relevant compatibility conditions |
|---|---|---|
| Compilation | Parsed/elaborated units and completed graph artifacts | Source/import closure, options, ownership, interfaces, producer and artifact integrity |
| Synthesis | Prepared and mapped region bodies | Structural correspondence, port layout, effective recipe, library and timing assumptions |
| Simulation | Generated kernels/objects and compatible build artifacts | Color structure, semantic/runtime context, backend and producer identity |
| Timing | Analysis of a mapped design | Netlist, library, constraints, parasitics and timer identity |
| Physical flow | Completed compatible physical state; otherwise eligible coordinate hints | Graph, physical settings, technology, constraints, frame and artifact integrity |
| Formal | Reusable verdicts | Compared obligations/designs, assumptions, proof profile and producer identity |

For mapped-region reuse, a digest discovers candidates and an exact structural
comparison authorizes reuse. Port correspondence and transformation recipe must
also agree. A matching internal name is not enough. Compilation has its own
source/tree and artifact-inventory checks; the synthesis comparison should not
be generalized into an invented universal cache proof.

## 3. Invalidating the right dependencies

Hierarchy can make a local edit cheap, but only while the transformation
respects its boundary. If specialization, structural loop repair or inlining
consumes a callee's body, the caller's derived result depends on that body.
An interface-only invalidation rule would then be unsound. The current
compilation cache tracks source/dependency closure and transformation ownership;
this reference does not promise that every body-only edit rebuilds exactly one
source unit. Conservative invalidation can still repeat more work than ideal.

Technology and timing changes are equally significant. A logical region may be
unchanged while its mapped implementation becomes invalid because loads,
constraints or the library changed. Build-time producer salts separate code
versions that can produce different artifacts. The first run after a relevant
producer change is consequently expected to miss; reuse should be measured
without rebuilding between the compared runs.

## 4. Publication and partial reuse

**Algorithm 5 — reuse or recompute a stage.**

1. Resolve the effective input and transformation context.
2. Find candidate artifacts and validate their schema, provenance and integrity.
3. Perform the stage's semantic/structural compatibility checks.
4. Restore a compatible complete result, or compute a replacement under the
   stage's resource limits.
5. Publish the new result with the evidence and dependency metadata needed by
   the next invocation.

Independent mapper tasks use private sessions; reconstruction and publication
retain deterministic region correspondence. Memory admission must account for
concurrent work, not only the largest individual region.

Physical reuse has an additional distinction. An exact compatible completed
state can be restored as a generation. After a design edit, surviving cell
coordinates may instead be reused as **movable hints**. Those hints do not
restore old connectivity, fixed status, parasitics or timing validity.

The correctness target is that reuse preserves the result justified by the
current inputs and policy. Cold/warm timing differences are evaluation data,
not part of this contract. The
[shared synthesis reference](https://github.com/masc-ucsc/livehd/blob/main/pass/synth/README.md)
and [physical reference](https://github.com/masc-ucsc/livehd/blob/main/pass/place/README.md)
describe the individual tiers; operational measurement histories remain outside
this chapter.
