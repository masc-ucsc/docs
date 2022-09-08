# Variables and types

A variable is an instance of a given type. The type may be inferred from use.
The basic types are Boolean, Function, Integer, Range, and String. All those
types can be combined with tuples. All the complex types are built around
these types.


## Mutable/Immutable

Variables first use or declaration must indicate the mutability intention
(`var`) or immutability (`let`).

* `var` is used to declare mutable variables. Following statements can
  overwrite the variable.

* `let` is used to declare immutable variables. Following statements can not
  modify the contents. For methods, only use `let` when no overloading/traits
  should be allowed.


```
a  = 3         // compile error, no previous let or var

var b  = 3
b  = 5     // OK
b += 1     // OK, OP= assumes mutable

var c=(x=1,let b=2, var d=3)
c.x   = 3  // OK, x inherited the 'var' declaration
x.foo = 2  // compile error, tuple 'x' does not have field 'foo'
c.b   = 10 // compile error, 'c.b' is immutable
c.d   = 30 // OK, d was already var type

let d=(x=1, let y=2, var z=3)
d.x   = 2  // compile error: x inherits the 'let' declaration
d.foo = 3  // compile error, tuple 'd' does not have field foo'
d.z   = 4  // compile error, 'd.z' is immutable
```

Tuples fields (not contents) are immutable, but it is possible to construct new
tuples with the `++` (concatenate) and `...` (in-place operator):

```
var a=(a=1,b=2)
var b=(c=3)

var ccat1 = a ++ b
assert ccat1 == (a=1,b=2,c=3)
assert ccat1 == (1,2,3)

var ccat2 = a ++ (b=20)
assert ccat2 == (a=1,b=(2,20),c=3)
assert ccat2 == (1,(2,20),3)

var join1 = (...a,...b)
assert join1 == (a=1,b=2,c=3)
assert join1 == (1,2,3)

var join2 = (...a,...(b=20)) // compile error, 'b' already exists
```


The `a ++ b` concatenates two tuples. If the same field exists in both tuples,
the resulting field will have a tuple with the entries of `a` and `b`.  The
concat tries to match by field name, if the field names do not match or have no
name a new entry is created. The algorithm starts with tuple `a` and starts
from tuple field 0 upwards.

```
assert(((1,a=2,c=3) ++ (a=20,33,c=30,4)) == (1,a=(2,20),c=(3,30),33,4))
```

The `...` also concatenates, but it is an "inline concatenate". The difference
is where the fields are concatenated and that it triggers a compile error if
the same entry already exists.


## Register

Both mutable and immutable variables (`var`/`let`) are created every cycle. To
have persistence across cycles the `reg` keyword must be used.


```
reg counter = 10
var not_count = 20
```

In `reg`, the right-hand side of the initialization (`10` in the counterexample) is called only during reset. In `var/let`, the right-hand side is
called every cycle. As expected, `reg` is mutable.

## Public

All types of declarations (`let`, `var`, `reg`) can have a `pub` before. This
is used to indicate that the declaration is public and hence visible outside
the scope defined. 


The `pub` has different meaning depending on when it is applied:

* When the `pub` is applied to a tuple entry, it means that the tuple entry can
  be accessed outside the tuple. 

* When the `pub` is applied to a `pipestage` variable, it means that the
  variable is to be pipelined to the next type stage.
  Section [pipestage](06c-pipelining.md) has more details.

* When the `pub` is applied to a pyrope file upper scope variable, it means
  that an `import` command or register reference can access it across files.
  Section [typesystem](07-typesystem.md) has more details.


To avoid the common case of adding `pub var` to most tuple entries,
when no modifier is applied a `pub var` is assumed.

```
let x1  = (pub let b=3, pub var d=4, let e=5, var f=6)

let x2  = (pub let b=3,         d=4, let e=5, var f=6)

var x3  = (pub let b=3,         d=4, let e=5, var f=6)

type x4 = (pub let b=3,         d=4, let e=5, var f=6)

// x1,x2,x3,x4 have identical tuple entry modifiers
```

## Variable scope

Scope constrains defined variables visibility. There are three types of scope
delimitation in Pyrope: code blocks, lambda definitions, and tuples. Each has
a different set of rules constraining the variable scopes.


