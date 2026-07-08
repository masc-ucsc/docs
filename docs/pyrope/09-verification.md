# Extended Verification

!!! WARNING "TBD"
    What *runs today* (`lhd sim`) is the single-clock, single-threaded
    simulation form: a `test name { ... }` block declares the DUT as an instance
    (`mut acc = dut`), and a bounded `tick N { ... }` loop drives it with field
    pokes (`acc.x = v`), advances the clock with an explicit `step`, peeks
    outputs/registers (`acc.y`), and checks with `assert` — see
    [Running cycles](05b-statements.md#running-cycles-tick) (and `newtick.md` in
    the LiveHD repo). Waiting and concurrency are expressed *in that one loop*
    with ordinary `if`/`continue`/`break` (below) — there is no separate
    coroutine layer. Still not implemented: the temporal library
    (`past`/`next`/`rose`/`fell`/`stable`/`changed`/`eventually`/`always`,
    `.[rising]`/`.[falling]`), the string `poke`/`sigref` arbitrary-path layer,
    and `force`/`release`. Dotted test names and runtime `(...)` test parameters
    are the near-term `test` syntax. See [Implementation status](15-tbd.md).

This chapter extends [Verification](05-assert.md) for interactive testbench
work. The target is the cocotb style of "drive, wait, sample, score", but with
as little new syntax as possible — and, unlike cocotb, **without coroutines**: a
test is one `tick`/`step` loop, and stimulus, waiting, and monitors are just
`if`-blocks inside it.

The design rules are:

* Reuse existing `test`, `tick`, `step`, and `assert`/`cover`; express waiting
  and concurrency with `if`/`continue`/`break`, not new statement families.
* Prefer attribute reads such as `sig.[rising]` over new wait primitives.
* Keep monitors as inline checks (or a golden `mut`/`cpp` model) in the loop.
* Keep logging, wave dumps, and solver libraries out of the core language when
  the runner can provide them.

All the constructs in this chapter are debug-only. Removing them preserves the
same synthesizable design.


## Cocotb mental map

Pyrope tests are cycle based. `step` advances one or more cycles, so the core
language does not need a separate `Timer(..., units=...)` API.

| cocotb | Pyrope |
|--------|--------|
| `@cocotb.test()` coroutine | `test foo.bar { ... }` |
| `dut.sig.value = x` | `acc.sig = x` (poke an input) |
| `dut.sig.value` | `acc.sig` (peek an output / reg) |
| `await RisingEdge(dut.valid)` | `step; if not acc.valid.[rising] { continue }` |
| `await FallingEdge(dut.ready)` | `step; if not acc.ready.[falling] { continue }` |
| `await Edge(dut.sig)` | `step; if not acc.sig.[changed] { continue }` |
| `await Timer(5 cycles)` | `step 5` |
| `while True: await ...` (driver/monitor) | the `tick N { ... step ... }` loop itself |
| `@cocotb.test(timeout_time=N)` | `tick N { ... }` (the bound is the timeout) |
| `cocotb.start_soon(coro())` / `await t` / `task.cancel()` | no threads — interleave each "task" as an `if`-block in the one `tick` loop |
| `Force` / `Release` | `force(path, value)` / `release(path)` |
| `@cocotb.parametrize(...)` / plusargs | `test foo.bar(arg:T=def)` → `lhd sim foo.prp foo.bar --arg arg=val` |
| `Scoreboard` / golden model | a golden `mut` updated each cycle, or `cpp("model")` |

The main difference is that Pyrope keeps the verification code inside the same
language as the DUT. There is no separate Python object model for the design.


## Concurrent stimulus without threads

