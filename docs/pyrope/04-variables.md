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
tuples with the `++` (concatenate) and `...` (in place insert):

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
assert ((1,a=2,c=3) ++ (a=20,33,c=30,4)) == (1,a=(2,20),c=(3,30),33,4)
```

The `...` also concatenates, but it is an "inline concatenate". The difference
is where the fields are concatenated and that it triggers a compile error if
the same named entry already exists.


## Register

Both mutable and immutable variables (`var`/`let`) are created every cycle. To
have persistence across cycles the `reg` keyword must be used.


```
reg counter = 10
var not_count = 20
```

In `reg`, the right hand side of the initialization (`10` in the counter
example) is called only during reset. In `var/let`, the righ hand size is
called every cycle. As expected, `reg` is a mutable.

## public

All types of declarations (`let`, `var`, `reg`) can have a `pub` before. This
is used to indicate the the declaration is public and hence visible outside the
scope defined. Section (typesystem)[07-typesystem.md] has more details on how
to `import` or `punch` a declaration across files.

## Basic types

Pyrope has 5 basic types:

* `boolean`: either `true` or `false`
* `function`: A method/function
* `integer`: which is signed integer of unlimited precision
* `range`: A one hot encoding of values `1..=3 == 0b1110`
* `string`: which is a sequence of characters


All the types except the function can be converted back and
forth to an integer.


### Integer or `int`

Integers have unlimited precision and they are always signed. Type constraints 
can enforce a subset like unsigned or ranges.

```
var a:int          // any value, no constrain
var b:unsigned     // only positive values
var c:u13          // only from 0 to 1<<13
var d:int(20..=30) // only values from 20 to 30
var e:int(-1,0)    // 1 bit integer: -1 or 0
```
### Boolean

A boolean is either `true` or `false`. Booleans can not mix with integers in
expressions unless there is an explicit typecast (`false=0` and `true=-1`) or
the integer is a 1 bit signed integer (0 and -1).

```
let b = true
let c = 3

if c    {}     // compile error, 'c' is not a boolean expression
if c!=0 {}     // OK

d = b or false // OK
e = c or false // compile error, 'c' is not a boolean

let e = -1
if e { // OK e is a 1 bit signed value
}

assert (int(true)  + 1) == 0  // explicity typecast
assert (int(false) + 1) == 1  // explicity typecast
assert boolean(33) or false   // explicity typecast
```

### Function

Functions have several options (see [Functions](06-functions.md)), but from a
high level they provide a sequence of statements and they have a tuple for
input and a tuple for output. Functions also can capture values from function
declaration. Functions are immutable objects.


### Range

Ranges are very useful in hardware description languages to select bits, but
they are integrated all over the language. It is a type by itself that can be
converted to a single Integer. The range can also be seen as one hot
encoding of a set of integers.


They are 3 ways to specify a closed range:

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

### String

Strings are also Integers encoded using the ASCII sequence, but to perform arithmetic
operations a typecast must be used. The string encoding assigns the lower bits
to the first characters in the string, each character has 8 bits associated.

```
a = 'cad'              // c is 0x63, a is 0x61, and d is 0x64
b = 0x64_61_63
assert a == string(b)  // typecast number to string
assert int(a) == b     // typecast string to number
```

## comptime

Pyrope borrows the `comptime` keyword and functionality from Zig. Any statement
can be declared compile time constants or `comptime`. This means that the value
must be constant at compile time or an error is generated.

```
let comptime a = 1     // obviously comptime
var comptime b = a + 2 // OK too
let comptime c = $rand // compile error, 'c' can not be computed at compile time
```

The `comptime` directive considers values propagated across modules.

## debug

In software and more commonly in hardware, it is common to have extra
statements to debug the code. These statements can be more than plain
assertions, they can also include code.

The `debug` attribute marks a mutable or immutable variable. At synthesis, all
the statements that use a `debug` can be removed. `debug` variables can read
from non debug variables, but non-debug variables can not read from `debug`.
This guarantees that `debug` variables, or statements, do not have any
side-effect beyond debug statements.

```
var a = (debug b=2, c = 3) // a.b is a debug variable
let debug c = 3
```

## Basic type annotations

Global type inference and unlimited precision allow avoiding most of the
types. Pyrope allows declaring types. The types have two main uses, they
behave like assertions, and they allow function polymorphism.

```
var a:u120    // a is an unsigned value with up to 120bits, initialized to zero

