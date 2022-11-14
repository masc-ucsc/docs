# Variables and types

A variable is an instance of a given type. The type may be inferred from use.
The basic types are Boolean, lambda, Integer, Range, and String. All those
types can be combined with tuples.


## Variable scope

Scope constrains variables visibility. There are three types of scope
delimitation in Pyrope: code block scope, lambda scope, and tuple scope. Each
has a different set of rules constraining the variable visibility. Overall, the
variable/field is visible from declaration until the end of scope.


Pyrope uses `var` or `let` to declare a variable, but all the declarations must
have a value. `_` is used to specify the default value (`false` for boolean,
`0` for integer, `""` for string, undefined lambda for lambda, and `0..=0` for
range).


In all the cases, variable declaration is either:
* `let variable [:type] = expression`
* `var variable [:type] = expression`

In a tuple scope, `variable [:type] = expression` is equivalent to `var variable
[:type] = expression` because tuples do not have variable updates, and
therefore there is no need to distinguish between `variable[:type] = expr` (mutate
update) and `var variable[:type] = expr` (declaration).


=== "Code Block scope"

    ```
    assert a == 3        // compile error, undefined variable 'a'
    var a = 3
    {
      assert a == 3
      a = 33             // OK. assign 33
      a:int = 33         // OK, assign 33 and check that 'a' has type int
      let b = 4
      let a = 3333       // compile error, variable shadowing
      var a = 33         // compile error, variable shadowing
    }
    assert b == 3        // compile error, undefined variable 'b'
    ```

=== "Lambda scope"

    ```
    assert a == 3        // compile error, undefined variable 'a'
    var a = 3
    var x = 10
    let f1 = fun[a,x=a+1]() {
      assert a == 3
      a = 33             // compile error, upper scope is immutable
      x = 300            // compile error, capture/inputs are immutable
      let b = 4
      let a = 3333       // compile error, variable shadowing
      var a = 33         // compile error, variable shadowing
      assert a == 3333
    }
    f1()
    assert x == 10
    assert b == 3        // compile error, undefined variable 'b'

    let f2 = fun() {     // restrict scope
      assert a == 3      // compile error, undefined variable 'a'
    }
    let f3 = fun[ff=a]() { // restrict scope
      assert ff == 3     // OK
      ff = 3             // compile error, immutable variable
    }
    ```

=== "Tuple scope"

    ```
    var a = 3
    let r1 = (
      ,a = a+1           // same as var a = a+1
      ,c = {assert a == 3; assert self.a==4; 50}
    )
    r1.a = 33            // compile error, 'r1' is immutable variable

    var r2 = (a=100, let c=(a=a+1, e=self.a+30))
    assert r2 == (a=100,c=(a=101, e=131))  // checks values not mutability
    r2.a = 33            // OK
    r2.c.a = 33          // compile error, 'r2.c' is immutable variable
    ```

* Shadowing is not allowed in lambdas or code blocks. Tuples can redefine
  (shadow) the same variable but to use inside the tuple, the `self` keyword
  must be used always to access tuple scoped variables.

* Lambdas and tuples upper scope variables are always immutable.

* Lambdas can restrict upper scope visibility with `[]`.

* A variable is visible from definition until the end of scope in program order.


Since the captures and lambda inputs are always immutable, it is not allowed to
declare them as `var` and redundant to declare them as `let`.

```
let f3 = fun(var x) { x + 1 }    // compile error, inputs are immutable
let f2 = fun[var x](z) { x + z } // compile error, captures are immutable
```

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
var a:int         = _ // any value, no constrain
var b:unsigned    = _ // only positive values
var c:u13         = _ // only from 0 to 1<<13
var d:int(20..=30)= _ // only values from 20 to 30 (both included)
var d:int(-5..<6) = _ // only values from -5 to 6 (6 not included)
var e:int(-1,0)   = _ // 1 bit integer: -1 or 0
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

if c    { call(x) }  // compile error, 'c' is not a boolean expression
if c!=0 { call(x) }  // OK

var d = b or false   // OK
var e = c or false   // compile error, 'c' is not a boolean