cocotb spins up a coroutine per driver and monitor. Pyrope does not: a test is a
single `tick`/`step` loop, and each concurrent "task" is just an `if`-block in
that loop. The one `step` per iteration is the shared yield point, so the tasks
advance together every cycle — deterministically, with no scheduler, no `spawn`,
and no capture list (the body already shares all the test's `mut`s).

A FIFO exercised by a producer and a consumer at the same time: each side is an
`if`-block guarded by the FIFO's flow control, and a golden `mut` mirror checks
ordering.

```pyrope
test fifo.producer_consumer {
  mut dut  = Fifo
  mut sent = 0                 // next value to push
  mut got  = 0                 // next value to expect

  tick 1000 {
    // producer task: push while there is room and data left to send
    dut.push = not dut.full and sent < 10
    if dut.push { dut.din = sent }

    // consumer task: pop whenever data is available
    dut.pop = not dut.empty
    if dut.pop { assert(dut.dout == got, "FIFO out of order") }

    step                       // the one shared yield: both tasks advance

    if dut.push { sent = sent + 1 }
    if dut.pop  { got  = got  + 1 }
    if sent == 10 and got == 10 { break }
  }
  assert(sent == 10 and got == 10, "producer/consumer did not finish in 1000 cycles")
}
```

The two "threads" are the two `if`-blocks; `step` advances them together. To stop
one task early, gate its `if` on a flag; to cancel the whole test, `break`.


## Waiting on a condition

There is no `waitfor` primitive. Because a `tick` body runs every cycle and the
clock only advances on `step`, "wait until X" is just: `step` each cycle and
`continue` until the condition holds. The `tick N` bound *is* the timeout, and an
`assert` after the loop turns a timeout into a failure.

```pyrope
test wait.threshold {
  mut acc = accumulator
  tick 300 {
    acc.din = 1
    step
    if acc.total < 30 { continue }   // keep waiting
    break                            // condition met
  }
  assert(acc.total >= 30, "total did not reach 30 within 300 cycles")
}
```

The shape is always the same: `step`, `if not <cond> { continue }`, `break`, then
a post-loop `assert` for the timeout. Drive stimulus above the `step` if the wait
depends on it. This one idiom replaces every cocotb `await Edge/RisingEdge/...`
and the old `waitfor(ref c, timeout=N)`; `step N` covers `await Timer(N cycles)`.

The `continue` is what makes it a *wait*: it skips the rest of this cycle's body
and loops back to the next `step`. Without the `step`, the clock would never
advance and the condition could never change.

### Edge-sensitive reads

The condition can be any boolean, including the debug-only edge attributes:

* `sig.[rising]` — true on the cycle `sig` goes 0/false → non-zero/true.
* `sig.[falling]` — true on the cycle `sig` goes non-zero/true → 0/false.
* `sig.[changed]` — true on any cycle `sig` differs from the previous one.

These compare the current value against `past(sig)` and work anywhere a boolean
is expected — a wait's `if`, an `assert`, or a `cover`:

```pyrope
test edge.checks {
  mut dut = Top
  tick 64 {
    step
    assert(not dut.clk_en.[rising], "unexpected clock enable")
    cover(dut.clk_en.[falling])
  }
}
```

For multi-cycle edges and windowed assertions, use the [temporal
library](#temporal-library) below — `rose[R](sig)`, `fell[R](sig)`,
`eventually[R](sig)`, etc. The attribute forms above are the single-cycle case
(`rose(sig) == sig.[rising]`).


## Force and release

`poke` sets a value for the current cycle only. `force` and `release` provide
persistent overrides:

* `force(path, value)` overrides the signal until released.
* `release(path)` removes the override and restores the normal driver.

```pyrope
test fault.inject {
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


## Monitors as inline checks

A monitor is not a separate thread either — it is an `if`-block in the same loop
that watches signals and updates a checker `mut`. The req/ack protocol (every
`ack` must follow an outstanding `req`) is two edge checks plus a counter,
evaluated every cycle after the `step`:

```pyrope
test monitor.req_ack {
  mut dut         = Top
  mut outstanding = 0
  tick 1000 {
    // ... drive the bus here ...
    step
    if dut.req.[rising] { outstanding = outstanding + 1 }
    if dut.ack.[rising] {
      assert(outstanding > 0, "ack without req")
      outstanding = outstanding - 1
    }
  }
  assert(outstanding == 0, "unmatched req at end of test")
}
```

The monitor, the driver, and a scoreboard are all just `if`-blocks sharing the
loop's `mut`s — no callback API, no `spawn`/`cancel`, and no scheduling rules
beyond `step`.


## External C++ models

A `test name { }` block generates the simulation to run (the slop/sim), so a
golden model or scoreboard written in C++ plugs straight into it. Reach the C++
with [`cpp`](07-typesystem.md#external-c-calls-via-cpp) and call its typed
methods like any other lambda:

```pyrope
type GcdModel = ( call_method1: comb(a:u8, b:u3) -> (foo:u8, bar:u33) )
const gold:GcdModel = cpp("gcd_model")

test gcd.check {
  for a in 1..=100 {
    poke("top/a", a)
    poke("top/b", 3)
    step
    const (foo, _bar) = gold.call_method1(a=a, b=3)
    assert(sigref("top/z") == foo)        // DUT checked against the C++ reference
  }
}
```

The model and the DUT share one value type: a `sigref`/`peek` result, a `poke`
argument, and a `cpp` method's `Slop<N>` argument are the same bit-accurate
value. Because the C++ model and a Pyrope sub-block present the identical
flattened `Slop<N>` interface, either side can be swapped for the other without
touching the test — handy for bringing up a block against a reference and later
replacing the reference with the real RTL.

A `cpp` object is instantiated once per binding, so a stateful model (a
scoreboard accumulating across cycles, a memory model, an open trace file) keeps
its state in C++ for the life of the test — the same role an inline `if`-block
monitor (with its checker `mut`s) plays in Pyrope.

Everything here is debug-only and elided from synthesis, exactly like the rest
of this chapter; the synthesized netlist carries no C++ dependency. `cpp` is a
simulation-only build dependency. See
[External (C++) calls](07-typesystem.md#external-c-calls-via-cpp).


## Random stimulus

Pyrope already has `.[rand]` and `.[crand]` from
[Verification](05-assert.md#random). For many cocotb-style tests, that is
enough. Start with ordinary random values and filter them with normal Pyrope
control flow.

```pyrope
test random.opcodes {
  mut opcode:u4 = 0

  for i in 0..<100 {
    for _retry in 0..<64 {        // bounded retry: an unrolled loop, not `while true`
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
| `past[n:signed=1](x)` | past value | value of `x` `n` cycles ago; compiler inserts `n` flops |
| `next[n:signed=1](x)` | debug future peek | value of `x` `n` cycles ahead |
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

### Overriding defaulted inputs

User code can define small temporal helpers with defaulted inputs (see
[Functions](06-functions.md)). Defaults
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

* `spawn` / `join` / `cancel` (coroutine threads): a single `tick`/`step` loop
  with `if`-block tasks and `if`/`continue`/`break` covers the same use cases.
* `waitfor`: replaced by the `step` + `if not cond { continue }` idiom (the
  `tick N` bound is the timeout).
* `watch` / `unwatch`: an inline `if`-block monitor in the loop covers it.
* `log.info` / `log.warn` / `log.error`: existing `puts` and `print` are enough
  for the language core.
* `dump.start` / `dump.stop`: waveform capture fits better as a runner or tool
  option than as language syntax.
* A built-in constrained-random DSL: start with `.[rand]`, and add libraries
  only if they prove necessary.


## Summary of new constructs

| Construct | Context | Purpose |
|-----------|---------|---------|
| `tick N { }` | `test` only | Cycle-driven loop: run up to `N` cycles; one `step` (clock edge) per iteration. Waiting / concurrency / monitors are `if`-blocks inside it |
| `step [N]` | `test` only | Advance the clock one cycle (or `N`); the single yield point |
| `sig.[rising]` | debug only | True on a 0-to-1 transition (same as `rose(sig)`) |
| `sig.[falling]` | debug only | True on a 1-to-0 transition (same as `fell(sig)`) |
| `sig.[changed]` | debug only | True when value differs from previous cycle (same as `changed(sig)`) |
| `past[n](x)` | any context | Sample `x` at a past cycle (inserts `n` flops) |
| `next[n](x)` | debug only | Sample `x` at a future cycle |
| `rose[w](x)`, `fell[w](x)` | debug only | Windowed edge within range `w` |
| `stable[w](x)`, `changed[w](x)` | debug only | Windowed value-stability checks |
| `eventually[w](x)`, `always[w](x)` | debug only | Existence / universal quantifier over cycles in `w` |
| `force(path, val)` | `test` only | Override a signal persistently |
| `release(path)` | `test` only | Remove the override and restore the driver |
| `cpp("target")` | `test` only | Bind an external C++ model (golden model, scoreboard) |

Everything else in this chapter is built from existing Pyrope verification
constructs.
