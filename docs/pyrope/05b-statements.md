
# Statements

## Conditional (`if`/`elif`/`else`)


Pyrope uses a typical `if`, `elif`, `else` sequence found in most languages.
Before the if starts, there is an optional keyword `unique` that enforces that
a single condition is true in the if/elif chain. This is useful for synthesis
which allows a parallel mux. The `unique` is a cleaner way to write an
`assume` statement.

The `if` sequence can be used in expressions too.

```pyrope
a = unique if x1 == 1 {
    300
  }elif x2 == 2 {
    400
  }else{
    500
  }

mut x = nil
if a { x = 3 } else { x = 4 }
```

The equivalent code with an explicit `assume`, but unlike the `assume`, the
`unique` will guarantee to generate the `hotmux` statement. EDA tools can also
optimize `unique if` to tri-state buffers when the conditions are mutually
exclusive, providing the same behavior as a hardware bus without needing a
separate `bus` construct.

```pyrope
assume(!(x1==1 and x2==2))
a = if x1 == 1 {
    300
  }elif x2 == 2 {
    400
  }else{
    500
  }
```

Like several modern programming languages, there can be a list of expressions
in the evaluation condition. If variables are declared, they are restricted to
the remaining if/else statement blocks.


```pyrope
mut tmp = x+1

if mut x1=x+1; x1 == tmp {
   puts("x1:{} is the same as tmp:{}", x1, tmp)
}elif mut x2=x+2; x2 == tmp {
   puts("x1:{} != x2:{} == tmp:{}", x1, x2, tmp)
}
```


## Unique parallel conditional (`match`)

The `match` statement is similar to a chain of unique if/elif, like the
`unique if/elif` sequence. The `match` statement is a replacement for the
common "unique parallel case" Verilog directive, and behaves like also
having an `assume` statement, which allows for more efficient code
generation than a sequence of `if/else`.

A `match` declares its arms mutually exclusive *and* exhaustive (it behaves
like an `assume`/unique-parallel-case), so there is always exactly one matching
branch. The `else` arm is **optional**: when the arms already cover the whole
key space — e.g. every value of a bounded `uN`/`sN` selector — it can be left
out. An omitted `else` behaves like an unreachable `else { assert(false) }`:
in hardware it lowers to a *don't-care* (the Hotmux "none-of" slot is never
selected), and at compile time a constant selector that somehow matches no arm
leaves the result undefined (`nil`), exactly as for an `if`/`elif` chain with
no `else`. Add an explicit `else` only when you need a real catch-all value or
a `cassert(false)`.

```pyrope
// `sel:u2` lists all four values — no `else` needed.
res = match sel {
  == 0 { a }
  == 1 { b }
  == 2 { c }
  == 3 { d }
}
```

In addition to functionality, the syntax is different to avoid redundancy.
`match` joins the match expression with the beginning of the matching
entry to form a valid expression.

```pyrope
const x = 1
match x {
  == 1            { puts("always true") }
  in (2,3)        { puts("never")       }
  else            { cassert(false)      }
}
// It is equivalent to:
unique if x == 1  { puts("always true") }
elif x in (2,3)   { puts("never")       }
else              { cassert(false)      }
```

Like the `if`, it can also be used as an expression.

```pyrope
mut hot = match x {
    == 0sb001 { a }
    == 0sb010 { b }
    == 0sb100 { c }
    else      { cassert(false); 0 }
  }

// Equivalent
assume(x==0sb001 or x==0sb010 or x==0sb100)
mut hot2 = __hotmux(x, a, b, c)

assert(hot==hot2)
```

Like the `if` statement, a sequence of statements and declarations are possible in the match statement.

```pyrope
match const one=1 ; (one, 2) {
  == (1,2) { puts("one:{}", one) }      // should always hit
  else     { cassert(false) }
}
```

Since the `==` is the most common condition in the `match` statement, it can be
omitted.

