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
have a value. `_` is used to specify the default value (`false` for boolean,
`0` for integer, `""` for string, undefined lambda for lambda, and `0..=0` for
range).


Every declaration starts with one of six **kind keywords**:

| Kind    | Category | Implicit mutability |
|---------|----------|---------------------|
| `const` | data     | immutable           |
| `mut`   | data     | mutable             |
| `reg`   | data     | mutable, persists across cycles |
| `comb`  | lambda   | immutable (always)  |
| `pipe`  | lambda   | immutable (always)  |
| `mod`   | lambda   | immutable (always)  |

The three data kinds take `= expression`; the three lambda kinds take a
parameter list and a body. Data declarations:

* `const variable [:type] [:[attribute list]] = expression`
* `mut variable [:type] [:[attribute list]] = expression`
* `reg variable [:type] [:[attribute list]] = reset_expression`

Lambda declarations:

* `comb name[comptime_params][args] [-> outputs] { body }`
* `pipe[N] name[comptime_params][args] [-> outputs] { body }`
* `mod name[comptime_params][args] [-> outputs] { body }`

This rule applies uniformly, including inside **tuple literals**: any
**named** field must start with one of these kind keywords. Bare
`field = value` inside a data-tuple literal is a compile error.

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
  ,mod tick(ref self, enable:bool) { self.value += 1 when enable }
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
      a:int = 33         // OK, assign 33 and check that 'a' has type int
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
    comb f2() {
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
    assert(r2 == (a=100,c=(next=101, e=131))) // checks values not mutability
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
comb example(a:int, b:int=a+5) -> (result:int) {
  result = a + b
}
cassert(example(a=3) == (3+3+5))
cassert(example(6,7) == (6+7))
cassert(example(6) == (6+6+5))
assert(example(b=3) !=0) // error: undefined `a` argument
```

## Basic types

Pyrope has 7 basic types:

* `boolean`: either `true` or `false`
* `enum`: enumerated values, optionally with a per-case payload (the equivalent of a tagged union)
* `comb`: A function or pure combinational logic
* `int`: which is signed integer of unlimited precision
* `mod`: A module with state/clock or side-effects
* `range`: A one hot encoding of values `1..=3 == 0ub1110`
* `string`: which is a sequence of characters


All the types except functions can be converted back and forth to an
integer.


### Integer or `int`

Integers have unlimited precision and they are always signed. Unlike most other
languages, there is only one type for integer (unlimited), but the type system
allows to add constraints to be checked when assigning the variable contents.
Notice that the type is the same (`u32` is the same type as `i3`, they just have
different constraints). As a result, `u32 does u16` and `u16 does u32` are both
true as type-structure checks; assignment still performs the additional range
and precision checks described in the attribute section:

* `int`: an unlimited precision integer number.
* `unsigned`: An integer basic type constrained to be a natural number.
* `u<num>`: An integer basic type constrained to be a natural number with a maximum value of $2^{\texttt{num}}$. E.g: `u10` can go from zero to 1024.
* `i<num>`: an integer 2s complement number with a maximum value of $2^{\texttt{num}-1}-1$ and a minimum of $-2^{\texttt{num}}$.
* `int(a..<b)`: integer basic type constrained to be between `a` and `b`.

```pyrope
mut a:int         = nil // any value, no constrain
mut b:unsigned    = nil // only positive values
mut c:u13         = nil // only from 0 to 1<<13
mut d:int:[range=20..=30] = nil // only values from 20 to 30 (both included)
mut d:int:[min=-5, max=5] = nil // only values from -5 to 6 (6 not included)
mut e:int:[min=-1, max=0] = nil // 1 bit integer: -1 or 0
```

Integers can have 3 value (`0`,`1`,`?`) expression or a `nil`. Section
[Integers](02-basics.md#Integers) has more details, but those values can not be
part of the type requirement.


Integer typecast accepts strings as input. The string must be a valid formatted
Pryope number or an assertion is raised.


### Boolean

A boolean is either `true` or `false`. Booleans can not mix with integers in
expressions unless there is an explicit typecast (`int(false)==0` and
`int(true)==-1`) or the integer is a 1 bit signed integer (0 and -1). Unlike
integers, booleans do not support undefined value. A typecast from integer to
boolean will raise an assertion when the integer has undefined bits (`?`) or
`nil`.

```pyrope
const b = true
const c = 3

if c    { call(x) }  // error: 'c' is not a boolean expression
if c!=0 { call(x) }  // OK

mut d = b or false   // OK
mut e = c or false   // error: 'c' is not a boolean

const e = 0xfeed
if e#[3] {           // OK, bit extraction for single bit returns a boolean
  call(x)
}