=== "Code Block scope"

    ```
    assert a == 3    // compile error, undefined variable 'a'
    var a = 3
    {
      assert a == 3
      a = 33         // OK
      let b = 4
      let a = 3333   // compile error, variable shadowing
    }
    assert b == 3    // compile error, undefined variable 'b'
    ```

=== "Lambda scope"

    ```
    assert a == 3    // compile error, undefined variable 'a'
    var a = 3
    let f1 = fun[a]() {
      assert a == 3
      a = 33         // compile error, upper scope are always immutable
      let b = 4
      let a = 3333   // compile error, variable shadowing
      assert a == 3333
    }
    let f2 = fun() { // restrict scope
      assert a == 3  // compile error, undefined variable 'a'
    }
    let f3 = fun[ff=a]() { // restrict scope
      assert ff == 3 // OK
    }
    assert b == 3    // compile error, undefined variable 'b'
    ```

=== "Tuple scope"

    ```
    // a is not visible
    var a = 3
    let r1 = (
      ,a=a+1
      ,c = {assert a == 3; assert self.a==4; 50}
    )

    let r2 = (a=100, c=(a=a+1, e=self.a+30))
    assert r2 == (a=100,c=(a==101, e=131))

    ```

* Shadowing is not allowed in lambdas or code blocks. Tuples can redefine
  (shadow) the same variable but to use inside the tuple, the `self` keyword
  must be used always.

* Lambdas and tuples upper scope variables are always immutable.

* Lambdas can restrict upper scope visibility with `[]`.

* A variable is visible from definition until the end of scope in program order.


## Basic types

Pyrope has 7 basic types:

* `boolean`: either `true` or `false`
* `enum`: enumerated
* `proc` and `fun`: A procedure or a function
* `integer`: which is signed integer of unlimited precision
* `range`: A one hot encoding of values `1..=3 == 0b1110`
* `string`: which is a sequence of characters


All the types except the function can be converted back and
forth to an integer.


### Integer or `int`

Integers have unlimited precision and they are always signed. Unlike most other
languages, there is only one type for integer (unlimited), but the type system
allows to add constrains to be checked when assigning the variable contents.
Notice that the type is the same (`u32` is the same type as `i3`, they just have
different constraints):

* `int`: an unlimited precision integer number.
* `unsigned`: An integer basic type constrained to be a natural number.
* `u<num>`: An integer basic type constrained to be a natural number with a maximum value of $2^{\texttt{num}}$. E.g: `u10` can go from zero to 1024.
* `i<num>`: an integer 2s complement number with a maximum value of $2^{\texttt{num}-1}-1$ and a minimum of $-2^{\texttt{num}}$.
* `int(a..<b)`: integer basic type constrained to be between `a` and `b`.

```
var a:int          // any value, no constrain
var b:unsigned     // only positive values
var c:u13          // only from 0 to 1<<13
var d:int(20..=30) // only values from 20 to 30 (both included)
var d:int(-5..<6)  // only values from -5 to 6 (6 not included)
var e:int(-1,0)    // 1 bit integer: -1 or 0
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

```
let b = true
let c = 3

if c    { call(x) }     // compile error, 'c' is not a boolean expression
if c!=0 { call(x) }     // OK

d = b or false // OK
e = c or false // compile error, 'c' is not a boolean

let e = -1
if e { // OK e is a 1 bit signed value
  call(x)
}

