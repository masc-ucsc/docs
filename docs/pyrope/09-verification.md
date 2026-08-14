# Extended Verification

!!! WARNING "TBD"
    What *runs today* (`lhd sim`) is the single-clock, single-threaded
    simulation form: a `test name { ... }` block declares the DUT as an instance
    (`mut acc = dut`), and a bounded `tick N { ... }` loop drives it with field
    writes (`acc.x = v`, or a `regref` bound once), advances the clock with an
    explicit `step`, reads outputs/registers (`acc.y`, or a `sigref`), and checks
    with `assert` — see
    [Running cycles](05b-statements.md#running-cycles-tick) (and `newtick.md` in
    the LiveHD repo). Waiting and concurrency are expressed *in that one loop*
    with ordinary `if`/`continue`/`break` (below) — there is no separate
    coroutine layer. Dotted test names, runtime `(...)` test parameters, and the
    dotted and string-path forms of
    [`sigref`/`regref`](05b-statements.md#test-only-statements) all work today;
    `peek`/`poke` are **removed** in favor of that pair. Still not implemented: the whole [temporal library](#temporal-library)
    below (`past`/`rose`/`fell`/`stable`/`changed`/`eventually`/`always` — only
    the pipelining form `past[N](x)` exists, and only in a design body), the
    `force`/`release`. `for` loops, `.[rand]` and `.[crand]` are rejected
    inside a `test` block. See
    [Implementation status](15-tbd.md).

To INSPECT a run after the fact — read a signal at a cycle, count transitions,
find the cycle a condition first held — see
[Querying a simulation](09b-simquery.md), which is landed and needs no new
language syntax.

This chapter extends [Verification](05-assert.md) for interactive testbench
work. The target is the cocotb style of "drive, wait, sample, score", but with
as little new syntax as possible — and, unlike cocotb, **without coroutines**: a
test is one `tick`/`step` loop, and stimulus, waiting, and monitors are just
`if`-blocks inside it.

The design rules are:

* Reuse existing `test`, `tick`, `step`, and `assert`; express waiting
  and concurrency with `if`/`continue`/`break`, not new statement families.
* Prefer temporal reads such as `rose(sig)` over new wait primitives.
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
| `dut.sig.value = x` | `acc.sig = x`, or `regref(acc.sig)` bound once |
| `dut.sig.value` | `acc.sig`, or `sigref(acc.sig)` bound once |
| `dut._id(...)` cached handle | `const h = sigref(acc.core0.count)` — bound outside the loop, valid for the run |
| `await RisingEdge(dut.valid)` | `step; if not rose(acc.valid) { continue }` (TBD) |
| `await FallingEdge(dut.ready)` | `step; if not fell(acc.ready) { continue }` (TBD) |
| `await Edge(dut.sig)` | `step; if not changed(acc.sig) { continue }` (TBD) |
| `await Timer(5 cycles)` | `step 5` |
| `while True: await ...` (driver/monitor) | the `tick N { ... step ... }` loop itself |
| `@cocotb.test(timeout_time=N)` | `tick N { ... }` (the bound is the timeout) |
| `cocotb.start_soon(coro())` / `await t` / `task.cancel()` | no threads — interleave each "task" as an `if`-block in the one `tick` loop |
| `Force` / `Release` | `force(dut.block.signal, value)` / `release(dut.block.signal)` |
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

The DUT reads above the `step` (`dut.full`, `dut.empty`, `dut.dout`) are the
values the previous `step` settled — which is exactly what flow control wants
from a FIFO whose `full`/`empty`/`dout` are register outputs. Reading back
`dut.push` is likewise always the value just written, since an input port is a
single cell. But if one of those outputs were driven *combinationally* by
`push`/`pop`, the pre-`step` read would not see this iteration's drive; move such
a read below the `step`.


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

The condition can be any boolean, including an edge read from the
[temporal library](#temporal-library) — `rose(sig)`, `fell(sig)`,
`changed(sig)`. These are the single-cycle case of the windowed forms and work
anywhere a boolean is expected: a wait's `if` or an `assert`.

```pyrope
test edge.checks {
  mut dut = Top
  tick 64 {
    step
    assert(not rose(dut.clk_en), "unexpected clock enable")   // TBD
  }
}
```

!!! NOTE "Not implemented"
    There is no attribute spelling of these. `sig.[rising]`, `sig.[falling]`,
    `sig.[changed]` and `sig.[stable]` are **not** recognized attributes — they
    produce the same "no hardware lowering" error as any misspelled attribute.
    The function forms above are the intended surface, and they are TBD too.


## Force and release

!!! WARNING "Not implemented"
    `force` and `release` are TBD; the example below does not compile today.

A `regref` write lands in the storage immediately but takes effect only at the
next `step`, and on a register it drives `q` — which the design's own logic uses
for that cycle before the edge replaces it with the computed `din`. So it is a
one-shot override: re-writing it every `tick` iteration fully controls the cell,
but it does not persist on its own. `force` and `release` are the persistent
counterpart, and differ on both axes — they override `q` and they survive edges
until released:

* `force(signal, value)` overrides the signal until released.
* `release(signal)` removes the override and restores the normal driver.

```pyrope
test fault.inject {
  mut dut = Top

  assert(!dut.mem.error)

  force(dut.mem.error, true)
  step 3
  assert(dut.core.exception)

  release(dut.mem.error)
  step
  assert(!dut.mem.error)
}
```

`force` and `release` are debug-only. Their signal operands use the same direct
instance hierarchy as ordinary test reads and writes. Forcing a register
overrides the visible `q` value, not the internal `d` calculation.

They are **complementary to `regref`, not redundant with it**. A `regref` write
is consumed by one edge and the design's own `d` computation resumes
immediately after; a `force` keeps being re-applied after every edge, which a
plain reference into storage cannot express, and `release` restores the real
driver with no cycle of latency.


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
    if rose(dut.req) { outstanding = outstanding + 1 }   // TBD: rose()
    if rose(dut.ack) {
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

!!! WARNING "Not implemented"
    `cpp(...)` is TBD, and a `for` loop is not a supported statement inside a
    `test` block, so the example below does not run today.

A `test name { }` block generates the simulation to run (the slop/sim), so a
golden model or scoreboard written in C++ plugs straight into it. Reach the C++
with [`cpp`](07-typesystem.md#external-c-calls-via-cpp) and call its typed
methods like any other lambda:

```pyrope
type GcdModel = ( call_method1: comb(a:u8, b:u3) -> (foo:u8, bar:u33) )
const gold:GcdModel = cpp("gcd_model")

test gcd.check {
  mut dut = Gcd
  for a in 1..=100 {
    dut.a = a
    dut.b = 3
    step
    const (foo, _bar) = gold.call_method1(a=a, b=3)
    assert(dut.z == foo)                 // DUT checked against the C++ reference
  }
}
```

The model and the DUT share one value type: a value read from or written to a
DUT field and a `cpp` method's `Slop<N>` argument are the same bit-accurate
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

!!! WARNING "Not implemented"
    `.[rand]`/`.[crand]` and `for` loops are both rejected inside a `test`
    block today, so the example below does not run. See
    [Random](05-assert.md#random).

The intent is that `.[rand]` and `.[crand]` cover most cocotb-style stimulus:
start with ordinary random values and filter them with normal Pyrope control
flow.

```pyrope
test random.opcodes {
  mut dut = Top
  mut opcode:u4 = 0

  for i in 0..<100 {
    for _retry in 0..<64 {        // bounded retry: an unrolled loop, not `while true`
      opcode = opcode.[rand]
      if opcode <= 10 { break }
    }

    dut.opcode = opcode
    step
  }
}
```

If solver-backed constrained random is needed later, it should preferably be a
library layer on top of this style instead of a large new statement family in
the core language.


## Temporal library

SVA-style sampling over time. Every cycle argument is an ordinary **positional
argument** — Pyrope has no comptime-parameter slot on a call, so there is no
`f[N](x)` bracket form.

!!! WARNING "Not implemented"
    Nothing in this section works today. It is the agreed target surface, kept
    here so the syntax is settled before the implementation lands. The only
    temporal construct that exists is the *pipelining* `past[N](x)`
    ([Pipelining](06c-pipelining.md)), which is a different operator — it
    shifts the landing cycle rather than sampling history, so it cannot be
    compared against a present-cycle value. `lhd formal verify` rejects any of
    the calls below with an explicit "not implemented" diagnostic rather than
    attempting an unsound proof.

```pyrope
past(x)             // x one cycle ago
past(x, 3)          // x three cycles ago
rose(x)             // x became true this cycle
fell(x)             // x became false this cycle
stable(x)           // x is unchanged from last cycle
changed(x)          // x differs from last cycle
```

### Builtins

| Builtin | Meaning |
|---------|---------|
| `past(x [, n=1])` | value of `x` `n` cycles ago |
| `rose(x [, w])` | `x` becomes true — this cycle, or at some cycle in window `w` |
| `fell(x [, w])` | `x` becomes false — this cycle, or at some cycle in `w` |
| `stable(x [, w])` | `x` holds its value — since last cycle, or across `w` |
| `changed(x [, w])` | `x` differs from its prior value — this cycle, or at some cycle in `w` |
| `eventually(x, w)` | `x` is true at some cycle in window `w` |
| `always(x, w)` | `x` is true at every cycle in window `w` |

`rose`, `fell`, `stable` and `changed` are sugar over `past`:
`rose(x)` is `x and not past(x)`, `stable(x)` is `x == past(x)`, and so on.

Two rules make these tractable:

* They are **history sampling, not pipelining.** `past(x, n)` does not move the
  expression's cycle, so `assert(past(x) == x)` is well typed. (The pipelining
  `past[N]` does move it, which is why the two are separate operators.)
* A window `w` is a **bounded** range such as `1..=10`. Inside a `formal` block
  the engine resolves the whole family by indexing the bounded-model unrolling —
  `past(x, n)` at cycle `c` is the cycle-`c−n` value, and a window expands to an
  OR (`eventually`, `rose`) or an AND (`always`, `stable`) over its cycles. No
  auxiliary state is created. An obligation using `past(x, n)` is simply not
  checked before cycle `n`, where no history exists.

Unbounded liveness ("eventually, with no deadline") is **out of scope**: the
engine is a bounded ladder plus single-step induction, with no lasso detection.
A window is always required for `eventually` and `always`.

`sampled` and `next` from SVA are deliberately absent. `$sampled` describes
event-driven clock-domain sampling, which a per-cycle model already implies;
`next` cannot be observed by hardware and would only ever mean "look ahead
inside the bound".

### SVA comparison

A standard SVA implication assertion:

```systemverilog
assert property (@(posedge clk) $rose(req) |-> ##[1:10] $rose(ack));
```

is intended to translate as:

```pyrope
assert(rose(req) implies rose(ack, 1..=10))
```

More examples (all TBD):

```pyrope
// payload stable during a 5-cycle handshake window
assert(req implies stable(payload, 1..=5))

// ack must rise within 32 cycles of req
assert(rose(req) implies eventually(ack, 1..=32))

// grant is clean-high while sel is held
assert(sel implies always(grant, 1..=10))

// past values
assert(enable implies counter == past(counter) + 1)
assert(x == past(x, 3))          // same value three cycles ago
```

These are properties over time, so they belong in a
[`formal` block](05-assert.md#formal-blocks), which is the only context where
they can be *proven*. A `test` block only simulates them on the traces it
happens to drive.


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

| Construct | Context | Status | Purpose |
|-----------|---------|--------|---------|
| `tick N { }` | `test` only | works | Cycle-driven loop: run up to `N` cycles; one `step` (clock edge) per iteration. Waiting / concurrency / monitors are `if`-blocks inside it |
| `step [N]` | `test` only | works | Advance the clock one cycle (or `N`); the single yield point. One `step` is settle → commit → settle |
| `sigref(x)` | `test` only | works | Bind a read-only window onto a storage cell (register, memory word, module input/output); bound once outside the loop, valid for the run |
| `regref(x)` | `test` only | works | Bind a writable window. The write takes effect at the next `step`; on a register it drives `q` for one cycle |
| `past(x [, n])` | `formal`, `test` | TBD | Sample `x` `n` cycles ago (history, not a pipeline stage) |
| `rose(x [, w])`, `fell(x [, w])` | `formal`, `test` | TBD | Edge, this cycle or within window `w` |
| `stable(x [, w])`, `changed(x [, w])` | `formal`, `test` | TBD | Value-stability, this cycle or across `w` |
| `eventually(x, w)`, `always(x, w)` | `formal`, `test` | TBD | Existence / universal quantifier over the cycles in bounded window `w` |
| `force(signal, val)` | `test` only | TBD | Override a signal persistently: overrides `q` and survives edges — see [Force and release](#force-and-release) for how it differs from a `regref` write |
| `release(signal)` | `test` only | TBD | Remove the override and restore the driver |
| `cpp("target")` | `test` only | TBD | Bind an external C++ model (golden model, scoreboard) |

Everything else in this chapter is built from existing Pyrope verification
constructs. Note that the *pipelining* `past[N](x)`
([Pipelining](06c-pipelining.md)) is a different operator from the verification
`past(x, n)` above: it shifts the expression's landing cycle, so it cannot be
compared against a present-cycle value.