let e = 0xfeed
if e@[3] {           // OK, bit extraction for single bit returns a boolean
  call(x)
}

assert 0 == (int(true)  + 1)  // explicity typecast
assert 1 == (int(false) + 1)  // explicity typecast
assert boolean(33) or false   // explicity typecast
```

String input typecase is valid, but anything different than ("0", "1", "-1",
"true", "TRUE", "t", "false", "FALSE", "f") raises an assertion failure.

Logical and arithmetic operations can not be mixed.

```
let x = a and b
let y = x + 1    // compile error: 'x' is a boolean, '1' is integer
```

### Lambda

Lambdas have several options (see [Functions](06-functions.md)), but from a
high level they provide a sequence of statements and they have a tuple for
input and a tuple for output. Lambdas also can capture values from declaration.
Like strings, lambdas are always immutable objects but they can be assigned
to mutable variables.


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
assert b@[0]          == false

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


## Type declarations

Each variable has a type, either implicit or explicit, and as such, it can be
used to declare a new type. 

Pyrope does not have a `type` keyword. Instead it leverages the tuples for type
creation. The difference is that a type should be an immutable variable, and
therefore it is recommended to start with Uppercase.

```
var bund1 = (color:string, value:s33)
x:bund1        = _      // OK, declare x of type bund1 with default values
bund1.color    = "red"  // OK
bund1.is_green = fun(self) { ret self.color == "green" }
x.color        = "blue" // OK

let typ = (color:string, value:s33, is_green:fun(self) = _)
y:typ        = _        // OK
typ.color    = "red"    // compile error
typ.is_green = fun(self) { ret self.color == "green" }
y.color      = "red"    // OK

let bund3 = (color:string, value:s33)
z:bund3        = _                 // OK
bund3.color    = "red"             // compile error
bund3.is_green = fun(self) { ... } // compile error
z.color        = "blue"            // OK

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


## Type checks


When a type is used in the left-hand-side of a declaration statement, the
type is set for the whole existence of the variable. It is possible to also
use type checks outside the variable declaration. Those are to check that
the variable `does` comply with the type specified.


```
var a = true  // infer a is a boolean

foo = a:bool or false // checks that 'a' is a boolean
```

## Attributes

Attributes is the mechanism that the programmer specifies some special
checks/functionality that the compiler should perform. Attributes are
associates to variables either setting an attribute or checking the value. Some
example of check is to mark statements compile time constant, or read the
number of bits in an assertion, or placement hints, or even interact with the
synthesis flow to read timing delays.


Pyrope does not specify the attributes, the compiler flow specifies them.
Reading attributes should not affect a logical equivalence check. Writing
attributes can have a side-effect because it can change bits use for
wrap/saturate or change pins like reset/clock in registers. Additionally,
attributes can affect assertions, so they can stop/abort the compilation. 


The are three operations that can be done with attributes: set, check, read.

* Set: when associated to a variable type in the left-hand-side of an
  assignment or directly accessed. If a variable definition, this binds the
  attribute with all the use cases of the variable. If the variable just
  changes attribute value, a direct assignment is possible E.g: `foo::[max=300]
  = 4` or `baz.::[attr] = 10` 

* Check: when associated to a type property in the right-hand-side of an
  assignment. The attribute is a comma separated list of boolean expression
  that must evaluate true only at this statement. E.g: `var tmp =
  yy::[comptime, attr2>0] + xx`

* Read: a direct read of an attribute value is possible with `variable.field.::[attribute]`


The attribute set, writes a value to the attribute. If no value is given a
boolean `true` is set. The attribute checks are expressions that must evaluate
true. 


Since conditional code can depend on an attribute, which results in executing a
different code sequence that can lead to the change of the attribute. This can
create a iterative process. It is up to the compiler to handle this, but the
most logical is to trigger a compile error if there is no fast convergence.


```
// attribute set
var foo:u32:[comptime=true] = xx   // enforce that foo is comptime true always
var bar::[comptime] = xx           // same as previous statement
yyy = xx                           // yyy does not check comptime
yyy::[comptime=true] = xx          // now, checks that 'yyy` is comptime

