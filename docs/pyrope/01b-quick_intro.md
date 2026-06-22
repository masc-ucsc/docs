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
const my_constant = 42      // immutable after assignment (NOT compile-time)
mut my_wire = 0             // combinational: no persistence across cycles
wire my_net = nil           // single-driver comb net; readable before its driver
reg my_state = 0            // register: persists across cycles; '= 0' is the RESET value
```

* `const` means immutable, **not** compile-time; `comptime` is an explicit
  prefix modifier (`comptime mut` is valid too). Identifier casing carries no
  meaning.
* `nil` means "no value yet" — reading it is a compile error; `reg x = nil`
  declares a register with no reset. Unknown bits (Verilog `x`) are written
  `0sb?` / `0ub10??01`. There is no bare `?` and no `_` default.
* No variable shadowing, anywhere. `;` is the same as a newline.* `wire` is one **combinational net with exactly one driver**; unlike `mut`
  it may be *read before* its driver appears textually (Verilog net /
  continuous-assign model). `wire x = nil` forward-declares an undriven net.
  A second unconditional driver, a never-driven net, or a self-feeding
  combinational loop are compile errors.

Details: [Variables and types](04-variables.md).

## One integer type

Integers are unlimited-precision and signed; everything else is a range
constraint on that one type. `u8` is the same as `signed(min=0, max=255)`,
`s4` is `signed(min=-8, max=7)`, and `unsigned` is `signed(min=0)`:

```pyrope
mut a:u8 = 100
mut b:signed(min=0, max=300) = 0
wrap a = a + 200       // narrowing must be annotated: wrap drops bits, sat saturates
```

* Booleans and integers never mix: `if x != 0 {}`, casts `signed(true)`,
  `boolean(v#[3])`. `and`/`or`/`not`/`implies` are boolean-only; `& | ^ ~`
  are bitwise integer ops.
* Precedence is shallow — parenthesize: `3 & (4*4)`, never `3 & 4*4`.
* An unannotated narrowing assignment is a compile error; prefix it with
  `wrap` or `sat`.

Details: [Basics](02-basics.md), [Variables and types](04-variables.md),
[Attributes](04b-attributes.md).

## Tuples are the core data structure

```pyrope
mut p = (mut x:u8 = 0, mut y:u8 = 0)   // named fields use a kind keyword
mut t = (1, 2, 3)                      // positional entries are bare values
mut arr = [1, 2, 3]                    // [] = array: all entries same type

cassert(p.x == 0)        // named access (also p['x'])
cassert(t[0] == 1)       // integer indices select positional entries ONLY
```

Named fields are unordered and name-access only — `t[0]` never aliases a
named field. `(...a, ...b)` concatenates (splice). A selector `[...]` takes one expression
(integer, string, range, or conditional).

Details: [Tuples](03-bundle.md), [Type system](07-typesystem.md).

## Lambdas (the only functions)

| kind | contract |
|------|----------|
| `comb` | Pure combinational, zero cycles. No `reg`. |
| `pipe[N]` | Fixed latency `N > 0`; never a combinational input→output path. |
| `mod` | No constraints; every output declares its landing cycle: `-> (x:u8@[2])`. |
| `fluid` | Transactional valid/retry handshakes (TBD: not yet implemented). |

```pyrope
comb add(a:u8, b:u8) -> (r:u9) { r = a + b }

pipe mul(a:u16, b:u16) -> (c:u32)  { c = a * b }
pipe acc(a:u32, b:u32) -> (c:u32)  { wrap c = a + b }

mod mac(in1:u16, in2:u16) -> (out:u32@[4]) {
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
* `init` is the only implicit hook (the constructor, a `comb`); there are no
  getter/setter hooks. Overload by gathering: `const add = [add1, add2]` — a
  call dispatches to the first gathered lambda that can accept it (same argument
  rules as a direct call), resolved at compile time.

Details: [Lambdas](06-functions.md), [Pipelining](06c-pipelining.md),
[Fluid](06d-fluid.md), [Instantiation](06b-instantiation.md).

## Registers and time

```pyrope
reg counter:u8 = 0            // '= 0' is the reset value (nil ⇒ no reset)
const q   = counter           // a bare name reads the current q value
counter += 1                  // write with plain =/+=; lands at the cycle boundary
const old = past[2](counter)  // value 2 cycles ago (inserts flops) (TBD)
```

Clock and reset are implicit; customize at the declaration:
`reg c:u8:[clock_pin=ref clk2, reset_pin=ref rst2, sync=false] = 3`
(`_pin` attributes connect wires, so they take `ref`; `sync=false` selects an
asynchronous reset). Memories are register arrays: `reg mem:[256]u32 = 0`.

Details: [Statements](05b-statements.md), [Attributes](04b-attributes.md),
[Memories](08-memories.md).

## Control flow

```pyrope
if cond { y = 1 } elif other { y = 2 } else { y = 3 }   // also an expression

match state {              // exactly one arm runs; `else` is MANDATORY
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
v#|[..]               // or-reduce (int 0/1); also #& #^ #+ (popcount)
t[0]                  // tuple/array element
out@[4]               // cycle typecheck (never inserts flops)
```

`#[]` is bits, `[]` is elements, `@[]` is cycles — never mix them.

Details: [Variables and types](04-variables.md#reduce-and-bit-selection-operators),
[Internals](10-internals.md).

## A complete example

```pyrope
enum State = (Idle, Run, Done)

mod fsm(start:bool, fin:bool) -> (busy:bool@[0]) {
  reg state:State = State.Idle
  busy = state == State.Run
  match state {
    == State.Idle { if start { state = State.Run  } }
    == State.Run  { if fin   { state = State.Done } }
    else          { state = State.Idle }
  }
}

test "fsm starts" {
  const f = fsm(start=true, fin=false)
  assert(not f.busy)     // q value: still Idle this cycle
  step
  const f2 = fsm(start=false, fin=false)
  assert(f2.busy)        // Run after one cycle
}
```

Details: [Verification](09-verification.md) for `test`/`step`/temporal
operators.

## Coming from Verilog

| Verilog | Pyrope |
|---------|--------|
| `module m(...)` | `mod m(...) -> (out:T@[N])` (or `pipe[N]`/`comb`) |
| `reg [7:0] x` + reset | `reg x:u8 = 0` |
| `reg [7:0] x` / procedural blocking `=` | `mut x:u8 = 0` |
| `wire [7:0] x` / continuous `assign` | `wire x:u8 = ...` (single-driver net) |
| `x <= y` (non-blocking) | `x = y` on a `reg` (registered write) |
| `parameter N = 8` | `comptime const N = 8` |
| `always @(posedge clk)` / `@(*)` | implicit — `reg` vs `mut` |
| `case ... endcase` | `match x { == v {...} else {...} }` |
| `x[6:3]` | `x#[3..=6]` |
| `{a, b}` concat | per-range LHS bit assigns into a typed destination |
| `4'b10x?` | `0ub10??` |
| tri-state / one-hot mux | `unique if` |
| testbench `initial` | `test "name" { ... step ... }` |

More: [Hardware design](00-hwdesign.md), [vs other languages](10b-vslang.md).

## Common pitfalls

1. `return X` is always wrong — assign the named output, then bare `return`.
2. Outputs must be named in `-> (...)`; the clause is mandatory (`-> ()` for
   none; only `self` methods may omit it).
3. `match` without a final `else` arm is a parse error.
4. `const` is not comptime; write `comptime` explicitly.
5. A `wire` has exactly one driver; read-before-driver is allowed but a
   second unconditional driver is a compile error.
6. `@[N]` never inserts flops; `stage[N]` does (`mod`-only). A `pipe` call
   needs `stage[N]` at the call site.
7. No bool/int mixing: `if 5 {}` is a type error — write `if 5 != 0 {}`.
8. Narrowing assignments need `wrap`/`sat`.
9. Loop bounds must be comptime (loops unroll). No runtime loops, no
   comprehensions.
10. `0b1010` is invalid — write `0ub1010`/`0sb1010`.
11. Integer `[]` indexing selects positional tuple entries only; named fields
    are name-access only.
12. Enum comparisons use names (`State.Idle`), never raw integers.

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
* [Internals](10-internals.md) / [LNAST](12-lnast.md) — compiler view
* [Standard library](13-stdlib.md) (TBD)
* [Implementation status](15-tbd.md) — documented features not yet
  implemented in LiveHD (marked "TBD" throughout the chapters)
