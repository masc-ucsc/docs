# Variables and types

A variable is an instance of a given type. The type may be inferred from use.
The basic types are Boolean, Function, Number, Range, and String. All those
types can be combined with Bundles. All the complex types are build around
these types.


## Mutable/Immutable

Variables are immutable by default and bundle fields are mutable by default.
There are 3 keywords to handle mutability:

* `var` is used to declare mutable variables.
* `let` is used to declare immutable variables.
* `mut` is used to modify mutable variables. The `mut` keyword is not needed when there is a op= assignment.
* `set` is used to potentially add new fields to a mutable bundle.

```
a  = 3
a  = 4         // compile error, 'a' is immutable
a += 1         // compile error, 'a' is immutable

var b  = 3
mut b  = 5     // OK
    b  = 5     // compile error, 'b' is already declared as mutable
    b += 1     // OK, OP= assumes mutable
mut b += 1     // OK, mut is not needed in this case

var c=(x=1,let b=2, var d=3) // mut d is redundant
mut c.x   = 3  // OK
mut x.foo = 2  // compile error, bundle 'x' does not have field 'foo'
set x.foo = 3  // OK
mut c.b   = 10 // compile error, 'c.b' is immutable

let d=(x=1, let y=2)
mut d.x   = 2  // OK
set d.foo = 3  // compile error, bundle 'd' is immutable
mut d.y   = 4  // compile error, 'd.y' is immutable
```

Bundles can be mutable. This means that fields and subfields can be added with
successive statements.

```
var a.foo = (a=1,b=2)
mut a.bar = 3
set a.foo ++= (c=4)
assert a.foo.c == 4
```

## Basic types

### Boolean

A boolean is a number that can be `0` or `-1` but when mixed with other types a typecast
must be used.

```
b = true
c = 3

if c    {}     // compile error, 'c' is not a boolean expression
if c!=0 {}     // OK

d = b or false // OK
e = c or false // compile error, 'c' is not a boolean

assert (int(true)  + 1) == 0  // explicity typecast
assert (int(false) + 1) == 1  // explicity typecast
assert bool(33) or false      // explicity typecast
```

### Function

Functions have several options (see [Functions](06-functions.md)), but from a
high level they provide a sequence of statements and they have a bundle for
input and a bundle for output. Functions also can capture values from function
declaration.

### Number

Numbers have unlimited precision and they are always signed. Type constrains 
can enforce a subset of numbers

```
var a:int      // any value, no constrain
var b:unsigned // only positive values
var c:u13      // only from 0 to 1<<13
```

### Range

Ranges are very useful in hardware description languages to select bits, but
they are integrated all over the language.

The are 3 ways to specify a closed range:

* `first..=last`: Range from first to last element, both included
* `first..<last`: Range from first to last, but last element is not included
* `first..+size`: Range from first to `first+size`. Since there are `size`
  elements, it is equivalent to write `first..<(first+last)`.

When used inside selectors (`[range]`) the ranges can be open (no first/last specified)
or use negative numbers. The negative number is to specify distance from last.

* `[first..<-val]` is the same as `[first..<(last-val+1)]`. The advantage is that the `last` or 
size in the bundle does not need to be known.
* `[first..]` is the same as `[first..=-1]`.

```
a = (1,2,3)
assert a[0..] == (1,2,3)
assert a[1..] == (2,3)
assert a[..=1] == (1,2)
assert a[..<2] == (1,2)
assert a[1..<10] == (2,3)
b = 0b0110_1001
assert b@[1..]        == 0b0110_100
assert b@[1..=-1]     == 0b0110_100
assert b@[1..=-2]     == 0b0110_100  // unsigned result from bit selector
assert b@sext[1..=-2] == 0sb110_100 
assert b@[1..=-3]     == 0sb10_100
assert b@[1..<-3]     == 0b0_100
```

### String

Strings are also Numbers encoded using the ASCII sequence, but to perform arithmetic
operations a typecast must be used. The string encoding assigns the lower bits
to the first characters in the string, each character has 8 bits associated.