assert 0 == (int(true)  + 1)  // explicity typecast
assert 1 == (int(false) + 1)  // explicity typecast
assert boolean(33) or false   // explicity typecast
```

String input typecase is valid, but anything different than ("0", "1", "-1",
"true", "TRUE", "t", "false", "FALSE", "f") raises an assertion failure.

### Function

Functions have several options (see [Functions](06-functions.md)), but from a
high level they provide a sequence of statements and they have a tuple for
input and a tuple for output. Functions also can capture values from function
declaration. Functions are immutable objects.


### Range

Ranges are very useful in hardware description languages to select bits. They
are 3 ways to specify a closed range:

* `first..=last`: Range from first to the last element, both included
* `first..<last`: Range from first to last, but the last element is not included
* `first..+size`: Range from first to `first+size`. Since there is `size`
  elements, it is equivalent to write `first..<(first+last)`.

When used inside selectors (`[range]`) the ranges can be open (no first/last specified)
or use negative numbers. The negative number is to specify the distance from last.

* `[first..<-val]` is the same as `[first..<(last-val+1)]`. The advantage is that the `last` or
size in the tuple can be unknown.
* `[first..]` is the same as `[first..=-1]`.

```
let a = (1,2,3)
assert a[0..] == (1,2,3)
assert a[1..] == (2,3)
assert a[..=1] == (1,2)
assert a[..<2] == (1,2)
assert a[1..<10] == (2,3)

let b = 0b0110_1001
assert b@[1..]        == 0b0110_100
assert b@[1..=-1]     == 0b0110_100
assert b@[1..=-2]     == 0b0110_100  // unsigned result from bit selector
assert b@sext[1..=-2] == 0sb110_100
assert b@[1..=-3]     == 0sb10_100
assert b@[1..<-3]     == 0b0_100

let c = 1..=3
assert int(c) == 0b1110
assert range(0b01_1100) == 2..=4
```

Range typecase only accepts integers as input.

A closed range can be converted to a single integer or a tuple. A range
encoded as an integer is a set of one-hot encodings. As such, there is no
order, but in Pyrope, ranges always have the order from smallest to largest.
The `by expr` can be added to indicate a step or step function. This is only
possible when both begin and end of the range are fully specified.


```
assert((0..<30 by 10) == (0,10,20)) // ranges and tuples can combined
assert((1..=3) ++ 4 == (1,2,3,4))   // tuple and range ops become a tuple
assert 1..=3 == (1,2,3)
assert((1..=3)@[] == 0b1110)        // convert range to integer with @[]
```

### String

Strings are a basic type, but they can be typecasted to integers using the
ASCII sequence. The string encoding assigns the lower bits to the first
characters in the string, each character has 8 bits associated.

```
a = 'cad'              // c is 0x63, a is 0x61, and d is 0x64
b = 0x64_61_63
assert a == string(b)  // typecast number to string
assert int(a) == b     // typecast string to number
assert a@[] == b       // typecast string to number
```

Like ranges, strings can also be seen as a tuple, and when tuple operations are
performed they are converted to a tuple.

```
assert "hello" == ('h','e','l','l','o')
assert "h" ++ "ell" == ('h','e','l','l') == "hell"
```

## comptime

Pyrope borrows the `comptime` keyword and functionality from Zig. Any statement
can be declared compile time constants or `comptime`. This means that the value
must be constant at compile time or a compile error is generated.

```
comptime let a = 1     // obviously comptime
comptime var b = a + 2 // OK too
comptime let c = rand  // compile error, 'c' is not compile time constant
```

The `comptime` directive considers values propagated across modules.


In addition to `comptime`, any variable that starts with an uppercase is also a
compile time constant.

```
let Xconst1 = 1      // obvious comptime
let Xvar2   = rand   // compile error, 'Xvar2' is not compile time constant
```

## debug

In software and more commonly in hardware, it is common to have extra
statements to debug the code. These statements can be more than plain
assertions, they can also include code.

The `debug` attribute marks a mutable or immutable variable. At synthesis, all
the statements that use a `debug` can be removed. `debug` variables can read
from non debug variables, but non-debug variables can not read from `debug`.
This guarantees that `debug` variables, or statements, do not have any
side-effects beyond debug statements.

```
var a = (debug b=2, c = 3) // a.b is a debug variable
debug let c = 3
```

debug statements can also bypass protection access. This means that private
variables without a `pub` can be accessed (read-only) when used with `debug`
statements. This also applies to `assert` because the assert/assume directives
are consider debug statements.

```
var x:(var priv=3, pub var zz=4)

let tmp = x.priv       // compile error
debug let tmp = x.priv // OK

