# Logic synthesis, technology mapping and timing context

## 1. Two coupled optimization problems

A Boolean network and a standard-cell implementation are different objects.
Equivalent Boolean factorizations expose different mapping cuts; fewer Boolean
nodes need not imply less cell area or lower physical delay. LiveHD's default
backend uses [ABC](80-references.md#abc) to search Boolean structure, then cover,
buffer and size that structure using the selected cell library.

For a prepared region \(R\), the objective is to obtain a complete mapped
network \(N_R\) under the requested timing and resource constraints. Region
isolation makes this tractable and reusable, but removes some of the electrical
environment. Boundary refinement restores that information after stitching.
Neither local optimization nor refinement guarantees a globally optimal
implementation.

## 2. Boolean search

The backend imports the region into an AND-inverter graph (AIG). Structural
hashing shares identical two-input AND nodes and complemented edges. The
source expansion is an initial topology, not a mandated gate arrangement.

The built-in area and delay recipes use established ABC transformations.
Area-oriented synthesis combines structural reduction, rewriting and equivalent
choices. Delay-oriented synthesis also restructures through temporary LUT
networks, local don't-care resynthesis and balanced sum-of-products forms.
Temporary LUTs are optimization structures; the target remains a standard-cell
netlist. [DAG-aware rewriting](80-references.md#aig-rewriting) supplies part of
the algorithmic foundation. Equivalent alternatives help mapping escape the
structural bias of a single factoring.

The applicable recipe depends on the delay objective and region size. Large
regions use a shorter flow. Built-in flows preserve sequential boundaries;
retiming is not silently introduced to improve the reported delay. Source-state
correspondence remains necessary for reconstruction and independent checking,
although deliberate state merging or sweeping can remove redundant state.

## 3. Mapping and physical budget

The built-in flow performs standard-cell covering through a unit-delay library
view, then uses Liberty timing information for physical buffering and sizing.
Logic-depth selection and electrical optimization therefore have different
cost models. Detailed command strings and library eligibility rules belong in
the [ABC reference](https://github.com/masc-ucsc/livehd/blob/main/pass/abc/README.md).

When a target period \(T\) is provided, sequential overhead reduces the
combinational budget:

\[
B_R = T - m_R,
\qquad m_R \approx t_{\mathrm{clk}\to Q}+t_{\mathrm{setup}}
\]

for regions containing the relevant registers; combinational regions use the
applicable target without that register margin. This is a mapping budget, not a
replacement for whole-design clock and timing analysis.

**Algorithm 3 — realize and select a region.**

1. Resolve the region's objective, library, interface environment and budget.
2. Reuse a compatible mapped body if structural and recipe validation succeeds.
3. Otherwise lower the region and run the eligible logical recipe.
4. Cover the resulting network; buffer and size under the physical budget.
5. If late, attempt timing repair. If slack permits, attempt area recovery.
6. Where eligible, compare an alternate area-oriented realization under the
   same timing budget and retain a complete acceptable candidate.
7. Reconstruct the region's ports, state and native boundaries and publish it.

A bounded search can return a mapped design that still misses its timing
target; the timing report must make that visible. A resource refusal or failed
read-back is not a successful partial mapping.

## 4. Reconnecting the electrical environment

Before all regions are mapped, output loads and input drivers are estimates
derived from connectivity and the library. After reconstruction, crossing nets
have concrete sinks and drivers. For a crossing output \(p\), the physical
load includes the capacitances of the mapped pins it drives and any applicable
external load. Refinement replaces stand-ins with this stitched environment
and re-sizes eligible regions. Timing-aware refinement is conditional on the
available library model and objective; full reuse can avoid repeating it.

The distinction between *local* and *stitched* timing is essential. A region
can satisfy its isolated estimate while a path crossing several regions misses
the design constraint. OpenTimer provides the later mapped-design analysis;
its [incremental timing methods](80-references.md#opentimer) are relevant
background, while LiveHD's integration determines which loads, constraints and
parasitics are supplied.

## 5. Arithmetic and exploration

Arithmetic lowering chooses concrete adder, multiplier, comparison and shifter
structures before cell covering. Automatic policies can evaluate alternative
realizations where eligible and compare their effect on a stitched objective.
Explicit synthesis profiling can additionally store compatible decisions for
future runs. These mechanisms must not be conflated: the default profiling
mode replays prior decisions, and coarse partitioning does not automatically
extract the separate arithmetic modules described by the optional fine policy.

The native uSyn path chooses Boolean implementations before requesting an
optional mapping provider. Using ABC only as that provider is different from
running the default ABC optimizer. Its endpoint-selection and DOMINO research
methods remain a separate reference rather than being folded into this
baseline chapter.

Further detail: [shared mapping interface](https://github.com/masc-ucsc/livehd/blob/main/pass/synth/README.md),
[ABC algorithms and options](https://github.com/masc-ucsc/livehd/blob/main/pass/abc/README.md),
and [timing integration](https://github.com/masc-ucsc/livehd/blob/main/pass/opentimer/README.md).