// attribute check
if bar == 3 {
  tmp = bar::[comptime == true]    // check that this use of bar is comptime
  tmp = bar::[comptime]            // same as previous statement
  tmp = bar ; assert bar.::[comptime] // same as previous statements
}
                                   // bar/foo may not be comptime

// attribute read
assert tmp.::[bits] < 30 and !tmp.::[comptime]
```

The attribute check is like a type check, both can be converted to assertions,
but the syntax is cleaner.


=== "Attribute Check"
    ```
    let x = y::[cond,bar==3] + 1

    read_state = fun(x) {
      let f:u32:[comptime] = x // f is compile time or a error is generated
      ret f                    // f should be compile time constant
    }

    var foo = read_state(zz) // foo will be compile time constant
    ```

=== "Assertion Equivalent Check"
    ```
    let x = y + 1
    cassert y.::[cond]
    cassert y.::[bar]==3

    read_state = fun(x) {
      let f = x
      cassert f does u32
      cassert f.::[comptime]
      ret f
    }

    var foo = read_state(zz) // foo will be compile time constant
    ```

Pyrope allows to assign the attribute to a variable or a function call. Not to
statements because it is confusing if applied to the condition or all the
sub-statements.

```
if cond::[comptime] {    // cond is checked to be compile time constant
  x::[comptime] = a +1   // x is set to be compile time constant
}else{
  x::[comptime] = b      // x is set to be compile time constant
}


if cond.::[comptime] {  // checks if cond is compute at comptime
  let v = cond
  if cond {
    puts "cond is compile time and true"
  }
}
```


The programmer could create custom attributes but then a LiveHD compiler pass
to deal with the new attribute is needed to handle based on their specific
semantic. To understand the potential Pyrope syntax, this is a hypothetical
`::[poison]` attribute that marks tuple.

```
let bad = (a=3,b::[poison]=4)

let b = bad.b

assert b.::[poison] and b==4
```


Attributes control fields like the default reset and clock signal. This allows
to change the control inside procedures. Notice that this means that attributes
are passed by reference. This is not a value copy, but a pass by reference.
This is needed because when connecting things like a reset, we want to connect
to the reset wire, not the current reset value.

```
let counter = proc(en, width) {
  reg value:uint:[bits=width] = 0
  value = value + 1
  ret value
}

let counter2::[clock=clk1]=counter
let counter3::[reset=rst2]=counter

var ctr2 =# counter2(my_enable)
var ctr3 =# counter3(my_enable)
```

In the long term, the goal is to have any synthesis directive that can affect
the correctness of the result to be part of the design specification so that it
can be checked during simulation/verification.


There are 3 main classes of a attributes that all the Pyrope compilers should
always implement: Bitwidth, comptime, debug.

### Variable Attribute list

In the future, the compiler may implement some of the following attributes, as
such, these attribute names are reserved and not allowed for custom attribute
passes:

* `clock`: indicate a signal/input is a clock wire
* `critical`: synthesis time criticality
* `debug` (sticky): variable use for debug only, not synthesis allowed
* `delay`: synthesis time delay
* `deprecated`: to generate special warnigns about usage
* `donttouch`: do not touch/optimize away
* `file`: to print the file where the variable was declared
* `inline`, `noinline`: to indicate if a module is inlined
* `inp_delay`, `out_delay`: synthesis optimizations hints
* `keep`: same as donttouch but shorter
* `key`: variable/entry key name
* `left_of`, `right_of`, `top_of`, `bottom_of`, `align_with`: placement hints
* `let` and `var`: is the variable declared as `let` and/or `var`
* `loc`: line of code information
* `max_delay`, `min_delay`: synthesis optimizations checked at simulation
* `max_load`, `max_fanout`, `max_cap`: synthesis optimization hints
* `multicycle`: number of cycles for optimizations checked at simulation
* `pipeline`: pipeline related information
* `private`: variable/field not visible to import/regref
* `rand` and `crand`: simulation and compile time random number generation
* `reset`: indicate a signal/input is a reset wire
* `size`: Number of entries in tuple or array
* `typename`: type name at variable declaration
* `valid`, `retry`: for elastic pipelines
* `warn`: is a boolean what when set to false disables compile warnings for associated variable

Registers and other objects may have additional attributes.


### Bitwidth attribute

To set constrains on integer, boolean, range, and struct basic types, the compiler has a set
of bitwidth related attributes:


* `max`: the maximum value allowed
* `min`: the minimum value allowed
* `ubits`: Maximum number of bits to represent the unsigned value. The number must be positive or zero
* `sbits`: Maximum number of bits, and the number can be negative
* `wrap`: allows to drop bits that do not fit on the left-hand side. It performs sign
  extension if needed.
* `saturate` keeps the maximum or minimum (negative integer) that fits on the
  left-hand side.


The integer type constructor allows to use a range to set max/min, but it is
syntax sugar for direct attribute set.

```
opt1:uint(300) = 0
opt2:int:[min=0,max=300] = 0  // same
opt3::[min=0,max=300] = 0     // same
opt4:int(0..=300) = 0         // same

