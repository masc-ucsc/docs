# Verification

Verification covers the language constructs and special support to ease design verification.



## Assertions

Assertions are considered debug statements. This means that they can not
have side effects on non-debug statements.

Pyrope supports a syntax close to Verilog for assertions. The language is
designed to have 3 levels of assertion checking: compilation time,
simulation runtime, and formal verification time.

There are 5 main verification statements:

* `assert` and `cassert` are used to specify conditions that should hold true.
  `cassert` is required to hold true at compile time and `assert` can be
  checked either at compile or runtime if too slow to check. If the condition
  doesn't hold, an error is raised.

* `optimize` is exactly like `assert`, but it also allows the tool to simplify
  code based on the given conditions. This can lead to more efficient code
  generation. While unproven `assert` can be enabled/disabled during
  simulation, `optimize` can not be disabled because it can lead to incorrect
  simulation state.

* `requires` is statement that can be placed in lambdas. The clause specifies
  pre conditions to be true when the lambda is called. `requires` allows for code
  optimizations like `optimize` statement.

* `ensures` is a statement similar to `requires` but the clause specifies a
  post condition. `ensures` allows code optimizations like `optimize` statement.

Use the parenthesized form for verification conditions: `assert(expr)`,
`cassert(expr)`, `optimize(expr)`, `requires(expr)`, `ensures(expr)`, and
`cover(expr)`. This is the canonical style for new code and examples because it
keeps the checked expression visually grouped and avoids newline/precedence
ambiguity. A trailing message or gate still belongs to the statement:
`assert(expr, "message") when enable`.


Hardware setups always have an extensive CI/verification setup. This means that
run-time assertion failures are OK, better compile time to reduce design time,
but OK at simulation time. This means that in things like type check, if it may
be OK but not possible to prove, the compiler can decide to insert an assert
instead of forcing a code structure change. To enforce that an assertion is
checked only at compile time a `cassert` must be used. `assert`, `requires`,
`ensures` can be checked at runtime if not possible to check at compile time.


```pyrope
a = 3
assert(a == 3)         // checked at runtime (or compile time)
cassert(a == 3)        // checked at compile time

optimize(b > 3)        // may optimize and perform a runtime check

comb max_not_zero(a, b) -> (result) {
  requires(a > 0)
  requires(b > 0)
  ensures(result == a or result == b)

  result = if a > b { a } else { b }
}
```

A whole statement is conditionally executed using the `when`/`unless` gate expression.
This is useful to gate verification statements (`assert`, `optimize`)
that can have spurious error messages under some conditions.


```pyrope
a = 0
if cond {
  a = 3
}
assert(cond implies a == 3, "the branch was taken, so it must be 3??")
assert(a == 3, "the same error") when   cond
assert(a == 0, "the same error") unless cond
```


The recommendation is to write as many `assert` and `optimize` as possible. If
something can not happen, writing the `optimize` has the advantage of allowing
the synthesis tool to generate more efficient code.


The `optimize` will allow code optimizations, the `cassert` should also result
in code optimizations. The reason why `assert` does not trigger optimizations
is because they can be enabled/disabled at simulation time.


In a way, most type checks have equivalent `cassert` checks.

## Compile-time prints

`cputs(msg)` is the compile-time analog of `puts`. The compiler evaluates the
single string argument during elaboration and emits it on the compiler's
stderr, so the message is visible while the design is being built rather than
during simulation. Each `cputs` output is prefixed with `prp:` on its own line
so it can be grepped out of the surrounding compiler log:

```bash
prp:<message>
```

Rules:

* Exactly one argument is accepted.
* The argument must resolve to a comptime-known string. String interpolation
  (`"a is {a}"`) works because the producer lowers it to `format(...)`, which
  the upass folds at compile time when its operands are comptime-known.
* Any deviation — extra arguments, non-string operand, or an operand that
  cannot be folded to a known value at compile time — is a compile error, not
  a deferred runtime print.

```pyrope
a = 7
cputs("a is {a}")    // prints: prp:a is 7
cputs("plain")       // prints: prp:plain

b = some_runtime_signal
cputs("b is {b}")    // compile error: operand not comptime-known
```

Use `cputs` for elaboration-time diagnostics (which branch of a `comptime
if` was taken, which generic parameter was selected, etc.); use `puts` for
messages that should appear in the simulator at run time.

