# Verification

Verification covers the language constructs and special support to ease design verification.



## Assertions

Assertions are considered debug statements. This means that they can not
have side effects on non-debug statements.

Pyrope supports a syntax close to Verilog for assertions. The language is
designed to have 3 levels of assertion checking: compilation time,
simulation runtime, and formal verification time.

There are 3 verification statements, and the difference between them is **who
discharges the obligation**:

* `cassert(expr [, "msg"])` — an **elaboration** check. The upass must fold it
  to true at compile time; if it cannot, that is a compile error. `cassert`
  never reaches the formal engine, never becomes a runtime check, and never
  appears in the netlist. Use it for facts about comptime values (generic
  parameters, widths, table contents).

* `assert(expr [, "msg"])` — a **design** obligation. `pass.formal` tries to
  prove it at compile time; what it cannot prove is kept as a runtime check for
  simulation. So an `assert` may be discharged formally *or* at run time, and
  the compiler chooses.

* `assume(expr [, "msg"])` — a constraint the tool may rely on, and therefore
  one it must first justify. Each `assume` is proven **independently** (no
  other assume is used as a hypothesis, so assumes can never prove each other),
  and only a *proven* assume becomes a hypothesis for the surrounding
  `assert`s. A refuted `assume` is a build error — it can never silently prune
  a real counterexample.

The distinction that matters in practice: `cassert` is "the compiler must know
this now", `assert` is "this must be true of the hardware".

Use the parenthesized form: `assert(expr)`, `cassert(expr)`, `assume(expr)`.
A trailing message belongs to the statement: `assert(expr, "message")`.

```pyrope
comptime const W = 8
cassert(W % 2 == 0)    // elaboration: folds to true, or the build fails

a = 3
assert(a == 3)         // design obligation: proven, else a runtime check

comb max_not_zero(a, b) -> (result) {
  assume(a > 0)        // proven first; only then used as a hypothesis
  result = if a > b { a } else { b }
}
```

### Where an `assume` can be discharged

An `assume` over a lambda's **free inputs** cannot be proven in isolation —
inputs are unconstrained, so some input value always falsifies it. What happens
next depends on where the lambda sits:

* At the **top** module, the inputs are the design boundary, so there is
  nothing left to constrain them: the assume is reported refuted and the build
  fails (`assume-refuted`). Pass `--set compile.formal.on_refute=warn` to
  downgrade it, or state the constraint in a `formal` block instead, where it
  is an environment constraint rather than an obligation.
* In an **instantiated** module, the parent's drivers are what make it true, so
  the check is *deferred* with a warning and kept as a runtime check.

!!! WARNING
    A guarded verification statement does **not** inherit its guard today —
    `if cond { assert(x) }` is lowered as an unconditional `assert(x)`. Write
    the guard into the condition instead:

    ```pyrope
    assert(cond implies x == 3, "only claimed when cond holds")
    ```

    The `if`-wrapped form is a known compiler bug, not a style choice.

The recommendation is to write as many `assert` and `assume` as possible.
`assume` is the stronger statement: it tells the tool a case cannot happen, and
a proven one is available to the optimizer as a don't-care.

## Compile-time prints

`cputs(msg)` is the compile-time analog of `puts`. The compiler evaluates the
single string argument during elaboration and emits it on the compiler's
stderr, so the message is visible while the design is being built rather than
during simulation. Like every `puts`/`assert` message, each `cputs` output is
prefixed with its source origin — `<file>:<line>:cputs:` — on its own line so
it can be grepped out of the surrounding compiler log and traced back to the
statement that produced it:

```bash
<file>:<line>:cputs:<message>
```

Rules:

* Exactly one argument is accepted.
* The argument must resolve to a comptime-known string. String interpolation
  (`"a is {a}"`) works because the producer lowers it to `format(...)`, which
  the upass folds at compile time when its operands are comptime-known.
* Any deviation — extra arguments, non-string operand, or an operand that
  cannot be folded to a known value at compile time — is a compile error, not
  a runtime print emitted at simulation.

```pyrope
a = 7
cputs("a is {a}")    // prints: foo.prp:2:cputs:a is 7
cputs("plain")       // prints: foo.prp:3:cputs:plain

b = some_runtime_signal
cputs("b is {b}")    // compile error: operand not comptime-known
```