assert opt1.::[ubits] == 0    // opt1 initialized to 0, so 0 bits
opt1 = 200
assert opt1.::[ubits] == 8    // last assignment needs 9 sbits or 8 ubits
tmp  = opt1::[ubits==8] + 1   // expression AND assert opt1.::[ubits]==8 check
```

The wrap/saturate are attributes that only make sense for attribute set. There
is not much to check/read besides checking that it was set before.

```
a:u32 = 100
b:u10 = 0
c:u5  = 0
d:u5  = 0
w:u5:[wrap] = 0     // attribute set for all the 'w' uses

b = a               // OK, o precision lost
c::[wrap] = a       // OK, same as c = a@[0..<5] (Since 100 is 0b1100100, c==4)
c = a               // compile error, 100 overflows the maximum value of 'c'
w = a               // OK, 'w' has a wrap set at declaration

c::[saturate] = a   // OK, c == 31
c = 31
d = c + 1           // compile error, '32' overflows the maximum value of 'd'

d::[wrap] = c + 1   // OK d == 0
d::[saturate] = c+1 // OK, d==31
d::[saturate] = c+1 // OK, d==31

x::[saturate] boolean = c // compile error, saturate only allowed in integers
```

### comptime attribute

Pyrope borrows the `comptime` functionality from Zig. Any variable can
set/check/read the compile time status. This means that the value must be
constant at compile time or a compile error is generated.

```
let a::[comptime] = 1     // obviously comptime
b::[comptime] = a + 2     // OK too
let c::[comptime] = rand  // compile error, 'c' is not compile time constant
```

To avoid too frequent comptime directives, Pyrope treats all the variables that
start with uppercase as compile time constants.

```
var Xconst1 = 1      // obvious comptime
var Xvar2   = rand   // compile error, 'Xvar2' is not compile time constant
```

### debug attribute

In software and more commonly in hardware, it is common to have extra
statements and state to debug the code. These debug functionality can be more
than plain assertions, they can also include code.


The `debug` attribute marks a mutable or immutable variable. At synthesis, all
the statements that use a `debug` can be removed. `debug` variables can read
from non debug variables, but non-debug variables can not read from `debug`.
This guarantees that `debug` variables, or statements, do not have any
side-effects beyond debug statements.

```
var a = (b::[debug]=2, c = 3) // a.b is a debug variable
let c::[debug] = 3
```

Assignments to debug variables also bypass protection access. This means that
private variables in tuples can be accessed (read-only). Since `assert` marks
all the results as debug, it allows to read any public/private variable/field.


```
x:(_priv=3, zz=4) = _

let tmp = x._priv         // compile error
let tmp::[debug] = x.priv // OK