## LEC

The `lec` command is a formal verification step that checks that all the
arguments are logically equivalent. `lec` only works for combinational logic,
so does not need to worry about state or reset signals. The first argument is
the gold model, the rest are implementation. This matters because the gold
model unknown output bit checks against any value for the equivalent
implementation bit.


!!! NOTE
    The recommendation is to use `optimize` and `assert` frequently, but
    clearly to check preconditions and postconditions of methods. The 1949
    Turing quote of how to write assertions and programs is still valid "the
    programmer should make a number of definite assertions which can be checked
    individually, and from which the correctness of the whole program easily
    follows."

```pyrope
comb fun1(a, b) -> (r) { r = a | b }
comb fun2(a, b) -> (r) { r = ~(~a | ~b) }
lec(fun1, fun2)
```

In addition, there is the `lec_valid` command. It is similar to `lec` but it
checks the optional or valid (`.[valid]`) from the output. It can take several
cycles to show the same result.

```pyrope
mod mul2(a, b) -> (reg out) {
  reg pipe1 = nil

  out = pipe1

  pipe1 = a * b
}

comb mul0(a, b) -> (out) { out = a * b }

lec_valid(mul0, mul2)
```

## Coverage

A bit connected with the assertion is coverage. The goal of an assertion is to be
true all the time. The goal of a coverage point is to be true at least once
during testing.


There are two directives `cover` and `covercase`. The names are similar to the
System Verilog `coverpoint` and `covergroup` but the meaning is not the same.

* `cover cond [, message]` the boolean expression `cond` must evaluate true
  sometime during the verification or the tool can prove that it is true at
  compile time.

* `covercase grp, cond [,message]` is very similar to cover but it has a `grp`
  group. There can be one or more covers for a given group. The extra check is
  that one of the `cond` in the cover case must be true each time.


```pyrope
// coverage case NUM group states that random should be odd or even
covercase(NUM,   random&1 , "odd number")
covercase(NUM, !(random&1), "even number")

covercase(COND1, reset, "in reset")
covercase(COND1, val>3, "bigger than 3")

assert((!reset and val>3) or reset)  // less checks than COND1

cover(a==3, "at least a is 3 once in a while")
```

The `covercase` is similar to writing the assertions, but it checks that all
the conditions happen through time or a low coverage is reported. In the
`COND1` case, the assertion does not check that sometimes reset is set, and
others the value is bigger than 3.  The assertion will succeed if reset is always
set, but the covercase will fail because the "bigger than 3" case will not be
tested.


The `cover` allows to not be true a given cycle. To allow the same in a
`covercase`, the designer can add `covercase GRP, true`. This is a true always
cover point for the indicated cover group.


## Reset, optional, and verification

In hardware is common to have an undefined state during the reset period. To
avoid unnecessary assertion failures, if any of the inputs depends on a
register directly or indirectly, the assertion is not checked when the reset is
high for the given registers. In Pyrope, the registers and memory contents
outputs are "invalid" (`.[valid]` attribute). `assert` and `optimize` will not
check when any of the signals are invalid. This is useful to avoid unnecessary
assert checks during reset or when the lambda is called with invalid data.


Adding the `always` modifier before the assert/coverage keywords guarantees
that the check is performed every cycle independent of the valid attribute.

To provide assert/optimize during reset, Pyrope provides a `always_assert`,
`always_cassert`, `always_optimize`, `always_covercase`, and
`always_cover`.

```pyrope
reg memory:[3]u33 = (1, 2, 3) // may take cycles to load this contents

assert(memory[0] == 1) // not checked during reset

always_assert(memory[1] == 2) // may fail during reset
always_assert(memory[1] == 2) unless memory.reset  // should not fail
```

## Random

Random number generation are quite useful for verification. Pyrope provides
easy interfaces to generate "compile time" (`.[crand]`) and "simulation time"
random number (`.[rand]`) generation.


```pyrope
mut x:u8 = nil

for i in 1..=99 {
  cassert(0 <= x.[crand] <= 255)
}

comb get_rand_0_255(a:u8) -> (r) {
  r = a.[rand]
}
```

Both rand and crand look at the set type max/min value and create a randon value
between them. rand picks randomly in boolean and enumerate types, but it triggers
a compile error for string, range, and lambda types.

When applied to a tuple, it randomly picks an entry from the tuple.