Use `cputs` for elaboration-time diagnostics (which branch of a `comptime
if` was taken, which generic parameter was selected, etc.); use `puts` for
messages that should appear in the simulator at run time.

!!! NOTE
    `cputs` currently resolves only at **file top-level scope**. Inside a
    lambda body — including inside a `comptime if` within one — it is an
    undefined call. Until that is lifted, elaboration tracing inside a lambda
    is not available.

## Illegal operations

The compiler never aborts on bad user input — every illegal operation is a
clean compile error. An illegal or undefined low-level operation yields `nil`
(e.g. division/modulo by zero, or arithmetic on a `nil`/uninitialized operand),
and a `nil` produced by an arithmetic operation, or a `nil` used as an `if` /
`while` condition, is reported as a compile error rather than silently folding
to a degenerate value.

## LEC

Logical equivalence checking is a tool command, not a language construct:

```bash
lhd lec --ref pyrope:gold.prp --impl pyrope:impl.prp --top mod_name
```

`--ref` is the gold model and `--impl` the implementation; the gold model's
unknown output bits check against any value for the equivalent implementation
bit. `lec` handles **sequential** designs as well as combinational ones — a
flop-cut inductive miter plus BMC, so registers and reset are modelled.

`lhd lec` takes no `formal` block sidecar: a block is an independent test (see
[Formal blocks](#formal-blocks)) while `lec` has a single obligation, so a
block's assumes could only ever apply globally. Prove blocks with
`lhd formal verify`; an environment constraint meant for `lec` belongs in the
design itself.


!!! NOTE
    The recommendation is to use `assume` and `assert` frequently, including
    to check preconditions and postconditions of methods. The 1949
    Turing quote of how to write assertions and programs is still valid "the
    programmer should make a number of definite assertions which can be checked
    individually, and from which the correctness of the whole program easily
    follows."

!!! NOTE "Not implemented"
    An in-language `lec(gold, impl)` call and a `lec_valid` variant that
    compares only `.[valid]` outputs are both TBD; neither exists today. Use
    the `lhd lec` command above. See [TBD](15-tbd.md).

## Coverage

The goal of an assertion is to be true all the time; the goal of a coverage
point is to be true at least once during testing.

!!! NOTE "Not implemented"
    `cover` and `covercase` are TBD — neither exists today, in a design body,
    a `test`, or a `formal` block. The intended meaning is recorded in
    [TBD](15-tbd.md): `cover(cond [, msg])` must be true at least once during
    verification, and `covercase(grp, cond [, msg])` groups several covers so
    that one arm of the group must be true each time.

## Reset and verification

In hardware it is common to have an undefined state during the reset period.
An `assert` in a design body is checked in the run window after reset; an
`assert_always` is checked at every cycle, reset included. That pair is the
whole reset story — write `assert_always` when the claim must survive reset.

!!! NOTE "Not implemented"
    Valid-based gating (skipping a check while any operand is `.[valid]`-false)
    does not exist: only the condition itself is wired into the obligation.
    Neither does the `always_` statement family (`always_assert`,
    `always_cassert`, `always_assume`, `always_cover`, `always_covercase`) —
    the implemented spelling is `assert_always`.

## Random

!!! NOTE "Not implemented"
    `.[rand]` (simulation-time) and `.[crand]` (elaboration-time) random value
    generation are TBD. Both are rejected in `test` blocks and design bodies
    today; they survive only where they constant-fold. The intended semantics —
    pick within the type's min/max, pick an entry when applied to a tuple, and
    a compile error for string/range/lambda types — are recorded in
    [TBD](15-tbd.md).

## Test

A `test` is a debug-only block named by a dotted identifier (a selector path),
with optional runtime parameters and no return: `test name.path [(params)] {
stmts+ }`. See [Testing](05b-statements.md#testing-test) for naming, parameters,
and the `tick` cycle loop.

=== "Many parallel tests"
    ```pyrope
    comb add(a, b) -> (r) { r = a + b }

    for a in 0..=20 {
      for b in 0..=20 {
        test add.sweep {
           cassert(a + b == add(a=a, b=b))
        }
      }
    }
    ```

=== "Single large test"
    ```pyrope
    comb add(a, b) -> (r) { r = a + b }

    test add.batch {
      for a in 0..=20 {
        for b in 0..=20 {
           cassert(a + b == add(a=a, b=b))
        }
      }
    }
    ```


To drive a stateful design across cycles, call it inside a `tick N` loop: each
iteration is one cycle, the call drives that cycle's inputs and returns that
cycle's outputs, and a `mut` declared before the loop captures the result for an
end-of-simulation `assert`. This is the form the `lhd sim` runner executes (see
[Running cycles](05b-statements.md#running-cycles-tick)):

```pyrope
mod counter(enable:bool) -> (value:u8@[0]) {
  reg count:u8 = 0

  value = count                     // combinational read of count.q -> @[0]

  if enable { wrap count += 1 }
}

test counter.held_high {
  mut v_final = nil
  tick 20 {                         // 20 cycles, one clock per iteration
    const v = counter(enable=true)  // call the DUT each cycle, capture its output
    v_final = v
  }
  assert(v_final == 20)
}
```

The `test` code block also accepts the keyword `step` that advances one clock
cycle, and the test continues from that given point (the lower-level,
manual-stepping style of the concurrent-thread testbench layer; not yet run by
`lhd sim`). This is useful for when a lambda is instantiated and we want to
check/update the inputs/outputs.

```pyrope
// mod: output 'value' is combinational (reads register directly)
mod counter_mod(update:bool) -> (value:u8@[0]) {
  reg count:u8 = 0

  value = count              // combinational output (no extra flop) -> @[0]

  if update { wrap count = count + 1 }
}

// pipe: 'value' lands 1 cycle after the inputs (no comb input-to-output path)
// Same logic, but output is delayed by 1 cycle compared to mod version
pipe[1] counter_pipe(update:bool) -> (value:u8) {
  reg count:u8 = 0

  value = count              // reads state q; the appended output flop lands it 1 cycle later

  if update { wrap count = count + 1 }
}

test counter.cycles {

  mut inp = true
  wire inp_w = inp                   // single-driver net feeding the call
  mut x = counter_mod(inp_w)

  assert(x == 0) // x.value == 0
  assert(inp == true)

  step

  assert(x == 1)
  inp = false

  step

  assert(x == 1)
  assert(inp == false)
  inp = true

  assert(inp == true)
  assert(x == 1)

  step

  assert(inp == true)
  assert(x == 2)
}
```

During `test` simulation, all the assertions are checked but the test does not
stop with a failure until the end.

!!! NOTE "Not implemented"
    `assert.[failed]` — reading or clearing an accumulated failure flag so a
    test can assert that an assertion *did* fail — is TBD. There is no
    `assert` object to read today.

!!! WARNING
    An `assert` written in a **design body** is not executed by `lhd sim`
    at all: the simulation code generator skips every property node, so a
    violated design assert reports `PASS`. Only assertions written inside the
    `test` block itself are checked at simulation time. Design-body asserts are
    checked by `pass.formal` at compile time and emitted into the Verilog
    netlist, but the simulation runtime fallback is still pending.

## Formal blocks

A `formal` block is a declarative verification overlay, named by a dotted
identifier exactly like a `test`: `formal name.path { stmts+ }`. It differs
from a `test` in two ways: every statement is a claim that must hold at
**every cycle** (there is no `step`/`tick` — nothing is procedural), and it
never lowers to hardware or simulation — the design compile skips it entirely,
and only `lhd formal verify` consumes it. This lets a design
and its properties live in one file, or the properties in a separate *sidecar*
file that is versioned and reviewed like source code.

**Blocks are independent tests.** Exactly like `test` blocks, they are not run
together: each block's `assume`s constrain only that block's own obligations, so
two blocks may carry mutually exclusive assumes and both still prove. A block
bound to a submodule with N instances is still *one* block with one assume set
(all N instances in force together). `assume`s written in the design itself are
the other tier — always in force, for every block. A block whose own assume set
is contradictory is named and fails the run; its proofs would be vacuous.

The body binds the design with the test-block import/alias style, then states
properties over dotted signal paths: top input/output ports, registers reached
through instance names, and — for a block bound to a submodule — the target
instance's own input/output ports (the block is checked once per instance,
reported `[block@instance]`):

* `assert(expr [, "msg"])` — must hold at every checked cycle (after reset).
* `assert_always(expr [, "msg"])` — must hold at every cycle, reset included.
* `assume(expr [, "msg"])` — what it means depends on what `expr` touches.
  Over **primary inputs only**, it is an environment constraint: it prunes the
  traces the tool explores and is *disclosed* ("under N input assume(s)" — this
  block's verdicts become conditional on it). Touching **registers or outputs**,
  it is a *proof obligation* (prove-then-use): the tool proves it before using
  it, a proven cycle constrains the remaining properties, and a **false** claim
  is REFUTED — it can never silently fake a proof. A contradictory assume set is
  reported and fails the run, never silently vacuous.
* `assume_nocheck_formal(expr)` — a free constraint by explicit user fiat,
  even over state: accepted with a per-use warning and a distinct
  "under N UNCHECKED assume(s)" disclosure. `assume_nocheck_synth(expr)` is
  invisible to verification (a synthesis-only don't-care).

```pyrope
// cnt.prp — the design
mod cnt(enable:bool) -> (value:u8@[0]) {
  reg count:u8 = 0
  reg par:bool = false
  value = count
  if enable {
    wrap count += 1
    par = not par
  }
}
```

```pyrope
// cnt.verify.prp — a sidecar of formal blocks (never becomes hardware)
const top = import("cnt.cnt")

formal cnt.parity {
  mut acc = top
  assert(u1(acc.par) == acc.count#[0], "parity tracks bit0")
}

formal cnt.bounded {
  mut acc = top
  assume(acc.enable == 0)            // environment: the counter never runs
  assert(acc.count != 5, "frozen")   // provable under the assume
}
```

```bash
lhd formal verify cnt.prp cnt.verify.prp --top cnt --set formal.bound=10 --workdir w
#   assert at cnt.verify.prp:5 "'parity tracks bit0'" [cnt.parity]: PROVEN (inductive — every cycle of every bound)
#   assume at cnt.verify.prp:10 [cnt.bounded]: in force (input environment constraint; verdicts are conditional on it)
#   assert at cnt.verify.prp:11 "'frozen'" [cnt.bounded]: PROVEN (inductive — every cycle of every bound)
lhd formal verify cnt.prp cnt.verify.prp --top cnt --formal 'cnt.parity'  # run one block
jq '.obligations' w/formal_report.json   # the same table machine-readable, every PASSED
                                         # obligation included; a REFUTED run adds
                                         # formalfail.prp/.json + a replay VCD under w/
```

The dotted block name is the enable/disable handle (`--formal <glob>` selects
blocks); presence in the file list is the activation — there is no
registration step. Property expressions are ordinary Pyrope (casts, bit
selects, operators): the tool compiles each block through the normal compiler,
so their semantics can never diverge from the language. The same sidecar
format is the target for tool-mined invariants: proven helper facts are
emitted as `formal` blocks with provenance comments, re-checked on every run,
and speed up the remaining proofs.

## Hierarchy access from verification code

A verification statement reads design signals the same way any other Pyrope
code does: through the instance hierarchy, by name. A `formal` block binds the
design with an alias and then uses dotted paths (`acc.core0.count`); a `test`
block reads and drives the instance it names — by bare dotted access, or through
an explicit [`sigref`/`regref`](05b-statements.md#test-only-statements) bound
outside the `tick` loop.

Both spellings of a ref work in a `test` block: the dotted
`sigref(acc.core0.fifo0.full)` names exactly one cell (a path that does not
resolve is a setup error), and the string form `sigref("fifo0/full")` reaches a
`"unit/field"` by name. Note that `full` there is an *output*, not a register:
`sigref` binds any storage cell — register, memory word, input or output — and
`regref` is the same binding made writable.

!!! NOTE "Not implemented"
    The **multi-match** string path — one `regref` resolving to zero or many
    cells across the elaborated hierarchy, the synthesizable form described in
    [Register reference](07-typesystem.md#register-reference) — and the
    `bind`-style *monitor* pattern built on it are TBD, and are not needed for
    `assert`/`assume` today. See [TBD](15-tbd.md).