assert x._priv == 3    // OK, assert is a debug statement
```


## Register

Both mutable and immutable variables are created every cycle. To have
persistence across cycles the `reg` type must be used.


```
reg counter:u32   = 10
var not_a_reg:u32 = 20
```

In `reg`, the right-hand side of the initialization (`10` in the
counterexample) is called only during reset. In non-register variables, the
right-hand side is called every cycle. Most of the cases `reg` is mutable but
it can be declared as immutable.

## Public vs private

All variables are public by default. To declare a variable private within
the tuple or file an underscore must be used (`_private` vs `public`) or
explicitly use the `private` attribute explicitly like in languages like Ruby.

The private has different meaning depending on when it is applied:

* When is applied to a tuple entry (`(_field = 3)`), it means that the tuple
  entry can not be accessed outside the tuple. 

* When is applied to a `pipestage` variable (`_foo`), it means that the
  variable is not pipelined to the next type stage. Section
  [pipestage](06c-pipelining.md) has more details.

* When is applied to a pyrope file upper scope variable (`reg _top_reg = 0` or
  `reg top_reg::[private] = 0`), it means that an `import` command or register
  reference can not access it across files. Section
  [typesystem](07-typesystem.md) has more details.


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
* `a >> b` arithmetic right shift
* `a@[] >> b` logical right shift
* `a << b` left shift

In the previous operations, `a` and `b` need to be integers. The exception is
`a << b` where `b` can be a tuple. The `<<` allows having multiple values
provided by a tuple on the right-hand side or amount. This is useful to create
one-hot encodings.

```
cassert 1<<(1,4,3) == 0b01_1010
```


### Binary Boolean operators

* `a and b` logical and
* `a or b` logical or
* `a implies b` logical implication
* `a !and b` logical nand
* `a !or b` logical nor
* `a !implies b` logical not implication

### Tuple/Set operators

* `a in b` is element `a` in tuple `b`
* `a !in b` true when element `a` is not in tuple `b`

Most operations behave as expected when applied to signed unlimited precision
integers. 

The `a in b` checks if values of `a` are in `b`. Notice that both can be
tuples. If `a` is a named tuple, the entries in `b` match by name, and then
contents. If `a` is unnamed, it matches only contents by position.

```
cassert (1,2) in (0,1,3,2,4)
cassert (1,2) in (a=0,b=1,c=3,2,e=4)
cassert (a=2) !in (1,2,3)
cassert (a=2) in (1,a=2,c=3)
cassert (a=1,2) in (3,2,4,a=1)
cassert (a=1,2) !in (1,2,4,a=4)
cassert (a=1) !in (a=(1,2))
```

The `a in b` has to deal with undefined values (`nil`, `0sb?`). The LHS with an undefined
will be true if the RHS has the same named entry either defined or undefined.

```
cassert (x=nil,c=3) in (x=3,c=3)
cassert (x=nil,c=3) in (x=nil,c=3,d=4)
cassert (c=3)      !in (c=nil,d=4)
```

* `a ++ b` concatenate two tuples. If field appears in both, concatenate field. The a field is
defined in one tupe and undefined in the other, the undefined value is not concatenated.

```
cassert ((a=1,c=3) ++ (a=1,b=2,c=nil)) == (a=(1,1), c=3, b=2)
cassert ((1,2) ++ (a=2,nil,5)) == (1,2,a=2,5)
cassert ((x=1) ++ (a=2,nil,5)) == (x=1,a=2,nil,5)

cassert ((x=1,b=2) ++ (x=0sb?,3)) == (x=1,b=2,3)
```

* `(,...b)` in-place insert `b`. Behaves like `a ++ b` but it triggers a
  compile error if both have the same defined named field.

```
cassert (1,b=2,...(3,c=3),6) == (1,b=2,3,c=3,6)
cassert (1,b=2,...(nil,c=3),0sb?,6) == (1,b=2,nil,c=3,0sb?,6)
```


### Type operators

* `a has b` checks if `a` tuple has the `b` field where `b` is a string or
  integer (position).

```
cassert((a=1,b=2) has "a")
```

* `a does b` is the tuple structure of `a` a subset of `b`
* `a equals b` same as `(a does b) and (b does a)`
* `a case b` same as `cassert a does b` and for each `b` field with a defined value,
  the value matches `a` (`nil`, `0sb?` are undefined values)
* `a is b` is a nominal type check. Equivalent to `a::[typename] == b::[typename]`

Each type operator also has the negated `(a !does b) == !(a does b)`, `(a
!equals b) == !(a equals b)`, `a !case b == !(a case b)`

The `does` performs just name matching when the LHS is a named tuple. It
reverts to name and position matching when some of the LHS entries are unnamed.

```
cassert (a=1,b=3) does (b=100,a=333,e=40,5)
cassert (a=1,3) does (a=100,300,b=333,e=40,5)
cassert (a=1,3) !does (b=100,300,a=333,e=40,5)
```

A `a case b` is equivalent to `cassert b does a` and for each defined value in
`b` there has to be the same value in `a`. This can be used in any expression
but it is quite useful for `match ... case` patterns.

```
match (a=1,b=3) {
  case (a=1) { cassert true }
  else { cassert false }
}

