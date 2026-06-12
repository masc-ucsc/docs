# Extended Verification

This chapter extends [Verification](05-assert.md) for interactive testbench
work. The target is the cocotb style of "drive, wait, sample, and run helper
coroutines", but with as little new syntax as possible.

The design rules are:

* Reuse existing `test`, `step`, `waitfor`, `poke`, `sigref`, and `regref`.
* Prefer attribute reads such as `sig.[rising]` over new statement families.
* Keep monitors as ordinary Pyrope threads.
* Keep logging, wave dumps, and solver libraries out of the core language when
  the runner can provide them.

All the constructs in this chapter are debug-only. Removing them preserves the
same synthesizable design.


## Cocotb mental map

Pyrope tests are cycle based. `step` advances one or more cycles, so the core
language does not need a separate `Timer(..., units=...)` API.

| cocotb | Pyrope |
|--------|--------|
| `dut.sig.value = x` | `poke("top/sig", x)` |
| `dut.sig.value` | `sigref("top/sig")` |
| `await RisingEdge(dut.valid)` | `mut e = valid.[rising]; waitfor(ref e)` |
| `await FallingEdge(dut.ready)` | `mut e = ready.[falling]; waitfor(ref e)` |
| `await Edge(dut.sig)` | `mut e = sig.[changed]; waitfor(ref e)` |
| `await Timer(5 cycles)` | `step 5` |
| `cocotb.start_soon(coro())` | `spawn name = { ... }` |
| `await t` | `join t` |
| `task.cancel()` | `cancel t` |
| `Force` / `Release` | `force(path, value)` / `release(path)` |

The main difference is that Pyrope keeps the verification code inside the same
language as the DUT. There is no separate Python object model for the design.


## Concurrent test threads (`spawn`/`join`/`cancel`)

Pyrope `test` blocks are single-threaded today, with `step` as the explicit
yield point. To run concurrent stimulus and monitors inside a test, `spawn`
declares a new test thread and binds it to a name. `join` waits until all
the listed threads complete, and `cancel` requests that a running thread
stop at the next yield point.

`spawn` is a declaration keyword (in the same slot as `const`/`mut`/`reg`
and `comb`/`pipe`/`mod`) — the name comes right after `spawn`, followed by
`= { body }`. It is only valid inside `test` blocks.

```pyrope
test "producer consumer" {
  spawn producer = {
    for i in 0..<10 {
      mut not_full = !sigref("fifo/full")
      waitfor(ref not_full)
      poke("fifo/push", true)
      poke("fifo/din",  i)
      step
      poke("fifo/push", false)
    }
  }

  spawn consumer = {
    for i in 0..<10 {
      mut not_empty = !sigref("fifo/empty")
      waitfor(ref not_empty)
      poke("fifo/pop", true)
      step
      assert(sigref("fifo/dout") == i)
      poke("fifo/pop", false)
    }
  }

  join(producer, consumer)
}
```

Multiple test threads run cooperatively:

* Each thread runs until it reaches `step`, `waitfor`, or completion.
* Threads advance deterministically in spawn order within a cycle.
* `cancel h` is observed at the next `step` or `waitfor` in thread `h`.
* When the enclosing `test` finishes, any still-running spawned threads are
  cancelled automatically.

The goal is to keep `spawn` syntax small. There is only one task-creation form:

```pyrope
spawn x = {
  some_statement()
}
```

The declared name is used later with `join` or `cancel`:

```pyrope
test "temporary monitor" {
  spawn mon = {
    const req = sigref("top/req")
    mut req_rose = req.[rising]
    while true {
      waitfor(ref req_rose)
      puts("req rose")
    }
  }

  step(1000)
  cancel(mon)
}
```

Spawned blocks may read enclosing values and update enclosing `reg` variables.
No separate capture-list syntax is needed.


## `waitfor` and edge-sensitive waits

`waitfor` is a regular `mod` (not special syntax). It blocks the current
test thread until a boolean variable becomes true:

```pyrope
mod waitfor(ref cond: bool, timeout: u32 = 0) -> () {  }
```

The first argument must be passed by `ref`, and it must be a plain variable
(no expression, no attribute read). The `ref` makes "the callee samples the
live value each cycle" explicit at the call site, matching Pyrope's "by
value unless explicit" rule. Missing `ref` is a compile error; passing an
expression or `.[…]` read directly is also a compile error — bind the
predicate to a variable first.

```pyrope
test "wait for valid" {
  const valid = sigref("top/core0/valid")
  mut valid_rose = valid.[rising]

  waitfor(ref valid_rose)

  assert(valid)
  puts("valid just went high")
}
```