```pyrope
mut a = (1, 2, 3, b=4)
mut x = a.[rand]

cassert(x == 1 or x == 2 or x == 3 or x == 4)
cassert(x.b == 4) when x == 4
```

The simulation random number is considered a `.[debug]` statement, this means
that it can not have an impact on synthesis or a compile error is generated.

## Test

Pyrope has the `test [message [,args]+] ( [stmts+] }`.

=== "Many parallel tests"
    ```pyrope
    comb add(a, b) -> (r) { r = a + b }

    for a in 0..=20 {
      for b in 0..=20 {
        test "checking add({},{})", a, b {
           cassert(a + b == add(a, b))
        }
      }
    }
    ```

=== "Single large test"
    ```pyrope
    comb add(a, b) -> (r) { r = a + b }

    test "checking add" {
      for a in 0..=20 {
        for b in 0..=20 {
           cassert(a + b == add(a, b))
        }
      }
    }
    ```


The `test` code block also accepts the keyword `step` that advances one clock
cycle, and the test continues from that given point. This is useful for when a
lambda is instantiated and we want to check/update the inputs/outputs.

```pyrope
// mod: output 'value' is combinational (reads register directly)
mod counter_mod(update) -> (value) {
  reg count:u8 = 0

  value = count              // combinational output (no extra flop)

  if update { wrap count = count + 1 }
}

// pipe: 'value' lands 1 cycle after the inputs (no comb input-to-output path)
// Same logic, but output is delayed by 1 cycle compared to mod version
pipe[1] counter_pipe(update) -> (value) {
  reg count:u8 = 0

  value = count              // reads state q; the appended output flop lands it 1 cycle later

  if update { wrap count = count + 1 }
}

test "counter_mod through several cycles" {

  mut inp = true
  mut x = counter_mod(inp.[defer])   // inp contents at the end of each cycle

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
stop with a failure until the end. Sometimes it is useful to write tests to
check that assertions fail. Assertion failures will be printed but the test
will continue and fail only if the `assert.[failed]` is true. The `test` code
block also accepts to read and/or clear failed attribute.

```pyrope
test "assert should fail" {

 const n = assert.[failed]
 assert(n == false)

 assert(false) // FAILS

 assert(assert.[failed])
}
```

## Signal reference

While `regref` references registers in the instantiated hierarchy, `sigref`
generalizes this to any signal: inputs, outputs, wires, and tuple fields.
Together they provide read access into the design hierarchy for verification.

```pyrope
const r1 = regref("top/core0/counter")   // register only
const s1 = sigref("top/core0/fifo0/full") // any signal
```

The recommended mental model is:

* `import` traverses the file/directory hierarchy and copies definitions.
* `regref` traverses the instance hierarchy and references registers.
* `sigref` traverses the instance hierarchy and references any signal.

The two references have different synthesizability rules:

* `sigref` is **debug-only**: it is allowed only inside debug statements
  (`assert`, `test`, `cover`, `puts`, monitors), never in synthesizable
  code of any lambda kind. A synthesizable cross-hierarchy wire reference
  would create combinational coupling invisible to the module interfaces
  (hidden combinational loops); a register reference can not, because every
  access crosses the flop boundary.
* `regref` in a debug statement can read **any** register, `pub` or not.
  In synthesizable code, `regref` can only attach to registers declared
  `pub`, and then behaves like a local `reg` (see
  [Register reference](07-typesystem.md#register-reference)).

In debug statements both are read-only: they can not create a second writer
or affect the valid bits, resets, or scheduling of the DUT. The single
writer multiple reader semantics are preserved.

When a partial path is given (no leading instance), `sigref` matches all
instances that contain a signal with that name, returning a tuple of
references. This follows the same matching rules as `regref`.

```pyrope
const all_full = sigref("full")  // every "full" signal in the hierarchy
```

If a full path does not resolve to exactly one signal, elaboration fails.


## Monitor

Monitors provide a way to attach verification logic to an already elaborated
design without modifying the original source. The goal is similar to
SystemVerilog `bind`, but monitors in Pyrope are just `test` blocks that use
`sigref` and `regref` to observe the design hierarchy.

No new keywords are needed. The debug-only semantics come from `test`,
`assert`, and `cover` which are already debug statements. This means that
removing all monitor tests preserves the same synthesizable design.


### Observing a single instance

A `test` block can use `sigref` and `regref` with a full instance path to
check invariants on a specific instance.

```pyrope
test "fifo0 checks" {
  const push  = sigref("top/core0/fifo0/push")
  const pop   = sigref("top/core0/fifo0/pop")
  const full  = sigref("top/core0/fifo0/full")
  const empty = sigref("top/core0/fifo0/empty")

  assert(!(push and full),  "enqueue while full")
  assert(!(pop and empty),  "dequeue while empty")

  cover(push)
  cover(pop)
}
```


### Observing all instances of a lambda

When `sigref` is given a partial path, it matches across all instances. This
replaces the `bind target_lambda` pattern with the same matching rules already
used by `regref`.

```pyrope
test "all fifo checks" {
  const full  = sigref("full")
  const push  = sigref("push")

  assert(!(push and full), "enqueue while full")
}
```


### Stateful monitors

A `test` block can declare local `reg` to keep verification state across
cycles. This state belongs to the test and is not visible to the DUT.

```pyrope
test "req ack protocol" {
  const req = sigref("top/core0/req")
  const ack = sigref("top/core0/ack")
  reg pending = false

  pending = true  when req
  pending = false when ack

  assert(!ack or pending, "ack without earlier req")
}
```


### Reusable monitor lambdas

For monitors that are attached to many instances or shared across files, a
regular lambda can encapsulate the checks. The caller passes `sigref` and
`regref` values as arguments.

```pyrope
comb fifo_checks(push, pop, full, empty) {
  assert(!(push and full),  "enqueue while full")
  assert(!(pop and empty),  "dequeue while empty")
  cover(push)
  cover(pop)
}