```pyrope
for x in 1..=5 {
  const v1 = match x {
    3 { "three" }
    4 { "four" }
    else { "neither"}
  }

  const v2 = match x {
    == 3 { "three" }
    == 4 { "four" }
    else { "neither"}
  }
  cassert(v1 == v2)
}
```


## Conditional statements

Conditional behavior is expressed with `if`/`else` blocks, `if` expressions,
or `match` chains. Runtime conditions synthesize muxes or enables. Comptime
conditions are folded during elaboration, but declarations inside an `if`
block still follow normal block scope.

```pyrope
comptime const DEBUG = true
mut a = 3

if false {
  a += 1
}
cassert(a == 3)

if DEBUG {
  assert(a == 3)
}

if not DEBUG {
  return
}
```

```pyrope
mut x = c                      // always declared
if cond { x = other }          // runtime-gated assignment
result = if cond { other } else { c }
```


## Code block

A code block is a sequence of statements delimited by `{` and `}`. The
functionality is the same as in other languages. Variables declared within
a code block are not visible outside the code block. In other words, code block
variables have scope from definition until the end of the code block.


Code blocks are different from lambdas. A lambda consists of a code block but
it has several differences. In lambdas, (1) visible comptime bindings from
upper scopes are available lexically, but runtime upper-scope variables are not
implicitly visible; (2) inputs and outputs could be constrained, and (3) the
`return` statement finishes a lambda not a code block.


The main features of code blocks:

* Code blocks define a new scope. New variable declarations inside are not visible outside it.

* Code blocks do not allow variable declaration shadowing.

