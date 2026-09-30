# Variables and types

A variable is an instance of a given type. The type may be inferred from use.
The basic types are Boolean, function, Integer, Range, and String. All those
types can be combined with tuples.


## Variable scope

Scope constrains variables visibility. There are three types of scope
delimitation in Pyrope: code block scope, lambda scope, and tuple scope. Each
has a different set of rules constraining the variable visibility. Overall, the
variable/field is visible from declaration until the end of scope.


Pyrope uses `mut` or `const` to declare a variable, but all the declarations must
have a value. Use a concrete expression for initialization. Use `nil` only when
the variable intentionally has no meaningful value yet; reading `nil` is invalid
until the variable is assigned a real value. The bare `_` default value syntax
has been removed.

`const x [:type] = nil` is therefore a **forward declaration**: the variable has
no value yet, and its one later assignment binds it. A `const` is bound exactly
once, so that assignment defines the variable on *every* control path — writing
it inside an `if` with no `else` means the same as writing it unconditionally
(the same rule [`wire`](#wire-single-driver-combinational-nets) follows; an
un-taken path is a don't-care, not an unknown). A second assignment is a rebind
error, and — unlike a `wire` — the bind must precede every read.

```pyrope
const w:U8 = nil       // forward declaration: no value yet
if c {
  wrap w = a + 1       // the ONE bind; `w` is `a + 1` whether or not `c` holds
}
o = w                  // read AFTER the bind
```


Implemented declarations start with one of seven **kind keywords**:

| Kind    | Category | Implicit mutability |
|---------|----------|---------------------|
| `const` | data     | immutable           |
| `mut`   | data     | mutable             |
| `wire`  | data     | single-driver combinational net (read before driver allowed) |
| `reg`   | data     | mutable, persists across cycles |
| `comb`  | lambda   | immutable (always)  |
| `pipe`  | lambda   | immutable (always)  |
| `mod`   | lambda   | immutable (always)  |

`fluid` is an additional, TBD lambda kind: its syntax parses, but LiveHD does
not lower it yet. See [Fluid Blocks](06d-fluid.md).

The four data kinds take `= expression`; the three lambda kinds take a
parameter list and a body. Data declarations:

* `const variable [:type] [:[attribute list]] = expression`
* `mut variable [:type] [:[attribute list]] = expression`
* `wire variable [:type] [:[attribute list]] = expression`
* `reg variable [:type] [:[attribute list]] = reset_expression`

When the type is omitted but attributes are given, the type colon remains:
`reg counter::[retime=true] = 0` but `reg counter:U8:[retime=true] = 0`.
Bare attributes are always `::[...]` — a single `:[...]` after the variable
name would parse as an array type (`:[16]U8`).

Lambda declarations:

* `comb name [<generics>] [::[attrs]] (inputs) -> (outputs) { body }`
* `pipe[N] name [<generics>] [::[attrs]] (inputs) -> (outputs) { body }`
* `mod name [<generics>] [::[attrs]] (inputs) -> (outputs) { body }`

The `<generics>` list and the `::[attrs]` slot are optional
(`mod legacy::[timecheck=false](…)`, `mod add<T>::[…](…)`); `-> (outputs)` is
mandatory (`-> ()` for none; only a `self` method may omit it). In `pipe[N]`
the latency `[N]` is part of the keyword, and a bare `pipe` lets the caller
pick it (see [Functions](06-functions.md#declaration)).

This rule applies uniformly, including inside **tuple literals**: any
**named** field must start with one of these kind keywords. Bare
`field = value` inside a data-tuple literal is a compile error.
Bare named values are still valid at call sites (`foo(a=3, b=4)`) and when an
explicit type on the destination provides the field declarations
(`const p:Point = (x=1, y=2)`).

A **positional** (unnamed) field is just a value expression and inherits
its mutability from the enclosing tuple. To override that mutability on a
single positional field, prefix the value with `const` or `mut` —
`(1, const 3)` is two positional fields, the second one immutable.
A tuple literal is either all named or all positional: mixing the two
(`(1, const b=2)`) is a compile error (see [Tuples](03-bundle.md)).
Positional fields take no name slot, so `const _ = 3` is not valid (and
bare `_` is reserved as a future placeholder, see
[Identifiers](02-basics.md#identifiers)).

```pyrope
const point = (mut x:U8 = 0, mut y:U8 = 0)

const counter_iface = (
  ,mut value:U8 = 0
  ,comb read(self) -> (v:U8)      { v = self.value }
  ,comb inc(ref self)             { wrap self.value += 1 }
  ,mod `tick`(ref self, enable:Bool) { if enable { wrap self.value += 1 } }
)

mut y = (1, const 3)              // 2nd field positional and immutable
```

Named-argument passing in calls (`foo(a=3, b=4)`) is **not** a declaration
— the names are matched against the callee's declared parameters — so no
kind keyword is required there.

The generics list after a lambda name (`<T, N=4>`) declares explicit
compile-time parameters — types, constants, or lambdas (see
[Functions](06-functions.md)).
It is not a capture list. Name lookup is lexical: lambdas can read visible
comptime bindings from enclosing scopes (`comptime const`, a plain `const`
whose value is a compile-time constant such as a file-scope `const x = 2`,
generics of the enclosing lambda, the index of an enclosing `for`, imports,
types, and lambdas). Reading an enclosing **runtime** value — a `const`
computed from a runtime value, a `mut`, `reg`, `wire`, input, or the element
of a `for` over runtime values — is a compile error; pass the value as a
normal input.
Reading a name with no accessible declaration is a compile error at the read,
never `nil`. The compiler records lexical comptime references as explicit
comptime dependencies of the lambda.


=== "Code Block scope"

    ```pyrope
    assert(a == 3) // error: undefined variable 'a'
    mut a = 3
    {
      assert(a == 3)
      a = 33             // OK. assign 33
      a = Signed(33)        // OK, explicit conversion/check on the RHS
      const b = 4
      const a = 3333       // error: variable shadowing
      mut a = 33         // error: variable shadowing
    }
    assert(b == 3) // error: undefined variable 'b'
    ```

=== "Lambda scope"

    ```pyrope
    assert(a == 3) // error: undefined variable 'a'
    comptime const A = 3
    comptime const X = A + 1
    comb f1() -> (r) {
      cassert(A == 3)
      // A = 33          // error: comptime const is immutable
      const b = 4
      // const A = 3333  // error: variable shadowing
      // mut A = 33      // error: variable shadowing
      r = b + 3
    }
    assert(f1() == 7)
    assert(b == 3) // error: undefined variable 'b'

    mut a = 3
    const k = 2          // current value is known at compile time
    comb f2() -> () {
      cassert(k == 2)    // OK: `k` is a constant
      // assert(a == 3)  // error: runtime outer variable not visible
    }
    mod m(i:U8) -> (o:U9@[0]) {
      const s = i + 1    // computed from the input `i`: a runtime value
      comb f3() -> (r:U9) {
        // r = s         // error: `s` is runtime; pass it as an input
        r = k            // OK
      }
      o = f3()
    }
    ```

=== "Tuple scope"

    ```pyrope
    mut base = 3
    const r1 = (
      ,mut a = base+1    // tuple fields must use a kind keyword
      ,const c = {assert(a == 4); 50}
    )
    r1.a = 33            // error: 'r1' is immutable variable

    mut r2 = (mut a=100, const c=(mut next=a+1, const e=next+30))
    assert(r2 == (const a=100, const c=(const next=101, const e=131))) // checks values not mutability
    r2.a = 33            // OK
    r2.c.next = 33       // error: 'r2.c' is immutable variable

    const r3 = (a = 1)   // error: tuple field missing kind keyword
    ```

* Shadowing is not allowed in lambdas or code blocks. A visible enclosing
  comptime binding counts: a lambda local or loop index named like a
  file-scope `const x = 2` shadows it. Tuple field initializers follow program
  order and can read earlier tuple fields by name.

* Data tuple literals do not have a `self` binding. The `self` name is only
  available when declared as a lambda argument, such as in tuple methods.

* Tuple upper scope variables are always immutable.

* Lambdas lexically see only visible comptime bindings from upper scopes
  (a `const` with a compile-time value included). Runtime upper scope values
  (file-scope ones included) must be passed explicitly.

* A variable is visible from definition until the end of scope in program order.


Since lambda inputs and generics are always immutable, it is not
allowed to declare them as `mut` and redundant to declare them as `const`.


Tuple scope is also useful for declaring function default values:

```pyrope
comb example(a:Signed, b:Signed=a+5) -> (result:Signed) {
  result = a + b
}
cassert(example(a=3) == (3+3+5))
cassert(example(a=6,b=7) == (6+7))
cassert(example(a=6) == (6+6+5))
assert(example(b=3) !=0) // error: undefined `a` argument
```

A default does not change what kind of unit a `comb` is. Only a `comb` with
an untyped input or with generics is a template, inlined at each call with no
module of its own. A fully typed `comb` stays a normal unit with its own module
(it can be the compile top) even when an input has a default:
`comb inc(a:U8, b:U8=1) -> (r:U9)` has a real `b` port, and the default
applies only at a call site that omits `b` (see
[Functions](06-functions.md#declaration)).

## Basic types

Pyrope has 9 basic types:

* `Bool`: `true` or `false`, or an unknown comparison result (`0sb?`).
  `Bool(x)` is the cast from an integer.
* `Clock` / `Reset`: the clock and reset wires of registers, described in the
  [type system](07-typesystem.md#clock-and-reset)
* `enum`: enumerated values, optionally with a per-case payload (the equivalent of a tagged union)
* `comb`: A function or pure combinational logic
* `Signed`: a signed integer of unlimited precision
* `mod`: A module with state/clock or side-effects
* `range`: A one hot encoding of values `1..=3 == 0ub1110`
* `String`: which is a sequence of characters

All the types except functions and `Clock` can be converted back and forth to
an integer. A `Clock` is not data: `U1(clk)` is a compile error, and its
numeric view (a cycle counter in simulation) is readable only in debug
contexts (tests, `puts`, `assert`/`cassert`). A `Reset` is Bool-like.

Built-in type names are capitalized: `U<num>`, `S<num>`, `Unsigned`,
`Signed`, `Bool`, `String`, `Clock`, and `Reset`. They are reserved type
words, and the old lowercase spellings (`u8`, `s20`, `i32`, `bool`,
`string`, ...) are **banned words**: a compile error in every position, names
included (`s1`, `i0`, `u4`). A backticked reserved or banned word is an
ordinary name. The full rules are in
[Built-in types](07-typesystem.md#built-in-types) and
[Identifiers](02-basics.md#identifiers).

```pyrope
mut s1 = 3            // error: `s1` is a banned word (the type is `S1`)
mut st1 = 3           // OK
mut `s1` = 3          // OK: backticked, an ordinary name
mut U4 = 3            // error: `U4` is a reserved type word
mut `U4` = 3          // OK: a variable named U4, not the type
mut g:u8 = 0          // error: `u8` was renamed `U8`
```


### Integer or `Signed`

Integers have unlimited precision and they are always signed. Unlike most other
languages, there is only one type for integer (unlimited), but the type system
allows to add constraints to be checked when assigning the variable contents.
Notice that the type is the same (`U32` is the same type as `S3`, they just have
different constraints). The `does` operator compares the range envelope: `a does
b` is true when `a`'s range is a superset of `b`'s (`a.max >= b.max and a.min <=
b.min`). So `U32 does U16` is true (U32's range covers U16's) but `U16 does U32`
is false. Assignment still performs the additional range and precision checks
described in the attribute section:

* `Signed`: an unlimited precision integer number.
* `Unsigned`: the same as `Signed(min=0)` — a de-facto unsigned integer. There is
  nothing special beyond the constraint, but it usually allows nicer Verilog
  generation (`logic` vs `signed logic`).
* `U<num>`: An integer basic type constrained to be a natural number with a maximum value of $2^{\texttt{num}}-1$. E.g: `U10` can go from zero to 1023.
* `S<num>`: a signed (2s complement) number with a maximum value of $2^{\texttt{num}-1}-1$ and a minimum of $-2^{\texttt{num}-1}$.
  There is no `I<num>`/`i<num>` spelling: `i32` is a compile error (write `S32`).
* `Unsigned(bits=N)` / `Signed(bits=N)`: the same as `U<num>`/`S<num>` when the width
  is a comptime expression, such as a generic. `num` in `U<num>` is a literal,
  so a generic width has no `U<num>` form. It is valid wherever a type is: ports, locals,
  tuple field types, array elements (`[N]Unsigned(bits=N)`), type aliases
  (`type Row = Unsigned(bits=N)`), and generic arguments.

```pyrope
mut a:Signed         = nil // any value, no constrain
mut b:Unsigned    = nil // only positive values
mut c:U13         = nil // only from 0 to (1<<13)-1
mut d:Signed(min=20, max=30) = nil // only values from 20 to 30 (both included)
mut e:Signed(min=-5, max=5) = nil // only values from -5 to 5 (both included)
mut f:Signed(min=-1, max=0) = nil // 1 bit integer: -1 or 0
mut g:i8          = nil // error: `i8` was renamed `S8`

comb pad<N=8>(a:Unsigned(bits=N)) -> (y:Unsigned(bits=N+1)) { y = a }
```

A type word can head a suffix chain: `U8.[max]` reads an attribute of the
type, and `U8(x)#[0]` selects a bit of the cast result. A type has no fields,
so `U8.x` is an error.

```pyrope
cassert(U8.[max] == 255)
cassert(U8(6)#[1] == 1)
const bad = U8.x      // error: a type has no fields
```

Integers can have 3 value (`0`,`1`,`?`) expression or a `nil`. Section
[Integers](02-basics.md#integers) has more details, but those values can not be
part of the type requirement.


Integer typecast accepts strings as input. The string must be a valid formatted
Pryope number or an assertion is raised.


### Boolean

A known boolean is either `true` or `false`. Comparisons involving unknown
bits can produce an unknown boolean (`0sb?`), which may be bound to a variable:

```pyrope
const flag = 0sb? == 0       // legal: flag is 0sb?
cassert(flag)               // error: an unknown result cannot satisfy cassert
```

Booleans can not mix with integers in
expressions unless there is an explicit typecast (`U1(false)==0`,
`U1(true)==1`, `Bool(0)==false`, and `Bool(1)==true`). A typecast from integer to
boolean will raise an assertion when the integer is a comptime and has
undefined bits (`?`) or `nil`. Like with `unique if...` chains that generate a
hotmux and the compiler does a quick formal to check that it is unique, we do
the same for `Bool(x)` conversion to check that it is known (not `?`) but
there is a quick timeout. Unlike `unique if` that falls the unfinished checks
to simulation, we can not know at simulation because we do not do unknowns at
simulation. So a raised error is a guarantee of error, but a not-raised is not
a guarantee (just a warning is issued).


Hardware realizes a boolean result as one unsigned bit (`U1`): false is `0`
and true is `1`. The idiomatic bool->bit conversion is `U1(b)`;
`Unsigned(b)` and `U<num>(b)` also preserve true as `1`. An explicit
`Signed(b)` or `S<num>(b)` cast deliberately reinterprets that single bit as
signed, so true becomes the one-bit signed all-ones value `-1`. That is a
reinterpretation, not the way to turn a flag into a number.

```pyrope
const b = true
const c = 3

if c    { call(x) }  // error: 'c' is not a boolean expression
if c!=0 { call(x) }  // OK

mut d = b or false   // OK
mut e = c or false   // error: 'c' is not a boolean

const e = 0xfeed
if Bool(e#[3]) {  // OK, explicit conversion from unsigned bit to boolean
  call(x)
}

cassert(U1(true)  == 1)           // the bool->bit idiom
cassert(U1(false) == 0)
cassert(0 == (Signed(true)  + 1)) // reinterpretation: true is signed all-ones
cassert(1 == (Signed(false) + 1)) // explicity typecast
cassert(Bool(33) or false) // explicity typecast
```

A `Bool` is a legal port on every lambda and at every level, including the
top-level IOs, where it is a 1-bit port (true is `1`). Declare a port `U1` only
where the value is used as a number. Booleans and integers do not mix at port
boundaries or on instance outputs either: bind an integer bit to a `Bool` input
with `Bool(x)` (or `x == 1`), and use a `Bool` output as a number with
`U1(child.flag)`. A wider integer into a `Bool` port is an error.

```pyrope
mod child(go:Bool, n:U4) -> (flag:Bool@[0]) {
  flag = go and n != 0
}

mod parent(v:U8) -> (cnt:U9@[0]) {
  const c = child(go=Bool(v#[0]), n=v#[4..<8]) // OK: bit -> bool input
  cnt = v + U1(c.flag)                             // OK: bool output -> bit
  // child(go=v#[0], n=0)                          // error: a U1 into a Bool port
  // cnt = v + c.flag                              // error: Bool used as an integer
}
```

String input typecase is valid, but anything different than ("0", "1", "-1",
"true", "TRUE", "t", "false", "FALSE", "f") raises an assertion failure.

Logical and arithmetic operations can not be mixed.

```pyrope
const x = a and b
const y = x + 1    // error: 'x' is a boolean, '1' is integer
```

### Functions (`comb`/`pipe`/`mod`)

Functions have several options (see [Functions](06-functions.md)), but from a
high level they provide a sequence of statements and they have a tuple for
input and a tuple for output. Functions can have generics (explicit
compile-time type/constant/lambda parameters)
and can lexically read visible comptime bindings from enclosing scopes. Like
strings, functions are always immutable objects but they can be assigned to
mutable variables.


### Range

Ranges are very useful in hardware description languages to select bits. They
are 3 ways to specify a closed range:

* `first..=last`: Range from first to the last element, both included
* `first..<last`: Range from first to last, but the last element is not included
* `first..+size`: Range from first to `first+size`. Since there are `size`
  elements, it is equivalent to write `first..<(first+size)`.

When used inside selectors (`[range]`) ranges can be open (no first/last
specified). Negative selector indices are compile errors; there is no
distance-from-end indexing. Use an open range such as `[first..]` to select
through the end.

```pyrope
const a = (1,2,3)
cassert(a[0..] == (1,2,3))
cassert(a[1..] == (2,3))
cassert(a[..=1] == (1,2))
cassert(a[..<2] == (1,2))
cassert(a[1..<10] == (2,3))

const b = 0ub0110_1001
cassert(b#[1..]        == 0ub0110_100)
cassert(b#[0]          == 1)
const bad = b#[-1]     // error: negative selector index
const bad2 = b#[1..=-1] // error: decreasing/negative-end selector range
```


A range is a valid unnamed tuple and can compare directly with an unnamed
tuple; no explicit `tuple(...)` conversion is required. If the range does not
contain negative values, it can be converted to an integer back and forth
using a one-hot encoding.

Range type cast from integers use the same one-hot encoding. It is not possible
to type cast from tuple to range, but it is possible from range to tuple.

```pyrope
const c = 1..=3
cassert(Signed(c) == 0ub1110)
cassert(range(0ub01_1100) == 2..=4)

assert(range(1,2,3)) // error: typecast not allowed
cassert((1,2,3) == tuple(1..=3))
```

In most cases, the range can be used in contructs like `for` for positive and
negative numbers. The `tuple` typecast is not needed, but if placed the
semantic is the same. The same `tuple` typecast is also optional when doing a
comparison. Both ranges a `step` to change the step. The `step` amount must be
a positive integer.

```pyrope
cassert(Signed(0..=10 step  2) == 0ub101_0101_0101)
cassert(tuple(0..=10 step  2) == ( 0,2,4,6,8,10))

cassert(-1..=2 == (-1,0,1,2))
const x = -1..=2

cassert((0..=10 step 2) == (0,2,4,6,8,10))
```

Since the range is an integer, a decreasing range should have the same meaning
that an increasing range (`1..=3 == 3..=1`) but to avoid mistakes/confusions,
Pyrope generates a compile error in decreasing ranges. Only ascending ranges
are allowed — there is no descending form, and a negative or zero `step` is
also a compile error.

```pyrope
assert(5..=0)          // error: 5 never reaches 0
assert(5..=0 step -1)  // error: descending ranges are not allowed
assert(0..=10 step -1) // error: range step must be a positive integer
```

A closed range can be converted to a single integer or a tuple. A range
encoded as an integer is a set of one-hot encodings. As such, there is no
order, but in Pyrope, ranges always have the order from smallest to largest.
The `step expr` can be added to indicate a step or step function. This is only
possible when both begin and end of the range are fully specified.


```pyrope
cassert((0..<30 step 10) == (0,10,20)) // ranges and tuples can combined
cassert((...(1..=3), 4) == (1,2,3,4))   // tuple and range ops become a tuple
cassert(1..=3 == (1,2,3))
cassert((1..=3)#[..] == 0ub1110)        // convert range to integer with #[..]
```

The last line deserves attention, because the line above it says that `1..=3
== (1,2,3)` and yet `#[..]` gives the two spellings different words. This is
intentional. `#[..]` is the full bit vector of a value, and it asks the *type*
for that bit vector: a positional tuple answers with the packing of its
entries, entry 0 in the lowest bits, while a `range` is its own type and
answers with the one-hot set encoding above. The equality compares the values a
range enumerates, not how either type is laid out in bits.

The tuple side would not have an answer here anyway. In a packing every entry's
width comes from its declared type, never from the value or the literal's
spelling, so `(1,2,3)#[..]` is an error rather than a different number: a tuple
of untyped literals states no layout. See [Reduce and bit selection
operators](#reduce-and-bit-selection-operators), and the bit packing rules in
[internals](10-internals.md).

### String

Strings are an opaque basic type. They do not spread into character tuples
and do not support bit packing, bit reductions, or numeric reinterpretation.
Use `String(value)` to render an integer as decimal text. String literals,
escapes, and interpolation are described in [Strings](02-basics.md#strings);
string methods in the [standard library](13-stdlib.md).

```pyrope
const value = 123
cassert(String(value) == "123")
```

## Type declarations

Each variable has a type, either implicit or explicit, and as such, it can be
used to declare a new type.

Pyrope provides a `type` keyword for type declarations. It is equivalent to
a `const` whose value is a type (tuple shape or lambda signature); `type`
simply makes the intent explicit and is the recommended spelling when
declaring types ahead. It is recommended to start type names with
Uppercase. **Complicated lambda types cannot be written inline in a
`foo:Type` annotation — declare them ahead with `type` and reference them
by name.**

```pyrope
comb check_is_green(self) -> (r:Bool) { r = self.color == "green" }

type IsGreen = comb(self) -> (r:Bool)

mut Bund1 = (mut color:String = "", mut value:S33 = nil)
mut x:Bund1    = nil    // OK, declare x of type Bund1 with default values
Bund1.color    = "red"  // OK
Bund1.is_green = check_is_green
x.color        = "blue" // OK

type Typ = (mut color:String = "", mut value:S33 = nil, mut is_green:IsGreen = nil)
mut y:Typ    = nil      // OK
Typ.color    = "red"    // error:

Typ.is_green = check_is_green
y.color      = "red"    // OK

type Bund3 = (mut color:String = "", mut value:S33 = nil)
mut z:Bund3    = nil                // OK
Bund3.color    = "red"              // error:
Bund3.is_green = check_is_green     // error: (const can not add fields)
z.color        = "blue"             // OK

assert(x equals Typ) // same type structure
assert(z equals Typ) // same type structure
assert(x equals z) // same type structure
```

## Type checks

A `:Type` annotation is **only** valid at a declaration site (`mut`, `reg`,
`const`, `comb`, `pipe`, `mod`, lambda parameters, lambda return types, and
tuple field declarations). Once the variable is declared, the type is set
for its whole existence.

To check that an existing value matches a type, use the `does` operator
inside `cassert`/`assert`. To convert a value to a type, call the
type as a constructor — `U8(value)`.

```pyrope
mut a = true                // infer a is a boolean

cassert(a does Bool) // type check on an existing variable
foo = a or false            // ordinary use; no inline type annotation
```

## Attributes

Attributes are the mechanism for the programmer to specify special
checks/functionality that the compiler should perform (bitwidth constraints,
`comptime`, `debug`, synthesis hints, register/memory configuration, …). They
are bound at declaration with `::[…]` and read at use sites with `.[…]`.

See [Attributes](04b-attributes.md) for the full description, the reserved
attribute lists, and the `wrap`/`sat`/`comptime`/`debug` statement-level
prefix modifiers.

## Register

Both mutable and immutable variables are created every cycle. To have
persistence across cycles the `reg` type must be used.


```pyrope
reg counter:U32   = 10
mut not_a_reg:U32 = 20
```

In `reg`, the right-hand side of the initialization (`10` in the
counterexample) is called only during reset. In non-register variables, the
right-hand side is called every cycle. Most of the cases `reg` is mutable but
it can be declared as immutable.

### Tuple registers

A `reg` of tuple type is not a single wide flop: **each field is its own
register**, with its own reset value. A field that is never written holds its
value, and a field written on some paths only holds on the others (the same
implicit hold a scalar `reg` has).

Field reads and writes then obey the same two rules a scalar `reg` obeys:

* A read of a register field is the field's **current state**, no matter where
  the read sits relative to the writes of the same cycle. Program order decides
  what is written, never what is read.
* The **last write in program order wins**, so an unconditional write is the
  default for the cycle and a later conditional write overrides it.

```pyrope
reg flags:(active:Bool, delayed:Bool) = (active=false, delayed=false)

flags.active  = false         // the default for this cycle
flags.delayed = flags.active  // the PREVIOUS cycle's flags.active
if request {
  flags.active = true         // overrides the default
}
```

`flags.delayed` samples last cycle's `flags.active` even though the statement
just above assigns `flags.active`: a write only picks what the flop captures at
the next clock edge. To read a next-state value in the same cycle, name it as a
[`wire`](#wire-single-driver-combinational-nets) and read the wire.

A `reg` of array type is different: it is a memory, not a bank of per-entry
flops. See [Memories](08-memories.md).
## Wire: single-driver combinational nets

A `wire` declares one **combinational** net with exactly **one driver**,
modeled on the Verilog continuous-assign / net. Unlike `mut` (whose value is
the last write in *program order*, and where a read-before-write is an error),
a `wire` may be **read before its driver appears textually**: every read
observes the single resolved driver, independent of statement position.

Removing *program order* is the whole point: it is what lets a Verilog module
interconnect be expressed directly. When the driver already precedes every read,
a `const x = nil` forward declaration says the same thing about the value and
additionally checks def-before-use — prefer it, and reach for `wire` when a read
genuinely comes first.

```pyrope
wire x = nil           // forward declaration: an as-yet-undriven net
                       // reads of 'x' here are legal
x = some_expr          // the one driver (may appear later in program order)

wrap wire y:U8 = a + b // declare and drive in one statement (U8: needs `wrap`)
```

Exports use `pub const`, `pub` lambdas, or `pub` types. A wire cannot be exported.

Rules:

* **Exactly one driver.** The driver may be a mux — an `if`/`match`
  *expression*, or mutually-exclusive conditional assignments. A second
  *unconditional* assignment is a compile error. One `if`/`match` statement
  counts as a single driver, however many of its arms write the net.
* The driver may be **conditional**, and it need not cover every path. A
  `wire` is defined by its one assignment, so wherever that assignment sits
  the net carries its value on *every* path — writing it inside an `if` with
  no `else` means the same as writing it unconditionally. An un-taken path is
  a don't-care, not an unknown: there is no mux against a `nil`/`x` default.
* `wire x = nil` forward-declares an undriven net; a `wire` still `nil` at the
  end of elaboration (never driven at all) is a compile error.
* `wire` removes *textual* ordering only, not cyclic dataflow. A `wire`
  combinationally driven by a function of itself is a real combinational loop
  and is rejected (the standard combinational-cycle / SCC check). A ring is
  legal only when a `reg` breaks it.
* A `for`/`while`/`loop` body may **read** a `wire` (the compiler then unrolls
  that loop instead of keeping it compact), so a read needs no hoisting. It
  may not **write** (drive) one: the body runs once per iteration, so a write
  there would be one driver per iteration and break the single-driver rule.
  Drive the wire outside the loop. See
  [Loops and `wire`](05b-statements.md#loops-and-wire).

Primary uses are closing module-interconnect rings without ordering
gymnastics, and routing a computed reset/flush into a register `reset_pin`
(`reg r:U2:[reset_pin=my_wire] = 0`; a `*_pin` takes the signal directly,
without `ref`, and a `Reset` accepts a `Bool` net without a cast).

```pyrope
// close a ring without reordering the calls:
wire f4 = nil
f1 = ring(x=a, prev=f4) // reads f4 before its driver appears
f2 = ring(x=b, prev=f1)
f3 = ring(x=c, prev=f2)
f4 = ring(x=d, prev=f3) // the single driver of f4
```


## Visibility: private by default, `pub` to export

All declarations are **private by default**: they can not be accessed from
other files by `import`. The `pub` prefix modifier (same declaration slot as
`comptime`) exports a top-scope declaration for import:

* `pub` on a top-scope lambda, type, or constant allows other files to
  `import` it.
* `pub mut`, `pub reg`, and `pub wire` are compile errors. Registers, including memories,
  are not imported or exported as values. Cross-scope register access is
  planned through the *synthesizable, multi-match* `regref`, which would resolve
  instantiated registers by hierarchy path or name — TBD, see
  [Register reference](07-typesystem.md#register-reference) and
  [Memories](08-memories.md#shared-memories-with-regref). A `formal` block does
  not need it: it reaches registers through the ordinary instance hierarchy
  (`acc.core0.count`). A `test` block additionally has the single-cell
  [`regref`](05b-statements.md#test-only-statements), which is a
  different, already-implemented construct.

```pyrope
pub comb get_five() -> (v) { v = 5 }  // importable by other files
pub const default_depth = 1024         // importable constant
reg internal:U8 = 0                   // private: this file/instance only

pub comb my_log::[lg="foo_mod"](a) -> (r) { r = a } // lgraph named foo_mod
```

A `pub` lambda may pin the name of its generated lgraph (the netlist/Verilog
module name) with the `lg` attribute. This renames only the generated
artifact — `import` still uses the declared name (`my_log` above). See
[lg: explicit lgraph name](04b-attributes.md#lg-explicit-lgraph-name).

**Debug is exempt from visibility.** Debug statements (`assert`, `test`,
`puts`, monitors) can observe any storage cell read-only through bare dotted access, and a
`test` block can additionally drive one through `regref`. Visibility restricts
`import` only; nothing can be hidden from verification. There is no
`private` attribute.

For tuple fields, a leading underscore (`_field`) marks the entry as
private to the tuple: it can not be accessed outside the tuple methods,
but debug statements can still read it (see
[debug attribute](04b-attributes.md)).


## Operators

There are the typical basic operators found in most common languages except
exponent operations. The reason is that those are very hardware intensive and a
library code should be used instead.

All the operators work over unlimited precision signed integers. The one
operator whose result depends on the operand's declared type is `~` (below).

### Unary operators

* `!a` or `not a` logical negation
* `~a` bitwise negation
* `-a` arithmetic negation

`!a`/`not a` needs a `Bool` operand: on an integer it is a compile error
(write `a == 0`, or `a#[0] == 0` for one bit).

A bitwise not is ambiguous unless the operand's type is known, so `~a` needs
one:

* On an **unsigned-typed** operand of known width `N` it flips exactly those
  `N` bits: `~a == (2^N - 1) - a`, and the result is a `U<N>` (a `U1` toggles
  between 0 and 1). An operand is unsigned-typed when its type states the
  width: a name declared with an unsigned type (a variable, a port, a
  register, a tuple field, an instance output; `N` is its `.[bits]`, so
  `Unsigned(max=5)` flips 3 bits), an untyped `const` alias of one (`const t
  = w` has `w`'s type), an element `arr[i]` of an `[M]U<N>` array, a bit slice
  `a#[..]` (`a#[i]` is a `U1` for any position `i`), a `U<N>(...)` cast, or a
  `~`, `&`, `|`, `^` whose operands are all unsigned-typed (the widest one
  sets `N`). An untyped input of a template `comb` takes its argument's type
  at each call, as its `.[bits]` does.
* On a **signed-typed** operand (`S<N>`, a `Signed(...)`/`S<N>(...)` cast, a
  bitwise op over typed operands one of which is signed) `~a == -a - 1`, the
  two's complement at its width.
* A **compile-time** integer with no type (`~5`, `const k = 5; ~k`) is a
  signed integer: `~a == -a - 1`.
* An **untyped runtime** value (an arithmetic result such as `~(a + 1)`, a
  `mut` bound without a type, a bitwise op with a literal operand, an
  `if`/`match` expression, which is not an alias of one value) is a
  compile error: give it a type (`const t:U9 = a + 1`) or slice it
  (`(a + 1)#[0..<8]`).

```pyrope
const x:U1 = 0
const w:U3 = 2
const s:S4 = 2
const t    = w          // an alias of `w`: a U3 too
cassert(~x == 1)        // U1: 0 <-> 1
cassert(~w == 5)        // U3: 7 - 2
cassert(~s == -3)       // signed: -2 - 1
cassert(~t == 5)        // the alias flips w's 3 bits
cassert(~2 == -3)       // compile-time integer: -2 - 1
cassert(~w#[0..<2] == 1)  // a 2-bit slice flips 2 bits
cassert(~U8(w) == 253)  // the cast makes it a U8
```

A wider destination does not widen the flip: `y:U8 = ~w` is 5. To flip a
wider window, give the operand that width first (`~U8(w)`, `~w#[0..<8]`).

### Binary integer operators

* `a + b` addition
* `a - b` substraction
* `a * b` multiplication
* `a / b` division
* `a % b` modulo (hardware only for a power-of-two/`3`/larger-than-`a` divisor; see [basics](02-basics.md))
* `a & b` bitwise and
* `a | b` bitwise or
* `a ^ b` bitwise xor
* `a >> b` arithmetic right shift
* `a#[..] >> b` logical right shift
* `a << b` left shift

There are no binary nand/nor/xnor operators: negate the bitwise result,
`~(a & b)`, `~(a | b)`, `~(a ^ b)`. The `~` rule above applies to the result:
when both operands are unsigned-typed the widest operand's bits flip
(`a:U3`, `b:U5`: `~(a & b)` is `31 - (a & b)`), a signed-typed operand gives
`-(a & b) - 1`. The bit-select reductions (`x#&[..]`, `x#|[..]`, `x#^[..]`,
`x#+[..]`) have no negated forms either: compare the reduction instead
(`x#&[..] == 0` is a nand reduction).

In the previous operations, `a` and `b` need to be integers. The exception is
`a << b` where `b` can be a tuple. The `<<` allows having multiple values
provided by a tuple on the right-hand side or amount. This is useful to create
one-hot encodings.

```pyrope
cassert(1<<(1,4,3) == 0ub01_1010)
```


### Binary boolean operators

* `a and b` logical and
* `a or b` logical or
* `a implies b` logical implication


Negation uses the unary `not` (e.g. `not (a and b)` for nand). There are no
dedicated `!and` / `!or` / `!implies` operators.

### Tuple/Set operators

* `a in b` is element `a` in tuple `b`. Negate compositionally with
  `not (a in b)`.

Most operations behave as expected when applied to signed unlimited precision
integers.

The left operand of `a in b` is a scalar. Membership checks the values in
the right operand; field names do not participate in the comparison.

```pyrope
cassert(2 in (0, 1, 3, 2, 4))
cassert(not (5 in (0, 1, 3, 2, 4)))
```

* `(...a, ...b)` concatenate two tuples (splice). A tuple is either all named
  or all unnamed (see [Tuples](03-bundle.md)), and so is the splice result:
  * Two **unnamed** tuples append: `b`'s entries follow `a`'s.
  * Two **named** tuples merge: a field present on only one side is copied
    in. When the same field appears on both sides it is a compile error,
    unless one side is `nil` (the other side wins) or constant propagation
    proves both sides hold the same value (matching tuple-valued fields
    merge recursively). An unknown `0sb?` is not `nil` and does not yield.
  * Splicing a named tuple with an unnamed one is a compile error.

  The splice inserts each tuple's entries at its position, so it can also
  insert in the middle of a literal and add arguments to a function call
  (`foo(a=1, ...rest)` with a named `rest`).

```pyrope
cassert((...(const a=1, const c=3), ...(const a=1, const b=2, const c=nil)) == (const a=1, const c=3, const b=2))
cassert((...(1,2), ...(nil, 5)) == (1, 2, nil, 5))

const bad  = (...(const a=1), ...(const a=2))  // error: 'a' defined with different values on both sides
const bad2 = (...(1,2), ...(const a=2))        // error: splices an unnamed and a named tuple
const bad3 = (1, const b=2)                    // error: a tuple mixes unnamed and named entries
const bad4 = (...(const x=1), ...(const x=0sb?)) // error: 'x' on both sides and neither is nil

// the splice can also insert in the middle of a literal:
cassert((1, 2, ...(3, 4), 6) == (1, 2, 3, 4, 6))
cassert((const a=1, ...(const b=nil, const c=3), const d=6) == (const a=1, const b=nil, const c=3, const d=6))
```

* `a ++ b` is the tuple-concat operator, a shorthand for the two-tuple splice
  `(...a, ...b)` with the exact same semantics (append for unnamed, field-name
  merge for named, same same-field/`nil` rules, mixing is an error). It is a
  priority-3 ("other binary") associative operator, so `a ++ b ++ c` chains
  left-to-right. The `++=` compound-assign form appends in place (`acc ++= b`
  is `acc = acc ++ b`).

```pyrope
const a = (1, 2)
const b = (3, 4)
cassert((a ++ b) == (...a, ...b))
cassert((a ++ b) == (1, 2, 3, 4))
cassert(((1,2) ++ (3,4) ++ (5,6)) == (1, 2, 3, 4, 5, 6))

const n = (const foo=2)
const m = (const bar=4)
cassert((n ++ m) == (const foo=2, const bar=4))
const bad = a ++ n   // error: an unnamed tuple ++ a named tuple

mut acc = (0,)
acc ++= a            // acc = acc ++ a
cassert(acc == (0, 1, 2))
```


### Type operators

* `a has b` checks if `a` tuple has the `b` field where `b` is a string (a
  named tuple) or integer (a position of an unnamed tuple).

```pyrope
cassert((const a=1, const b=2) has "a")
```

* `a does b` is true when `a` has all the tuple structure required by `b`
* `a equals b` same as `(a does b) and (b does a)`
* `a case b` same as `(a does b)` plus value matching for every defined value
  in `b`. Values in `b` that are undefined (`nil`, `0sb?`) act as wildcards.

Negate any type operator with `not (...)`, e.g. `not (a does b)`,
`not (a equals b)`, `not (a case b)`.

A tuple is either all named or all unnamed. The `does` performs name
matching when the required tuple is named, and position matching when it is
unnamed. A named tuple has no positions and an unnamed tuple has no names, so
one never `does` the other. Values are ignored by `does`; use `case` when the
values should be matched too.

```pyrope
cassert((const b=100, const a=333, const e=40) does (const a=1, const b=3))
cassert((100, 300, 5) does (1, 3))
cassert(U32 does U16)          // U32's range is a superset of U16's
cassert(not (U16 does U32))    // U16's range is NOT a superset of U32's
cassert(not (U32 does String)) // different basic type → false
cassert((100,30) does 30)
cassert(not (30 does (30,200)))
cassert(not ((const a=3) does (30, 200)))           // named vs unnamed
cassert(not ((3, 30) does (const a=3)))             // unnamed vs named
cassert(not ((const a=3) does (const a=30, const b=200)))  // 'b' missing
```

A `a case b` first checks `a does b`, then checks that every defined value in
`b` has the same value in `a`. Undefined values in `b` (`nil`, `0sb?`) do not
participate in the value check and act as wildcards. This can be used in any
expression but it is quite useful for `match ... case` patterns.

```pyrope
match (const a=1, const b=3) {
  case (a=1) { cassert(true) }
  else { cassert(false) }
}

match const t=(const a=1, const b=3); t {
  case (a=1, c=4) { cassert(false) }
  case (b=nil, a=1) { cassert(t.b==3 and t.a==1) }
  else { cassert(false) }
}
```

An `x = a case b` can be translated to:

```pyrope
___0 = a does b
___1 = b in a
x = ___0 and ___1
```

### Reduce and bit selection operators

The reduce operators and bit selection share a common syntax
`variable#op[sel]` where:

+ `variable` is a tuple where all the tuple fields and subfields must have a
  explicit type size unless the tuple has 1 entry.

+ `op` is the operation to perform

    * `|`: or-reduce.
    * `&`: and-reduce.
    * `^`: xor-reduce or parity check.
    * `+`: pop-count.
    * `sext`: Sign extends selected bits.
    * `zext`: Zero extends selected bits (default option)

+ `sel` is a single expression: an integer (one bit), a close-range like
  `1..=4`, or an open range like `3..`. Internally, the open range is converted
  to a close-range based on the variable size. Multi-entry tuple indices like
  `#[1,4,6]` are not allowed; use one bit-range assignment per group of bits.


The or/and/xor reduce have an unsigned integer result with `min=0` and `max=1`
(not boolean). This means that the result can be `0` or `1`. Since booleans and
integers do not mix, compare a reduction against integer values, or cast
explicitly when comparing with a boolean (`Bool(x#|[..]) == flag` or
`x#|[..] == U1(flag)`). pop-count and `zext` have always positive results.
`sext` is sign-extended, so it can be positive or negative.

If no operator is provided, a `zext` is used by default. The bit selection without
operator can also be used on the left-hand side to update a set of bits.


The or-reduce and and-reduce are always size insensitive. This means that to
perform the reduction it is not needed to know the number of bits. It could
pick more or fewer bits and the result is the same. E.g: 0sb111 or 0sb111111
have the same and/or reduce. This is the reason why both can work with open and
close ranges.


This is not the case for the xor-reduce and pop-count. These two operations are
size insensitive for positive numbers but sensitive for negative numbers. E.g:
pop-count of 0sb111 is different than 0sb111111. When the variable is negative
a close range must be used. Alternatively, a `zext` must be used to select
bits accordingly. E.g: `variable#[0..=3]#+[..]` does a `zext` and the positive result
is passed to the pop-count. The compiler could infer the size and compute, but
it is considered non-intuitive for programmers.


```pyrope
const x = 0ub1_0110   // positive
const y = 0sb1_0110   // negative
cassert(x#[2]    == 1)
cassert(x#[0..=2] == 0ub110)
cassert(y#[100]       == 1   and x#[100]       == 0) // out-of-range follows sign
cassert(y#sext[0..=2] == 0sb110 and x#sext[0..=2] == 0ub110)
cassert(x#|[..] == 1)
cassert(x#&[0..=1] == 0)
cassert(Bool(x#|[..]) == true)
cassert(x#+[0..=5] == x#+[0..<100] == 3)
assert(y#+[0..=5]) // error: 'y' can be negative
cassert(y#[..]#+[..] == 3)
cassert(y#[0..=5]#+[..] == 3)
cassert(y#[0..=6]#+[..] == 4)

mut z     = 0ub0110
z#[0] = 1
cassert(z == 0ub0111)
z#[0] = 0ub11 // error: '0ub11` overflows the maximum allowed value of `z#[0]`
```

!!!Note
    It is important to remember that in Pyrope all the operations use signed
    numbers. This means that an and-reduce over any positive number is always going
    to be zero because the most significant bit is zero, E.g: `0xFF#&[..] == 0`. In
    some cases, a close-range will be needed if the intention is to ignore the sign.
    E.g: `0xFF#&[0..<8] == 1`.



`variable#op[sel]` operates on a bit vector: an integer, boolean, range,
or a packed positional tuple or array. Strings are opaque and have no bit
vector. A tuple packs entry 0 into the lowest bits, with each entry's width
specified by its declared type. A tuple with multiple named fields has no
packing order; select its fields explicitly, as in `(x.lo, x.hi)#[..]`.
An entry without a declared width specifies no layout. See the bit packing
rules in [internals](10-internals.md).

Every `#op[sel]` variant reads that same word, so there is no separate list of
which operators a tuple is allowed to take: the reductions `#|`, `#&`, `#^`,
and `#+` count bits of a packed tuple exactly as they count bits of an integer,
`#[range]` selects a sub-range of it, and `#sext` reinterprets it as signed
(`x#[..]` is always non-negative).

```pyrope
const p:[3]U4 = (0ub0011, 0ub0101, 0ub0000)
cassert(p#[..]  == 0ub0000_0101_0011) // entry 0 in the lowest bits
cassert(p#+[..] == 4)                 // pop-count over the packed 12 bits
cassert(p#|[..] == 1)
```

The bit selection operator takes a single expression: a bit index, a range, or
any expression that produces one of those (including a conditional). Picking
non-contiguous bits in one shot is intentionally not supported. A positional
tuple does have a canonical bit order — entry 0 at bit 0, each later entry
stacked above it — but `#[1,2]` is not a positional tuple, it is a *set* of bit
positions, and a set has no order: nothing in it says whether bit 1 or bit 2
lands at the bottom of the result, and `#[2,1]` names the same set. The order
has to be written down somewhere, and a selector is not where Pyrope writes it.
To build or transpose a value from non-contiguous bits, declare a destination
and assign bits explicitly: each line states which bit range receives which
value, and the compiler checks widths and coverage.

```pyrope
mut v = 0ub10
cassert(v#[0..=1] == v#[..] == v#[..=1] == 0ub10)

mut trans:U2 = nil

trans#[0] = v#[1]
trans#[1] = v#[0]
cassert(trans == 0ub01)

// Building a wider value from several pieces — the destination layout is
// written verbatim. Every bit of `r` must be driven exactly once or it is
// a compile error.
const a = 0ub1010  // 4 bits
const b = 0ub01    // 2 bits
const c = 0ub1     // 1 bit

mut r:U7 = nil
r#[0]    = c
r#[1..=2] = b
r#[3..=6] = a
cassert(r == 0ub1010_01_1)
```

A lambda output starts as `nil`, exactly like `mut v:U8 = nil`, so an output
can be built bit by bit without a prior whole assignment, and an array output
lane by lane. The same coverage rule applies: every bit must be driven.

```pyrope
mod reverse(a:U4) -> (q:U4@[0]) {
  for i in 0..<4 {
    q#[i] = a#[3-i]    // OK: `q` starts as nil, like `mut q:U4 = nil`
  }
}

mod split(a:U4) -> (v:[4]U1@[0]) {
  for i in 0..<4 {
    v[i] = a#[i]       // OK: array output lanes likewise
  }
}
```


## Precedence

Pyrope has very shallow precedence, unlike most other languages the
programmer should explicitly indicate the precedence. The exception is for
widely expected precedence.

* Unary operators (not,!,~) bind stronger than binary operators (+,-,*...)
* Comparators can be chained (a<=c<=d) same as (a<=c and c<=d)
* mult/div precedence is only against +,- operators.
* Parenthesis can be avoided when a expression left-to-right has the same
  result as right-to-left.

| Priority | Category | Main operators in category |
|:-----------:|:-----------:|-------------:|
| 1          | unary       | not ! ~ |
| 2          | mult/div    | *, /         |
| 3          | other binary | ..,^, &, -,+, ++, <<, >>, in, does, has, case, equals, to |
| 4          | comparators |    <, <=, ==, !=, >=, > |
| 5          | logical     | and, or, implies |


```pyrope
assert((x or !y) == (x or (!y)) == (x or not y))
assert((3*5+5) == ((3*5) + 5) == 3*5 + 5)

a = x1 or x2==x3 // same as b = x1 or (x2==x3)
b = 3 & 4 * 4    // error: use parenthesis for explicit precedence
c = 3
  & 4 * 4
  & 5 + 3        // error: use parenthesis for explicit precedence
c2 = 3
  & (4 * 4)
  & (5 + 3)      // OK

d = 3 + 3 - 5    // OK, same result right-left

e = 1
  | 5
  & 6           // error: use parenthesis for explicit precedence

f = (1 & 4)
  | (1 + 5)
  | 1

g = 1 + 3
  * 1 + 2
  + 5           // OK, but not nice

g1= 1 + (3 * 1)
  + 2
  + 5           // OK

g2= (1 + 3)
  * (1 + 2)
  + 5           // OK

h = x or y and z// error: use parenthesis for explicit precedence

i = a <= 3 < b <= d
assert(i == (a<=3 and 3<b and b<=d))
```

Comparators can be chained, but only when they follow the same type or the
direction is the same.

```pyrope
assert(a <= b <= c) // same as a<=b and b<=c
assert(a <  b <= c) // same as a< b and b<=c
assert(a == b <= c) // error: chained only allowed with same comparator
assert(a <= b >  c) // error: not same direction
```

## Optional

The `?` is used by several languages to handle optional or null pointer
references. In non-hardware languages, `?` is used to check if there is valid
data or a null pointer. Pyrope has no `?` operator for this: the check is the
`.[valid]` attribute.


Pyrope does not have null pointers or memory associated management. Pyrope uses
`.[valid]` to handle optional data. The data is left to behave without the
optional, but there is a new "valid" field associated with each tuple entry.
Notice that it is not for each tuple level but each tuple entry.


There are 3 explicit ways to interact with valids:

* `tup.f1.[valid]` reads the valid for field `f1` from tuple `tup`.

* `tup.f1.[valid] = cond` explicitly sets the field `f1` valid to `cond`.

* `a = b op c` — variable `a` will be valid if `b` AND `c` are valid.

To produce a value only when the source is valid, write the conditional
explicitly: `if tup.f1.[valid] and tup.f2.[valid] { tup.f1 + tup.f2 } else { 0sb? }`.


The optional or valid attached to each variable and tuple field is implicitly
computed as follows:

* Non-register variables are initialized with valid unless `nil` is used in the
  initialization, which explicitly clears the valid attribute.

* Registers set the valid after reset, but if the reset clears the valid, there
  is not guaranteed on attribute `[valid]` during reset. If the register does
  not have a reset signal, the register is always valid unless explicitly
  cleared.

* Left-hand side variables `valids` are set to the and-gate of all the variable
  valids used in the expression

* memory/arrays do not tend to have reset signals. As such they are always
  valid unless the memory has explicit reset code. In which case the valid
  behaves like in flops.

* Writing to a register updates the register valid based on the din valid, or
  when the attribute `[valid]` is explicitly managed.

* conditionals (`if`) update valids independently for each path

* A tuple field has the valid set to false if any of the tuple fields is
  invalid

* The valid computation can be overwritten with the `[valid]` attribute. This
  is possible even during reset.


!!! Observation
    The variable valid calculation is similar to the Elastic 'output_written'
    from [Liam](https://masc.soe.ucsc.edu/docs/memocode17.pdf) but it is not an
    elastic update because it does not consider the abort or retry.


The previous rules will clear a valid only if an expression has no valid, but
the only way to have a non-valid is if the inputs to the lambda are invalid or
if the valid is explicitly clear. The rules are designed to have no overhead
when valid are not used. The compiler should detect that the valid is true all
the time, and the associated logic is removed.


Most statements evaluate independent of the valid expression. Expressions will
evaluate the same if any of the inputs is valid or invalid. The valid attribute
is computed in parallel to avoid being in the critical path. The exception are
the verification statements like asserts and printing statatements like `puts`.
These statements are gated or not performed if any of the inputs is invalid. To
ignore the valid check, the `always` command can be appended before and as a
result the statments will evaluate every cycle independent of the reset/valid
status.


```pyrope
mut v1:U32 = nil                 // v1 is zero every cycle AND not valid
assert(v1.[valid] == false)
mut v2:U32 = 0                 // v2 is zero every cycle AND     valid
assert(v2.[valid] == true)

cassert(v1.[valid])
cassert(not v2.[valid])

assert(v1 == 0 and v2 == 3) // data still same as usual

v1 = 0sb?                      // OK, poison data
v2 = 0sb?                      // OK, poison data, and update valid
assert(v2.[valid]) // valid even though data is not

assert(v1 != 0) // usual verilog x logic
assert(v2 != 0) // usual verilog x logic

const res1 = v1 + 0              // valid with just unknown 0sb? data
const res2 = v2 + 0              // valid with just unknown 0sb? data

assert(res1.[valid])
assert(res2.[valid])

reg counter:U32 = 0

assert(counter.[valid])  // checked after reset: the register is valid once reset
```

`valid` can be overwritten by the `init` constructor:

```pyrope
const Custom = (
  ,mut data:S16 = nil
  ,comb init(ref self, v) {
    self.data = v
    self.[valid] = v != 33
  }
)

mut x:Custom = 33      // init runs at construction
cassert(not x.[valid])

mut y:Custom = 100
cassert(y.[valid])

y = Custom(33)         // explicit construction also calls init
cassert(not y.[valid])
```

The contents of the tuple field do not affect the field valid bit. It is
data-independent. Tuples also can have an optional type, which behaves like
adding optional to each of the tuple fields.

```pyrope
const Complex = (
  ,reg v1:String = "foo"
  ,mut v2:String = nil

  ,comb init(ref self, v) {
     self.v1 = v
     self.v2 = v
  }
)

mut x1:Complex = nil
mut x2:Complex:[valid=false] = 0  // toggle valid, and set zero
mut x3:Complex = 0
x3.[valid] = false                // set invalid

assert(x1.v1 == "" and x1.v2 == "")
assert(not x2.[valid] and not x2.v1.[valid] and not v2.v2.[valid])
assert(x2.v1 == "" and x2.v2 == "")

// When x2 is invalid, reads of x2 fields propagate 0sb?; comparisons against
// concrete values are false in both directions.

x2.v2 = "hello" // direct access still OK

assert(not x2.[valid] and x2.v1 == "" and x2.v2 == "hello")

x2 = Complex("world") // explicit construction calls init

assert(x2.[valid] and x2.v1 == "world")
```


## Variable initialization


Variable initialization indicates the default value set every cycle and the
optional (`.[valid]` attribute).


The `const` and `mut` statements require an explicit initialization value for
each cycle. There are exactly two ways to produce an undefined value:

* **`nil`** — the variable is *invalid* (`.[valid]==false`). Reading it is
  an assertion error at simulation and a compile error at elaboration
  wherever the compiler can prove the read. Use `nil` when there is no
  meaningful value yet.
* **`0sb?`** (and related bit-literal forms like `0ub101?`, `0ub??10`) —
  unknown bits, behaving like Verilog `x`. The variable is still *valid*
  from the optional standpoint; only the bits are unknown. Use this for
  don't-care states or deliberately unobserved bits.

The bare `_` sink and the bare `?` shorthand have been removed in favor of
these two explicit values. Every initialization must supply a concrete
expression — a literal (`0`, `false`, `""`, `0sb?`), `nil`, or a normal
expression.

```pyrope
mut a:Signed = 0
cassert(a==0 and a.[valid] and a.[valid])

mut b:Signed = nil
cassert(b==nil and b.[valid] == false and not b.[valid])
b = 0
cassert(b==0 and b.[valid] and b.[valid])

mut d:[] = ()              // empty tuple literal
cassert(d != nil and d.[valid])

mut e:Signed = 0sb?           // valid but with unknown bits
cassert(e.[valid])           // validity does not require known bits
cassert(e != 0)              // error: comparison is unknown, so cassert fails
```

The same rules apply when a tuple or a type is declared. Tuple fields must
also use explicit initial values:

```pyrope
const a = "foo"

mut at1 = (
  ,const a:String = a     // copy enclosing 'a' as the initial value
)
cassert(at1.a == "foo")

mut at2 = (
  ,mut a:String = nil     // invalid field
)
cassert(at2.a.[valid] == false)
at2.a = "torrellas"
cassert(at2.a == "torrellas")  // a named field: `at2[0]` is an error
```

Conditional paths affect variable initialization and values. If all the
conditional paths assign a value, the valid will be true. If only one path
assigns a value, the valid will be set only on that path, but the data may
always have the path.

```pyrope
mut x:Signed = nil
mut y:Signed = 2
mut z:Signed = nil
if rand {
  x = 3
  y = 4
  z = 5
}else{
  z = 6
}
assert(rand      implies x.[valid])
assert(x.[valid] implies rand)

assert(y.[valid])
assert(rand implies y == 4)
assert(!rand implies y == 2)

assert(z.[valid])
assert(rand implies z == 5)
assert(!rand implies z == 6)
```

For structured bindings where one of the return values is unused, name the
variable and treat the name as the documentation:

```pyrope
comb weird_pick_bits(b:U32) -> (x:U1, unused:U4) {
  x = b#[2..<3]
  unused = b#[5]
}

comb fcall_returns_2_values() -> (xx, yy) {
  xx = 3
  yy = 7
}

const (a = fcall_returns_2_values.xx, b_unused = fcall_returns_2_values.yy) = fcall_returns_2_values()
cassert(a == 3)
```