```
a = 'cad' // a is 0x61, c is 0x63, and d is 0x64
b = 0x64_61_63
assert a == string(b)  // typecast number to string
assert int(a) == b     // typecast string to number
```


## Variable modifiers

The first character[s] in the variable modify/indicate the behavior:

* `$`: for inputs, all the inputs are immutable. E.g: `$inp`
* `%`: for outputs, all the outputs are mutable. E.g: `%out`
* `#`: for registers, all the registers are mutable. E.g: `#reg`
* `_`: for private variables. It is a recommendation, not enforced by the compiler.

```
%out = #counter
if $enable {
  #counter = (#counter + 1) & 0xFF
}
```

## comptime

Pyrope borrows the `comptime` keyword and functionality from Zig. Variables, or expressions,
can be declared compile time constants or `comptime`. This means that the value must be 
constant at compile time or an error is generated.

```
let comptime a = 1     // obviously comptime
var comptime b = a + 2 // OK too
let comptime c = $rand // compile error, 'c' can not be computed at compile time
```

The `comptime` directive considers values propagated across modules.

## debug

In software and more commonly in hardware, it is common to have extra statements
to debug the code. These statements can be more than plain assertions, they can also
include code.

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

Global type inference and unlimited precision allows to avoid most of the
types. Pyrope allows to declare types. The types have two main uses, they
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
* `{||}`: is a function without any statement which can be used as function type.
* `unsigned`: an unlimited precision natural number.
* `u<num>`: a natural number with a maximum value of $2^{\texttt{num}}$. E.g: `u10` can go from zero to 1024.
* `int`: an unlimited precision integer number.
* `i<num>`: an integer 2s complement number with a maximum value of $2^{\texttt{num}-1}-1$ and a minimum of $-2^{\texttt{num}}$.


Each bundle is has a type, either implicit or explicit, and as such it can be
used to declared a new type. The `type` keywords guarantees that a variable is
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

There are the typical basic operators found in most common languages with the
exception exponent operations. The reason is that those are very hardware
intensive and a library code should be used instead.

All the operators work over signed integers.

### Unary operators

* `!` or `not` logical negation
* `~` bitwise negation
* `-` arithmetic negation

### Binary operators

* `+` addition
* `-` substraction
* `*` multiplication
* `/` division
* `and` logical and
* `or` logical or
* `implies` logical implication
* `&` bitwise and
* `|` bitwise or
* `^` bitwise or
* `>>` shift right
* `<<` shift left

Most operations behave as expected when applied to signed unlimited precision integers. Logical
and arithmetic operations can not be mixed.

```
x = a and b
y = x + 1    // compile error: 'x' is a boolean, '1' is not
```

### Reduce and bit selection operators

The reduce operators and bit selection share a common syntax `@op[selection]`
where there can be different operators (op) and/or bit selection.

The valid operators:
* `|`: or-reduce.
* `&`: and-reduce.
* `^`: xor-reduce or parity check.
* `+`: pop-count.
* `sext`: Sign extend select bits.
* `zext`: Zero sign extend select bits.

If no operator is provided, a `zext` is used. The bit selection without
operator can also be used on the left hand side to update a set of bits.
The bit selector.

The or/and/xor reduce have a single bit signed output (not boolean). This means
that the result can be 0 (`0sb0`) or -1 (`0sb1`).

```
x = 0b10110
y = 0s10110
assert x@[0,2] == 0b10
assert y@[100,200]     == 0b11 and x@[100,200]     == 0
assert y@sext[100,200] ==   -1 and x@sext[100,200] == 0
assert x@|[] == -1 
assert x@&[0,1] == 0
assert x@+[] == 3 and y@+[] == 3

var z     = 0b0110
mut z@[0] = 1    // same as mut z@[0] = -1 
assert z == 0b0111
mut z@[0] = 0b11 // compile error, '0b11` overflows the maximum allowed value of `z@[0]`
```

### Operator with bundles

There are some operators that can also have bundles as input and/or outputs.

* `++` concatenate two bundles
* `<<` shift left. The bundle can be in the right hand side
* `has` checks if a bundle has a field.

The `<<` allows to have multiple values provided by a bundle on the right hand side or amount. This is useful
to create one-hot encodings.

```
y = (a=1,b=2) ++ (c=3)
assert y == (a=1,b=2,c=3)
assert y has 'a' and y has 'c'