var x:s3 = 0  // x is a signed value with 3 bits (-4 to 3)
mut x = 3     // OK
mut x = 4     // compile error, '4' overflows the maximum allowed value of 'x'

var person = (
  ,name:string // empty string by default
  ,age:u8      // zero by default
)

var b
b ++= (1,2)
b ++= (3,4)

assert b == (1,2,3,4)
```

The basic type keywords provided by Pyrope:

* `boolean`: true or false boolean. It can not be undefined (`0sb?`).
* `string`: a string.
* `{||}`: is a function without any statement which can be used as a function type.
* `unsigned`: an unlimited precision natural number.
* `u<num>`: a natural number with a maximum value of $2^{\texttt{num}}$. E.g: `u10` can go from zero to 1024.
* `int`: an unlimited precision integer number.
* `i<num>`: an integer 2s complement number with a maximum value of $2^{\texttt{num}-1}-1$ and a minimum of $-2^{\texttt{num}}$.


Each tuple is has a type, either implicit or explicit, and as such, it can be
used to declare a new type. The `type` keywords guarantee that a variable is
just a type and not an instance.

```
var bund1 = (color:string, value:s33)
var x:bund1          // OK
bund1.color = "red"  // OK
x.color     = "blue" // OK

type typ = (color:string, value:s20)
var y:typ            // OK
typ.color = "red"    // compile errro
y.color   = "red"    // OK
```

## Operators

There are the typical basic operators found in most common languages except exponent operations. The reason is that those are very hardware
intensive and a library code should be used instead.

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
* `a >> b` shift right
* `a << b` shift left

### Binary Boolean operators

* `a and b` logical and
* `a or b` logical or
* `a implies b` logical implication


Most operations behave as expected when applied to signed unlimited precision
integers. Logical and arithmetic operations can not be mixed.

```
let x = a and b
let y = x + 1    // compile error: 'x' is a boolean, '1' is not
```

### Reduce and bit selection operators

The reduce operators and bit selection share a common syntax `variable@op[selection]`
where there can be different operators (op) and/or bit selection. The selection
can be a close range like `1..<=4` or `(1,4,6)` or an open range like `3..`.
Internally, the open range is converted to a close range based on the variable
size.


Reduce and bit selection operators:

* `|`: or-reduce.
* `&`: and-reduce.
* `^`: xor-reduce or parity check.
* `+`: pop-count.
* `sext`: Sign extends selected bits.
* `zext`: Zero sign extends selected bits.

The or/and/xor reduce have a single bit signed result (not boolean). This means
that the result can be 0 (`0sb0`) or -1 (`0sb1`). pop-count and `zext` have 
always positive results. `sext` is a sign-extended, so it can be positive or
negative.

If no operator is provided, a `zext` is used. The bit selection without
operator can also be used on the left hand side to update a set of bits.


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
mut z@[0] = 1    // same as mut z@[0] = -1 
assert z == 0b0111
mut z@[0] = 0b11 // compile error, '0b11` overflows the maximum allowed value of `z@[0]`
```

!!!Note
    It is important to remember that in Pyrope all the operations use signed
    numbers. This means that an and-reduce over any positive number is always going
    to be zero because the most significant bit is zero, E.g: `0xFF@&[] == 0`. In
    some cases, a close range will be needed if the intention is to ignore the sign.
    E.g: `0xFF@&[0..<8] == -1`.

Another important characteristic of the bit selection is that the order of the
bits on the selection does not affect the result. Internally, it is a bitmask
that has no order. For the `zext` and `sext`, the same order as the input
variable is respected. This means that `var@[1,2] == var@[2,1]`. As a result,
the bit selection can not be used to transpose bits. A tuple must be used for
such an operation.

```
var = 0b10
assert var@[0,1] == var@[1,2] == var@[] == var@[0..=1] == var@[..=1] == 0b10

trans = (var[1], var[0])@[]
assert trans == 1
```

### Operator with Tuples

Some operators can also have tuples as input and/or outputs.

* `a ++ b` concatenate two tuples. If field appears in both, concatenate field
* `(,...b)` inplace insert `b`. Compile error if both have same named field
* `a << b` shift left. `b` can be a tuple
* `a has b` checks if `a` tuple has the `b` field

The `<<` allows having multiple values provided by a tuple on the right-hand
side or amount. This is useful to create one-hot encodings.

```
assert (a=1,b=2) ++ (c=3    ) == (a=1    ,b=2,c=3)
assert (a=1,b=2) ++ (a=3,c=4) == (a=(1,3),b=2,c=4)