* Expressions can have multiple code blocks but they are not allowed to have
  side-effects for variables outside the code block. The [evaluation
  order](02-basics.md#evaluation-order) provides more details on expressions
  evaluation order.

* A code block used as an expression evaluates to the value of its last
  expression. This is a property of code blocks, not lambdas — see
  [lambdas](06-functions.md#output-tuple) for how lambda outputs work
  (declared by name, assigned in the body, no implicit return).

```pyrope
mut yy = 0
{
  mut x=1
  mut z=0
  {
    z = 10
    mut x=2           // error: 'x' is a shadow variable
  }
  cassert(z == 10)
  yy = x
}
const zz = x            // error: `x` is out of scope
cassert(yy == 1)

mut yy2 = {const x=3 ; 33/3} + 1
cassert(yy2 == 12)
const xx = {yy=1 ; 33}  // error: 'yy' has side effects

if {const a=1+yy2; 13<a} {
  // a is not visible in this scope
  some_code()
}

comb doit(f, a) -> (r) {
  const x = f(a)
  assert(x == 7)
  r = 3
}

comb real_doit(a) -> (r) {
  assert(a != 0)
  r = 7
  return               // exit the current lambda; later statements skipped
  r = 100              // never reached
}

const z3 = doit(real_doit, 33)
cassert(z3 == 3)
```

## Loop (`for`)

The `for` iterates over the first-level elements in a tuple or the values in a
range.  In all the cases, the number of loop iterations must be known at
compile time. The loop exit condition can not be run-time data-dependent.


The loop can have an early exit when calling `break` and skip of the current
iteration with the `continue` keyword.

```pyrope
for i in 0..<100 {
 some_code(i)
}

mut bund = (1,2,3,4)
for (index, i) in bund {  // a pair binding IS the enumerate: index (position) first, value second
  assert(bund[index] == i)
}
```

The loop binding controls what is exposed, with the index/position first (as in
most languages):

* `for value in t` — just the element value.
* `for (index, value) in t` — `index` is the (const) position, `value` the element.
* `for (index, value, key) in t` — `key` is the field name (empty `''` for a
  positional slot).

The `value` is a copy; iterate over `ref t` (e.g. `for (index, value) in ref t`)
to write the element back into the tuple.

```pyrope
const b = (const a=1, const b=3, const c=5, 7, 11)
cassert(b.keys() == ('a', 'b', 'c', '', ''))

for (index, i, key) in b {
  cassert(i==1  implies (index==0 and key == 'a'))
  cassert(i==3  implies (index==1 and key == 'b'))
  cassert(i==5  implies (index==2 and key == 'c'))
  cassert(i==7  implies (index==3 and key == '' ))
  cassert(i==11 implies (index==4 and key == '' ))
}
```

To build a tuple/array from a loop, use an explicit `for` over a `mut`
accumulator and rebuild it with `...` each iteration (`d = (...d, i)`).
Trailing-`for` comprehensions on expressions are not supported (they make
trailing tokens of every expression ambiguous to parse) — write the loop out
instead.

```pyrope
mut d:[] = nil
for i in 0..<5 {
  d = (...d, i)
}

mut e:[] = nil
for i in 0..<5 {
  if i {
    e = (...e, i)
  }
}
cassert((0,1,2,3,4) == d)
cassert(e == (1,2,3,4))
```

The iterating element is copied by value, if the intention is to iterate over a
vector or array to modify the contents, a `ref` must be used. Only the element
is mutable. When a `ref` is used, it must be a variable reference, not a
function call return (value). The mutable for can not be used in
comprehensions.

```pyrope
mut b = (1,2,3,4,5)

for x in ref b {
  x += 1
}
cassert(b == (2,3,4,5,6))
```

### Code block control

Code block control statements allow changing the control flow for `lambdas` and
loop statements (`for`, `loop`, and `while`). **`return` is a terminator only
— it never carries a value.** Whatever has been assigned to the lambda's
declared output names is what the caller sees.

* `return` is for early exits — it terminates the current lambda before
  reaching the end of the body. It takes no arguments; `return X` is a
  syntax error. To return early with a specific value, assign the output
  first: `r = X; return`. For conditional early exits, put the terminator
  inside an `if` block: `if cond { return }`.

* `break` terminates the closest inner loop (`for`/`while`/`loop`). If none is
  found, a compile error is generated.

* `continue` looks for the closest inner loop (`for`/`while`/`loop`) code
  block. The `continue` will perform the next loop iteration. If no inner loop
  is found, a compile error is generated.


```pyrope
mut total:[] = nil
for a in 1..=10 {
  if a == 2 { continue }
  total = (...total, a)
  if a == 3 { break }    // exit for scope
}
cassert(total == (1,3))

if true {
  code(x)
  continue             // error: no upper loop scope
}

mut a = 3
mut total2:[] = nil
while a>0 {
  total2 = (...total2, a)
  if a == 2 { break }    // exit if scope
  a = a - 1
  continue
  assert(false) // never executed
}
cassert(total2 == (3,2))

mut total3:[] = nil
for i in 1..=9 {
  if i<3 {
    total3 = (...total3, i+10)
  }
}
cassert(total3 == (11, 12))
```

## while/loop

`while cond { [stmts]+ }` is a typical while loop found in most programming
languages. The only difference is that like with loops, the while must be fully
unrolled at compilation time. The `loop { [stmts]+ }` is equivalent to a `while
true { [stmts]+ }`.


Like `if`/`match`, the `while` condition can have a sequence of statements with
variable declarations visible only inside the while statements.

```pyrope
// a do while contruct does not exist, but a loop is quite clean/close

mut a = 0
loop {
  puts("a:{}",a)

  a += 1

  if a >= 10 { break }
} // do{ ... }while(a<10)
```

`for`, `while`, and `loop` are compile-time only and fully unrolled. For a
runtime, cycle-driven loop inside a `test` (run for `N` cycles or forever), use
[`tick`](#running-cycles-tick).

## Cycle access

Cycle-based access to values is expressed through a small set of
constructs:

* The first bare `variable` reads before update hold the register's 'q' value:

  ```pyrope
  reg counter:u32 = 0
  const counter_q = counter         // snapshot 'q' before any updates this cycle

  if whatever {
    counter = counter + 1
  }
  ```

* `past[N](variable)` pipelines the value over `N` cycles. `N` must be a
  literal positive decimal; the compiler inserts `N` flops, so the hardware
  cost is explicit in the call, and the expression's landing cycle shifts by
  `N`. There is no bare `past(x)` in a design body. Do not confuse it with the
  verification `past(x, n)` history sample, which does *not* shift the cycle —
  see [Temporal library](09-verification.md#temporal-library).

* To escape *program order* within a cycle — read a value that is only
  produced by a later statement, e.g. to close a ring — declare it as a
  `wire` (single-driver combinational net) and read it before its driver
  appears. See [Wire](04-variables.md#wire-single-driver-combinational-nets).

* For pipeline timing, use `stage[N]` (declaration modifier that pipelines
  the whole RHS over `N` cycles; `mod`-only) and `foo@[N]` (pure timing type
  check, legal in both `mod` and `pipe` bodies — it asserts the inferred
  stage and never inserts flops).

* For debug-only sampling over time (inside `assert`, `test`, `formal`, …),
  use the temporal library — `past(x, n)`, `rose(x)`, `eventually(x, 1..=N)`,
  etc. Every cycle argument is positional; there is no bracket form, and the
  whole library is still TBD. See
  [Temporal library](09-verification.md#temporal-library).

`foo@[N]` is a pure cycle-alignment type check, never a flop insertion, and
is legal inside both `mod` and `pipe` bodies. `foo@[3]` checks that `foo` is
3 pipeline stages ahead of the lambda inputs. To actually delay a value, use
`stage[N] lhs = rhs` (a `mod`-only construct) or `past[N](x)`. There is no
future-cycle read in synthesizable code.

To feed a register's next-state into both the register and a same-cycle
consumer, name the value as a `wire` and read it in both places:

```pyrope
wire nx = nil          // forward-declared net for the next-state value
nx = counter + 1       // its single driver
reg counter:u32 = 0
counter = nx           // registered write
const also = nx + 1    // same-cycle consumer reads the same net
```

To connect `ring` calls in a loop, forward-declare the back edge as a `wire`:

```pyrope
wire f4 = nil
f1 = ring(a, f4)       // reads f4 before its driver appears
f2 = ring(b, f1)
f3 = ring(c, f2)
f4 = ring(d, f3)       // the single driver of f4
```

## Testing (`test`)

A `test` block is a debug-only simulation entry point. It is named by a
**dotted identifier** (a selector path), not a string, so individual tests and
whole groups can be selected from the command line:

```pyrope
test add.basic {
  assert(add(2, 3) == 5)
}
```

```bash
lhd sim add.prp            # run every test in add.prp
lhd sim add.prp add        # run every test under the `add.` group (prefix match)
lhd sim add.prp add.basic  # run one test
```

`lhd sim <file.prp> [test.name]` takes the source file as the first positional
and an optional dotted test selector as the second. With no selector every test
in the file runs.

The leading segments form the group and the final segment is the leaf. A
fully-qualified test name must be unique (a selector maps to one definition).
There is no `test "string"` form: a human-readable message is just a `puts(...)`
(or an `assert` message) inside the body. A `test` body still behaves like a
`puts` followed by a scope, and its statements can not have any effect outside.

### Runtime parameters

A `test` may declare runtime parameters in a `(...)` list, exactly like a lambda
but **without** a `-> (...)` return (a test never returns a value). The
parameters are ordinary values usable inside the body — to drive a DUT input,
size a `tick` loop, or seed a `cpp` model — so a single test becomes a small
parametrized experiment:

```pyrope
test add.checked(lhs:i32=3, rhs:i32) {
  assert(add(lhs, rhs) == lhs + rhs)   // lhs and rhs are the DUT inputs
}
```

Each parameter is either **optional** or **required**:

* `lhs:i32=3` has a default, so it is optional: the runner uses `3` unless it is
  overridden.
* `rhs:i32` has **no** default, so it is required: the runner MUST supply a
  value. `rhs:i32=nil` means exactly the same thing — an explicit `nil` default
  and an omitted default both say "the runner must set this". A `nil` that
  reaches the body is a runner error, never a silent `0`.

Values are passed with `--arg name=value` (repeatable). Supplying a required
argument is mandatory; running without it is an error, not a default-to-zero:

```bash
lhd sim add.prp add.checked --arg rhs=7               # lhs=3 (default), rhs=7
lhd sim add.prp add.checked --arg lhs=10 --arg rhs=-4 # both overridden
lhd sim add.prp add.checked                           # error: required `rhs` not set
```

A required parameter is the hook for *external setup*: the value can come from
the command line as above, or from a harness that fills it in (a fuzzer, a
constrained-random or directed-test generator, a CI matrix). The test declares
*what* it needs; the runner decides *how* the value is produced.

Runtime parameters are debug-only simulation values (they drive the DUT,
`poke`/`step`, or feed a `cpp` model); they never reach synthesizable logic. A
value that must size hardware is a `comptime` parameter and belongs in the
`[...]` slot (planned; see [Implementation status](15-tbd.md)), not in `(...)`.

Many tests can run in parallel to increase throughput. A comptime `for` loop
multiplies the number of tests; each unrolled instance shares the leaf name and
the runner disambiguates them by index:

=== "Parallel tests"
    ```pyrope
    comb add(a,b) -> (r) { r = a + b }

    for i in 0..<10 { // 10 tests
      const a = (-30..<100).rand
      const b = (-30..<100).rand

      test add.sweep {
        assert(add(a,b) == (a+b))
      }
    }
    ```

=== "Single test"
    ```pyrope
    comb add(a,b) -> (r) { r = a + b }

    test add.batch {
      for i in 0..<10 { // 10 checks
        const a = (-30..<100).rand
        const b = (-30..<100).rand

        assert(add(a,b) == (a+b))
      }
    }
    ```

### Test only statements

`test` code blocks are allowed to use special statements not available outside
testing blocks:

* `step [ncycles]` advances the simulation one cycle (or `ncycles`). The local
  variables preserve their value; the inputs may change value. `step` is the
  explicit yield point of a test — the clock edge.

To *wait* for a condition there is no separate primitive: `step` each cycle and
`continue` until it holds (the `tick N` bound is the timeout). See
[Waiting on a condition](09-verification.md#waiting-on-a-condition).

```pyrope
test wait.one {
  mut dut = top
  tick 100 {
    dut.a = 1
    step
    if not dut.ready { continue }   // wait until ready, then proceed
    break
  }
  assert(dut.ready, "ready did not assert within 100 cycles")
}
```

### Running cycles (`tick`)

`for`, `while`, and `loop` all unroll at compile time, so they can not express
"run for a runtime number of cycles". That is what `tick` does — a
**non-unrolling**, cycle-driven loop usable only inside `test`:

```pyrope
tick N { stmts }   // run up to N cycles; one `step` (clock edge) per iteration
```

Each `tick` iteration is **one cycle**. You declare the design under test (DUT)
once as an *instance* before the loop and interact with it by field access:
`acc.x = v` drives input `x` (pre-edge), `acc.y` reads an output or an internal
register (`acc.total`). The clock edge is the explicit **`step`** in the body —
statements above it drive this cycle's inputs, statements below sample the
results — and there is exactly one `step` per iteration. The current cycle index
is the first-class value `clock` (0-based), usable in `puts`, `assert`, and to
gate inputs such as reset (`acc.reset = clock < 2`; reset is just an input):

```pyrope
mod counter(enable:bool) -> (value:u8@[0]) {
  reg count:u8 = 0

  value = count                     // combinational read of count.q -> @[0]

  if enable { wrap count += 1 }
}

test counter.held_high {
  mut acc     = counter             // one persistent instance, reset on declaration
  mut v_final = nil
  tick 20 {                         // run up to 20 cycles
    acc.enable = true               // drive this cycle's input (pre-edge)
    step                            // the clock edge
    v_final = acc.value             // sample this cycle's output (post-edge)
  }
  assert(v_final == 20, "after 20 enabled cycles the count must be 20")
}
```

Test-local `mut`s persist across iterations, so a golden value updated in
lockstep inside the same loop mirrors the design's next-state and makes the
final `assert` self-checking:

```pyrope
test counter.gated {
  mut acc      = counter
  mut en       = false
  mut expected = 0
  mut v_final  = nil
  tick 20 {
    en = not en                       // this cycle's enable
    if en { expected = expected + 1 } // golden mirror of count
    acc.enable = en
    step
    v_final = acc.value
  }
  assert(v_final == expected, "gated counter disagrees with golden model")
  assert(v_final == 10)               // enable was high on 10 of the 20 cycles
}
```

Reset is an ordinary input — drive it from the cycle index rather than a magic
window. Holding `acc.reset` for the first cycles keeps the registers at their
reset value until you release it:

```pyrope
test counter.with_reset {
  mut acc = counter
  tick 8 {
    acc.enable = true
    acc.reset  = clock < 2     // cycles 0,1 held in reset; counting starts at cycle 2
    step
  }
  assert(acc.value == 6)       // counted only on cycles 2..7
}
```

A [runtime parameter](#runtime-parameters) can drive the simulation itself.
Because `tick` takes a runtime count (unlike the unrolling `for`), the cycle
bound can be a test argument set from outside — the value comes from `--arg`, or
from the runner when it is omitted:

```pyrope
test counter.run_for(cycles:u8=20) {
  mut acc     = counter
  mut v_final = nil
  tick cycles {                       // a runtime argument sets the loop length
    acc.enable = true
    step
    v_final = acc.value
  }
  assert(v_final == cycles, "after {} enabled cycles the count must be {}", cycles, cycles)
}
```

```bash
lhd sim counter.prp counter.run_for                 # cycles=20 (default)
lhd sim counter.prp counter.run_for --arg cycles=50 # run 50 cycles instead
```

The `N` bound doubles as a watchdog: a `break` stops the loop early once a
runtime condition holds, while `N` guarantees the test can never spin forever.

```pyrope
test runner.until_done {
  mut r          = runner
  mut done_final = false
  tick 100 {                       // watchdog bound: never spin forever
    r.start = clock == 0           // one-cycle start pulse on cycle 0
    r.len   = 5
    step
    done_final = r.done
    if r.done { break }
  }
  assert(done_final, "runner never reached Done within 100 cycles")
}
```

Like `step` and `poke`, `tick` is a statement-level construct, not a reserved
identifier: it is recognized only at the start of a statement (`tick`, a cycle
count, then a `{ ... }` block). A variable or method named `tick` (such as a
`mod tick(ref self, ...)` clock method) is unaffected.

An unbounded `tick { }` (no count: run until a `break`) is TBD; the simulation
runner currently requires the `N` bound, which doubles as the watchdog/timeout.
Stimulus, waiting, and monitors all live *inside* the one bounded loop as
`if`-blocks — see [Extended Verification](09-verification.md).


"Wait until a condition" is `step` plus `if`/`continue` — there is no `waitfor`
primitive. The `tick N` bound is the timeout, and a post-loop `assert` turns a
timeout into a failure:

```pyrope
total = 3
tick 1000 {
  step
  if not a_cond { continue }   // wait until a_cond is true
  break
}
assert(total == 3 and a_cond, "a_cond did not hold within 1000 cycles")
```

The main reason for using the `step` is that the "equivalent" `#>[1]` is a more
structured construct. The `step` behaves more like a "yield" in that the next
call or cycle it will continue from there. The `#>[1]` directive adds a
pipeline structure which means that it can be started each cycle. Calling a
lambda that has called a `step` and still has not finished should result in a
simulation assertion failure.

* `peek` allows to read any flop, and lambda input or output

* `poke` is similar to `peek` but allows to set a value on any flop and lambda
  input/output.
