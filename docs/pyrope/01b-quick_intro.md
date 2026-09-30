# Quick Intro to Pyrope

Pyrope is a hardware description language: every construct elaborates to
wires, muxes, flops, and memories. This page is the working subset needed to
read and write correct Pyrope, with pointers to the chapters that explain
each topic in depth. If you read nothing else, read this and the
[pitfalls](#common-pitfalls) at the end.

## Declarations and storage kinds

Every declaration starts with a kind keyword — data: `const` / `mut` / `wire`
/ `reg`; lambda: `comb` / `pipe` / `mod` / `fluid` — and every data
declaration needs `= value`:

```pyrope
comptime const SIZE = 16    // compile-time constant (explicit `comptime`)
const my_constant = 42      // immutable; this value is known at compile time
mut my_wire = 0             // combinational: no persistence across cycles
wire my_net = nil           // single-driver comb net; readable before its driver
reg my_state = 0            // register: persists across cycles; '= 0' is the RESET value
```

* `const` means immutable; it does not require compile-time evaluation.
  The `comptime` prefix requires it (`comptime mut` is valid too), while
  ``.[`comptime`]`` checks whether the current value is known at compile time.
  Identifier casing carries no
  meaning, but the built-in type names (`U8`, `Bool`, ...) are reserved words.
* `nil` means "no value yet" — reading it is a compile error; `reg x = nil`
  declares a register with no reset. Unknown bits (Verilog `x`) are written
  `0sb?` / `0ub10??01`. There is no bare `?` and no `_` default.
* No variable shadowing, anywhere. `;` is the same as a newline.
* `wire` is one **combinational net with exactly one driver**; unlike `mut`
  it may be *read before* its driver appears textually (Verilog net /
  continuous-assign model). `wire x = nil` forward-declares an undriven net.
  A second unconditional driver, a never-driven net, a self-feeding
  combinational loop, or a write to a `wire` inside a loop body are compile
  errors (a loop body may read a `wire`).

Details: [Variables and types](04-variables.md).

## One integer type

Integers are unlimited-precision and signed; everything else is a range
constraint on that one type. `U8` is the same as `Signed(min=0, max=255)`,
`S4` is `Signed(min=-8, max=7)`, and `Unsigned` is `Signed(min=0)`:

```pyrope
mut a:U8 = 100
mut b:Signed(min=0, max=300) = 0
wrap a = a + 200       // narrowing must be annotated: wrap drops bits, sat saturates
```

* Booleans and integers never mix: `if x != 0 {}`. Convert explicitly:
  `U1(flag)` for bool->bit (true == 1), `Bool(v#[3])` or `v#[3] == 1` for
  bit->bool (`Signed(true) == -1` is a reinterpretation, not the idiom).
  `and`/`or`/`not`/`implies` are boolean-only; `& | ^ ~` are bitwise integer
  ops.
* `Bool` is legal on every port, top level included (a 1-bit port). The
  no-mixing rule holds at the boundary too: bind with
  `const d = dut(go=Bool(v#[0]))`, then read `U1(d.flag)`.
* Precedence is shallow — parenthesize: `3 & (4*4)`, never `3 & 4*4`.
* An unannotated narrowing assignment is a compile error; prefix it with
  `wrap` or `sat`. Argument binding follows the same rule: a `U16` into
  `a:U4` is an error, so slice it (`f(a=x#[0..<4])`).
* Built-in types are capitalized: `U<num>`/`S<num>` (`S32`; there is no
  `I32`), `Unsigned`, `Signed`, `Bool`, `String`, `Clock`, `Reset`. A width
  from a comptime value is `Unsigned(bits=N)`/`Signed(bits=N)`. The old
  lowercase spellings (`u8`, `bool`, `signed`, ...) are banned words: a
  compile error in every position, names included (`s1`, `i0`, `u4` are not
  legal variable names). A variable spelled like a type word or a banned word
  must be backticked (`` `U4` ``, `` `u4` ``).

Details: [Basics](02-basics.md), [Variables and types](04-variables.md),
[Attributes](04b-attributes.md).

## Tuples are the core data structure

```pyrope
mut p = (mut x:U8 = 0, mut y:U8 = 0)   // named fields use a kind keyword
mut t = (1, 2, 3)                      // positional entries are bare values
mut arr = [1, 2, 3]                    // [] = array: all entries same type

cassert(p.x == 0)        // named access (also p['x'])
cassert(t[0] == 1)       // integer indices select positional entries ONLY
```

A tuple is either **all named** or **all unnamed**; mixing named and unnamed
entries in one tuple is a compile error. Named fields are unordered and
name-access only (`p.x`, never `p[0]`); unnamed entries are positional only
(`t[0]`). `(...a, ...b)` concatenates (splice): two unnamed tuples append, two
named tuples merge (a field on both sides is an error), and splicing a named
with an unnamed tuple is an error. A selector `[...]` takes one expression
(integer, string, range, or conditional).

Details: [Tuples](03-bundle.md), [Type system](07-typesystem.md).

## Lambdas (the only functions)

| kind | contract |
|------|----------|
| `comb` | Pure combinational, zero cycles. No `reg`. |
| `pipe[N]` | Fixed latency `N > 0`; never a combinational input→output path. |
| `mod` | No constraints; every output declares its landing cycle: `-> (x:U8@[2])`. |
| `fluid` | Transactional valid/retry handshakes (TBD: not yet implemented). |

```pyrope
comb add(a:U8, b:U8) -> (r:U9) { r = a + b }

pipe mul(a:U16, b:U16) -> (c:U32)  { c = a * b }
pipe acc(a:U32, b:U32) -> (c:U32)  { wrap c = a + b }

mod mac(in1:U16, in2:U16) -> (out:U32@[4]) {
  stage[3] tmp     = mul(a=in1, b=in2)            // pipe call: 3 stages
  stage[3] in1_d   = in1                          // pure 3-cycle delay
  stage[1] out@[4] = acc(a=tmp@[3], b=in1_d@[3])  // alignments typechecked
}
```

* Outputs are always declared **by name** in `-> (...)`; the body assigns
  them. **`return` is a terminator only** — `return X` is a syntax error.
* Name your call arguments (`f(a=1, b=2)`); parentheses always (`noarg()`).
* UFCS `x.f(args)` works only when `f` declares `self` first; `ref self`
  needs a `mut` receiver. `ref` is written at declaration **and** call.
  Callable tuple fields are independent of external names and need not declare
  `self`. A callable field plus a matching external `self` function makes the
  dotted call ambiguous and is an error.
* `init` is the only implicit hook (the constructor, a `comb`); there are no
  getter/setter hooks. Overload by gathering: `const add = [add1, add2]` — a
  call dispatches to the first gathered lambda that can accept it (same argument
  rules as a direct call), resolved at compile time.

Details: [Lambdas](06-functions.md), [Pipelining](06c-pipelining.md),
[Fluid](06d-fluid.md), [Instantiation](06b-instantiation.md).

## Registers and time

```pyrope
reg counter:U8 = 0            // '= 0' is the reset value (nil ⇒ no reset)
const q   = counter           // a bare name reads the current q value
wrap counter += 1             // write with =/+= (wrap: U8 narrows); lands at the cycle boundary
const old = past[2](counter)  // pipelined 2 cycles (inserts 2 flops)
```

Clock and reset bind by **type**, not by name. A `mod`'s clock is its single
`Clock` input and its reset its single `Reset` input, whatever they are
called, and registers bind to them implicitly. A module with registers and no
`Clock` (or `Reset`) input gets one minted, `clock:Clock` (or `reset:Reset`);
a non-`Clock` input already named `clock` (a non-`Reset` one named `reset`) is
then a compile error. With two or more `Clock` (or `Reset`) inputs, every
register names its own:
`reg c:U8:[clock_pin=clk2, reset_pin=rst2, async=true] = 3`
(a `_pin` takes the signal directly, no `ref`; `async=true` selects an
asynchronous reset). A reset is active-high unless `negreset=true`; the name
(`rst_n`) means nothing. A `Clock` is not data: it only drives clock pins,
`Clock` ports, or a `Clock_cell` (clock gating), is never bound to a constant,
and `U1(clk)` is an error; its simulation cycle count is readable only in
tests, `puts`, and `assert`/`cassert`. A `Reset` is Bool-like: it can be computed
(`rst or soft_rst`), and `false` means no reset. An instance's unbound
`Clock`/`Reset` input is wired to the caller's single one (two or more in the
caller: bind it explicitly). A `comb` has no `Clock`/`Reset` inputs. Memories
are register arrays: `reg mem:[256]U32 = 0`.