assert (a=1,b=2,3,...(e=4,5)) == (a=1,b=2,3,e=4,5)

assert (a=1,b=2) has "a"

assert 1<<(1,4,3) == 0b01_1010
```

## Precedence

Pyrope has very shallow precedence, unlike most other languages the
programmer should explicitly indicate the precedence. The exception is for
widely expected precedence.

* Unary operators (not,!,~,?) bind stronger than binary operators (+,++,-,*...)
* Comparators can be chained (a==c<=d) same as (a==c and c<=d)
* mult/div precedence is only against +,- operators.
* Parenthesis can be avoided when a expression only has variables (no function
  calls) and the left-to-right has the same result as right-to-left.
* Always left-to-right evaluation (only matter with mutable functions).

| Priority | Category | Main operators in category |
|:-----------:|:-----------:|-------------:|
| 1          | unary       | not ! ~ ? |
| 2          | mult/div    | *, /         |
| 3          | other binary | ..,^, &, -,+, ++, <<, >> |
| 4          | comparators |    <, <=, ==, !=, >=, > |
| 5          | logical     | and, or, implies |


```
assert (x or !y) == (x or (!y)) == (x or not y)
assert (3*5+5) == ((3*5) + 5) == 3*5 + 5

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

## Valid or optional

Pyrope has support to handle valids. The `?` is used by several languages to
handle optional or null pointer references. The `?` is used to check if there
is valid data or a null pointer.

Pyrope has no pointers, but the same syntax is used for handle "valid" data.
Instead the data is left to behave like without the optional, but there is a
new "valid" field associated with the tuple.


```
var v1:u32
var v2:u32?

comptime assert v1 == 0 and v2 == 0 // data still same as usual

comptime assert v1?            // compile error, no optional type
comptime assert not v2?

v1 = 0sb?                      // OK, poison data
v2 = 0sb?                      // OK, poison data, and unset valid

comptime assert v1 != 0        // usual verilog x logic
comptime assert v2 != 0        // usual verilog x logic

let res1 = v1 + 0              // OK, just unknown result
let res2 = v2 + 0              // OK, just unknown result
```


Notice that the data field can be poison with `nil` or `0sb?`. The nil in
Pyrope is a bit more strict and notifies on any usage error. nil poisons the
data. Any op with it is a compile or runtime error. This behavior does not change
because of the optional `?` type.

```
v1 = nil                       // OK, poison data
v2 = nil                       // OK, poison data, and unset valid

let res3 = v1 + 0              // compile or runtime error
let res4 = v2 + 0              // compile or runtime error

comptime assert v1 == nil       // compile error, can not do ops with nil
comptime assert v2 == nil       // compile error, can not do ops with nil

v2 = 100
comptime assert v2? and (v2 + 1) == 101

v2? = false                    // keep data, just toggle valid
comptime assert not v2? and v2 == 101
```

Tuples also can have optional type:

```
type complex = (
  ,reg v1:string
  ,pub v2:string

  ,pub set = {|(self,v)->(self)|
     self.v1 = v
     self.v2 = v
  }
)

var x1:complex
var x2:complex?

comptime assert x1.v1 == "" and x1.v2 == ""
comptime assert not x2?  and x2.v1 == "" and x2.v2 == ""

comptime assert x2?.v1 == "" and x2?.v1 != ""  // any comparison is false

// When x2? is false, any x2?.foo returns 0sb? with the associated x rules

x2.v2 = "hello" // direct access still OK

comptime assert not x2? and x2.v1 == "" and x2.v2 == "hello"

x2 = "world"

comptime assert x2? and x2?.v1 == "world" and x2.v1 == "world"
```

The valid bit can be overwritten:

```
//--------------
// custom valid code

type custom_valid = (
  ,pub v:string

  ,pub set = {|(self,v)->(self)|
     self.v = v
     self.my_valid = true
  }

  ,pub valid = {|(self)->(:boolean)| self.v != 0 and self.my_valid }
  ,pub valid ++= {|(self,v)->(self)| self.my_valid = v }
)

var x:custom_valid  // no need to say x:custom_valid?, but legal

comptime assert not x?

x.v = "bypassed"
comptime assert not x? and x.v == "bypassed"

x = "direct"
comptime assert x? and x.v == "direct" and x == Custom_valid("direct")

x? = false
comptime assert not x? and x.v == "direct" and x != Custom_valid("direct")
```