cassert(0 == (int(true)  + 1)) // explicity typecast
cassert(1 == (int(false) + 1)) // explicity typecast
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
* `first..+size`: Range from first to `first+size`. Since there is `size`
  elements, it is equivalent to write `first..<(first+last)`.

When used inside selectors (`[range]`) the ranges can be open (no first/last specified)
or use negative numbers. Ranges only work with positive numbers, a negative
number is to specify the distance from last.

* `[first..<-val]` is the same as `[first..<(last-val+1)]`. The advantage is that the `last` or
size in the tuple can be unknown.
* `[first..]` is the same as `[first..=-1]`.

```pyrope
const a = (1,2,3)
cassert(a[0..] == (1,2,3))
cassert(a[1..] == (2,3))
cassert(a[..=1] == (1,2))
cassert(a[..<2] == (1,2))
cassert(a[1..<10] == (2,3))

const b = 0ub0110_1001
cassert(b#[1..]        == 0ub0110_100)
cassert(b#[1..=-1]     == 0ub0110_100)
cassert(b#[1..=-2]     == 0ub0110_100) // unsigned result from bit selector
cassert(b#sext[1..=-2] == 0sb110_100)
cassert(b#[1..=-3]     == 0sb10_100)
cassert(b#[1..<-3]     == 0ub0_100)
cassert(b#[0]          == false)
```


A range is a separate tuple. As such it can not directly compare with
tupes. It requires an explicit conversion. If the range does not contain
negative values, it can be converted to an integer back and forth which
corresponds to a one-hot encoding.

Range type cast from integers use the same one-hot encoding. It is not possible
to type cast from tuple to range, but it is possible from range to tuple.

```pyrope
const c = 1..=3
cassert(int(c) == 0ub1110)
cassert(range(0ub01_1100) == 2..=4)

assert(range(1,2,3)) // error: typecast not allowed
cassert (1,2,3) == tuple(1..=3)
```

In most cases, the range can be used in contructs like `for` for positive and
negative numbers. The `tuple` typecast is not needed, but if placed the
semantic is the same. The same `tuple` typecast is also optional when doing a
comparison. Both ranges a `step` to change the step.

```pyrope
cassert(int(0..=10 step  2) == 0ub101_0101_0101)
cassert(tuple(0..=10 step  2) == ( 0,2,4,6,8,10))
cassert(tuple(10..=0 step -2) == (10,8,6,4,2, 0))
cassert((10..=0 step -2) == (10,8,6,4,2, 0))

cassert(-1..=2 == (-1,0,1,2))
const x = -1..=2

cassert((0..=10 step 2) == (0,2,4,6,8,10))
```

Since the range is an integer, a decreasing range should have the same meaning
that an increasing range (`1..=3 == 3..=1`) but to avoid mistakes/confusions,
Pyrope generates a compile error in decreasing ranges.

```pyrope
assert(5..=0) // error: 5 + 1 never reaches 0
assert(5..=0 step -1 == (5,4,3,2,1,0))
```

A closed range can be converted to a single integer or a tuple. A range
encoded as an integer is a set of one-hot encodings. As such, there is no
order, but in Pyrope, ranges always have the order from smallest to largest.
The `step expr` can be added to indicate a step or step function. This is only
possible when both begin and end of the range are fully specified.


```pyrope
cassert((0..<30 step 10) == (0,10,20)) // ranges and tuples can combined
cassert((1..=3) ++ 4 == (1,2,3,4))     // tuple and range ops become a tuple
cassert(1..=3 == (1,2,3))
cassert((1..=3)#[..] == 0ub1110)        // convert range to integer with #[..]
```

### String

Strings are a basic type, but they can be typecasted to integers using the
ASCII sequence. The string encoding assigns the lower bits to the first
characters in the string, each character has 8 bits associated.

```pyrope
const a = 'cad'          // c is 0x63, a is 0x61, and d is 0x64
const b = 0x64_61_63
cassert(a == string(b)) // typecast number to string
cassert(int(a) == b) // typecast string to number
cassert(a#[..] == b) // typecast string to number
```