```pyrope
mod cnt(c:Clock, r:Reset, en:Bool) -> (q:U8@[0]) {
  reg n:U8 = 0                // clocked by `c`, reset by `r`: bound by type
  if en { wrap n += 1 }
  q = n
}
```

Details: [Statements](05b-statements.md), [Attributes](04b-attributes.md),
[Implicit clock and reset](04b-attributes.md#implicit-clock-and-reset),
[Memories](08-memories.md).

## Control flow

```pyrope
if cond { y = 1 } elif other { y = 2 } else { y = 3 }   // also an expression

match state {              // exactly one arm runs; `else` may be omitted only if the arms are exhaustive
  == State.Idle { if start { state = State.Run } }
  else          { state = State.Idle }
}

for i in 0..<N { acc += f(i) }   // loops fully unroll: bounds must be comptime
```

* `unique if` asserts mutually exclusive conditions (one-hot mux; replaces
  tri-state).
* There are no `when`/`unless` trailing gates and no runtime-bounded loops.
* Ranges: `0..=7` (inclusive), `0..<8` (exclusive), `2..+3` (size-based).

Details: [Statements](05b-statements.md), [Assertions](05-assert.md).

## Bits vs elements vs cycles

```pyrope
v#[3]                 // bit 3          v#[1..=4]  // bit slice
v#sext[0..=2]         // sign-extended slice
v#|[..]               // or-reduce (integer 0/1); also #& #^ #+ (popcount)
t[0]                  // tuple/array element
out@[4]               // cycle typecheck (never inserts flops)
```

`#[]` is bits, `[]` is elements, `@[]` is cycles — never mix them.

Details: [Variables and types](04-variables.md#reduce-and-bit-selection-operators),
[Internals](10-internals.md).

## A complete example

```pyrope
enum State = (Idle, Run, Done)

mod fsm(start:Bool, fin:Bool) -> (busy:Bool@[0]) {
  reg state:State = State.Idle
  busy = state == State.Run
  match state {
    == State.Idle { if start { state = State.Run  } }
    == State.Run  { if fin   { state = State.Done } }
    else          { state = State.Idle }
  }
}

test fsm.start {
  mut f = fsm              // one persistent instance, reset on declaration
  tick 1 {                 // one cycle; the tick mints `clock:Clock` for `f`
    f.start = true
    f.fin   = false
    assert(not f.busy)     // q value: still Idle this cycle
    step                   // the clock edge
    assert(f.busy)         // Run after one cycle
  }
}
```

Details: [Verification](09-verification.md) for `test`/`step`/temporal
operators, [Running cycles](05b-statements.md#running-cycles-tick) for `tick`.

## Coming from Verilog

| Verilog | Pyrope |
|---------|--------|
| `module m(...)` | `mod m(...) -> (out:T@[N])` (or `pipe[N]`/`comb`) |
| `reg [7:0] x` + reset | `reg x:U8 = 0` |
| `reg [7:0] x` / procedural blocking `=` | `mut x:U8 = 0` |
| `wire [7:0] x` / continuous `assign` | `wire x:U8 = ...` (single-driver net) |
| `x <= y` (non-blocking) | `x = y` on a `reg` (registered write) |
| `parameter N = 8` | `comptime const N = 8` |
| `input clk, rst` | `clk:Clock, rst:Reset` inputs (bound by type) |
| `always @(posedge clk)` / `@(*)` | implicit — `reg` vs `mut` |
| `case ... endcase` | `match x { == v {...} else {...} }` |
| `x[6:3]` | `x#[3..=6]` |
| `{a, b}` concat | `(b, a)#[..]` — entry 0 lands in the LOW bits, so the order reverses |
| `4'b10x?` | `0ub10??` |
| tri-state / one-hot mux | `unique if` |
| testbench `initial` | `test name { ... step ... }` |

More: [Hardware design](00-hwdesign.md), [vs other languages](10b-vslang.md).

## Common pitfalls

1. `return X` is always wrong — assign the named output, then bare `return`.
2. Outputs must be named in `-> (...)`; the clause is mandatory (`-> ()` for
   none; only `self` methods may omit it).
3. A `match` needs a final `else` arm unless its arms cover every selector
   value; an omitted `else` is an unreachable don't-care, not a hold.
4. `const` requires immutability; `comptime` requires compile-time evaluation.
5. A `wire` has exactly one driver; read-before-driver is allowed but a
   second unconditional driver is a compile error. A loop body may read a
   `wire` but not write it.
6. `@[N]` never inserts flops; `stage[N]` does (`mod`-only). A `pipe` call
   needs `stage[N]` at the call site.
7. No bool/integer mixing: `if 5 {}` is a type error — write `if 5 != 0 {}`.
   Bool->bit is `U1(flag)`, not `Signed(flag)` (which is `-1` for true).
8. Narrowing assignments need `wrap`/`sat`.
9. Loop bounds must be comptime (loops unroll). No runtime loops, no
   comprehensions.
10. `0b1010` is invalid — write `0ub1010`/`0sb1010`.
11. A packed tuple reads left-to-right as low-to-high bits: `(a, b)#[..]` puts
    `a` in the LOW bits, the reverse of Verilog's `{a, b}`.
12. A tuple is all named or all unnamed, never mixed. Integer `[]` indexing
    selects entries of an unnamed tuple only; named fields are name-access
    only.
13. Enum comparisons use names (`State.Idle`), never raw integers.
14. Built-in types are capitalized (`U8`, `S4`, `Bool`, `String`); `u8`,
    `bool`, and `i32` are compile errors, also as names (`mut s1` is an error).
15. A clock is a `Clock` input and a reset a `Reset` input; an input named
    `clk` or `rst` of another type is plain data. Reset polarity comes only
    from `negreset=true`, never from an `_n` name.

## Where to go next

* [Hardware design mindset](00-hwdesign.md) — why HDLs differ from software
* [Basics](02-basics.md) — literals, operators, comments
* [Tuples](03-bundle.md) — the core data structure, enums
* [Variables and types](04-variables.md) / [Attributes](04b-attributes.md)
* [Assertions](05-assert.md) / [Statements](05b-statements.md)
* [Lambdas](06-functions.md) / [Instantiation](06b-instantiation.md) /
  [Pipelining](06c-pipelining.md) / [Fluid](06d-fluid.md)
* [Type system](07-typesystem.md) / [Struct types](07b-structtype.md)
* [Memories](08-memories.md) — arrays, SRAMs, `__memory`, `regref`
* [Verification](09-verification.md) — tests, temporal library
* [Querying a simulation](09b-simquery.md) — inspect a run with `lhd sim --query`
* [Internals](10-internals.md) / [LNAST](12-lnast.md) — compiler view
* [Standard library](13-stdlib.md) (TBD)
* [Implementation status](15-tbd.md) — documented features not yet
  implemented in LiveHD (marked "TBD" throughout the chapters)
