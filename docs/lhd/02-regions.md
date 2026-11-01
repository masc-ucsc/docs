# Synthesis decomposition and private preparation

## 1. Optimization scope is a design decision

A synthesis region is a subgraph optimized as a unit with an explicit interface.
A coloring assigns eligible nodes to regions; colors are not placement bins or
simulator scheduling colors. Region boundaries trade optimization freedom
against memory, concurrency and incremental reuse. Small regions bound local
work but expose artificial timing boundaries and can prevent useful sharing.
Large regions retain more interacting logic but can make one mapping task
expensive.

The current fused synthesis flow selects **coarse** partitioning independently
of its default ABC optimizer. This matters: selecting ABC no longer implies
that its fine-grained coloring profile is selected. The older description of
all default regions as bounded by a predicted-AIG threshold does not describe
this coarse policy.

## 2. Backward cones and overlap

Let a definition contain eligible operations \(V\), and let \(\pi(v)\) estimate
the Boolean construction cost of operation \(v\). Costs depend on operator and
width: wiring is cheap, while mux networks, arithmetic and variable shifts can
expand substantially when lowered to bits. For a set \(S\), define
\(\pi(S)=\sum_{v\in S}\pi(v)\). This is a construction estimate, not physical
cell area or a mapped-gate count.

**Algorithm 2 — form synthesis regions.**

1. Identify observable logic and state, memory, instance and output boundaries.
2. Grow backward cones from data roots under the selected boundary profile.
3. Assign first ownership of visited logic and record overlap when another
   cone reaches it, without duplicating ownership.
4. Merge cones according to sharing and the profile's constraints.
5. Apply permitted forward/tiny-region merges and deterministic renumbering;
   preserve explicit source grouping and required native boundaries.

Under the **coarse register-to-register profile**, walks reach register
boundaries and overlapping cones merge even when their union exceeds the
usual predicted-AIG limit. That limit still constrains the subsequent forward
merge. A large reconvergent region is consequently a possible outcome, not a
violation of a hard region-size guarantee.

The optional **fine profile** introduces operator cuts, separate control cones
and arithmetic extraction. Backward growth and overlap merging use the soft
predicted-AIG budget. It is useful when bounded mapper tasks are worth the
additional boundaries. Memory-first growth and boundary-wiring exposure are
further optional policies, not assumptions of the baseline. Memories remain
traversal boundaries regardless of which growth policy is selected.

The distinction from a cut-minimizing partition is the unit being preserved:
state-rooted computation and shared logic guide decomposition. Incremental
stability is a motivation, but deterministic traversal alone does not guarantee
that an arbitrary local edit leaves every neighboring region unchanged.

## 3. Prepare a synthesis copy

The mapper operates on a private design closure. It can simplify implementation
structure without changing the compiled graphs consumed by simulation or
verification. The default synthesis preparation includes:

- **Constant specialization:** form reusable specialized versions where
  constant instance inputs simplify a callee, and propagate returned constants.
- **Register merging:** combine structurally identical state machines with
  matching data and control semantics, repeating when a merge exposes another.
- **Observability sweeping:** propagate bit demand backward from observable
  outputs, memories and opaque cells across hierarchy; remove unobserved state
  and narrow retained values where justified. It also applies to memories
  lowered into registers.
- **Clock-enable factoring:** extract a shared enable conjunct for compatible
  registers into a clock-gating structure, when the library supplies a suitable integrated clock-gating cell, subject
  to eligibility and size thresholds, while retaining the residual per-register enable.

These transformations preserve the chosen state semantics; they are not
retiming or an automatic latency-changing optimization. Memory policy decides
whether storage remains a native boundary or becomes a synthesizable register
network. Compact loops and hierarchy require preparation before region bodies
are lowered. Unsupported state/control structures stay explicit or produce a
diagnostic; an incomplete Boolean network is not a valid mapped result.

## 4. Lowering and reconstruction contract

A region becomes a backend-neutral Boolean network with ordered inputs,
outputs and state correspondence. The backend returns a cell netlist over that
interface. Reconstruction reconnects ports and retained native boundaries,
keeps the attribution needed for diagnostics and checking, and publishes a
complete region body. Backend-private objects do not become the design's
persistent representation.

This interface permits separate policies for optimization and cell mapping.
The default uses ABC for both; native uSyn is an alternate optimizer and is not
covered as a default algorithm here. See the
[shared pipeline](https://github.com/masc-ucsc/livehd/blob/main/pass/synth/README.md)
and [coloring reference](https://github.com/masc-ucsc/livehd/blob/main/pass/color/README.md)
for implementation details and alternate profiles.