match let t=(a=1,b=3); t {
  case (a=1  ,c=4) { cassert false }
  case (b=nil,a=1) { cassert t.b==3 and t.a==1 }
  else { cassert false }
}
```

An `x = a case b` can be translated to:

```
cassert b does a
x = b in a
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
bits accordingly. E.g: `variable@[0..=3]@+[]` does a `zext` and the positive result
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



The bit selection operator only works with ranges, boolean, and integers. It
does not work with tuples or strings. For converting in these object a `union:`
must be used.


Another important characteristic of the bit selection is that the order of the
bits on the selection does not affect the result. Internally, it is a bitmask
that has no order. For the `zext` and `sext`, the same order as the input
variable is respected. This means that `var@[1,2] == var@[2,1]`. As a result,
the bit selection can not be used to transpose bits. A tuple must be used for
such an operation.

```
var v = 0b10
assert v@[0,1] == v@[1,2] == v@[] == v@[0..=1] == v@[..=1] == 0b10

var trans = 0

trans@[0] = v@[1]
trans@[1] = v@[0]
assert trans == 0b01
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
| 3          | other binary | ..,^, &, -,+, ++, <<, >>, in, does, has, case, equals |
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

Comparators can be chained, but only when they follow the same type.

```
assert a <= b <= c  // same as a<=b and b<=c
assert a == b <= c  // compile error, chained only allowed with same comparator
```

## Optional

The `?` is used by several languages to handle optional or null pointer
references. In non-hardware languages, `?` is used to check if there is valid
data or a null pointer. This is the same as checking the `::[valid]` attribute
with a more friendly syntax.


Pyrope does not have null pointers or memory associated management. Pyrope uses
`?` to handle `::[valid]` data. Instead, the data is left to behave without the
optional, but there is a new "valid" field associated with each tuple entry.
Notice that it is not for each tuple level but each tuple entry.


There are 4 explicitly interact with valids:

* `tup.f1?` reads the valid for field `f1` from tuple `tup`

* `tup?.f1.f2` returns `0bs0` if tuple fields `f1` or `f2` are invalid

* `tup.f1? = cond` explicitly sets the field `f1` valid to `cond`

* `a = b op c` variable `a` will be valid if `b` AND `c` are valid


The optional or valid attached to each variable and tuple field is implicitly
computed as follows:

* Each cycle the `valid` is set for non-register variables initialization[^clear].

* Registers set the valid after reset, but if the reset clears the valid, there
  is not guaranteed on `::[valid]` during reset.

* Left-hand side variables `valids` are set to the and-gate of all the variable
  valids used in the expression

* Reading from a memory/array is always a valid contents. Even during reset.

* Writing to a register updates the register valid based on the din valid, or
  when the `::[valid]` is explicitly cleared.

* conditionals (`if`) update valids independently for each path

* A tuple field has the valid set to false if any of the parent tuple fields is
  invalid

* The valid computation can be overwritten with the `::[valid]` attribute. This
  is possible even during reset.


[^clear]: Non-register variables are initialized, but when initialized to `_`
  the valid is cleared.


!!! Observation
    The variable valid calculation is similar to the Elastic 'output_written'
    from [Liam](https://masc.soe.ucsc.edu/docs/memocode17.pdf) but it is not an
    elastic update because it does not consider the abort or retry.


The previous rules will clear a valid only if an expression has no valid, but
the only way to have a non-valid is if the inputs to the lambda are invalid or
if the valid is explicitly clear. The rules are designed to have no overhead
when valid are not used. The compiler should detect that the valid is true all
the time, and the associated logic is removed.


```
var v1:u32 = _                 // v1 is zero every cycle AND not $valid
assert v1.::[valid] == false
var v2:u32 = 0                 // v2 is zero every cycle AND     $valid
assert v2.::[valid] == true