test "fifo0 monitor" {
  fifo_checks(
    push  = sigref("top/core0/fifo0/push"),
    pop   = sigref("top/core0/fifo0/pop"),
    full  = sigref("top/core0/fifo0/full"),
    empty = sigref("top/core0/fifo0/empty"),
  )
}
```


## Timing rules

For combinational signals, `sigref` observes the same value visible at the
instance boundary in that cycle.

For registers, `sigref` and `regref` read the current `q` value. A test may
use `.[defer]` or the temporal library (`next(x, N)`, `eventually[R](x)`,
`rose[R](x)`, …) inside debug contexts using the same timing rules as
ordinary assertions.

Tests acting as monitors follow the same invalid/reset rules as `assert`:

* `assert` and `cover` are skipped when an observed value is invalid.
* `always_assert` and `always_cover` force checking independent of valid.


## Relation with test and poke

`test` blocks can combine stimulus (`step`, `poke`) with monitoring
(`sigref`, `regref`). The expected layering is:

* `test` with `step` and `poke` drives stimulus and checks top-level behavior.
* `test` with `sigref` checks local invariants close to each instance.
* `poke` is useful for mocking and fault injection.

```pyrope
test "mocking taken branches" {
  const taken = sigref("core/fetch/bpred0/taken")

  cover(taken)

  poke("core/fetch/bpred0/taken", true)

  mut l = core.fetch.predict(0xFFF)
}
```


## Restrictions

The following restrictions keep monitor semantics simple and deterministic:

* `sigref` is read-only. A test can not assign through `sigref`.
* A test can not create a second writer for a DUT register via `regref`.
* A test acting as a monitor can not instantiate synthesizable logic visible
  from the DUT.
* A test can not depend on execution order between sibling modules.

These restrictions ensure that removing all `test` blocks preserves the same
synthesizable design.


## Example

```pyrope
// file fifo.prp
mod fifo(clk, rst, push, pop, din) -> (full, empty, dout) {
  reg count:u3 = 0

  full  = count == 4
  empty = count == 0

  if push and !full  { count += 1 }
  if pop  and !empty { count -= 1 }
}

// file fifo_checks.prp (verification only, does not modify fifo.prp)
test "fifo invariants" {
  const push  = sigref("fifo/push")
  const pop   = sigref("fifo/pop")
  const full  = sigref("fifo/full")
  const empty = sigref("fifo/empty")
  const count = regref("fifo/count")

  assert(!(push and full))
  assert(!(pop and empty))
  assert(count <= 4)
  assert(empty implies count == 0)
  assert(full  implies count == 4)
}
```

This test can be added from a verification file without editing the file
that defines `fifo`.
