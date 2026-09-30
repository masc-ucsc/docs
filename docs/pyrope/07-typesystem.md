# Type system

Type system assign types for each variable (type synthesis) and check that each
variable use/expression respects the allowed types (type check). Additionally, a
language can also use the type synthesis results to implement polymorphism.


Most HDLs do not have modern type systems, but they could benefit like in other
software domains. Unlike software, in the hardware, we do not need to have many integer
sizes because hardware can implement any size. This simplifies the type system
allowing unlimited precision integers but it needs a bitwidth inference mechanism.


Additionally, in hardware, it makes sense to have different implementations that
adjust for performance/constraints like size, area, FPGA/ASIC. Type systems
could help in these areas.


## Built-in types

The built-in type names are capitalized:

* `U<N>`: unsigned integer of `N` bits, for any literal width (`U1`, `U8`, `U32`, `U1333`)
* `S<N>`: signed integer of `N` bits (`S4`, `S20`)
* `Unsigned` / `Signed`: unsigned/signed integer, optionally constrained
  (`Unsigned(bits=N)`, `Unsigned(max=.., min=..)`, `Signed(bits=N)`), see
  [Bitwidth](#bitwidth)
* `Bool`: `true` or `false`, or an unknown comparison result (`0sb?`); see
  [Boolean](04-variables.md#boolean)
* `String`: text (see [Strings](02-basics.md#strings))
* `Clock` / `Reset`: the clock and reset wires of registers, see
  [Clock and Reset](#clock-and-reset)

The type name is also the cast: `U1(flag)`, `U8(x)`, `S8(x)`, `Unsigned(x)`,
`Signed(x)`, `Bool(x)`, `String(x)` (see [Bitwidth](#bitwidth) for the
reinterpretation rules).

There are no aliases. The lowercase spellings and the `I<N>` integers (use
`S<N>`) are gone, and the old spellings are banned words: `u`, `s`, or `i`
followed by digits (`u8`, `s20`, `i32`), `bool`, `boolean`, `unsigned`,
`signed`, and `string`. Using one anywhere (a type, a cast, a variable,
lambda, parameter, or field name) is a compile error whose diagnostic names
the new spelling (`` `u8` was renamed `U8` ``), so `s1`, `i0`, and `u4` are
not legal names. A backticked banned word (`` `u4` ``) is an ordinary name.

`U<N>`, `S<N>`, `Unsigned`, `Signed`, `Bool`, `String`, `Clock`, and `Reset`
are reserved type words, where `U<N>`/`S<N>` is `U` or `S` followed by any
digit string (`U0`, `U1333`, `S99999999`). They can not be declared or used
as a variable, port, parameter, lambda, or field name, not even after a `.`
(`foo.U33` is an error). A name with that spelling must be backticked
(`` `U4` ``, `` foo.`U33` ``), and a backticked reserved word is an ordinary
name, never the type, in every position (see
[Identifiers](02-basics.md#identifiers)).

A type word may head a suffix chain: `U8.[max]` reads an attribute of the type,
and `U8(x)#[0]` bit-selects the cast result. A type has no fields, so `U8.x` is
a compile error.

```pyrope
cassert(U8.[max] == 255 and S4.[min] == -8)

mut x:U8 = 0x0F
cassert(U8(x)#[0] == 1)

mut cnt4 = 3
const `U4` = cnt4 + 1       // backticked: a name, not the type
mut y:U4 = `U4`
const `u4` = 2              // backticked banned word: an ordinary name

mut z:u8 = 0                // error: `u8` was renamed `U8`
mut u4 = 3                  // error: `u4` is a banned old spelling (now `U4`)
const U4 = 3                // error: 'U4' is a reserved type word
const f = U8.x              // error: a type has no fields
```

### Clock and Reset

`Clock` and `Reset` bind by type, not by name. A `mod`/`pipe` input typed
`Clock` (`c:Clock`) is a clock and an input typed `Reset` (`r:Reset`) is a
reset, whatever the port is called. The name carries no meaning: an input
called `clk` or `rst` that is not typed `Clock`/`Reset` is plain data, and a
`_n` suffix does not make a reset active-low (only `negreset=true` does).
Registers bind to the module's single `Clock`/`Reset` input, a module with
registers and none gets `` `clock`:Clock``/`` `reset`:Reset`` minted, two or more need
`clock_pin=x`/`reset_pin=x` (no `ref`), instances auto-wire their unbound
`Clock`/`Reset` inputs, and a `comb` has no `Clock`/`Reset` inputs: the
binding rules are in
[Implicit clock and reset](04b-attributes.md#implicit-clock-and-reset).

`Clock` and `Reset` are distinct basic types (`Clock does Bool` is false).

A `Clock` is not data. In synthesis and LEC it is a 1-bit signal; in
simulation it counts cycles (its rising edges, one counter per `Clock`
input). That numeric view is legal only in debug contexts (`test` blocks,
`puts`, `assert`/`cassert`). In synthesizable logic a `Clock` may only drive
a clock pin, a `Clock_cell` (clock gating with an `en` enable), or another
`Clock` port: arithmetic on it or a conversion such as `U1(clk)` is a compile
error. A `Clock` is never bound to a constant and never modified except
through a `Clock_cell`; there are no derived clocks or clock muxes (use
enables). A `Clock_cell` is written as a `Clock` construction with named
arguments, `Clock(clock_pin=clk, enable=en)`: an ICG whose result is a gated
`Clock` (the one-argument `Clock(x)` is not a cast). A test passes a real
`Clock` to its design, never a constant (`clk=1`): each `tick` block has a
minted `` `clock`:Clock`` that counts the tick's cycles from 0 (see
[Running cycles](05b-statements.md#running-cycles-tick)).

A `Reset` is Bool-like: it can be computed (`rst or soft_rst`, a
synchronizer), the constant `false` means no reset, and a `Bool` expression
is assigned or bound to a `Reset` without a cast (``acc.`reset` = `clock` < 2`` in a
test).

```pyrope
mod cnt8(c:Clock, r:Reset, en:Bool) -> (q:U8@[0]) {
  reg cnt:U8 = 0                         // clocked by 'c', reset by 'r'
  if en { wrap cnt = cnt + 1 }
  q = cnt
  puts("cycle {c}: cnt={cnt}")           // OK: debug-only cycle count of 'c'
}

mod two_clk(clk_a:Clock, clk_b:Clock, rst:Reset, a:U8, b:U8) -> (qa:U8@[0], qb:U8@[0]) {
  reg ra:U8:[clock_pin=clk_a] = 0        // two Clock inputs: name the clock
  reg rb:U8:[clock_pin=clk_b] = 0        // one Reset input: 'rst' is implicit
  reg rc:U8 = 0                          // error: two Clock inputs, 'rc' needs clock_pin
  if a != 0 { ra = a }
  if b != 0 { rb = b }
  qa = ra
  qb = rb + clk_a                        // error: a Clock is not a number
  const bit = U1(clk_b)                  // error: a Clock is not data
}

comb gated(c:Clock, a:U8) -> (y:U8) { y = a } // error: a comb has no Clock input

mod gate_en(clk:Clock, en:Bool, d:U8) -> (q:U8@[1]) {
  const gclk = Clock(clock_pin=clk, enable=en) // a Clock_cell: clk gated by en
  reg r::[clock_pin=gclk] = 0                  // loads only on cycles where en is high
  r = d
  q = r
}
```


## Types vs `cassert`

To understand the type check, it is useful to see an equivalent `casser`
translation. The type system has two components: type synthesis and type check.
The type check can be understood as a `cassert`.


After type synthesis, each variable has an associated type. Pyrope checks that
for each each assignment, the left-hand side (LHS) has a compatible type with
the right-hand side (RHS) of the expression. Additional type checks happen when
variables have a type check explicitly set (`variable:type`) in the rhs expression.


Although the type system is not implemented with asserts, it is an equivalent
way to understand the type system "check" behavior.  Although it is possible to
declare just the `cassert` for type checks, the recommendation is to
use the explicit Pyrope type syntax because it is more readable and easier to
optimize.


=== "Snippet with declaration-site types"

    ```pyrope
    mut b = "hello"

    mut a:U32 = 0

    a += 1

    a = b                       // incorrect (b is String)


    mut dest:U32 = 0
    mut foo:U16 = 0
    mut v:U8   = 0

    dest = foo + v              // types come from the declarations
    ```

=== "Snippet with comptime assert"

    ```pyrope
    mut b = "hello"

    mut a:U32 = 0

    a += 1
    cassert(a does U32)
    a = b                       // incorrect
    cassert(b does U32) // fails

    mut dest:U32 = 0
    mut foo:U16 = 0
    mut v:U8   = 0
    cassert((dest does U32) and (foo does U16) and (v does U8))
    dest = foo + v
    ```


## Building types

Each variable can be a basic type. In addition, each variable can have a set of
constraints from the type system. Pyrope type system constructs to handle types:

* `mut` and `const` allows declaring types.

* `a does b`: Checks 'a' is a superset or equal to 'b'. In the future, the
  Unicode character "\u{2287}" could be used as an alternative to `does` (`a`
&#8839 `b`).

* `a:b` binds variable `a` to type `b`. It is **only** allowed at
  declaration sites (`mut`/`reg`/`const`/`comb`/`pipe`/`mod`, lambda
  parameters and return types, and tuple field declarations). To check
  that an existing value has type `b`, use `a does b`. To
  convert a value to type `b`, call the type as a constructor: `b(a)`.

* `a equals b`: Checks that `a does b` and `b does a`. Effectively checking
  that they have the same type. Notice that this is not like checking for
  logical equivalence, just type equivalence.

```pyrope
const t1 = (const a:Signed=1, const b:String = "")
const t2 = (const a:Signed=100, const b:String = "")
mut v1 = (const a=33, const b="hello")

comb f1() -> (a:Signed, b:String) {
  a = 33
  b = "hello"
}

cassert(t1 equals t2)
cassert(t1 equals v1)
cassert(f1() equals t1)
cassert(not (f1 equals t1))
cassert(t1 equals t2)
```


`equals` and `does` check for types. Sometimes, the type can have a function
call and you do not want to call it. The solution in this case is to use the
`:type` to avoid the function call.


Since the `puts` command understands types, it can be used on any variable, and
it is able to print/dump the results.

```pyrope
const At:Signed(min=33) = nil    // number bigger than 32
const Bt = (
  mut c:String = nil,
  mut d = 100,
  comb init(ref self, ...args) { self.c = args }
)

mut a:At = 40
mut a2 = At(40)
cassert(a == a2)

mut b:Bt = "hello"
mut b2 = Bt("hello")
cassert(b == b2)

puts("a:{a} or {a2}")     // a:40 or 40
puts("b:{b}")             // b:(c="hello",d=100)
```

### Type equivalence


The `does` operator is the base to compare types. It follows structural typing rules.
These are the detailed rules for the `a does b` operator depending on the `a` and `b` fields:


* false when `a` and `b` are different basic types (`Bool`, `Clock`, `comb`,
  `integer`, `mod`, `range`, `Reset`, `String`, `enums`).

* true when `a` and `b` have the same basic type of either `Bool` or `String`.

* true when `a` and `b` are `enum` and `a` has all the possible enumerates
  fields in `b` with the same value.

* `a.max>=b.max and a.min<=b.min` when `a` and `b` are integers. The `max/min`
  are previously constrained values in left-hand-side statements, or inferred
  from right-hand-side if no lhs type is specified.

* `(a#[..] & b#[..]) == b#[..]` when `a` and `b` are `range`. This means that the `a`
  range has at least all the values in `b` range.

* A tuple is either all named or all unnamed (a tuple that mixes both is an
  error, see [Tuples](03-bundle.md)). For two named tuples, `a does b` is true
  if for all the root fields in `b` the `a.field does b.field`; position plays
  no role. For two unnamed tuples, the match is by position: for each entry
  `i` in `b`, `a[i] does b[i]`. A named and an unnamed tuple share neither
  names nor positions, so `does` is false between them.

* `a does b` is false if the explicit array size of `a` is smaller than the
  explicit array size of `b`. If the size check is true, the array entry type
  is checked. `:[]x does :[]y` is false when `:x does :y` is false.

* The lambdas have a more complicated set of rules explained later.

```pyrope
const a:Signed(max=33, min=0) = nil
const b:Signed(max=20, min=5) = nil
cassert(a does b)
cassert(not (b does a))

cassert(    (const a:String=nil, const b:Signed=nil) does (const a="hello", const b=33))
cassert(not (const b:String=nil, const a:Signed=nil) does (const a="hello", const b=33))

type T_complex = comb(x, xxx2) -> (y, z)
type T_simple  = comb(x)       -> (y, z)
cassert(T_complex does T_simple)
cassert(not (T_simple does T_complex))
```

For named tuples, this code shows some of the corner cases. A typed tuple
construction binds its values with the same rules as a call binds its
arguments (see [Argument naming](06-functions.md#argument-naming)): a value
may drop its field name only when a naming exception applies, such as a value
whose type is unique among all the fields.

```pyrope
const T1 = (const a:String = "", const b:Signed = nil)
const T2 = (const b:Signed = nil, const a:String = "")
const T3 = (const a:Signed = 0, const b:Signed = 0)

mut a:T1 = ("hello", 3)      // OK: each type is unique, a="hello", b=3
mut a1:T1 = (3, "hello")     // OK: same binding, b=3, a="hello"
mut b:T1 = (a="hello", 3)    // OK: 3 binds to b by type
mut c:T1 = (a="hello", b=3)  // OK
mut c1:T1 = (b=3, a="hello") // OK: named values bind by name, in any order

mut e:T3 = (1, 2)            // error: two Signed fields, name them
mut e1:T3 = (a=1, b=2)       // OK

mut d:T2 = c                 // OK, both named
cassert(d.a == c.a and d.b == c.b)
const d0 = d[0]              // error: a named tuple has no positions
```

Ignoring the value is what makes `equals` different from `==`. As a result
different functionality functions could be `equals`.

```pyrope
comb a() -> (r) { r = 1 }
comb b() -> (r) { r = 2 }
type Ab_type = comb() -> (r)
cassert(a equals Ab_type)

cassert(a() != b()) // 1 != 2
cassert(a() equals b()) // 1 equals 2
```

## Type check with values

Many programming languages have a `match` with structural checking. Pyrope
`does` allows to do so, but it is also quite common to filter/match for a given
value in the tuple. This is not possible with `does` because it ignores all the
field values. Pyrope has a `case` that extends the `does` comparison and also
checks that for the matching fields, the value is the same.


The previous explanation of `a does b` and `a case b` ignored types. When types
are present, both need to match type.

```pyrope
cassert(not ((const a:U32=0, const b:Bool=false) does (const a:U32=0, const c:String="hello", const b=false)))
cassert((const a:U32=0, const c:String="hello", const b=false) case (a = 0, b:Bool=nil)) // b is nil

cassert(not ((const a:U32=0, const c:String="hello", const b=false) case (a:U32 = 1, b:Bool=nil)))
cassert(not ((const a:U32=0, const c:String="hello", const b=false) case (a:Bool=nil, b:Bool=nil)))
cassert(not ((const a:U32=0, const c:String="hello", const b=false) case (a = 0, b = true)))
```

## Enums with types

Enumerates (enums) create a number for each entry in a set of identifiers.
Pyrope also allows associating a tuple or type for each entry. Another
difference from a tuple is that the enumerate values must be known at compile
time.


```pyrope
const Rgb = (
  mut c:U24 = nil,
  comb init(ref self, c) { self.c = c }
)

enum Color = (
  Yellow:Rgb = 0xffff00,
  Red:Rgb = 0xff0000,
  Green = Rgb(0x00ff00), // alternative
  GBlue = Rgb(0x0000ff)
)

mut y:Color = Color.Red
if y == Color.Red {
  puts("c1:{y} c2:{y.c}\n")  // prints: c1:Color.Red c2:0xff0000
}
```

## Bitwidth

Integers can be constrained based on the maximum and minimum value (not by
the number of bits).

Pyrope automatically infers the maximum and minimum values for each numeric
variable. If a variable width can not be inferred, the compiler generates a
compilation error. A compilation error is generated if the destination
variable has an assigned size smaller than the operand results.

The programmer can specify the maximum number of bits, or the maximum value range.
The programmer can not specify the exact number of bits because the compiler has
the option to optimize the design.


In fact, internally Pyrope only tracks the `max` and `min` value. When a
width-constrained type such as `U14` or `S4` is used, it is converted to a
`max/min` range. Pyrope code can read bitwidth attributes for each integer
variable, but these attributes are read-only; constrain them through the
declared type, not through an attribute write.

`U<N>`/`S<N>` take a literal width only (`U8`, `S20`). A width that depends on
a generic or on another comptime value is spelled `Unsigned(bits=N)` /
`Signed(bits=N)`, the width-parameterized form of `U<N>`/`S<N>` (`U<W>` with a
generic `W` is not a type). It is valid
wherever a type is: ports, locals, tuple field types, array elements
(`[N]Unsigned(bits=W)`), type aliases (`type Row = Unsigned(bits=W)`), and
generic arguments (`<T=Unsigned(bits=W)>`). See
[Generic widths](06-functions.md#generic-widths).

```pyrope
mod sel<N=4, W=8>(v:[N]Unsigned(bits=W), i:Unsigned(bits=std.clog2(N)))
  -> (y:Unsigned(bits=W)@[0]) {
  y = v[i]
}

comptime const K = 4
mut x:Signed(bits=K) = 0         // same range as S4
cassert(x.[bits] == 4 and x.[min] == -8 and x.[max] == 7)
```

* `max`: the declared maximum value
* `min`: the declared minimum value
* `bits`: the number of bits needed to represent the declared `max`/`min`
  range (sugar over `max`/`min` — see
  [Attributes](04b-attributes.md#integer-bitwidth-attribute-list)). A typed
  value reports its declared type. An untyped **comptime** integer has no
  declared range, so its `bits` is the minimal width of its value
  (`comptime const N = 13` gives `N.[bits] == 4`; `0` gives 1; a negative
  value gives its signed width). An untyped runtime value reads `nil`.
  There are no `ubits`/`sbits` attributes: use `bits`, and check the sign
  with `sign` (1 when `min < 0`, else 0). To size an index into `N`
  entries, use `std.clog2(N)`, not `N.[bits]` (see
  [Standard library](13-stdlib.md#built-in-std-namespace)).
* `bw_max`/`bw_min`: the *actual* range computed by the bitwidth pass —
  readable only inside debug statements (`cassert`/`assert`)


Internally, Pyrope has 2 sets of `max/min`. The constrained and the current.
The constrained is set during type declaration. The current is computed based
on the possible max/min value given the current path/values. The current should
never exceed the constrained: when the current range of a right-hand side may
fall outside the constrained range of its typed destination (above `max` or
below `min`), the assignment is a mandatory compile error unless it carries
`wrap` or `sat`. The rule applies to every typed destination (a local, a
`reg`, a tuple field, a `comb`/`pipe`/`mod` output, and an argument bound to a
typed input) and to comptime and runtime values alike. A runtime value is
checked on its computed range, not on the values it happens to take: a
`reg cnt:U8` may be 255, so `cnt = cnt + 1` is an error and
`wrap cnt = cnt + 1` is the counter idiom (see
[wrap and sat](04b-attributes.md#wrap-and-sat-modifier)). Similarly, the
current should be bound to a given size or a compile error is generated.


The constraint does not need to be specified. In this case, the hardware will
use whatever current value is found. This allows to write code that adjust to
the needed number of integer bits.

When `max`/`min`/`bits` are read, they return the declared constraint (for an
untyped comptime integer, `bits` comes from its value, as above). The
current range is readable as `bw_max`/`bw_min`, but **only inside debug
statements**: each elaboration may compute a different (legal) current range,
so non-debug code must not make decisions based on it.

```pyrope
mut val:U8 = 0   // designer constrains val to be between 0 and 255
cassert(val.[max] == 255 and val.[min] == 0 and val.[bits] == 8)

val = 3          // declared attributes unchanged: max=255, min=0
cassert(val.[bw_max] == 3) // current range: debug-only read

val = 300        // error: '300' overflows the maximum allowed value of 'val'

wrap val = 0x1F0 // Drop bits from 0x1F0 to fit in constrained type
cassert(val == 240 == 0xF0)

val = U8(0x1F0)  // error: 0x1F0 needs 9 bits — a sized cast can widen but
                 // never drops bits; use `wrap`/`sat` to drop bits
val = U8(200)    // OK: 200 fits U8, reinterprets through unchanged
cassert(val == 200)
```

Binding an argument to a typed input follows the same overflow rule as an
assignment, for `comb` and `mod`, generic or not: an argument whose range
may not fit the input's declared range (a `U16` into `a:U4`, or into
`a:Unsigned(bits=N)` with `N=4`) is a compile error. The caller drops the
bits explicitly (see [Argument types](06-functions.md#argument-types)):

```pyrope
comb low(a:U4) -> (r:U4) { r = a }

mut w:U16 = 0x1234
const r1 = low(a=w)            // error: 0x1234 overflows 'a:U4'
const r2 = low(a=w#[0..<4])    // OK: explicit slice
cassert(r2 == 4)
```

A sign cast `Signed(x)`/`Unsigned(x)`/`S<N>(x)`/`U<N>(x)` *reinterprets* `x`'s bits
under the target signedness. The unsized `Signed(x)`/`Unsigned(x)` keep the bit
width unchanged (so `x` must be fully sized and `Signed(Unsigned(x)) == x`); the
sized `S<N>(x)`/`U<N>(x)` may widen but never drop bits — a target with fewer bits
than `x` is a compile error (use a `wrap`/`sat` prefix to drop bits on purpose),
e.g. `U30(S22(x))` is fine but `S22(U30(x))` is a compile error.

Booleans never mix with integers implicitly. The idiomatic bool-to-bit
conversion is `U1(b)` (`true` is `1`; `Unsigned(b)` and `U<N>(b)` give the same
value). A `Bool` is realized in hardware as an unsigned `U1`, and a cast
interprets that single bit under the target's signedness, so
`Signed(true) == -1` / `S8(true) == -1` is a *reinterpretation* of the bit
(1-bit signed), not the way to turn a flag into a number. The reverse,
`Bool(x)` on an integer, is `x != 0` (so `Bool(33)` is true;
for one bit, `Bool(v#[3])` or `v#[3] == 1`); an undefined (`?`) or `nil`
operand is a compile error. Port boundaries follow the same rule: a `Bool`
input binds a `Bool` value (`Bool(bit)`, not a bare `U1`), a `Bool` output
is used as a number through `U1(child.flag)`, and a wider integer bound to a
`Bool` input is a compile error (see
[Boolean ports](06-functions.md#boolean-ports)).

```pyrope
cassert(U1(true) == 1 and U1(false) == 0)   // Bool -> bit
cassert(Signed(true) == -1)                  // reinterpretation, not the idiom
cassert(Bool(0x8#[3]) and 0x8#[3] == 1)      // bit -> Bool
```

Branching on `bw_max`/`bw_min` outside a debug statement is a compile error
because the result would not converge — the next elaboration can compute a
different range and silently change the circuit:

```pyrope
if x.[bw_max] != 30 { // compiler error 'bw_max' is debug-only
  x = 30
} else {
  x = 40
}
```

Pyrope leverages LiveHD bitwidth pass to compute the maximum and minimum value
of each variable. For each operation, the maximum and minimum are computed. For
control-flow divergences, the worst possible path is considered.

```pyrope
mut a = 3                  // a: current(max=3,min=3) constrain()
mut c:Signed(min=0,max=10) = nil // c: current(max=0,min=0) constrain(max=10,min=0)
if b {
  c = a + 1                // c: current(max=4,min=4) constrain(max=10,min=0)
} else {
  c = a                    // c: current(max=3,min=3) constrain(max=10,min=0)
}
                           // c: current(max=4,min=3) constrain(max=10,min=0)

mut e:S4 = nil             // e: current(max=0,min=0) constrain(max=7,min=-8)
e = 2                      // e: current(max=2,min=2) constrain(max=7,min=-8)
mut d = c                  // d: current(max=4,min=3) constrain()
if d == 4 {
  d = e + 1                // d: current(max=3,min=3) constrain()
}
mut g:U3 = d               // g: current(max=4,min=3) constrain(max=7,min=0)
mut h = c#[0..=1]          // h: current(max=3,min=0) constrain()
```


Bitwidth uses narrowing to converge (see
[internals](10-internals.md/#type-synthesis)). The GCD example does not specify
the input/output size, but narrowing allows it to work without typecasts.  To
understand, the comments show the max/min bitwidth computations.

```pyrope
if cmd.[valid] {
  x = cmd.a     // x.max=cmd.a.max; x.min = 0 (unsigned) ; ....
  y = cmd.b
} elif x > y {
                // narrowing: x.min = y.min + 1 = 1
                // narrowing: y.max = x.min - 1
  x = x - y     // x.max = x.max - x.min = x.max - 1
                // x.min = x.min - y.max = 1
} else {        // x <= y
                // narrowing: x.max = y.min
                // narrowing: y.min = x.min
  y = y - x     // y.max = y.max - x.min = y.max
                // y.min = y.min - x.max = 0
}
                // merging: x.max = x.max ; x.min = 0
                // merging: y.max = y.max ; y.min = 0
                // converged because x and y is same or smaller at beginning
```

The bitwidth pass may not converge to find a valid size even with narrowing.
In this case, the programmer must constrain the bitwidth with a `wrap` or
`sat` assignment into a typed destination (a sized cast never drops bits, so
it cannot do it). For example, this could work:

```pyrope
reg x:cmd.a = 0   // use cmd.a type for x
reg y:cmd.b = 0   // use cmd.b type for y
if cmd.[valid] {
  x = cmd.a
  y = cmd.b
} elif x > y {
  wrap x = x - y  // drop bits as needed
} else {
  sat y = y - x   // saturate (adds a compare and a mux)
}
```


Pyrope uses signed integers for all the operations and transformations, but
when the code is optimized it does not need to waste bits when the most
significant bit is known to be always zero (positive numbers like `U4`). The
verilog code generation or the synthesis netlist uses the bitwidth pass to
remove the extra unnecessary bit when it is guaranteed to be zero. This
effectively "packs" the encoding.


## Tagged unions (enum `enum`)


A tagged union — the equivalent of a `enum` type — is spelled with `enum`
in Pyrope and carries a payload per case. The bits used are shared across
cases (only one case is active at a time), so the storage is the size of the
largest case plus the tag.


Unlike a C-style `union`, the tag is tracked from the assignment, and an
error is generated if the wrong case is accessed. Bit-level reinterpretation
across cases requires explicit bitwise operations.


The main advantage of a tagged enum is to save space, so the typical use is
in combination with registers or memories, where alternative types share a
single storage location.


```pyrope
enum E_type = (str:String = "hello", num=22)
enum V_type = (str:String, num:Signed)      // No default value when used as a tagged union

mut vv:V_type = (num=0x65)
cassert(vv.num == 0x65)
const xx = vv.str                         // error: active case is `num`
```


The variable allows to explicitly or implicitly access the active case.
Cases may not be solved at compile time, and the error will be a simulation
error. A `comptime` directive can force a compile time-only check.

```pyrope
enum Vtype = (str:String, num:Signed, b:Bool)

const x1a:Vtype = "hello"                 // implicit case
const x1b:Vtype = (str="hello")           // explicit case

comptime const x2:Vtype = "hello"                  // comptime

cassert(x1a.str == "hello" and x1a == "hello")
cassert(x1b.str == "hello" and x1b == "hello")

const err1 = x1a.num                      // error: active case is `str`
const err2 = x1b.b                        // error: active case is `str`
const err3 = x2.num                       // error: comptime value is `str`
```

As a reference, `enums` allow to compare for field but not update enum entries.

```pyrope
mut ee = E_type
ee.str = "new_string"       // error: enum is immutable

match ee {
 == E_type.str { }
 == E_type.num { }
 else { }
}
```


## Typecasting


To convert between tuples, an explicit `init` is needed unless the tuple field
names and types match (the order of named fields carries no meaning).

```pyrope
const At = (const c:String = nil, const d:U32 = nil)
const Bt = (const c:String = nil, const d:U100 = nil)

const Ct = (
  const d:U32 = nil,
  const c:String = nil
)
// different order
const Dt = (
  mut d:U32 = nil,
  mut c:String = nil,
  comb init(ref self, x:At) { self.d = x.d; self.c = x.c }
)

mut b:Bt = (c="hello", d=10000)
mut a:At = nil

a = b          // OK c is String, and 10000 fits in U32

mut c:Ct = a   // OK even different order because all names match

mut d:Dt = a   // OK, calls init to typecast at construction
```

* To string: `String(value)` renders an integer as decimal text; string interpolation embeds values in text.
* To integer: `variable#[..]` is the full bit vector of the variable: for an
  unnamed tuple or array, the packing of its entries with entry 0 in the
  lowest bits; for a range or `Bool`, that type's own encoding.
  The entry widths come from the declared types, never from the
  values, so a layout is always something the source states (see the bit
  packing rules in [internals](10-internals.md)).

## Introspection

Introspection is possible for tuples.

```pyrope
const a = (const b=1, const c:U32=2)
mut b = a
b.c = 100

cassert(a equals b)
cassert(a['b'] == 1)
cassert(a['c'] equals U32)

cassert(a has 'c')
cassert(!(a has 'foo'))

cassert(a.[id] == 'a')
cassert(a['b'].[id] == 'b' and a.b.[id] == 'b')
cassert(a['c'].[id] == 'c' and a.c.[id] == 'c')

cassert(a.[size] == 0)  // a named tuple has 0 unnamed entries
cassert(a.[fields] == ('b','c'))
```

Function definitions allocate a tuple, which allows to introspect the
function but not to change the functionality. The `.[inp]` and `.[out]`
attributes list the input and output names in declaration order.

```pyrope
comb fu(a, b=2) -> (c) { c = a + b }
cassert(fu.[inp] == ('a', 'b'))
cassert(fu.[out] == ('c',))
```

These name lists describe the interface; they are not type descriptors.
Overload selection also considers the declared input types and how the caller
consumes the outputs, as described in [Functions](06-functions.md).

Any runtime precondition is expressed by the caller (e.g., with an
`if`/`elif` chain that picks which named lambda to invoke); there is no
`where` clause on declarations.

There are several uses for introspection, but for example, it is possible to build a
function that returns a randomly mutated tuple.

!!! NOTE "Not implemented"
    The next example does not compile today. It uses three constructs that are
    TBD: the standard library (`import("prp/rnd")`, see
    [Standard Library](13-stdlib.md)); a `ref self` method used in a
    right-hand-side expression (`const y = x.randomize()` — the statement form
    and UFCS both work); and the random generation it calls. See
    [TBD](15-tbd.md).

```pyrope
comb randomize::[debug](ref self) {
  const rnd = import("prp/rnd")
  for i in ref self {
    if i equals Signed {
      i = rnd.between(max=i.[max], min=i.[min])
    } elif i equals Bool {
      i = rnd.flip()
    }
  }
  self
}

const x = (const a=1, const b=true, const c="hello")
const y = x.randomize()

assert(x.a == 1 and x.b == true and x.c == "hello")
cassert(y.a != 1)
cassert(y.b != true)
assert(y.c == "hello") // string is not supposed to mutate in randomize()
```


## Global scope

There are no global variables or functions in Pyrope. Variable scope is
restricted by code block `{ ... }` and/or the file. Each Pyrope file is a
function, but they are only visible to the same directory/project Pyrope files.
The one exception is the built-in `std` namespace (`std.clog2(x)`), which every
file sees without an `import` (see
[Standard library](13-stdlib.md#built-in-std-namespace)).

A lambda body may read only the **compile-time** bindings of the scopes
around it: `comptime const` declarations, a plain `const` whose value folds
to a constant (such as a file-scope `const x = 2`), the generics of an
enclosing lambda, imports, types, and lambdas. Reading an enclosing
**runtime** value (a `const` computed from an input, a `mut`, `reg`, `wire`,
or an input) is a compile error; pass the value as an input (see
[Declaration](06-functions.md#declaration)).

```pyrope
comptime const W = 8
const x = 2                                // folds to a constant: readable below

comb f(a:U8) -> (r:U9) { r = a + W }       // OK: W is comptime
comb g(a:U8) -> (r:U9) { r = a + x }       // OK: x is a compile-time constant
mod m(b:U8) -> (o:U9@[0]) {
  const t = b + 1                          // computed from the input `b`: runtime
  comb h(a:U8) -> (r:U10) { r = a + t }    // error: 't' is an enclosing runtime value
  comb k(a:U8, t2:U9) -> (r:U10) { r = a + t2 } // OK: pass it as an input
  o = b
}
```


There are two separate mechanisms for accessing declarations outside a Pyrope
file. The `import` statement copies `pub` top-scope lambdas, types, and
constants from other files. Registers are never imported; `pub reg` is a
compile error. To reference an instantiated register outside the local scope,
use `regref`, which resolves through the instantiation hierarchy instead of
through the file import namespace. Debug statements can still observe registers
read-only (see
[Visibility](04-variables.md#visibility-private-by-default-pub-to-export)).


### import


`import` keyword allows to access functions not defined in the current file.
Any call to a function or tuple outside requires a prior `import` statement;
the built-in `std` namespace is the only exception.


```pyrope
// file: src/my_fun.prp
pub comb fun1(a, b) -> (r) { r = a + b }
pub comb fun2(a) -> (r) {
  comb inside() -> (r) { r = 3 }
  r = a
}
comb another(a) -> (r) { r = a }   // no pub: private to this file

pub const mytup = (
  comb call3(self) -> () { puts("call called") }
)
```

```pyrope
// file: src/user.prp
const a = import("my_fun")    // all the pub entries of the file
a.fun1(a=1, b=2)        // OK
a.another(a=1)          // error: 'another' is not pub, not imported
a.fun2.inside()         // error: `inside` is not in top scope variable

const fun1 = import("my_fun.fun1")  // a single pub entry
lec(gold=fun1, `impl`=a.fun1)

const x = import("my_fun.mytup")

x.call3()               // prints call called
```

The import string is either a file (`import("file")`, which brings all the
`pub` entries) or a single pub entry (`import("file.pub_name")`). Directory
hierarchy uses slashes: `import("proj/dir/file.pub_name")`. There are no glob
patterns.

An `lg:` prefix imports an already-compiled **lgraph** instead of a source
unit — e.g. a Verilog module compiled earlier, or a previously built Pyrope
lambda:

```pyrope
const add_sub = import("lg:add_sub")  // the compiled module, not its source
```

The `import` points to a file [setup code](06b-instantiation.md#setup-code)
list of `pub` lambdas, types, and constants. The setup code corresponds to the
"top" scope in the imported file. Registers are intentionally excluded from
imports; use `regref` for register instances. The import statement can only be
executed during the setup phase. The import allows for cyclic dependencies between files as long as
there is no true cyclic dependency between variables. This means that "false"
cyclic dependencies are allowed but not true ones.

`import` always uses the declared `pub` name. The `lg` attribute
([explicit lgraph name](04b-attributes.md#lg-explicit-lgraph-name))
renames only the generated lgraph, never the import key:
`pub comb my_log::[lg="foo_mod"](...)` is still imported as
`import("my_fun.my_log")`.

There is no wildcard namespace import and no version pinning syntax; aliasing
is plain assignment:

```pyrope
import math::*       // error: wildcard import not allowed
import std@1.2 as s  // error: version pinning not supported

const math = import("some/hierarchy/math")  // alias by assignment
```

To select among library versions, point the import path at the desired
version. Different parts of a project may import different versions of the
same library this way.


The import behaves like cut and pasting the imported code. It is not a
reference to the file, but rather a cut and paste of functionality. This means
that when importing a constant or lambda, it creates a copy. If two files import
the same declaration, they are not referencing the same declaration, but each
has a separate copy.


The import is delayed until the imported declaration is used in the local file.
There is no order guarantee between imported files, just that the code needed
to compute the used imported declarations is executed before.


The import statement is a filename or path without the file extension.
Directories named `code`, `src`, and `lib` are skipped. No need to add them in
the path. `import` stops the search on the first hit. If no match happens, a
compile error is generated.


`import` allows specialized libraries per subproject.  For example, xx/yy/zz can
use a different library version than xx/bb/cc if the library is provided by yy,
or use a default one from the xx directory.

```pyrope
const a = import("prj1/file1")
const b = import("file1")       // import xxx_fun from file1 in the local project
const c = import("file2")       // import the functions from local file2
const d = import("prj2/file3")  // import the functions from project prj2 and file3
```

Many languages have a "using" or "import" or "include" command that includes
all the imported functions/constants to the current scope. Pyrope does not allow
that, but it is possible to use a mixin to add the imported functionality to a
tuple.

```pyrope
const b = import("prp/Number")
mut a = import("fancy/Number_mixin")

const Number = (...b, ...a) // patch the default Number class

mut x:Number = 3
```

### Register reference


While import "copies" file-scope declarations, `regref` or Register reference
allows code to reference (not copy) an existing register in the call hierarchy.


The syntax of `regref` is similar to `import` but the semantics are very
different. While `import` looks through Pyrope files, `regref` looks through
the instantiation hierarchy for matching register names or paths. `regref`
binds an addressable storage cell — a register, a memory word, or (in a `test`
block) a module input or output port; it can not reference functions, constants,
types, ordinary variables, or an internal combinational net, none of which has a
cell to bind.

!!! NOTE "Two constructs share this name"
    The **synthesizable, string-path** `regref` described in this section
    resolves through the elaborated hierarchy, may match **zero or many**
    registers, and is still TBD. The **`test`-block** `regref(expr)` — see
    [Test only statements](05b-statements.md#test-only-statements) — names
    exactly one cell and is implemented, in both the dotted and the string form.
    The rules below are the synthesizable ones.

`regref` is independent of `pub`
([Visibility](04-variables.md#visibility-private-by-default-pub-to-export)):

* In **debug statements** (`assert`, `test`, `puts`, monitors), `regref`
  can read any register.
* In **synthesizable code**, `regref` can attach to an instantiated register
  outside the local scope. The attached reference behaves exactly like a
  local `reg`: bare reads return the `q` value, assignments drive the `din`
  input, and stage inference classifies it like any state register (see
  [Pipelining](06c-pipelining.md)). Because every access crosses the flop
  boundary, a `regref` connection is sequential by construction — it can
  never create a combinational path between distant modules.

```pyrope
mod do_increase() -> () {
  reg counter:U32 = 0     // no pub needed: puts below is a debug statement

  wrap counter = counter + 1
}

mod do_debug() -> () {
  const cntr = regref("do_increase/counter")

  puts("The counter value is {cntr}")
}
```


Verilog has a more flexible semantics with the Hierarchical Reference. It also
allows to go through the module hierarchy and read/write the contents of any
variable. Pyrope only allows you to reference registers by unique name. Verilog
hierarchical reference is not popular for 2 main reasons: (1) It is considered
"not nice" to bypass the module interface and touch an internal variable; (2)
some tools do not support it as synthesizable; (3) the evaluation order is not
clear because the execution order of the modules is not defined.


Allowing only a single lambda to update registers avoids the evaluation order
problem. From a low level point of view, the updates go to the register `din`
pin, and the references read the register `q` pin. The register references
follow the model of single writer multiple reader.  This means that only a
single lambda can update the register, but many lambdas can read the register.
This allows to be independent on the `lambda` evaluation order.


The register reference uses instantiated registers. This means that if a lambda
having a register is called in multiple places, only one can write, and the
others are reading the update. It is useful to have configuration registers. In
this case, multiple instances of the same register can have different values.
As an illustrative example, a UART can have a register and the controller can
set a different value for each uart base register.

```pyrope
// file remote.prp

mod xxx(some:U32, code:U32) -> () {
  reg uart_addr:U32 = nil
  assert(0x400 > uart_addr >= 0x300)
}

// file local.prp
mod setup_xx() -> () {
  mut xx = regref("uart_addr") // match xxx.uart_addr if xxx is in hierarchy
  mut index = 0
  for val in ref xx {          // ref does not allow enumerate
    val = 0x300 + index * 0x10 // sets uart_addr to 0x300, 0x310, 0x320...
    index += 1
  }
}
```


Maybe the best way to understand the `regref` is to see the differences with
the `import`:

* Instantiation vs File hierarchy
  + `regref` finds matches across instantiated registers.
  + `import` traverses the file/directory hierarchy to find one match.
* Success vs Failure
  + `regref` keeps going to find all the matches, and it is possible to have a zero matches
  + `import` stops at the first match, and a compile error is generated if there is no match or multiple matches.

The multi-match behavior is specific to the **string** form. The dotted
`regref(acc.core0.cnt)` used in a `test` block names exactly one instantiated
cell, and a path that does not resolve is an error rather than an empty set —
which is what lets it bind to a single reference.


### Mocking library

One possible use of the register reference is to create a "mocking" library. A
mocking library instantiates a large design but forces some subblocks to
produce some results for testing. The challenge is that it needs undriven
registers. During testing, a `regref` is more flexible and it can overwrite an
existing value. It uses the same reference form as `import` or the register
reference, and it accepts the string path directly.

```pyrope
const bpred = ( // complex predictor
  comb taken(self) -> (r:Bool) { r = self.some_table[som_var] >= 0 }
)

test mock.branches {
  mut taken = regref("bpred_file/taken")   // bound once
  taken = true

  mut l = core.fetch.predict(0xFFF)
}
```

## Operator overloading

There is no operator overload in Pyrope. `+` always adds Numbers, `...` always
splices/concatenates a tuple or a String, `and` is always for `Bool` values,...


## Init method (constructor)

Pyrope tuples can use the same syntax as a lambda call or a direct assignment.
Both forms bind values with the same rules as lambda calls; see
[Argument naming](06-functions.md#argument-naming). A value may omit its field
name only when a naming exception applies (for example, its type is unique
among all the fields); otherwise name it.

```pyrope
const Typ1 = (
  const a:String = "none",
  const b:U32 = 0
)

const w = Typ1(a="foo", b=33)       // OK
const x:Typ1 = (a="foo", b=33)      // OK, same as before

const v:Typ1 = Typ1(a="foo", b=33)  // OK, but redundant Typ1
const y:Typ1 = ("foo", 33)          // OK, each value's type is unique

mut z:Typ1 = nil                    // OK, default field values
cassert(z.a == "none" and z.b == 0)
z = (a="foo", b=33)

cassert(v == w == x == y == z)
```

Pyrope allows an `init` method to intercept construction. The same `init`
method is called in all the previous construction forms: a typed declaration
(`mut x:T = value`), a `nil` declaration (`mut x:T = nil`), and an explicit
call (`T(value)`). `init` is an implicit construction hook and must be
declared as `comb`. If an operation needs register state, pipeline latency, or
other cycle-level side effects, make it an explicit `mod` or `pipe` method
instead.

`init` runs only at construction. Once the variable exists, assignments and
field writes are plain structural writes — no hook is invoked, and reads
always return the structural value.


```pyrope
const Typ2 = (
  mut a:String = "none",
  mut b:U32 = 0,
  comb init(ref self, a, b) { self.a = a; self.b = b }
)

mut x:Typ2 = (a="x", b=0)       // init(ref x, a="x", b=0)
mut y:Typ2 = (a="hello", b=44)  // init(ref y, a="hello", b=44)
mut z = Typ2(a="hello", b=44)   // same init, explicit call form
cassert(y == z)
mut e:Typ2 = ("hello", 44)      // error: init's 'a' and 'b' are untyped, name them

x.a = "hello"                 // plain field write, init is NOT called
x.b = 44
cassert(x == y)
```

Tuples can be multi-dimensional, and each dimension is indexed with its own
`[...]` (e.g. `m[i][j]`, not `m[i,j]`).

```pyrope
comb matrix8x8_set_xy(ref self, x:Signed(min=0,max=7), y:Signed(min=0, max=7), v:U16) {
  self.data[x][y] = v
}
comb matrix8x8_set_row(ref self, x:Signed(min=0, max=7), v:U16) {
  for ent in ref self.data[x] {
    ent = v
  }
}

const Matrix8x8 = (
  mut data:[8][8]U16 = 0,
  comb init(ref self) {       // default construction
    for ent in ref self.data {
      ent = 0
    }
  },
  const set_xy  = matrix8x8_set_xy,
  const set_row = matrix8x8_set_row
)

mut m:Matrix8x8 = nil          // init runs
cassert(m.data[0][3] == 0)

m.set_xy(x=1, y=2, v=100)      // explicit method call
cassert(m.data[1][2] == 100)
m.set_row(x=1, v=3)
cassert(m.data[1][2] == 3)
m.data[4][5] = 33              // plain structural indexed write
cassert(m.data[4][5] == 33)
```

There is no read hook: indexing or reading a tuple field always returns the
structural value (`m.data[1]` is the row slice, `m.data[1][2]` the element).
After construction, indexed writes are also structural; custom write behavior
is an explicit method like `set_xy` above.

The `init` method can be [overloaded](06-functions.md#declaration) to select
between construction forms.

```pyrope
comb my_2_elem_init_xv(ref self, x:Unsigned(min=0,max=1), v:String) { self.data[x] = v }
comb my_2_elem_init_copy(ref self, v:My_2_elem)          { self.data = v.data }
comb my_2_elem_init_default(ref self)                    { self.data = ("", "") }

const My_2_elem = (
  mut data:[2]String = ("", ""),
  const init = [my_2_elem_init_xv, my_2_elem_init_copy, my_2_elem_init_default]
)

mut v:My_2_elem = nil          // init_default
mut x:My_2_elem = (1, "hello") // init_xv: data[1] = "hello"
mut w:My_2_elem = x            // init_copy

v.data[0] = "world"            // plain structural write

cassert(v.data == ("world", ""))
cassert(w.data[1] == "hello")

const z = w                    // plain structural copy, no hook involved
cassert(z equals w)
```


A nested tuple field can have its own `init`; computed views of hidden fields
are explicit `comb` methods.


```pyrope
const Some_obj = (
  mut a1:String = nil,
  mut a2 = (
    mut _val:U32 = nil,                        // hidden field
    comb init(ref self, x) { self._val = x + 1 },
    comb val(self) -> (r) { r = self._val + 100 }
  ),
  comb init(ref self, a, b) {                  // constructor
    self.a1 = a
    self.a2._val = b
  }
)

mut x:Some_obj = (a="hello", b=3)

assert(x.a1 == "hello")
assert(x.a2.val() == 103)  // explicit method call; reads are never intercepted
```


Since there is no read hook, typecast-style views are also explicit methods,
dispatched by name at the call site:

```pyrope
comb my_obj_to_string(self) -> (r:String) { r = String(self.val) }
comb my_obj_to_bool(self)   -> (r:Bool)   { r = self.val != 0 }
const My_obj = (
  ,mut val:U32 = 0
  ,const to_string = my_obj_to_string
  ,const to_bool   = my_obj_to_bool
)

mut s:My_obj = nil
s.val = 100
const r1:String = s.to_string()
const r2:Bool   = s.to_bool()
```

### Attribute access in init

The `init` method can also access attributes:

```pyrope
mut obj1::[attr1] = (
  ,mut data:Signed = nil
  ,comb init(ref self, v) {
    if v.[attr2] {
      self.data.[attr3] = 33
    }
    cassert(self.[attr1])
  }
)
```

### Default init value

All variable declarations need an explicit assigned value. For complex tuple
types, constructing with no arguments (`nil` or `T()`) triggers the no-arg
`init` overload below.


```pyrope
const fint:Signed  = 0
cassert(fint == 0)

mut fbool:Bool = false
cassert(!fbool)

comb tup_init_default(ref self) { // no-argument overload
  cassert(self.v == "")
  self.v = "empty33"
}
comb tup_init_v(ref self, v) {
  self.v = v
}
const Tup = (
  ,mut v:String = ""    // default to empty
  ,const init = [tup_init_default, tup_init_v]
)

mut x:Tup = nil
cassert(x.v == "empty33")

mut x2:Tup = "Padua"
cassert(x2.v == "Padua")

mut y = Tup()
cassert(y.v == "empty33")

mut y2 = Tup("ucsc")
cassert(y2.v == "ucsc")
```

### Array/Tuple access

Array indexing reads and writes the underlying field directly. Custom indexed
access is an explicit method; hidden fields (leading underscore) keep the
representation private.

```pyrope
const Point = (
  ,mut _x:Signed = 0    // leading underscore: private to the tuple
  ,mut _y:Signed = 0

  ,comb init(ref self, x:Signed, y:Signed) {
    self._x = x
    self._y = y
  }

  ,comb get(self, idx:String) -> (r:Signed) {
    r = match idx {
     == 'x' { self._x }
     == 'y' { self._y }
     else   { 0        }
    }
  }
)

const p:Point = (x=1, y=2)
const q:Point = (1, 2)   // error: init's 'x' and 'y' are both Signed, name them

cassert(p.get('x') == 1 and p.get('y') == 2)
cassert(p._x == 1) // error: _x is private outside the tuple
```

## Comparisons

`==` and `!=` compare tuple structure and field values. Named-field order
does not affect equality. The ordered comparisons (`<`, `<=`, `>`, `>=`)
require integer operands; compare an object's integer fields explicitly.

```pyrope
const t1 = (const long_name:String = "foo", const b = 33)
const t2 = (const b = 33, const long_name:String = "foo")
cassert(t1 == t2)
cassert(t1.b < 40)
```

Methods named `eq`, `lt`, `to_string`, or `to_bool` are ordinary explicit
methods. Operators and conversions do not dispatch to them. The `init`
constructor and its overload lists remain supported.

## External (C++) calls via `cpp`

External code is reached through `cpp`, a reserved keyword that behaves like
[`import`](10-internals.md) (a comptime alias) but resolves to a C++ build
target instead of a Pyrope file:

```pyrope
const gold = cpp("gcd_model")   // build edge: compile and link the `gcd_model` C++ unit
```

The string is a logical build-target name — the build config maps it to the
actual source or library; it is not a filesystem path. Because `cpp` is a
keyword, the toolchain extracts the exact set of C++ dependencies with a simple
static scan, with no Pyrope evaluation.

`cpp` is the *only* way to reach external C++. The `__name` convention is now
reserved for compiler intrinsics and basic gates (`__eq`, `__lt`, ...); it no
longer doubles as a foreign-call escape hatch.

### The typed interface is the source of truth

A `cpp` unit carries no Pyrope signatures, so the interface is declared on the
Pyrope side. That one declaration drives both the bit-accurate widths and the
generated C++ header — the boundary is a generated contract, never matched by
hand on both sides:

```pyrope
type GcdModel = (
  call_method1: comb(a:U8, b:U3) -> (foo:U8, bar:U33),
)

const gold:GcdModel = cpp("gcd_model")
```

Each method is an ordinary typed lambda (`comb` is the common case — a pure
function of its inputs). Width and signedness live in the Pyrope types; the C++
side sees only `Slop<N>` — the simulation value type, fixed-width with every bit
concrete (its width is `N`; the sign is applied by the generated glue per the
declared type). Tuples flatten to scalar `Slop<N>` arguments using the same
port-flattening as a module boundary.

### Generated C++ contract

From the type above, the toolchain emits the prototype to implement. Inputs are
`const Slop<N>&`; a single output returns a bare `Slop<N>` and a multi-output
tuple returns a small struct. One object instance is created per binding, so a
model may keep internal state across calls within a run:

```c++
struct gcd_model {
  struct call_method1_out { Slop<8> foo; Slop<33> bar; };
  call_method1_out call_method1(const Slop<8>& a, const Slop<3>& b);
};
```

```pyrope
const arg1:U8 = 2
const (foo, bar) = gold.call_method1(a=arg1, b=3)
```

### Simulation only (debug)

A `cpp` call runs in simulation. It is called from a `test` block — which itself
generates the simulation to run — and executes per cycle as a golden model,
scoreboard, or reference checker. It is debug-only and elided from synthesis: it
cannot drive a synthesizable signal, so the synthesized netlist carries no C++
dependency. See [External C++ models](09-verification.md#external-c-models).

`cpp` is therefore a simulation-only build dependency — needed when building the
simulator, never for synthesis. Typing the interface also catches argument and
width mismatches early.

!!! NOTE
    Calling C++ at compile time (elaboration-time configuration, e.g. reading a
    json file to pick parameters) is not exposed today. The natural extension is
    to attach `comptime` to the import — `comptime cpp("...")` — so its calls
    fold during elaboration and may feed synthesizable logic. Such a call would
    interface through `Dlop`, not `Slop<N>`: comptime values are
    arbitrary-precision and may carry unknown bits, so they lack the fixed-width,
    every-bit-concrete guarantees `Slop<N>` relies on (`Dlop` is the dynamic,
    three-valued equivalent). The compiler's `pass`/`cprop` already evaluates C++
    through `Dlop` internally; only the surface API is unsettled.
