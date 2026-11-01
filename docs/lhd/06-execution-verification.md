# Simulation, verification and evidence boundaries

## 1. One compiled design, different decompositions

Simulation and formal analysis consume the compiled graph, not the mapped
region partition by default. A synthesis color bounds Boolean optimization;
a simulation color groups computations for scheduling and code generation.
Conflating them would impose hardware optimization boundaries on an execution
problem with different costs.

The simulator builds a private occurrence-aware dependency graph. Ordinary
small combinational instances can be absorbed into their caller's evaluation
colors without changing the frontend's no-inlining default. Larger or reused
bodies can retain useful boundaries. Compact loops retain a compact execution
representation; independent compatible loops can be combined where dependency
analysis permits it.

## 2. Activity and state phases

Simulation grouping trades fewer function calls and boundary transfers against
finer activity skipping. Internal values can remain local to an evaluator;
values crossing colors require explicit storage and change handling. The
partition therefore considers live-value pressure, hierarchy and execution
phases rather than only Boolean size. The default backend emits native LLVM
objects. The Slop C++ backend remains an explicit alternative; unsupported LLVM
lowering is not silently interpreted as permission to switch backends.

The state schedule preserves simultaneous hardware sampling:

1. Settle input changes and supported latch cones before the rising edge.
2. Sample rising-edge registers, then commit their pending values together.
3. Settle the resulting combinational and latch activity.
4. Sample falling-edge registers, then commit their pending values together.
5. Settle again and publish the period's outputs.

A register cannot see another register's pending update from the same edge.
Supported latch transparency is handled within settling phases; cyclic or
unsupported transparent dependencies are not resolved by arbitrarily ordering
updates. This is a zero-delay digital model, not an analog timing simulation.
Activity scheduling and reuse must preserve this state contract regardless of
the selected performance policy.

The [simulation implementation reference](https://github.com/masc-ucsc/livehd/blob/main/inou/cgen/README.md)
contains the detailed grouping, lowering and runtime contracts. Profiling and
measurement procedures belong there or in dedicated experiment documentation,
not in the algorithm description.

## 3. Proof and measurement boundaries

The compile formal tier cheaply discharges supported obligations and retains
unresolved checks according to its documented policy. Independent equivalence
checking compares two designs, using structural correspondence and formal
reasoning where needed. The solver infrastructure includes
[cvc5](80-references.md#cvc5); the encoding and proof obligations determine what
its answer establishes. A tool name alone is not a correctness argument.

| Evidence | Establishes | Does not establish |
|---|---|---|
| Graph legality and width checks | Required representation invariants | Equivalence to an independently supplied design |
| Unbounded equivalence proof | The specified relation under its assumptions | Physical timing, power or routability |
| Bounded verification | The checked property over the stated bound | An unbounded theorem unless induction or another complete argument closes it |
| Simulation | Behavior for the executed stimuli and modeled schedule | Exhaustive functional correctness |
| Mapped or placed STA | Timing under the supplied models and constraints | Post-route sign-off without corresponding parasitics and checks |
| Legal placement or coarse routing feasibility | The constraints actually enforced | Detailed connectivity and DRC closure |

UNKNOWN, timeout and deferred checks remain distinct from proof. A physical or
logic optimization should be evaluated against the evidence appropriate to its
claim: a locally improved cost is not by itself proof of preserved behavior,
and preserved behavior is not evidence of improved physical QoR.

The [formal reference](../livehd/07-formal.md) is the authority for verdicts,
assumptions, bounded versus inductive checks and counterexample artifacts.
The [usage guide](../livehd/02-usage.md) describes how to request them. This
chapter locates those analyses in the flow without duplicating their contracts.
