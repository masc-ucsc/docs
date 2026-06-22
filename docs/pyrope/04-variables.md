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


Every declaration starts with one of seven **kind keywords**:

| Kind    | Category | Implicit mutability |
|---------|----------|---------------------|
| `const` | data     | immutable           |
| `mut`   | data     | mutable             |
| `wire`  | data     | single-driver combinational net (read before driver allowed) |
| `reg`   | data     | mutable, persists across cycles |
| `comb`  | lambda   | immutable (always)  |
| `pipe`  | lambda   | immutable (always)  |
| `mod`   | lambda   | immutable (always)  |

The four data kinds take `= expression`; the three lambda kinds take a
parameter list and a body. Data declarations:

* `const variable [:type] [:[attribute list]] = expression`
* `mut variable [:type] [:[attribute list]] = expression`
* `wire variable [:type] [:[attribute list]] = expression`
* `reg variable [:type] [:[attribute list]] = reset_expression`

When the type is omitted but attributes are given, the type colon remains:
`reg counter::[retime=true] = 0` but `reg counter:u8:[retime=true] = 0`.
Bare attributes are always `::[...]` — a single `:[...]` after the variable
name would parse as an array type (`:[16]u8`).

Lambda declarations:

* `comb name[comptime_params][args] [-> outputs] { body }`
* `pipe[N] name[comptime_params][args] [-> outputs] { body }`
* `mod name[comptime_params][args] [-> outputs] { body }`

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
Positional fields take no name slot, so `const _ = 3` is not valid (and
bare `_` is reserved as a future placeholder, see
[Identifiers](02-basics.md#identifiers)).

```pyrope
const point = (mut x:u8 = 0, mut y:u8 = 0)

const counter_iface = (
  ,mut value:u8 = 0
  ,comb read(self) -> (v:u8)      { v = self.value }
  ,comb inc(ref self)             { wrap self.value += 1 }
  ,mod tick(ref self, enable:bool) { if enable { self.value += 1 } }
)

mut y = (1, const 3)              // 2nd field positional and immutable
```

Named-argument passing in calls (`foo(a=3, b=4)`) is **not** a declaration
— the names are matched against the callee's declared parameters — so no
kind keyword is required there.

The `[...]` slot after a lambda name declares explicit comptime parameters.
It is not a capture list. Lambdas can lexically read visible comptime bindings
from enclosing scopes, but runtime `const`, `mut`, and `reg` declarations from
enclosing lambda scopes are not visible in nested lambdas unless passed as
normal inputs. The compiler records lexical comptime references as explicit
comptime dependencies of the lambda.


=== "Code Block scope"

    ```pyrope
    assert(a == 3) // error: undefined variable 'a'
    mut a = 3
    {
      assert(a == 3)
      a = 33             // OK. assign 33
      a = signed(33)        // OK, explicit conversion/check on the RHS
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
    comb f2() -> () {
      // assert a == 3   // error: runtime outer variable not visible
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

* Shadowing is not allowed in lambdas or code blocks. Tuple field initializers
  follow program order and can read earlier tuple fields by name.

* Data tuple literals do not have a `self` binding. The `self` name is only
  available when declared as a lambda argument, such as in tuple methods.

* Tuple upper scope variables are always immutable.

* Lambdas lexically see only visible comptime bindings from upper scopes.
  Runtime upper scope variables must be passed explicitly.

* A variable is visible from definition until the end of scope in program order.


Since lambda inputs and comptime parameters are always immutable, it is not
allowed to declare them as `mut` and redundant to declare them as `const`.


Tuple scope is also useful for declaring function default values:

```pyrope
comb example(a:signed, b:signed=a+5) -> (result:signed) {
  result = a + b
}
cassert(example(a=3) == (3+3+5))
cassert(example(a=6,b=7) == (6+7))
cassert(example(a=6) == (6+6+5))
assert(example(b=3) !=0) // error: undefined `a` argument
```

## Basic types

Pyrope has 7 basic types:

* `boolean`: either `true` or `false`
* `enum`: enumerated values, optionally with a per-case payload (the equivalent of a tagged union)
* `comb`: A function or pure combinational logic
* `signed`: a signed integer of unlimited precision
* `mod`: A module with state/clock or side-effects
* `range`: A one hot encoding of values `1..=3 == 0ub1110`
* `string`: which is a sequence of characters


All the types except functions can be converted back and forth to an
integer.


### Integer or `signed`

Integers have unlimited precision and they are always signed. Unlike most other
languages, there is only one type for integer (unlimited), but the type system
allows to add constraints to be checked when assigning the variable contents.
Notice that the type is the same (`u32` is the same type as `s3`, they just have
different constraints). The `does` operator compares the range envelope: `a does
b` is true when `a`'s range is a superset of `b`'s (`a.max >= b.max and a.min <=
b.min`). So `u32 does u16` is true (u32's range covers u16's) but `u16 does u32`
is false. Assignment still performs the additional range and precision checks
described in the attribute section:

* `signed`: an unlimited precision integer number.
* `unsigned`: the same as `signed(min=0)` — a de-facto unsigned integer. There is
  nothing special beyond the constraint, but it usually allows nicer Verilog
  generation (`logic` vs `signed logic`).
* `u<num>`: An integer basic type constrained to be a natural number with a maximum value of $2^{\texttt{num}}-1$. E.g: `u10` can go from zero to 1023.
* `s<num>`: a signed (2s complement) number with a maximum value of $2^{\texttt{num}-1}-1$ and a minimum of $-2^{\texttt{num}-1}$.

```pyrope
mut a:signed         = nil // any value, no constrain
mut b:unsigned    = nil // only positive values
mut c:u13         = nil // only from 0 to (1<<13)-1
mut d:signed(min=20, max=30) = nil // only values from 20 to 30 (both included)
mut e:signed(min=-5, max=5) = nil // only values from -5 to 5 (both included)
mut f:signed(min=-1, max=0) = nil // 1 bit integer: -1 or 0
```

Integers can have 3 value (`0`,`1`,`?`) expression or a `nil`. Section
[Integers](02-basics.md#Integers) has more details, but those values can not be
part of the type requirement.


Integer typecast accepts strings as input. The string must be a valid formatted
Pryope number or an assertion is raised.


### Boolean

A boolean is either `true` or `false`. Booleans can not mix with integers in
expressions unless there is an explicit typecast (`signed(false)==0`,
`signed(true)==-1`, `boolean(0)==false`, and `boolean(1)==true`). Unlike integers,
booleans do not support undefined value. A typecast from integer to boolean
will raise an assertion when the integer has undefined bits (`?`) or `nil`.

```pyrope
const b = true
const c = 3

if c    { call(x) }  // error: 'c' is not a boolean expression
if c!=0 { call(x) }  // OK

mut d = b or false   // OK
mut e = c or false   // error: 'c' is not a boolean

const e = 0xfeed
if boolean(e#[3]) {  // OK, explicit conversion from unsigned bit to boolean
  call(x)
}

cassert(0 == (signed(true)  + 1)) // explicity typecast; true is signed all-ones
cassert(1 == (signed(false) + 1)) // explicity typecast
cassert(boolean(33) or false) // explicity typecast
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
input and a tuple for output. Functions can have explicit comptime parameters
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


A range is a separate tuple. As such it can not directly compare with
tupes. It requires an explicit conversion. If the range does not contain
negative values, it can be converted to an integer back and forth which
corresponds to a one-hot encoding.

Range type cast from integers use the same one-hot encoding. It is not possible
to type cast from tuple to range, but it is possible from range to tuple.

```pyrope
const c = 1..=3
cassert(signed(c) == 0ub1110)
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
cassert(signed(0..=10 step  2) == 0ub101_0101_0101)
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

### String

Strings are a basic type. They can be typecasted to integers using the ASCII
sequence: the string encoding assigns the lower bits to the first characters
in the string, and each character has 8 bits associated. Casting an integer to
`string` produces decimal text, not an ASCII-byte decode.

```pyrope
const a = 'cad'          // c is 0x63, a is 0x61, and d is 0x64
const b = 0x64_61_63
cassert(signed(a) == b) // typecast string to number
cassert(a#[..] == b) // typecast string to number
cassert(string(b) == "6578531") // integer to string is decimal text
```

Like ranges, strings can also be seen as a tuple, and when tuple operations are
performed they are converted to a tuple.

```pyrope
cassert("hello" == ('h','e','l','l','o'))
cassert((..."h", ..."ell") == ('h','e','l','l') == "hell")
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
comb check_is_green(self) -> (r:bool) { r = self.color == "green" }

type IsGreen = comb(self) -> (r:bool)

mut bund1 = (mut color:string = "", mut value:s33 = nil)
x:bund1        = nil    // OK, declare x of type bund1 with default values
bund1.color    = "red"  // OK
bund1.is_green = check_is_green
x.color        = "blue" // OK

type Typ = (mut color:string = "", mut value:s33 = nil, mut is_green:IsGreen = nil)
y:Typ        = nil      // OK
Typ.color    = "red"    // error:

Typ.is_green = check_is_green
y.color      = "red"    // OK

type Bund3 = (mut color:string = "", mut value:s33 = nil)
z:Bund3        = nil                // OK
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
type as a constructor — `u8(value)`.

```pyrope
mut a = true                // infer a is a boolean

cassert(a does bool) // type check on an existing variable
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
reg counter:u32   = 10
mut not_a_reg:u32 = 20
```

In `reg`, the right-hand side of the initialization (`10` in the
counterexample) is called only during reset. In non-register variables, the
right-hand side is called every cycle. Most of the cases `reg` is mutable but
it can be declared as immutable.
## Wire: single-driver combinational nets

A `wire` declares one **combinational** net with exactly **one driver**,
modeled on the Verilog continuous-assign / net. Unlike `mut` (whose value is
the last write in *program order*, and where a read-before-write is an error),
a `wire` may be **read before its driver appears textually**: every read
observes the single resolved driver, independent of statement position.

```pyrope
wire x = nil           // forward declaration: an as-yet-undriven net
                       // reads of 'x' here are legal
x = some_expr          // the one driver (may appear later in program order)

wire y:u8 = a + b      // declare and drive in one statement
pub wire z = a & b     // composes with prefix modifiers, like the other kinds
```

Rules:

* **Exactly one driver.** The driver may be a mux — an `if`/`match`
  *expression*, or mutually-exclusive conditional assignments. A second
  *unconditional* assignment is a compile error.
* `wire x = nil` forward-declares an undriven net; a `wire` still `nil` at the
  end of elaboration (never driven), or driven on some paths but not others
  (incompletely driven), is a compile error.
* `wire` removes *textual* ordering only, not cyclic dataflow. A `wire`
  combinationally driven by a function of itself is a real combinational loop
  and is rejected (the standard combinational-cycle / SCC check). A ring is
  legal only when a `reg` breaks it.

Primary uses are closing module-interconnect rings without ordering
gymnastics, and routing a computed reset/flush into a register `reset_pin`
(`reg r:u2:[reset_pin = my_wire] = 0`).

```pyrope
// close a ring without reordering the calls:
wire f4 = nil
f1 = ring(a, f4)       // reads f4 before its driver appears
f2 = ring(b, f1)
f3 = ring(c, f2)
f4 = ring(d, f3)       // the single driver of f4
```


## Visibility: private by default, `pub` to export

All declarations are **private by default**: they can not be accessed from
other files by `import`. The `pub` prefix modifier (same declaration slot as
`comptime`) exports a top-scope declaration for import:

* `pub` on a top-scope lambda, type, or constant allows other files to
  `import` it.
* `pub mut` and `pub reg` are compile errors. Registers, including memories,
  are not imported or exported as values. Cross-scope register access uses
  `regref`, which resolves an instantiated register by hierarchy path or
  name. See [Register reference](07-typesystem.md#register-reference) and
  [Memories](08-memories.md#shared-memories-with-regref).

```pyrope
pub comb get_five() -> (v) { v = 5 }  // importable by other files
pub const default_depth = 1024         // importable constant
reg internal:u8 = 0                   // private: this file/instance only

pub comb my_log::[lg="foo_mod"](a) -> (r) { r = a } // lgraph named foo_mod
```

A `pub` lambda may pin the name of its generated lgraph (the netlist/Verilog
module name) with the `lg` attribute. This renames only the generated
artifact — `import` still uses the declared name (`my_log` above). See
[lg: explicit lgraph name](04b-attributes.md#lg-explicit-lgraph-name).

**Debug is exempt from visibility.** Debug statements (`assert`, `test`,
`puts`, monitors) can observe any variable read-only through
`sigref`/`regref`. Visibility restricts `import` only; nothing can be hidden
from verification. There is no
`private` attribute.

For tuple fields, a leading underscore (`_field`) marks the entry as
private to the tuple: it can not be accessed outside the tuple methods,
but debug statements can still read it (see
[debug attribute](04b-attributes.md)).


## Operators

There are the typical basic operators found in most common languages except
exponent operations. The reason is that those are very hardware intensive and a
library code should be used instead.

All the operators work over signed integers.

### Unary operators

* `!a` or `not a` logical negation
* `~a` bitwise negation
* `-a` arithmetic negation

### Binary integer operators

* `a + b` addition
* `a - b` substraction
* `a * b` multiplication
* `a / b` division
* `a % b` modulo (hardware only for a power-of-two/`3`/larger-than-`a` divisor; see [basics](02-basics.md))
* `a & b` bitwise and
* `a | b` bitwise or
* `a ^ b` bitwise xor
* `a ~& b` bitwise nand
* `a ~| b` bitwise nor
* `a ~^ b` bitwise xnor
* `a >> b` arithmetic right shift
* `a#[..] >> b` logical right shift
* `a << b` left shift

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
* `tuple(a)` converts `a` to tuple, `a` can be a boolean, range, integer,
  string, or already a tuple

Most operations behave as expected when applied to signed unlimited precision
integers.

The `a in b` checks if values of `a` are in `b`. Notice that both can be
tuples. If `a` is a named tuple, the entries in `b` match by name, and then
contents. If `a` is unnamed, it matches only contents by position.

```pyrope
cassert((1,2) in (0,1,3,2,4))
cassert((1,2) in (const a=0, const b=1, const c=3, 2, const e=4))
cassert(not ((const a=2) in (1,2,3)))
cassert((const a=2) in (1, const a=2, const c=3))
cassert((const a=1, 2) in (3, 2, 4, const a=1))
cassert(not ((const a=1, 2) in (1, 2, 4, const a=4)))
cassert(not ((const a=1) in (const a=(1,2))))
```

The `a in b` has to deal with undefined values (`nil`, `0sb?`). The LHS with an undefined
will be true if the RHS has the same named entry either defined or undefined.

```pyrope
cassert((const x=nil, const c=3) in (const x=3, const c=3))
cassert((const x=nil, const c=3) in (const x=nil, const c=3, const d=4))
cassert(not ((const c=3) in (const c=nil, const d=4)))
```

* `(...a, ...b)` concatenate two tuples (splice). A field present on only one
  side is copied in. When the same field appears on both sides it is a compile
  error, unless one side is `nil`/`0sb?` (the defined value wins) or both sides
  hold the same value (matching tuple-valued fields merge recursively). The
  splice inserts each tuple's fields at its position, so it can also insert in
  the middle of a literal and add arguments to a function call
  (`foo(a=1, ...rest)`).

```pyrope
cassert((...(const a=1, const c=3), ...(const a=1, const b=2, const c=nil)) == (const a=1, const c=3, const b=2))
cassert((...(1,2), ...(const a=2, nil, 5)) == (1, 2, const a=2, nil, 5))
cassert((...(const x=1), ...(const a=2, nil, 5)) == (const x=1, const a=2, nil, 5))

cassert((...(const x=1, const b=2), ...(const x=0sb?, 3)) == (const x=1, const b=2, 3))

const bad = (...(const a=1), ...(const a=2))  // error: 'a' defined with different values on both sides

// the splice can also insert in the middle of a literal:
cassert((1, const b=2, ...(3, const c=3), 6) == (1, const b=2, 3, const c=3, 6))
cassert((1, const b=2, ...(nil, const c=3), 0sb?, 6) == (1, const b=2, nil, const c=3, 0sb?, 6))
```


### Type operators

* `a has b` checks if `a` tuple has the `b` field where `b` is a string or
  integer (position).

```pyrope
cassert((const a=1, const b=2) has "a")
```

* `a does b` is true when `a` has all the tuple structure required by `b`
* `a equals b` same as `(a does b) and (b does a)`
* `a case b` same as `(a does b)` plus value matching for every defined value
  in `b`. Values in `b` that are undefined (`nil`, `0sb?`) act as wildcards.

Negate any type operator with `not (...)`, e.g. `not (a does b)`,
`not (a equals b)`, `not (a case b)`.

The `does` performs just name matching when the required tuple is fully named.
It reverts to name and position matching when some of the required tuple entries
are unnamed. Values are ignored by `does`; use `case` when the values should be
matched too.

```pyrope
cassert((const b=100, const a=333, const e=40, 5) does (const a=1, const b=3))
cassert((const a=100, 300, const b=333, const e=40, 5) does (const a=1, 3))
cassert(not ((const b=100, 300, const a=333, const e=40, 5) does (const a=1, 3)))
cassert(u32 does u16)          // u32's range is a superset of u16's
cassert(not (u16 does u32))    // u16's range is NOT a superset of u32's
cassert(not (u32 does string)) // different basic type → false
cassert((100,30) does 30)
cassert(not (30 does (30,200)))
cassert(not ((const a=3) does (30, const a=200)))
cassert(not ((const a=3) does (const a=30, 200)))
cassert(not ((3) does (30, const a=200)))
cassert(not ((3) does (const a=30, 200)))
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
explicitly when comparing with a boolean (`boolean(x#|[..]) == flag` or
`x#|[..] == signed(flag)`). pop-count and `zext` have always positive results.
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
const y = 0s1_0110   // negative
cassert(x#[2]    == 1)
cassert(x#[0..=2] == 0ub110)
cassert(y#[100]       == 1   and x#[100]       == 0) // out-of-range follows sign
cassert(y#sext[0..=2] == 0sb110 and x#sext[0..=2] == 0ub110)
cassert(x#|[..] == 1)
cassert(x#&[0..=1] == 0)
cassert(boolean(x#|[..]) == true)
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



The bit selection operator only works with ranges, boolean, and integers. It
does not work with tuples or strings. For converting in these object a `union:`
must be used.


The bit selection operator takes a single expression: a bit index, a range, or
any expression that produces one of those (including a conditional). Picking
non-contiguous bits in one shot is intentionally not supported, because the
ordering of a bit set is ambiguous and easy to get wrong (e.g. is `#[1,2]` the
same as `#[2,1]`?). To build or transpose a value from non-contiguous bits,
declare a destination and assign bits explicitly: each line states which bit
range receives which value, and the compiler checks widths and coverage.

```pyrope
mut v = 0ub10
cassert(v#[0..=1] == v#[..] == v#[..=1] == 0ub10)

mut trans:u2 = nil

trans#[0] = v#[1]
trans#[1] = v#[0]
cassert(trans == 0ub01)

// Building a wider value from several pieces — the destination layout is
// written verbatim. Every bit of `r` must be driven exactly once or it is
// a compile error.
const a = 0ub1010  // 4 bits
const b = 0ub01    // 2 bits
const c = 0ub1     // 1 bit

mut r:u7 = nil
r#[0]    = c
r#[1..=2] = b
r#[3..=6] = a
cassert(r == 0ub1010_01_1)
```


## Precedence

Pyrope has very shallow precedence, unlike most other languages the
programmer should explicitly indicate the precedence. The exception is for
widely expected precedence.

* Unary operators (not,!,~,?) bind stronger than binary operators (+,-,*...)
* Comparators can be chained (a<=c<=d) same as (a<=c and c<=d)
* mult/div precedence is only against +,- operators.
* Parenthesis can be avoided when a expression left-to-right has the same
  result as right-to-left.

| Priority | Category | Main operators in category |
|:-----------:|:-----------:|-------------:|
| 1          | unary       | not ! ~ ? |
| 2          | mult/div    | *, /         |
| 3          | other binary | ..,^, &, -,+, <<, >>, in, does, has, case, equals, to |
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

i = a == 3 <= b == d
assert(i == (a==3 and 3<=b and b == d))
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
data or a null pointer. This is the same as checking the `.[valid]` attribute
with a more friendly syntax.


Pyrope does not have null pointers or memory associated management. Pyrope uses
`?` to handle `.[valid]` data. Instead, the data is left to behave without the
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
mut v1:u32 = nil                 // v1 is zero every cycle AND not valid
assert(v1.[valid] == false)
mut v2:u32 = 0                 // v2 is zero every cycle AND     valid
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

reg counter:u32 = 0

always_assert(counter.reset implies !counter.[valid])
```

`valid` can be overwritten by the `init` constructor:

```pyrope
const custom = (
  ,mut data:s16 = nil
  ,comb init(ref self, v) {
    self.data = v
    self.[valid] = v != 33
  }
)

mut x:custom = 33      // init runs at construction
cassert(not x.[valid])

mut y:custom = 100
cassert(y.[valid])

y = custom(33)         // explicit construction also calls init
cassert(not y.[valid])
```

The contents of the tuple field do not affect the field valid bit. It is
data-independent. Tuples also can have an optional type, which behaves like
adding optional to each of the tuple fields.

```pyrope
const complex = (
  ,reg v1:string = "foo"
  ,mut v2:string = nil

  ,comb init(ref self, v) {
     self.v1 = v
     self.v2 = v
  }
)

mut x1:complex = nil
mut x2:complex:[valid=false] = 0  // toggle valid, and set zero
mut x3:complex = 0
x3.[valid] = false                // set invalid

assert(x1.v1 == "" and x1.v2 == "")
assert(not x2.[valid] and not x2.v1.[valid] and not v2.v2.[valid])
assert(x2.v1 == "" and x2.v2 == "")

// When x2 is invalid, reads of x2 fields propagate 0sb?; comparisons against
// concrete values are false in both directions.

x2.v2 = "hello" // direct access still OK

assert(not x2.[valid] and x2.v1 == "" and x2.v2 == "hello")

x2 = complex("world") // explicit construction calls init

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
mut a:signed = 0
cassert(a==0 and a.[valid] and a.[valid])

mut b:signed = nil
cassert(b==nil and b.[valid] == false and not b.[valid])
b = 0
cassert(b==0 and b.[valid] and b.[valid])

mut d:[] = ()              // empty tuple literal
cassert(d != nil and d.[valid])

mut e:signed = 0sb?           // valid but with unknown bits
cassert(e.[valid] and e != 0) // any comparison against `?` is unknown
```

The same rules apply when a tuple or a type is declared. Tuple fields must
also use explicit initial values:

```pyrope
const a = "foo"

mut at1 = (
  ,const a:string = a     // copy enclosing 'a' as the initial value
)
cassert(at1.a == "foo")

mut at2 = (
  ,mut a:string = nil     // invalid field
)
cassert(at2.a.[valid] == false)
at2.a = "torrellas"
cassert(at2.a == "torrellas" and at2[0] == "torrellas")
```

Conditional paths affect variable initialization and values. If all the
conditional paths assign a value, the valid will be true. If only one path
assigns a value, the valid will be set only on that path, but the data may
always have the path.

```pyrope
mut x:signed = nil
mut y:signed = 2
mut z:signed = nil
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
comb weird_pick_bits(b:u32) -> (x:u1, unused:u4) {
  (x=b#[2..<3], unused=b#[5])
}

comb fcall_returns_2_values() -> (xx, yy) {
  xx = 3
  yy = 7
}

const (a = fcall_returns_2_values.xx, b_unused = fcall_returns_2_values.yy) = fcall_returns_2_values()
cassert(a == 3)
```