cassert v1?
cassert not v2?

assert v1 == 0 and v2 == 3     // data still same as usual

v1 = 0sb?                      // OK, poison data
v2 = 0sb?                      // OK, poison data, and update valid
assert v2?                     // valid even though data is not

assert v1 != 0                 // usual verilog x logic
assert v2 != 0                 // usual verilog x logic

let res1 = v1 + 0              // valid with just unknown 0sb? data
let res2 = v2 + 0              // valid with just unknown 0sb? data

assert res1?
assert res2?

reg counter:u32 = 0

always_assert counter.reset implies !counter?
```

`valid` can be overwritten with a method to change the default valid behavior:

```
let custom = (
  ,data:i16 = _
  ,valid = fun(self) {
    ret self.data != 33
  }
)

var x:custom = _

cassert x?       // compile time assert
x.data = 33
cassert not x?
```


The contents of the tuple field do not affect the field valid bit. It is
data-independent. Tuples also can have an optional type, which behaves like
adding optional to each of the tuple fields.

```
let complex = (
  ,reg v1:string = "foo"
  ,v2:string = _

  ,setter = proc(ref self,v) {
     self.v1 = v
     self.v2 = v
  }
)

var x1:complex = _
var x2:complex:[valid = false] = 0  // toggle invalid forever, and set zero
var x3:complex = 0
x3.::[valid] = false                // toggle invalid

assert x1.v1 == "" and x1.v2 == ""
assert not x2? and not x2.v1? and not v2.v2?
assert x2.v1 == "" and x2.v2 == ""

assert x2?.v1 == "" and x2?.v1 != ""  // any comparison is false

// When x2? is false, any x2?.foo returns 0sb? with the associated x rules

x2.v2 = "hello" // direct access still OK

assert not x2? and x2.v1 == "" and x2.v2 == "hello"

x2 = "world"

assert x2? and x2?.v1 == "world" and x2.v1 == "world"
```


## Variable Initialization


Variable initialization indicates the default value set every cycle and the
optional (`::[valid]` attribute).


The `let` and `var` statements require an initialization value for each cycle.
Pyrope only has undefined values unless explicitly indicated. A variable has an
undefined value if and only if the value is set to `nil` or all the bits are
unknown (`0sb?`). Undefined variables always have invalid optional
(`::[valid==false]`), and defined can have valid or invalid optional.


On any assignment (`v = _`) where the rhs is a single underscore `_`, the
variable optional is set to false, and it is assigned the default value:

* `0` for integer
* `false` for boolean
* `""` for string
* `nil` otherwise

```
var a:int = _
cassert a==0 and a.::[valid] == false and not a?

var b:int = 0
cassert b==0 and b::[valid] and b?
b = nil
cassert b==nil and b.::[valid] == false and not b?

var c:fun(a1) = _
cassert c == nil and c::[valid==false]
c = fun(a1) { cassert true }
cassert c!= nil and c::[valid]

var d = ()                       // empty tuple
cassert d != nil and d::[valid]

var e:int = nil
cassert e==nil and e::[valid==false] and not e?
e = 0
cassert e==0 and e::[valid] and e?
```

The same rules apply when a tuple or a type is declared.

```
let a = "foo"

var at1 = (
  ,a:string 
)
cassert at1[0] == "foo"
cassert at1 !has "a"    // at1.a undefined

var at2 = (
  ,a:string = _
)
cassert at2.a == ""  and at2.a.::[valid]==false
at2.a = "torrellas"
cassert at2.a == "torrellas" and at2[0] == "torrellas"

var at3:at2 = _
cassert at3.a == ""  and at3.a.::[valid]==false

var at4:at2 = (a="josep")
cassert at4.a == "josep"  and at4.a.::[valid] and at4.::[valid]

```