The bound variable holds a debug-only attribute read. Three are supported:

* `sig.[rising]` is true on the cycle where `sig` transitions from
  0/false to non-zero/true.
* `sig.[falling]` is true on the cycle where `sig` transitions from
  non-zero/true to 0/false.
* `sig.[changed]` is true on any cycle where `sig` differs from its
  previous value.

These reads are debug-only. They compare the current value against
`past(sig)` and work anywhere a boolean is expected, not only in `waitfor`.

```pyrope
test "edge in assertions" {
  const clk_en = sigref("top/clk_en")

  assert(!clk_en.[rising], "unexpected clock enable")
  cover(clk_en.[falling])
}
```

For multi-cycle edges and windowed assertions, use the [temporal
library](#temporal-library) below — `rose[R](sig)`, `fell[R](sig)`,
`eventually[R](sig)`, etc. The attribute forms above are sugar for the
single-cycle case (`rose(sig) == sig.[rising]`).

### Timeout

To avoid hung tests, `waitfor` accepts a `timeout` keyword argument bounding
the wait to `N` cycles:

```pyrope
test "bounded wait" {
  const done = sigref("top/done")
  mut done_rose = done.[rising]

  waitfor(ref done_rose, timeout=1000)
  assert(done, "done did not rise within 1000 cycles")
}
```

If the timeout expires, `waitfor` returns even when the condition is still
false. The following `assert` decides whether that should fail the test.

```pyrope
mut valid_rose = valid.[rising]
waitfor(ref valid_rose)
waitfor(ref valid_rose, timeout=500)

mut done_var = done
waitfor(ref done_var, timeout=2000)
step(5)
```


## Force and release

`poke` sets a value for the current cycle only. `force` and `release` provide
persistent overrides:

* `force(path, value)` overrides the signal until released.
* `release(path)` removes the override and restores the normal driver.

```pyrope
test "inject fault then release" {
  const mem_err = sigref("top/mem/error")

  assert(!mem_err)

  force("top/mem/error", true)
  step(3)
  assert(sigref("top/core/exception"))

  release("top/mem/error")
  step
  assert(!mem_err)
}
```

`force` and `release` are debug-only. A bad path is an elaboration error.
Forcing a register overrides the visible `q` value, not the internal `d`
calculation.


## Monitors as plain threads

Pyrope does not need a separate callback API like `watch`. A cocotb monitor is
just a spawned thread that waits on edges and checks state.

```pyrope
test "req ack monitor" {
  const req = sigref("top/bus/req")
  const ack = sigref("top/bus/ack")
  reg outstanding:u8 = 0

  spawn req_mon = {
    mut req_rose = req.[rising]
    while true {
      waitfor(ref req_rose)
      outstanding += 1
    }
  }

  spawn ack_mon = {
    mut ack_rose = ack.[rising]
    while true {
      waitfor(ref ack_rose)
      assert(outstanding > 0, "ack without req")
      outstanding -= 1
    }
  }

  step(1000)
  cancel(req_mon)
  cancel(ack_mon)
  assert(outstanding == 0)
}
```

This keeps the model small:

* No callback registration syntax.
* No extra scheduling rules beyond `spawn`, `join`, `cancel`, `step`, and
  `waitfor`.
* Monitors, drivers, and scoreboards all use the same thread model.


## Random stimulus

Pyrope already has `.[rand]` and `.[crand]` from
[Verification](05-assert.md#random). For many cocotb-style tests, that is
enough. Start with ordinary random values and filter them with normal Pyrope
control flow.

```pyrope
test "random legal opcodes" {
  mut opcode:u4 = 0

  for i in 0..<100 {
    while true {
      opcode = opcode.[rand]
      if opcode <= 10 { break }
    }

    poke("top/opcode", opcode)
    step
  }
}
```

If solver-backed constrained random is needed later, it should preferably be a
library layer on top of this style instead of a large new statement family in
the core language.


## Temporal library

The temporal library provides SVA-style sampling over time. Every entry is a
plain `comb` lambda whose cycle parameters live in the `[...]` comptime
parameter slot (see [Lambdas](06-functions.md#declaration)). Callers can
override the comptime slot at the call site to pick a specific cycle or range:

```pyrope
rose(x)           // single-cycle: true when x rises this cycle
rose[1..=4](x)    // true if x rises at any cycle in 1..=4
past(x)           // x one cycle ago (the compiler inserts one flop)
past[3](x)        // x three cycles ago
next(x, 1)        // debug peek: x one cycle ahead
eventually[1..=10](x)   // true if x is true at some cycle in 1..=10
```

Because the cycle arguments are comptime, the compiler elaborates them into
ordinary register reads and combinational logic — there is no runtime
scheduling or new language construct.

### Builtins

| Builtin | Signature | Meaning |
|---------|-----------|---------|
| `past[n:int=1](x)` | past value | value of `x` `n` cycles ago; compiler inserts `n` flops |
| `next[n:int=1](x)` | debug future peek | value of `x` `n` cycles ahead |
| `rose[w:range=1..=1](x)` | rising edge within window | `x` becomes true at some cycle in `w` |
| `fell[w:range=1..=1](x)` | falling edge within window | `x` becomes false at some cycle in `w` |
| `stable[w:range=1..=1](x)` | held constant | `x` has the same value across `w` |
| `changed[w:range=1..=1](x)` | value change within window | `x` differs from its prior value at some cycle in `w` |
| `eventually[w:range](x)` | existence within window | `x` is true at some cycle in `w` |
| `always[w:range](x)` | universal within window | `x` is true at every cycle in `w` |

`past` is valid in both production and debug code — it is the canonical way
to read a prior-cycle value, replacing the old `x@[-N]` notation. The
compiler inserts the necessary flops; the hardware cost is explicit in the
call (`past[3](x)` costs three flops).

The remaining builtins (`next`, `rose`, `fell`, `stable`, `changed`,
`eventually`, `always`) are debug-only — they are valid inside `assert`,
`cover`, `test`, and similar contexts, and are elided from synthesis.
Nothing can observe a future value at runtime, so `next` and the
window-quantified forms only make sense in assertion-style contexts.

### SVA comparison

A standard SVA implication assertion:

```systemverilog
assert property (@(posedge clk) $rose(req) |-> ##[1:10] $rose(ack));
```

translates directly:

```pyrope
assert(rose(req) implies rose[1..=10](ack))
```

More examples:

```pyrope
// x stable during a 5-cycle handshake window
assert(req implies stable[1..=5](payload))

// ack must eventually rise within 32 cycles of req
assert(rose(req) implies eventually[1..=32](ack))

// grant is always clean-high while sel is held
assert(sel implies always[1..=10](grant))

// past values
if enable {
  assert(counter == past(counter) + 1)
}
assert(x == past[3](x)) // same value three cycles ago
```

### Overriding comptime parameters

User code can define small temporal helpers with comptime parameters. Defaults
may refer to visible comptime bindings, and callers can override the parameter:

```pyrope
comptime const window = 1..=8
comb ack_within(w:range=window, req, ack) -> (r:bool) { r = req implies eventually[w](ack) }

assert(ack_within(req, ack)) // uses default w = 1..=8
assert(ack_within(w=1..<4, req, ack)) // tighter window at this call site
```


## Deliberate non-goals

To keep verification close to Pyrope and easy to learn, this chapter
intentionally does not add:

* `watch` / `unwatch`: `spawn` plus `waitfor` already covers the same use case.
* `log.info` / `log.warn` / `log.error`: existing `puts` and `print` are enough
  for the language core.
* `dump.start` / `dump.stop`: waveform capture fits better as a runner or tool
  option than as language syntax.
* A built-in constrained-random DSL: start with `.[rand]`, and add libraries
  only if they prove necessary.


## Summary of new constructs

| Construct | Context | Purpose |
|-----------|---------|---------|
| `spawn name = { }` | `test` only | Declare a concurrent test thread |
| `join h1, h2, ...` | `test` only | Wait for threads to complete |
| `cancel h` | `test` only | Stop a running thread at the next yield point |
| `sig.[rising]` | debug only | True on a 0-to-1 transition (same as `rose(sig)`) |
| `sig.[falling]` | debug only | True on a 1-to-0 transition (same as `fell(sig)`) |
| `sig.[changed]` | debug only | True when value differs from previous cycle (same as `changed(sig)`) |
| `past[n](x)` | any context | Sample `x` at a past cycle (inserts `n` flops) |
| `next[n](x)` | debug only | Sample `x` at a future cycle |
| `rose[w](x)`, `fell[w](x)` | debug only | Windowed edge within range `w` |
| `stable[w](x)`, `changed[w](x)` | debug only | Windowed value-stability checks |
| `eventually[w](x)`, `always[w](x)` | debug only | Existence / universal quantifier over cycles in `w` |
| `waitfor(ref c, timeout=N)` | `waitfor` only | Bound the wait to `N` cycles |
| `force(path, val)` | `test` only | Override a signal persistently |
| `release(path)` | `test` only | Remove the override and restore the driver |

Everything else in this chapter is built from existing Pyrope verification
constructs.