assert x.priv == 3     // OK, assert is a debug statement
```


## type vs let

Each variable has a type, either implicit or explicit, and as such, it can be
used to declare a new type. 


The `type` keywords guarantee that a variable is just a type and not an
instance. A type is also a special class of immutable tuple. It does not allow
to add variables, but it allows to add lambdas. As such there is a very small
difference betwee `type x =...` and `let x =...`. Besides allowing to add
methods, the other  main difference is that `type` assigns also a type name
that can be checked with nominal type check `is`.

```
var bund1 = (color:string, value:s33)
var x:bund1          // OK
bund1.color = "red"  // OK
bund1.is_green = fun(self) { ret self.color == "green" }
x.color     = "blue" // OK

type typ = (color:string, value:s33)
var y:typ            // OK
typ.color = "red"    // compile error
typ.is_green = fun(self) { ret self.color == "green" }
y.color   = "red"    // OK

let bund3 = (color:string, value:s33)
var z:bund3          // OK
bund3.color = "red"  // compile error
bund3.is_green = fun(self) { ... } // compile error
z.color     = "blue" // OK

assert x equals typ  // same type structure
assert z equals typ  // same type structure
assert x equals z    // same type structure

assert y is typ
assert typ is typ
assert z !is bund3 
assert z !is typ
assert z !is bund1
```

Adding a method to a tuple with `tup.fn = fun...` is the same as `tup = tup ++
(fn=fun...)`.


## Operators

There are the typical basic operators found in most common languages except
exponent operations. The reason is that those are very hardware intensive and a
library code should be used instead.

All the operators work over signed integers.

### Unary operators

* `!a` or `not a` logical negation
* `~a` bitwise negation
* `-a` arithmetic negation

### Binary Integer operators

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
* `a >> b` shift right
* `a << b` shift left

### Binary Boolean operators

* `a and b` logical and
* `a or b` logical or
* `a implies b` logical implication
* `a !and b` logical nand
* `a !or b` logical nor
* `a !implies b` logical not implication

### Set operators

* `a in b` is element `a` in tuple `b`
* `a !in b` true when element `a` is not in tuple `b`

Most operations behave as expected when applied to signed unlimited precision
integers. Logical and arithmetic operations can not be mixed.

```
let x = a and b
let y = x + 1    // compile error: 'x' is a boolean, '1' is integer
```

### Reduce and bit selection operators

The reduce operators and bit selection share a common syntax
`variable@op[sel]` where:

+ `variable` is a tuple where all the tuple fields and subfields must have a
  explicit type size unless the tuple has 1 entry.

+ `op` is the operation to perform

    * `|`: or-reduce.
    * `&`: and-reduce.
    * `^`: xor-reduce or parity check.
    * `+`: pop-count.
    * `sext`: Sign extends selected bits.
    * `zext`: Zero sign extends selected bits (default option)

+ `sel` can be a close-range like `1..<=4` or `(1,4,6)` or an open range like
  `3..`. Internally, the open range is converted to a close-range based on the
  variable size.


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
bits accordingly. E.g: `var@[0..=3]@+[]` does a `zext` and the positive result
is passed to the pop-count. The compiler could infer the size and compute, but
it is considered non-intuitive for programmers.


```
x = 0b1_0110   // positive
y = 0s1_0110   // negative
assert x@[0,2] == 0b10
assert y@[100,200]       == 0b11   and x@[100,200]       == 0
assert y@sext[0,100,200] == 0sb110 and x@sext[1,100,200] == 0b001
assert x@|[] == -1
assert x@&[0,1] == 0
assert x@+[0..=5] == x@+[0..<100] == 3
assert y@+[0..=5]  // compile error, 'y' can be negative
assert y@[]@+[] == 3
assert y@[0..=5]@+[] == 3
assert y@[0..=6]@+[] == 4

var z     = 0b0110
z@[0] = 1
assert z == 0b0111
z@[0] = 0b11 // compile error, '0b11` overflows the maximum allowed value of `z@[0]`
```

!!!Note
    It is important to remember that in Pyrope all the operations use signed
    numbers. This means that an and-reduce over any positive number is always going
    to be zero because the most significant bit is zero, E.g: `0xFF@&[] == 0`. In
    some cases, a close-range will be needed if the intention is to ignore the sign.
    E.g: `0xFF@&[0..<8] == -1`.


When the selected variable is a tuple with many entries, the result of the
tuple expansion may be unexpected because the compiler can infer bits used
independently of the type set. This is the case because the `tup@[]` is
effectively concatenating the bits in `tup` but the tuple fields can be
optimized making the resulting constant to be unexpected.

```
var tup = (a=0xf:u3232, b=0x1:int)  // explicit sizes set
assert tup@[] == 0b001_01111

