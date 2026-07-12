# Formal Verification

LiveHD's goal is a hardware flow "that you can trust" ([intro](00-intro.md)),
and formal verification is how that trust is earned mechanically rather than
by convention: equivalence proofs guard every translation the compiler
performs, user assertions become machine-checked obligations, and every
ordinary compile runs a small formal pass whose proofs feed back into the
generated design.

Three user-visible fronts share one formal engine:

| Front                    | Question answered                          | Entry point         |
| ------------------------ | ------------------------------------------ | ------------------- |
| Equivalence checking     | are these two designs the same?            | `lhd formal lec`           |
| Property verification    | do the asserts of this design hold?        | `lhd formal verify` |
| Compile-time checking    | what can be proven for free in every build | `lhd compile`       |

Two more components support them: a solver-free structural diff (`pass/semdiff`)
that tells the engine which parts of two designs already correspond, and a
research track that exports compiled designs to the Isabelle and Lean theorem
provers (`pass/isabelle`, `pass/lean`) for translation validation. The engine
core lives in `pass/lec` (shared by all fronts), the compile-time tier in
`pass/formal`.

The command syntax is documented in the
[usage chapter](02-usage.md#equivalence-checking-lec) and the property
language in the [Pyrope verification chapter](../pyrope/05-assert.md); this
chapter explains what the system does and why.

## User's point of view

### One verdict contract

Every front answers with one of three verdicts, under a single non-negotiable
contract: **PROVEN means definitively true, REFUTED means definitively false
with a counterexample, and everything else is reported as UNKNOWN** — an
inconclusive answer is acceptable, a wrong one never is. No optimization,
cache, hint, or shortcut inside the engine is allowed to change a verdict;
they may only change how fast it arrives.

The contract is deliberately asymmetric about what each verdict may rest on:

* A PROVEN is either an unbounded proof (holds at every cycle, forever) or a
  transparently labeled bounded one ("PROVEN to cycle k" — no violation within
  the explored window). The two are never conflated.
* A REFUTED always rests on a counterexample reachable from reset, replayable
  cycle by cycle. Anything less trustworthy — for example a violation that
  might start from an unreachable state — degrades to UNKNOWN instead.
* A conditional pass is always disclosed: a verdict proven under environment
  assumptions reads "PROVEN under N input assume(s)", one relying on unchecked
  user facts reads "under N unchecked assume(s)", and one relying on
  automatically guessed register pairings says so. The three can never be
  confused with an unconditional proof.

By default a refutation is a hard failure (non-zero exit), while an UNKNOWN
is a loud warning that does not fail the run; a strict mode turns UNKNOWN
into a failure too. One escalation: an equivalence check whose incomplete
run nonetheless surfaced a concrete divergence witness fails even without
strict mode.

### Equivalence checking

`lhd formal lec` proves two designs equivalent — a Pyrope compile against its
Verilog original, two revisions of a design, a pre- and post-synthesis
netlist. Each side may come from any front end (Verilog, Pyrope, or saved
LiveHD graphs), and the two sides' top modules are always force-paired so the
requested proof cannot silently become vacuous.

Hierarchical checking is the default: every module under the chosen top is
proven leaves-first, already-proven children are abstracted out of their
parents' proofs, and each module reports a machine-parseable progress line the
moment it settles. Combined with the on-disk cache (below), the practical
consequence is that editing one module of a large design re-proves roughly
that one module and its ancestors, not the world.

Register naming does not have to survive between the two sides. Registers are
matched by canonicalized name first; explicit correspondences can be supplied
for the rest; and remaining renamed registers are paired automatically by a
structural analysis whose guesses are applied speculatively — a wrong guess
can cost solve time but never a wrong verdict. Registers that stay unpaired
are reported with a reason (ambiguous twin, differing reset value, no
structural match) so the user can iterate instead of hitting a wall.

Users can also help the prover: `formal` blocks
([Pyrope syntax](../pyrope/05-assert.md#formal-blocks)) supply invariants and
environment assumptions. An internal invariant must itself be proven before it
may constrain the equivalence proof — the tool never accepts a user fact on
faith silently — and every admitted assumption is disclosed in the verdict.

Reset behavior is explicit rather than folded away: the tool separates the
reset-asserted and free-running regimes and by default compares the designs
after a held reset, with modes to compare during reset, ignore reset, or
require agreement in both regimes. Reset inputs are detected automatically or
named explicitly with polarity.

### Property verification

`lhd formal verify` takes one design plus optional sidecar property files and
adjudicates every assert as an independent obligation, reported in a
per-assert verdict table: PROVEN (inductive — holds at every cycle), PROVEN
to a cycle (bounded), REFUTED at a cycle with a trace, or UNKNOWN. Because
obligations are independent, a timeout is local — it costs one property at
one cycle, not the whole run.

Properties are written in ordinary Pyrope — inline `assert`/`assume` in the
design, or declarative `formal` blocks kept in sidecar files and bound to
module instances from the outside, so internals can be verified without
editing the module. Property expressions compile through the normal compiler,
which guarantees property semantics can never diverge from language
semantics. A block bound to a submodule is checked once per instance, each
reported separately.

Bounded results are not the ceiling: an induction step runs after the bounded
sweep and promotes every property that survives it to an unbounded PROVEN, so
full proofs — not just "no bug up to cycle k" — are the routine outcome for
well-behaved invariants.

### Formal checking inside every compile

Every optimizing `lhd compile` runs a formal tier (`pass/formal`) in a
deliberately cheap, deterministic profile (the tier is off at `-O0`). It
proves what it can quickly and never blocks a good build:

* An assert **proven** unbounded is elided from the generated design — the
  proof pays for itself as a synthesis optimization.
* A **refutation** of a user assert is a compile error only when it cannot
  be an artifact of unreachable state: in the default profile, a
  counterexample over a state-free cone at the committed design top; in the
  stronger opt-in profile, a counterexample confirmed reachable from a
  pinned reset, reported with its witness cycle.
* Everything else — timeout, unknown, a counterexample that might start from
  an unreachable state, a refutation inside a submodule whose real parent may
  constrain its inputs — is **deferred**: the assert stays as a runtime
  simulation check and the compile succeeds with a warning that says why.

Timeout is never an error in this tier; that is the design guarantee, not a
limitation. Because a proof here changes the build output, verdicts must be
reproducible: the tier budgets the solver with a machine-independent
resource limit rather than wall-clock time, so the same design gives the
same verdicts on every machine and build mode. The compiler also proves its
own generated obligations — every one-hot mux selector (from `unique if` /
`match`) is checked for overlapping arms, and a violated selector is
reported even when its counterexample may depend on register state, since
the construct is the user's own exclusivity claim. (Bitwidth consistency is
enforced by a separate static analysis of the compiler, not by the prover.)

### Counterexamples are simulation artifacts

A formal refutation is only useful if it can be debugged with familiar tools.
When a check fails under a working directory, the tool writes a
self-contained Pyrope testbench that instantiates the design (both designs,
for equivalence), drives the exact per-cycle counterexample stimulus including
the reset prologue, and replays it through the simulator to produce a single
VCD waveform whose traces show precisely where behavior diverges. The
testbench is an ordinary editable source file: fix the design and re-run it.

The witness also localizes: it names the first register whose state diverges —
the root the failing output merely inherits — and maps it back to the source
line that declared it, both in the verdict and as a comment in the generated
testbench. Alongside the testbench the tool writes a machine-readable witness
file (the full driven trace plus that root-cut record) for CI and triage
tooling, its input sequence guaranteed identical to the one the testbench
drives.

### Incremental re-verification

With a persistent working directory, verification is incremental across
invocations:

* Unchanged modules settle from a verdict cache with no solver call at all.
* Structurally identical module pairs are recognized and skipped without
  solving, independent of the cache.
* Work that previously ended UNKNOWN at a given budget is not re-ground on an
  unchanged design — it is skipped and reported inconclusive again until the
  design, options, budget, or prover changes, or a retry is forced.
* The cache remembers what worked — the winning proof strategy, the case-split
  choice, validated register pairings — and replays it first on the next run.
  These hints survive design edits and can never make a verdict wrong: a
  replayed pairing may lift an UNKNOWN to PROVEN and deletes itself when
  stale, nothing more.

Most of this machinery serves equivalence checking today; property
verification currently reuses the per-obligation verdict cache, with hint
replay and the UNKNOWN ledger pending on that front.

### Options

The equivalence and property-verification fronts share one option namespace,
`formal.*`, with the legacy `lec.*` spellings accepted interchangeably (the
table shows each knob in its customary spelling); the compile-time tier has
its own small knob set under `compile.formal.*`. A mistyped flag is a hard
error, never a silent no-op. The load-bearing knobs:

| Knob                    | Meaning                                                    |
| ----------------------- | ---------------------------------------------------------- |
| `formal.engine`         | `auto` (default: race complementary strategies), `bmc`; `ind` selects the inductive miter (equivalence only) |
| `formal.bound`          | BMC / induction depth (default 6)                          |
| `formal.timeout`        | soft total budget for **solver** (BMC/cvc5) time across the equivalence command — a target, not a hard wall-clock deadline; semdiff and encoding do not draw from it. A lone or compile-tier query treats it as its per-query cap; hard problems degrade to UNKNOWN |
| `formal.budget_mode`    | `wall` (spend `formal.timeout` as a soft solver-time total, default) or `rlimit` (no wall-clock budget — the deterministic CI path) |
| `formal.minetimeout`    | a **separate** budget for the diagnosis/mining phase (which also iterates the solver), so it never steals from `formal.timeout`; 0 = off |
| `formal.rlimit`         | deterministic solver budget for reproducible CI verdicts   |
| `formal.phase` / `formal.reset` | reset regime selection and explicit reset naming   |
| `formal.jobs`           | bound on concurrent solver processes (default 4)           |
| `formal.partitions` / `formal.split` | parallel input case-splitting              |
| `formal.strict`         | make UNKNOWN a hard failure                                |
| `lec.match`             | explicit register correspondences                          |
| `lec.state_pairing`     | automatic speculative register pairing (default on)        |
| `lec.cache` / `lec.retry` | verdict cache control under a working directory          |

### Structural diff as a standalone tool

The structural matcher is also a user-facing command: `lhd pass semdiff`
compares two compiled designs and stamps corresponding nodes with a shared
match id, so "what actually changed" is directly greppable and viewable —
matched regions collapse away and only genuinely differing logic remains. A
hierarchical mode sweeps all module pairs and reports state-correspondence
statistics, including exactly which registers could not be paired and why.

### Exporting to theorem provers

As an additional emission target of the standard compile, a design can be
exported as an executable model for the Isabelle or Lean theorem provers:
typed input/output/state records, a next-state and output function, and a
step function modeling one clock edge, plus a data-level certificate of the
design for machine-checked well-formedness proofs. This is a research-grade
translation-validation flow (see the developer section) rather than a routine
signoff tool, but it is exercised on real cores and has repeatedly caught
compiler bugs.

### Not implemented yet

!!! WARNING "TBD"
    The following are planned or under design, not usable today. Current
    plans live in the LiveHD repository's `todo/` hub.

* **Invariant mining.** The tool learning helper facts from its own solver
  work and emitting them as ready-to-paste `formal` blocks with provenance,
  so a stuck proof teaches the user (and the next run) how to go through.
* **The full three-form assume contract.** Both unchecked spellings already
  work inside formal blocks — the formal-only form is consumed with a
  per-use warning and disclosed in the verdict, and the synthesis-only form
  is parsed and correctly invisible to the provers. Pending are the uniform
  inline language-level contract and synthesis actually consuming the
  synthesis-only facts.
* **Temporal properties.** The SVA-style temporal library documented on the
  Pyrope side ([extended verification](../pyrope/09-verification.md)) does
  not lower to proofs yet; only single-cycle invariant properties are proven.
* **In-language `lec()`.** Calling equivalence checking from Pyrope source is
  documented as TBD in the [Pyrope chapter](../pyrope/05-assert.md#lec);
  the implemented form is the `lhd formal lec` command.
* **Alternative solver backends and IC3.** The `bitwuzla` solver value and
  the `ic3` engine value are accepted but have nothing behind them; the
  trust-path backend is cvc5, and the working engines are BMC, induction,
  and their portfolio. (A yosys-based cross-check backend exists for
  bring-up and gate-level netlists, never as a production verdict source.)
* **Transaction-level ("fluid") equivalence.** Proving designs equivalent
  across latency changes (retiming, elastic buffering) by comparing accepted
  transaction streams instead of cycle-accurate outputs — an early research
  direction, not started.

## Developer's point of view

### One relational core, several consumers

Internally the engine is framed not as an equivalence checker but as a
relational query engine over compiled designs: the primitive question is
"what is the relation between these cones of logic?". Equivalence checking,
property verification, and the compile-time tier are thin consumers of one
core (in `pass/lec`) that owns encoding, sequential reasoning, parallel
orchestration, and caching. This unification is deliberate policy: every
soundness rule is implemented once, and the compile-time tier's thorough
mode is just a restricted option profile of that core. (Its default cheap
mode keeps a dedicated single-frame prover — the one deliberate exception.)

### Word-level encoding, validated by construction

Designs encode directly into a word-level SMT theory (quantifier-free
bit-vectors plus arrays) discharged by an in-process solver — no intermediate
model checker, no bit-blasted netlist format. A combinational equivalence
proof is a classic miter: assert that some output differs and ask for
satisfiability; UNSAT is a proof, SAT is a witness.

The encoder is deliberately structured as a sibling of the Verilog code
generator — the same traversal, the same per-operator semantics — which
enables the strongest available validation: emit both the SMT model and the
Verilog from the same design and cross-check them with an independent
external checker. An encoder bug is thereby caught before it can mask a real
design difference; a cross-check disagreement is treated as an internal error,
never shipped as a verdict.

Memories map onto the theory of arrays: corresponding memories collapse to a
shared array symbol, reads are selects, writes are stores in port order, and
synchronous read ports become registered state. Don't-care semantics follow
industry practice: unknown bits in the reference design propagate as a
parallel bit-plane and are excluded from comparison, so any implementation of
a specification don't-care is accepted.

### Two sequential engines and a trust policy

Sequential equivalence uses two complementary engines whose failure modes are
opposite, and a policy that only trusts each engine where it is strong:

* **Induction with cut state** cuts every register into a free symbolic
  variable, assumes corresponding states equal, and proves next states and
  outputs agree. Its proofs are unbounded and definitive; its refutations may
  rest on unreachable states, so they are only hints.
* **Bounded model checking from reset** unrolls each design's own transition
  function from the initial state. Its refutations are real, replayable bugs;
  its proofs are only as deep as the bound.

The default mode races both in parallel and takes the first trustworthy
answer: inductive PROVEN and BMC REFUTED are final, an inductive refutation
never fails a build, and a bounded pass is reported as exactly that. When
both designs are stateless the induction miter *is* the combinational miter,
so the race is skipped entirely. Property verification applies the same
asymmetry per obligation.

All parallelism is process-based — solver instances are raced as forked
children — because it yields hard-kill cancellation for free and avoids
relying on unverified solver thread-safety. One global pool bounds total
concurrent solvers no matter how hierarchy, racing, and case-splits nest.

### Hierarchy: prove the leaves, abstract them away

Hierarchical equivalence walks the module-definition DAG bottom-up as a
parallel task graph: all ready leaves solve concurrently, and a parent
unlocks when its children settle. A proven child is then *collapsed* in its
parent's proof — a stateless child becomes an uninterpreted function shared
by both sides and all instances (congruence pairs interchangeable instances
for free), a stateful child becomes a state-aware opaque box whose outputs
depend only on its state. Collapse is an over-approximation, so the discipline
is one-sided: a proof under collapse stands, but a refutation under collapse
is re-confirmed on the flattened problem before it may be reported — a FAIL
only ever comes from a counterexample free of abstraction. A submodule
correspondence present on only one side gates the verdict to UNKNOWN rather
than guessing.

Before any solving, a structural pre-pass settles for free every module pair
that is structurally identical (guarded by all-children-proven, so a child's
internal difference is never masked). Cross-front-end pairs rarely match
structurally; same-source rebuilds almost always do — which is what makes
warm re-verification of a large design nearly proportional to the edit.

### State correspondence in two tiers

The inductive engine needs to know which register on one side corresponds to
which on the other. Correspondence is tiered by confidence:

* **Tier 1 — certain.** Names are canonicalized (front-end decoration and SSA
  suffixes stripped) so different toolchains' spellings of the same register
  converge; explicit user pairs layer on top. Memories are never paired by
  name at all — shape and occurrence order are the key — because renamed
  memories are common and nominal aliasing is a soundness trap.
* **Tier 2 — speculative.** Remaining unmatched registers are paired by the
  structural-signature analysis of the semantic diff (below) and injected as
  *uncertain* hypotheses under a strict discipline: an unbounded inductive
  proof under uncertain pairs is self-certifying (the pairing hypothesis is
  part of what was proven, given the enforced equal-reset-value
  precondition) and is accepted with disclosure; a refutation under pairs is
  never final — all pairs are dropped and the problem re-solved once, and
  only a pair-free refutation becomes a FAIL; a merely bounded pass under
  pairs is suppressed to UNKNOWN, since a wrong pairing could manufacture
  bounded agreement through the shared initial state.

The net effect is that speculation can move a verdict only between UNKNOWN
and PROVEN — never to a wrong answer. Pairings validated by a passing proof
persist (keyed by module name, so they survive edits), are re-validated on
every replay, and self-delete when stale.

### The structural diff

The semantic-diff engine (`pass/semdiff`) is an anchored, meet-in-the-middle
structural matcher: forward signatures grow from named inputs and constants,
backward signatures grow from named outputs, and nodes whose signatures agree
on both sides join a shared match class. The forward direction is
authoritative — once a node's input cone has no counterpart it is genuinely
different, and the backward pass may not rescue it. Commutative operands are
normalized only within one operand class of an operator (an adder's added and
subtracted operands never mix), and operator width stays in every key.

State cells are cut points, matched by the tiered scheme above; the tier-2
pass is a deliberately simplified variant of a companion signature-based
alignment scheme (a paper currently under submission), kept *full-match
only*: ambiguous candidate buckets are never force-picked, trading recall
for precision, because the consumer re-verifies every pair anyway. Signature
items are annotated with anchor distance so linear chains of identical
elements (shift registers) still resolve. Measured on an 18k-register
open-source core, name-based pairing is exact when names survive; with
names entirely destroyed the structural tier still recovers a quarter of
the pairs, and in a controlled experiment destroying 10% of the names it
recovers about half of them — with zero wrong pairs in every measured run,
precision being the property that matters.

!!! NOTE "TBD"
    The planned second algorithm matches the *unmatched gaps* n:m by proving
    per-gap boundary equivalence with small bounded miters, so equivalence
    checking can assume matched regions equal and hand the solver only the
    genuinely differing logic — shrinking the miter to the size of the edit.

### Divide and conquer without weakening verdicts

Two orthogonal accelerators split hard problems, both with sound fallbacks:

* **Per-cut decomposition** splits the output-difference disjunction into one
  small UNSAT query per output or state cut — a disjunction is unsatisfiable
  iff every disjunct is — so easy cuts discharge instantly and only the hard
  cone remains, with automatic fallback to the monolithic solve.
* **Input case-splitting** picks a small control input (scored by a
  linear-time sweep of the forward cone: how much wide mux/shift logic the
  candidate feeds), pins it to each constant value, and proves the disjoint
  cubes in parallel. Every satisfiable cube is a genuine counterexample; all
  cubes UNSAT is a proof; anything else falls back to the monolithic solve.
  Pinning a selector lets the solver fold control-dependent wide operators,
  which is why a proof that ran for tens of seconds can drop under a second.

### The property engine

Property verification restructures the same substrate around one persistent
incremental solver. Each obligation is checked cycle by cycle as a retractable
assumption query, and every proven fact is immediately re-asserted as a
constraint that prunes the search for everything checked after it — under
adversarially reviewed soundness rules: a fact proven to cycle k may be
assumed only at cycles ≤ k and only as the exact proven term; sibling
properties may be assumed only at strictly earlier cycles than the cycle
being checked (the circular-reasoning rule); and bounded facts are never
injected into an induction step frame, whose states may be unreachable.

After the bounded sweep, a simultaneous 1-induction pass with a
Houdini-style drop loop runs over the surviving properties: assume all
candidates, drop those that fail their step check, iterate to a fixed point —
the survivors' conjunction is inductive with the bounded run as its base
case, promoting them to unbounded verdicts. The default mode races two
whole-run strategies (deep-bound BMC first vs. shallow-bound induction
first) and merges per obligation, keeping the strongest verdict for each.

### Caching without lying

The verdict cache is engineered so that a cache hit is a theorem, not a hope:

* Equivalence verdicts are keyed by a hierarchical, Merkle-style canonical
  digest of each side — operators, widths, port-scoped connectivity,
  interface, recursively folded child digests — so a digest hit means "this
  exact proof problem", independent of process or build. A design containing
  anonymous state refuses to digest at all: soundness over coverage.
* Property-verification obligations are keyed by hashing the exact serialized
  solver encoding, so any change in encoder semantics invalidates cached
  results automatically.
* Everything verdict-relevant enters the key — engine, bounds, reset regime,
  assumption sets, certain and uncertain pairings as *distinct* segments — so
  a conditional proof can never replay as an unconditional one. Pure
  effort/strategy knobs deliberately stay out of the key.
* The whole verdict store is salted with a build-time content hash of the
  prover's own sources and solver version: any prover change silently
  invalidates every cached verdict with no human in the loop.
* Only proofs are cached today — a refutation is cheap to reconfirm, and
  caching it soundly would require re-validating its witness — and UNKNOWN
  is never cached as a verdict. A separate ledger records "already came back
  UNKNOWN at this budget" purely to skip re-grinding unchanged hopeless work.

Distinct from verdicts, *hints* are keyed by canonical module name so they
survive edits. Strategy hints — the winning engine, the case-split selector —
only reorder what is tried first and need no soundness machinery at all.
Validated register pairings are stronger medicine: they alter the proof
obligations, enter the verdict-cache key as their own segment, and are
re-validated on every replay under the full speculative discipline — which
is why they too survive prover changes: a stale pairing can waste time,
never mislead. Hints versus verdicts is the load-bearing soundness
distinction of the whole persistence layer.

### The compile tier as a formal consumer

The compile-time pass runs one of two asymmetric-soundness profiles, both
in-process, unraced, and budgeted by deterministic solver resources rather
than wall-clock. The default profile is single-frame induction: each
property's fan-in cone is encoded on demand with every register cut to a
free symbol, so a proof — unsatisfiability even over arbitrary state — is
sound for all reachable states, while a refutation is trusted only when the
cone crossed no state at all; a stateful counterexample may be unreachable
and defers. The stronger profile routes properties through the shared engine
as a tiny bounded check from reset plus one induction step, resolving the
single-frame dilemma by requiring the strong form on each side: only an
unbounded induction proof elides a runtime check, and only a reset-pinned,
reachable counterexample at the committed design top fails the build. In
both profiles, assumes are proven before they may be used as hypotheses (no
circular self-support), and refuted or undecided properties are never
exploited by optimization.

!!! NOTE "TBD"
    A planned extension hands formally established impossibilities — proven
    asserts and assumes, plus explicit user-owned synthesis-only don't-care
    facts — to logic synthesis as an external don't-care network, letting
    resynthesis exploit input combinations proven never to occur.

### Translation validation with theorem provers

The theorem-prover track addresses a different question: not "is this design
correct?" but "did the compiler translate it faithfully?" — per design, as
translation validation, rather than verifying the compiler once and for all.
Each compiled design is exported twice: as a fast executable model in the
prover (fixed-width words, one function per clock step) and as a *certificate*
— the design graph reified as plain data. Correctness decomposes into a chain
of links designed to be machine-checked (generated model = evaluated
certificate = mathematical graph semantics): the certificate-to-semantics
link is a generic, once-proven theorem, while the per-design
model-to-certificate bridge theorems are still being brought up. The
remaining link — source RTL = compiled graph — is discharged by bounded
equivalence checking: the in-house SMT engine, or an independent external
checker for the largest memory-heavy designs. The prover only ever trusts a
small hand-written semantics library of total, width-explicit operator
primitives, not the compiler.

Certificate well-formedness proofs are made scalable by chunking the
certificate into fixed-size pieces with local lemmas composed by a generic
combination rule, instead of one monolithic whole-graph proof (implemented
on the Isabelle target, still being ported to Lean). Memories stay
function-valued state in the final model — scalarizing realistic SRAMs into
per-bit registers is intractable in a prover and allowed only as a
diagnostic mode.

The pipeline ordering encodes a hard-won epistemological lesson: the fast
model and the certificate come from the same emitter, so a shared emission
bug leaves every internal theorem provable while the model is wrong. The
independent RTL-versus-graph equivalence gate therefore runs *first*,
mandatorily; it has caught real compiler bugs (alias ordering, undriven
nets, X-reintroduction) before any prover time was spent. The flow has been
exercised at scale — a full open-source cache subsystem proven
bounded-equivalent to its original RTL, and complete RISC-V cores
type-checking as prover models — and remains a research track: strict by
construction
(anything it cannot model faithfully aborts export), not yet a push-button
signoff.
