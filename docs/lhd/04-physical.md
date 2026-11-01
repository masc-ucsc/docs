# The conditional physical implementation flow

## 1. Scope and objective

Placement is requested explicitly; it is not part of an unqualified synthesis
run. Given mapped cells, LEF geometry, a floorplan or core-sizing policy, and
timing information, the physical stage seeks legal coordinates with useful
wirelength, density and timing. Its normal full mode produces a placement for
further physical implementation. It does not imply completed clock-tree
synthesis, detailed routing or sign-off.

LiveHD uses a native DREAMPlace integration. The analytical placement family
exemplified by [DREAMPlace](80-references.md#dreamplace) combines a smooth
wirelength objective with density optimization. The cited GPU/PyTorch research
is background for the method; it is not a claim that the current LiveHD native
execution uses the same runtime or reproduces the paper's measurements.

A useful abstraction of the global-placement objective is

\[
\min_{x,y}\; W_{\mathrm{smooth}}(x,y;w)
                 + \lambda D(x,y),
\]

with congestion and timing feedback modifying the effective demand, weights
or placement forces. This equation describes the core tradeoff, not every
stage-specific term. The continuous result still needs discrete row/site
legalization.

## 2. Physical scales and stage boundaries

Three partitions have distinct meanings. The **grid** accumulates density and
routing demand for global-placement forces. A **region** localizes boundary
refinement and related physical decisions. A **bin** bounds local legalization
work. None is automatically identical to a synthesis color.

With macros, the normal flow first places macros together with the surrounding
cell demand, then fixes the macro geometry and places standard cells. Without
macros, it uses a single placement stage. The optional centroid-floorplanning
phase and H2D macro solver are separate choices. Imported fixed geometry and
explicit floorplan bounds remain constraints; a generated core has its own
permitted sizing/retry policy.

Virtual fillers and density feedback distribute whitespace. The default
routing estimator is RSMT-based: estimated rectilinear net demand guides
congestion spreading. It predicts pressure on routing resources; it does not
construct a DRC-clean detailed route. Bus-order boundary refinement is enabled
within the physical flow and coordinates virtual crossing pins between regions.
This is a geometric refinement, not a proof that every boundary connection is
routable.

## 3. Timing feedback and physical repair

The fast GP feedback path ranks critical data nets using characterized gate
delay and approximate wire RC. It updates weights as geometry changes. Those
rankings guide movement; they must not be interpreted as sign-off WNS or an
electrically certified period. Detailed timing is retained for physical repair
validation and the final analysis.

**Algorithm 4 — normal full-placement path.**

1. Establish the physical frame, fixed obstacles, macro/cell geometry and IOs.
2. If macros exist, perform macro placement and the macro-to-cell handoff.
3. Place standard cells using density, congestion and timing feedback.
4. Refine region boundary bus order and obtain intermediate legal geometry
   where subsequent optimization requires it.
5. Run the enabled timing-driven refinement and resizing/buffer-repair work,
   checking candidate physical changes against timing and geometry criteria.
6. Finish with terminal legalization and produce the physical handoff and
   timing analysis.

With full placement and OpenTimer, timing-driven refinement and resizing are
normally enabled. Critical-cone resynthesis is a separate opt-in operation.
Whole-color IO-feedback resynthesis is another mechanism: for eligible ABC
runs with a work directory and clock constraints, placement-derived boundary
conditions can trigger one automatic remapping batch and a stage restart.
Saved compatible feedback can seed a later invocation. These are bounded
feedback policies, not an unconstrained synthesis/placement fixed-point loop.

## 4. Terminal legalization and routing boundary

The default terminal legalizer prioritizes critical pair alignment and timed
critical cells, then legalizes the remaining cells under local capacity and
row/site constraints. Local SAT reasoning can propose pair alignments inside
this legalizer; that does not make it the experimental whole cell-box legroute
flow. Physical legality and improved pin alignment still leave detailed router
work to do.

Legroute, general SAT legalization, signal pre-routing and native power-grid
construction are not default steps. Legroute jointly selects box locations and
coarse H/V routes under edge-capacity constraints, but in-box access and detailed
routing remain separate obligations. Its methodology and evolving experiments
remain in their dedicated references. Importing its algorithm into the
baseline would misstate what a normal placement currently does.

The physical handoff must distinguish a legal placement, estimated congestion,
actual emitted wires and an independently checked routed design. Only the
last supports a routed-design claim at the checks actually performed.

Further detail: [physical flow and stage gates](https://github.com/masc-ucsc/livehd/blob/main/pass/place/README.md).
Technology-specific controls and experimental routing policies remain in that
reference and the local placer option document.