assert((0xF:s8,0x1:s16)@[] == 0x0001_0F)
assert((0xF:u8,0x1:u16)@[] == 0x0002_0F) // 0xF needs 9 signed bits

assert((true,false,true,false,false,true )@[]     == 0sb0100101 == 0b100101
assert((true,false,true,false,false,true )@sext[] == 0sb100101
assert((true)@[]     == 0sb01)
assert((true)@sext[] == -1   )
```

A more straightforward solution is to explicitly set the bits expected:

```
var res

res@[0..<8]= 0x0F
res@[9..]  = 0x1

assert res == 0b1_00001111 == 0x1_0F
```

Another important characteristic of the bit selection is that the order of the
bits on the selection does not affect the result. Internally, it is a bitmask
that has no order. For the `zext` and `sext`, the same order as the input
variable is respected. This means that `var@[1,2] == var@[2,1]`. As a result,
the bit selection can not be used to transpose bits. A tuple must be used for
such an operation.

```
var v = 0b10
assert v@[0,1] == v@[1,2] == v@[] == v@[0..=1] == v@[..=1] == 0b10

var trans
trans@[0] = v@[1]
trans@[1] = v@[0]
assert trans == 0b01
```

### Operator with Tuples

Some operators can also have tuples as input and/or outputs.

* `a ++ b` concatenate two tuples. If field appears in both, concatenate field
* `(,...b)` in-place insert `b`. Compile error if both have the same named
  field
* `a << b` shift left. `b` can be a tuple
* `a has b` checks if `a` tuple has the `b` field where `b` is a string or
  integer (position).
* `a in b` checks if `a` values are in `b`

The `<<` allows having multiple values provided by a tuple on the right-hand
side or amount. This is useful to create one-hot encodings.

```
assert((a=1,b=2) ++ (c=3    ) == (a=1    ,b=2,c=3))
assert((a=1,b=2) ++ (a=3,c=4) == (a=(1,3),b=2,c=4))

assert((a=1,b=2,3,...(e=4,5)) == (a=1,b=2,3,e=4,5))

assert((a=1,b=2) has "a")

assert(2 in (a=1,b=2))
assert((2,5) in (a=1,b=2,4,5))

assert 1<<(1,4,3) == 0b01_1010
```

## Precedence

Pyrope has very shallow precedence, unlike most other languages the
programmer should explicitly indicate the precedence. The exception is for
widely expected precedence.

* Unary operators (not,!,~,?) bind stronger than binary operators (+,++,-,*...)
* Comparators can be chained (a==c<=d) same as (a==c and c<=d)
* mult/div precedence is only against +,- operators.
* Parenthesis can be avoided when a expression left-to-right has the same
  result as right-to-left.

| Priority | Category | Main operators in category |
|:-----------:|:-----------:|-------------:|
| 1          | unary       | not ! ~ ? |
| 2          | mult/div    | *, /         |
| 3          | other binary | ..,^, &, -,+, ++, <<, >> |
| 4          | comparators |    <, <=, ==, !=, >=, > |
| 5          | logical     | and, or, implies |


```
assert((x or !y) == (x or (!y)) == (x or not y))
assert((3*5+5) == ((3*5) + 5) == 3*5 + 5)

a = x1 or x2==x3 // same as b = x1 or (x2==x3)
b = 3 & 4 * 4    // compile error: use parenthesis for explicit precedence
c = 3
  & 4 * 4
  & 5 + 3        // compile error: use parenthesis for explicit precedence
c2 = 3
  & (4 * 4)
  & (5 + 3)      // OK

d = 3 + 3 - 5    // OK, same result right-left

e = 1
  | 5
  & 6           // compile error: use parenthesis for explicit precedence

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

h = x or y and z// compile error: use parenthesis for explicit precedence

i = a == 3 <= b == d
assert i == (a==3 and 3<=b and b == d)
```

## Optional

The `?` is used by several languages to handle optional or null pointer
references. In non-hardware languages, `?` is used to check if there is valid
data or a null pointer.


Pyrope does not have null pointers or memory associated management. Pyrope uses
`?` to handle "valid" data. Instead, the data is left to behave without the
optional, but there is a new "valid" field associated with each tuple entry.


There are 4 explicitly interact with valids:

* `tup.f1?` reads the valid for field `f1` from tuple `tup`

* `tup?.f1.f2` returns `0bs0` if tuple fields `f1` or `f2` are invalid

* `tup.f1? = cond` explicitly sets the field `f1` valid to `cond`

* `a = b op c` variable `a` will be valid if `b` AND `c` are valid


The optional or valid attached to each variable and tuple field is implicitly
computed as follows:

* Each cycle the `valid` is set for non-register variables initialization[^clear].

* Registers with reset set the valid on reset (not every cycle)

* Register have invalid data during reset. Hence, the output of registers is invalid during reset.

* Left-hand side variables `valids` are set to the and-gate of all the variable
  valids used in the expression

* Reading from a memory is always a valid contents

* Writing to a register updates the register valid based on the din valid

* conditionals (`if`) update valids independently for each path

* A tuple field has the valid set to false if any of the parent tuple fields is
  invalid

* The valid computation can be overwritten with the `__valid` attribute. This
  is possible even during reset.


[^clear]: Non-register variables are initialized to zero each cycle too, the
  valid is cleared at the same time.


!!! NOTE
    The variable valid calculation is similar to the Elastic 'output_written'
    from [Liam](https://masc.soe.ucsc.edu/docs/memocode17.pdf) but it is not an
    elastic update because it does not consider the abort or retry.


The previous rules will clear a valid only if an expression has no valid, but
the only way to have a non-valid is if the inputs to the lambda are invalid or
if the valid is explicitly clear. The rules are designed to have no overhead
when valid are not used. The compiler should detect that the valid is true all
the time, and the associated logic is removed.


```
var v1:u32                      // valid and zero every cycle
var v2:u32 = (__valid=false, 3) // not valid and 3 every cycle

comptime assert v1?
comptime assert not v2?

comptime assert v1 == 0 and v2 == 3 // data still same as usual

v1 = 0sb?                      // OK, poison data
v2 = 0sb?                      // OK, poison data, and update valid
comptime assert v2?            // valid even though data is not

comptime assert v1 != 0        // usual verilog x logic
comptime assert v2 != 0        // usual verilog x logic

let res1 = v1 + 0              // OK, just unknown result
let res2 = v2 + 0              // OK, just unknown result

comptime assert res1?
comptime assert res2?

reg counter:u32 = 0

always_assert counter.reset implies !counter?
```

A valid method allows to overwrite the default valid behavior:

```
type custom = (
  ,var data:i16
  ,var valid= fun () {
    ret self.data != 33
  }
)

var x:custom
comptime assert x?
x.data = 33
comptime assert not x?
```


The contents of the tuple field do not affect the field valid bit. It is
data-independent. Tuples also can have an optional type, which behaves like
adding optional to each of the tuple fields.

```
type complex = (
  ,reg v1:string
  ,pub v2:string

  ,pub set = proc (ref self,v) {
     self.v1 = v
     self.v2 = v
  }
)

var x1:complex
var x2:complex = (__valid=false)  // toggle valid, keep zero

comptime assert x1.v1 == "" and x1.v2 == ""
comptime assert not x2?  and not x2.v1? and not v2.v2?
comptime assert x2.v1 == "" and x2.v2 == ""

comptime assert x2?.v1 == "" and x2?.v1 != ""  // any comparison is false

// When x2? is false, any x2?.foo returns 0sb? with the associated x rules

x2.v2 = "hello" // direct access still OK

comptime assert not x2? and x2.v1 == "" and x2.v2 == "hello"

x2 = "world"

comptime assert x2? and x2?.v1 == "world" and x2.v1 == "world"
```

