# Semantic normalization before optimization

## 1. Problem and representation

The compiler must expose a hardware computation that several consumers can
transform consistently. Source-level types, bundles and elaboration constructs
are convenient for authors, but synthesis needs bit-level meanings and simulation
needs explicit state transitions. LiveHD therefore lowers language-specific
syntax through LNAST into a hierarchical word-level LGraph. The alternative
Yosys reader can enter at LGraph directly. The
[LNAST](../livehd/06-lnast.md) and [LGraph](../livehd/05-lgraph.md) chapters
specify these representations.

A word-level operation retains operand widths, signedness and state/control
roles until its consumer needs a lower-level representation. Keeping those
facts explicit avoids treating an untyped algebraic identity as a valid
finite-width hardware rewrite. It also allows synthesis and simulation to
choose different implementations of the same operation.

## 2. Acyclic equivalence and local extraction

The default simplifier builds an acyclic equivalence representation of eligible
pure expressions. Hash-consing identifies repeated structure. Rewrites run
when expressions are inserted: a simplification replaces a representation,
while an alternative retains another equivalent representation for extraction.
State, instances and other unsupported/effectful operations form boundaries.
This follows the acyclic e-graph approach developed for
[Cranelift](80-references.md#aegraphs), rather than assuming an unrestricted
whole-design equality-saturation search.

**Algorithm 1 — normalize a graph body.**

1. Traverse eligible expressions in dependency order, preserving semantic and
   synthesis-policy boundaries.
2. Canonicalize operands where the operation permits it and intern repeated
   expressions. Preserve operand multiplicity where it affects the function.
3. Propagate constant and range information. A partially unknown value is not
   silently replaced by a fully known constant.
4. Apply guarded rewrite rules and retain admissible alternatives.
5. Extract according to the selected cost profile; prefer the existing form
   on a cost tie.
6. Reconstruct the changed part of the graph, preserving source attribution
   and named/state boundaries, then run the shared cleanup operations.

For synthesis, the cost approximates hardware work and is width-aware. For
simulation, it approximates operations on host words. Sharing affects the
marginal cost: a subexpression still required by another reader is not charged
as if choosing one alternative could eliminate it. These are heuristic
extraction costs, not exact mapped area or measured execution time. The rules
establish admissible equalities; the cost model chooses among them.

## 3. Width, hierarchy and structural legality

The scheduled graph passes contain two simplification/bitwidth pairs, with
enable optimization between them. The driver inserts specialization and
structural legalization after the first width inference, and defers dependent
work until loop legality has been established. The second pair can exploit
facts exposed by the first inference and repairs. This is a fixed compilation
schedule, not an optimization-level search.

Compile-time module specialization propagates constant configurations through
instance boundaries while ordinary combinational inlining remains disabled.
Structural legalization may dissolve a state-free instance when needed to
resolve an apparent combinational loop; retaining hierarchy is therefore a
default policy, not an absolute prohibition on structural repair. Accepted
state and compact-loop boundaries must remain meaningful to all downstream
consumers.

The final compiled graph is sealed after normalization and checks. Synthesis
and simulation can make private copies for consumer-specific transformations.
In particular, the synthesis observability sweep described in the next chapter
is distinct from optional compile-time state proofs or whole-design flattening.

## 4. Correctness boundary

Legalization establishes a usable graph structure; it is not placement
legalization and it does not establish equivalence to an independent source.
The compile formal tier handles its supported obligations under a cheap,
resource-bounded policy. Unknown or deferred obligations must not be described
as proofs. Full relational verification belongs to the
[formal flow](06-execution-verification.md#3-proof-and-measurement-boundaries).
Compile-time SAT-based simplification is a separate opt-in transformation.

Further detail: [acyclic simplifier and cost model](https://github.com/masc-ucsc/livehd/blob/main/pass/aegraph/README.md),
[graph semantics](../livehd/05-lgraph.md), and
[formal obligations](../livehd/07-formal.md).