Like ranges, strings can also be seen as a tuple, and when tuple operations are
performed they are converted to a tuple.

```pyrope
cassert("hello" == ('h','e','l','l','o'))
cassert("h" ++ "ell" == ('h','e','l','l') == "hell")
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
comb check_is_green(self) { self.color == "green" }

type IsGreen = comb(self)

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

assert(y is Typ)
assert(Typ is Typ)
assert(not (z is Bund3))
assert(not (z is Typ))
assert(not (z is bund1))
```

## Type checks

A `:Type` annotation is **only** valid at a declaration site (`mut`, `reg`,
`const`, `comb`, `pipe`, `mod`, lambda parameters, lambda return types, and
tuple field declarations). Once the variable is declared, the type is set
for its whole existence.

To check that an existing value matches a type, use the `does` or `is`
operator inside `cassert`/`assert`. To convert a value to a type, call the
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

## Visibility: private by default, `pub` to export

All declarations are **private by default**: they can not be accessed from
other files or through the instantiation hierarchy. The `pub` prefix
modifier (same declaration slot as `comptime`) exports a top-scope
declaration:

* `pub` on a top-scope lambda, type, or variable allows other files to
  `import` it.
* `pub` on a `reg` (including memories) additionally allows synthesizable
  `regref` to attach to it from anywhere in the instantiation hierarchy.
  See [Register reference](07-typesystem.md#register-reference) and
  [Memories](08-memories.md#shared-memories-with-pub-reg-and-regref).

```pyrope
pub comb get_five() -> (v) { v = 5 }  // importable by other files
pub reg mem:[1024]u8 = nil            // synthesizable regref may attach
reg internal:u8 = 0                   // private: this file/instance only
```

**Debug is exempt from visibility.** Debug statements (`assert`, `test`,
`puts`, monitors) can observe any variable read-only through
`sigref`/`regref`, `pub` or not. Visibility restricts *synthesizable*
access only; nothing can be hidden from verification. There is no
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
cassert((1,2) in (a=0,b=1,c=3,2,e=4))
cassert(not ((a=2) in (1,2,3)))
cassert((a=2) in (1,a=2,c=3))
cassert((a=1,2) in (3,2,4,a=1))
cassert(not ((a=1,2) in (1,2,4,a=4)))
cassert(not ((a=1) in (a=(1,2))))
```

The `a in b` has to deal with undefined values (`nil`, `0sb?`). The LHS with an undefined
will be true if the RHS has the same named entry either defined or undefined.

```pyrope
cassert((x=nil,c=3) in (x=3,c=3))
cassert((x=nil,c=3) in (x=nil,c=3,d=4))
cassert(not ((c=3) in (c=nil,d=4)))
```

* `a ++ b` concatenate two tuples. If field appears in both, concatenate field. The a field is
defined in one tupe and undefined in the other, the undefined value is not concatenated.

```pyrope
cassert ((a=1,c=3) ++ (a=1,b=2,c=nil)) == (a=(1,1), c=3, b=2)
cassert ((1,2) ++ (a=2,nil,5)) == (1,2,a=2,5)
cassert ((x=1) ++ (a=2,nil,5)) == (x=1,a=2,nil,5)

cassert ((x=1,b=2) ++ (x=0sb?,3)) == (x=1,b=2,3)
```

* `(,...b)` in-place insert `b`. Behaves like `a ++ b` but it triggers a
  compile error if both have the same defined named field.

```pyrope
cassert (1,b=2,...(3,c=3),6) == (1,b=2,3,c=3,6)
cassert (1,b=2,...(nil,c=3),0sb?,6) == (1,b=2,nil,c=3,0sb?,6)
```


### Type operators

* `a has b` checks if `a` tuple has the `b` field where `b` is a string or
  integer (position).

```pyrope
cassert((a=1,b=2) has "a")
```

* `a does b` is true when `a` has all the tuple structure required by `b`
* `a equals b` same as `(a does b) and (b does a)`
* `a case b` same as `(a does b)` plus value matching for every defined value
  in `b`. Values in `b` that are undefined (`nil`, `0sb?`) act as wildcards.
* `a is b` is a nominal type check. Equivalent to `a.[typename] == b.[typename]`

Negate any type operator with `not (...)`, e.g. `not (a does b)`,
`not (a equals b)`, `not (a case b)`.

The `does` performs just name matching when the required tuple is fully named.
It reverts to name and position matching when some of the required tuple entries
are unnamed. Values are ignored by `does`; use `case` when the values should be
matched too.

```pyrope
cassert (b=100,a=333,e=40,5) does (a=1,b=3)
cassert (a=100,300,b=333,e=40,5) does (a=1,3)
cassert(not ((b=100,300,a=333,e=40,5) does (a=1,3)))
cassert(u32 does u16)
cassert(u16 does u32)
cassert(not (u32 does string))
cassert (100,30) does 30
cassert(not (30 does (30,200)))
cassert(not ((a=3) does (30,a=200)))
cassert(not ((a=3) does (a=30,200)))
cassert(not ((3) does (30,a=200)))
cassert(not ((3) does (a=30,200)))
```

A `a case b` first checks `a does b`, then checks that every defined value in
`b` has the same value in `a`. Undefined values in `b` (`nil`, `0sb?`) do not
participate in the value check and act as wildcards. This can be used in any
expression but it is quite useful for `match ... case` patterns.

```pyrope
match (a=1,b=3) {
  case (a=1) { cassert(true) }
  else { cassert(false) }
}

match const t=(a=1,b=3); t {
  case (a=1  ,c=4) { cassert(false) }
  case (b=nil,a=1) { cassert(t.b==3 and t.a==1) }
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
    * `zext`: Zero sign extends selected bits (default option)

+ `sel` is a single expression: an integer (one bit), a close-range like
  `1..=4`, or an open range like `3..`. Internally, the open range is converted
  to a close-range based on the variable size. Multi-entry tuple indices like
  `#[1,4,6]` are not allowed; use one bit-range assignment per group of bits.


The or/and/xor reduce have a single bit signed result (not boolean). This means
that the result can be 0 (`0sb0`) or -1 (`0sb1`). pop-count and `zext` have
always positive results. `sext` is a sign-extended, so it can be positive or
negative.

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
cassert(x#|[..] == -1)
cassert(x#&[0..=1] == 0)
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
    E.g: `0xFF#&[0..<8] == -1`.



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

* Unary operators (not,!,~,?) bind stronger than binary operators (+,++,-,*...)
* Comparators can be chained (a<=c<=d) same as (a<=c and c<=d)
* mult/div precedence is only against +,- operators.
* Parenthesis can be avoided when a expression left-to-right has the same
  result as right-to-left.

| Priority | Category | Main operators in category |
|:-----------:|:-----------:|-------------:|
| 1          | unary       | not ! ~ ? |
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

* Non-register variables are initialized with valid unless `_` is used in the
  initialization which explicitly clears the valid attribute.

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

`valid` can be overwritten by the setter method:

```pyrope
const custom = (
  ,mut data:i16 = nil
  ,comb setter(ref self, v) {
    self.data = v
    self.[valid] = v != 33
  }
)

mut x:custom = nil

cassert(x.[valid])
x.data = 33
cassert(not x.[valid])
x.data = 100
cassert(x.[valid])
```

The contents of the tuple field do not affect the field valid bit. It is
data-independent. Tuples also can have an optional type, which behaves like
adding optional to each of the tuple fields.

```pyrope
const complex = (
  ,reg v1:string = "foo"
  ,mut v2:string = nil

  ,comb setter(ref self, v) {
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

x2 = "world"

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
* **`0sb?`** (and related bit-literal forms like `0ub101.[valid]`, `0ub??10`) —
  unknown bits, behaving like Verilog `x`. The variable is still *valid*
  from the optional standpoint; only the bits are unknown. Use this for
  don't-care states or deliberately unobserved bits.

The bare `_` sink and the bare `?` shorthand have been removed in favor of
these two explicit values. Every initialization must supply a concrete
expression — a literal (`0`, `false`, `""`, `0sb?`), `nil`, or a normal
expression.

```pyrope
mut a:int = 0
cassert(a==0 and a.[valid] and a.[valid])

mut b:int = nil
cassert(b==nil and b.[valid] == false and not b.[valid])
b = 0
cassert(b==0 and b.[valid] and b.[valid])

mut d:[] = ()              // empty tuple literal
cassert(d != nil and d.[valid])

mut e:int = 0sb?           // valid but with unknown bits
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
mut x:int = nil
mut y:int = 2
mut z:int = nil
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

const (a, b_unused) = fcall_returns_2_values()
cassert(a == 3)
```