x = 1<<(1,4,3)
assert x == 0b01_1010
```

## Precedence

Pyrope has a very shallow precedence, unlike most other languages the
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
| 3          | other binary | ..,^, &, -,+, ++, --, <<, >> |
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

## Everything is a bundle

In Pyrope everything is a bundle, and it has some implications that this section tries to clarify.


A bundle starts with `(` and finishes with `)`. In most languages, the parenthesis have two
meanings, operation precedence and/or tuple/bundle/record. In Pyrope, since a single element
is a bundle too, the parenthesis always means a bundle.


A code like `(1+(2),4)` can be read as "Create a bundle of two entries. The
first entry is the result of the addition of `1` (which is a bundle of 1) and a
bundle that has `2` as unique entry. The second entry in the bundle is `4`".

The entries in a bundle are separated by comma (`,`). Extra commas do not add meaning.

```
a = (1,2)   // bundle of 2 entries, 1 and 2
b = (1)     // bundle of 1 entry, 1
c = 1       // bundle of 1 entry, 1
d = (,,1,,) // bundle of 1 entry, 1
assert a.0 == b.0 == c.0 == d.0
assert a!=b
assert b == c == d
```


Bundles are used in many places:

* The inputs for a function are in `$` bundle. E.g: `total = $.a + $[3]`
* The outputs for a function are in the `%` bundle. E.g: `%.out1 = 3` or `%sum = 4`
* The arguments for a call function are a bundle. E.g: `fcall(1,2)`
* The return of a function call is always a bundle. E.g: `foo = fcall()`
* The index for a selector `[...]` is a bundle. As syntax sugar, the bundle parenthesis can be omitted. E.g: `foo@[0,2,3]`
* The type declaration are a bundle. E.g: `type x = (f=1,var b:string)`

The bundle entries can be mutable/immutable and named/unnamed. By default
variables are immutable, and by default bundle entries follow the top variable
definition. The entry can be changed with the `var` and `let` keyword. The
`type` declaration is an immutable variable type.

To declare a named entry the default is `lhs = var` which follows the default
bundle entry type. Again, the `var` and `let` keyword can be added to change
it.

```
b = 3
a = (b:u8, 4)
assert a == (3:u8, 4)

var f = (b=3, let e=5)
f.b = 4             // OK
f.e = 10            // compile error, `f.e` is immutable

let x = (1,2)
x[0] = 3            // compile error, 'x' is immutable
var y = (1, let 3)
y[0] = 100          // OK
y[1] = 101          // compile error, `y[1]` is immutable
```

## Optional bundle parenthesis

Parenthesis mark the beginning and the end of a bundle. Those parenthesis can
be avoided for unnamed bundles in some cases:

* When doing a simple function call after an assignment (`=`, `:=`, `=#`) or at the beginning of a line.
* When used inside a selector `[...]`.
* When used after an `in` operator followed by a `{` like in a `for` and `match` statements.
* For the inputs in a match statement
* When the function types only has inputs.

```
fcall 1,2         // same as: fcall(1,2)
x = fcall 1,2     // same as: x = fcall(1,2)
b = xx[1,2]       // same as: xx[(1,2)]

for a in 1,2,3 {  // same as: for a in (1,2,3) {
}
y = match z {    
  in 1,2 { 4 }    // same as: in (1,2) { 4 }
  else { 5 }
}
y2 = match 1,z {  // same as: y2 = match (1,z) {
}

fun = {|a,b|      // same as: fun = {|(a,b)|
} 
```

A named bundle parenthesis can be omitted on the left hand side of an assignment. This is
to mutate or declare multiple variables at once. 

```
var a=0
var b=1

a,b = (2,3)
assert a==2 and b==3
```
