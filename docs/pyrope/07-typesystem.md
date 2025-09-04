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


=== "Snippet with types"

    ```
    var b = "hello"

    var a:u32 = 0

    a += 1

    a = b                       // incorrect


    var dest:u32 = 0

    dest = foo:u16 + v:u8
    ```

=== "Snippet with comptime assert"

    ```
    var b = "hello"

    var a:u32 = 0

    a += 1
    cassert a does u32
    a = b                       // incorrect
    cassert b does u32  // fails

    var dest:u32 = 0
    cassert (dest does u32) and (foo does u16) and (v does u8)
    dest = foo:u16 + v:u8
    ```


## Building types

Each variable can be a basic type. In addition, each variable can have a set of
constraints from the type system. Pyrope type system constructs to handle types:

* `var` and `let` allows declaring types.

* `a does b`: Checks 'a' is a superset or equal to 'b'. In the future, the
  Unicode character "\u02287" could be used as an alternative to `does` (`a`
&#8839 `b`).

* `a:b` is equivalent to `a does b` for type check, but it is also used by type
  synthesis when used in the left-hand-side of assignments.

* `a equals b`: Checks that `a does b` and `b does a`. Effectively checking
  that they have the same type. Notice that this is not like checking for
  logical equivalence, just type equivalence.

```
let t1 = (a:int=1, b:string)
let t2 = (a:int=100, b:string)
var v1 = (a=33, b="hello")

let f1 = fun() {
  (a=33, b="hello")
}

assert t1 equals t2
assert t1 equals v1
assert f1() equals t1
assert _:f1 !equals t1
assert _:t1 equals t2
```


`equals` and `does` check for types. Sometimes, the type can have a function
call and you do not want to call it. The solution in this case is to use the
`:type` to avoid the function call.


Since the `puts` command understands types, it can be used on any variable, and
it is able to print/dump the results.

```
let At:int(33..) = _      // number bigger than 32
let Bt = (
  c:string = _,
  d = 100,
  setter = fun(ref self, ...args) { self.c = args }
)

var a:At = 40
var a2 = At(40)
cassert a == a2

var b:Bt = "hello"
var b2 = Bt("hello")
cassert b == b2

puts "a:{} or {}", a, at // a:40 or 33
puts "b:{}", b           // b:(c="hello",d=100)
```

### Type equivalence


The `does` operator is the base to compare types. It follows structural typing rules.
These are the detailed rules for the `a does b` operator depending on the `a` and `b` fields:


* false when `a` and `b` are different basic types (`boolean`, `fun`,
  `integer`, `mod`, `range`, `string`, `enums`).

* true when `a` and `b` have the same basic type of either `boolean` or `string`.

* true when `a` and `b` are `enum` and `a` has all the possible enumerates
  fields in `b` with the same value.

* `a.max>=b.max and a.min<=b.min` when `a` and `b` are integers. The `max/min`
  are previously constrained values in left-hand-side statements, or inferred
  from right-hand-side if no lhs type is specified.

* `(a#[..] & b#[..]) == b#[..]` when `a` and `b` are `range`. This means that the `a`
  range has at least all the values in `b` range.

* There are two cases for tuples. If all the tuple entries are named, `a does
  b` is true if for all the root fields in `b` the `a.field does b.field`. When
  either `a` or `b` have unnamed fields, for each field in `b` the name but
  also position should match. The conclusion is that if any field has no name,
  all the fields should match by position and/or name if available.

* `a does b` is false if the explicit array size of `a` is smaller than the
  explicit array size of `b`. If the size check is true, the array entry type
  is checked. `_:[]x does _:[]y` is false when `_:x does _:y` is false.

* The lambdas have a more complicated set of rules explained later.

```
assert (a:int:(max=33, min=0) does (a:int(20, 5)))
assert (a:int(0..=33) !does (a:int(50, 5)))

assert (a:string, b:int) does (a:"hello", b:33)
assert ((b:int, a:string) !does (a:"hello", b:33)) // order matters in tuples

assert _:fun(x, xxx2) -> (y, z) does _:fun(x) -> (y, z)
assert (_:fun(x) -> (y, z) !does _:fun(x, xxx2) -> (y, z))
```

For named tuples, this code shows some of the corner cases:

```
let t1 = (a:string, b:int)
let t2 = (b:int, a:string)

var a:t1 = ("hello", 3)     // OK
var a1:t1 = (3, "hello")     // compile error, positions do not match
var b:t1 = (a="hello", 3)   // OK
var b1:t1 = (3, a="hello")   // compile error, positions do not match
var c:t1 = (a="hello", b=3) // OK
var c1:t1 = (b=3, a="hello") // OK

var d:t2 = c                 // OK, both fully named
assert d.0 == c.1 and c.0 == d.1
assert d.a == c.a and d.b == c.b
```

Ignoring the value is what makes `equals` different from `==`. As a result
different functionality functions could be `equals`.

```
let a = fun() { 1 }
let b = fun() { 2 }
assert a equals _:fun()    // 1 !equals :fun()

assert a() != b()              // 1 != 2
assert a() equals b()          // 1 equals 2

assert _:a equals _:fun()
```

## Type check with values

Many programming languages have a `match` with structural checking. Pyrope
`does` allows to do so, but it is also quite common to filter/match for a given
value in the tuple. This is not possible with `does` because it ignores all the
field values. Pyrope has a `case` that extends the `does` comparison and also
checks that for the matching fields, the value is the same.


The previous explanation of `a does b` and `a case b` ignored types. When types
are present, both need to match type.

```
cassert (a:u32=0, b:bool) does (a:u32, c:string="hello", b=false)
cassert (a:u32=0, c:string="hello", b=false) case (a = 0, b:bool) // b is nil

cassert (a:u32=0, c:string="hello", b=false) !case (a:u32 = 1, b:bool=nil)
cassert (a:u32=0, c:string="hello", b=false) !case (a:bool=nil, b:bool=nil)
cassert (a:u32=0, c:string="hello", b=false) !case (a = 0, b = true)
```

## Nominal type check


Pyrope has structural type checking, but there is a keyword `is` that allows to
check that the type name matches `a is b` returns true if the type of `a` has
the same name as the type of `b`. The `a is b` is a boolean expression like `a
does b`, not a `a:b` type check. This means that it can be used in `where`
statements or any conditional code.

`a is b` is equivalent to check the `a` variable declaration type name against
the `b` variable declaration type name. If their declaration had no type, the
inferred type name is used.

```
let a = 3
let b = 200
cassert a is b

let c:u32 = 10
cassert a !is c
cassert a::[typename] == "int" and c::[typename] == "u32"

let d:u32 = nil
cassert c is d

let e = (a:u32=1)
let f:(a:u32) = 33
cassert e is f
```

Since it checks equivalence, when `a is b == b is a`.

```
let X1 = (b:u32)
let X2 = (b:u32)

let t1:X1 = (b=3)
let t2:X2 = (b=3)
assert (b=3) !is X2  // same as (b=3) !is X2
assert t1 equals t2
assert t1 !is t2

let t4:X1 = (b=5)

assert t4 equals t1
assert t4 is t1
assert t4 !is t2

let f2 = fun(x) where x is X1 {
  x.b + 1
}
```

## Enums with types

Enumerates (enums) create a number for each entry in a set of identifiers.
Pyrope also allows associating a tuple or type for each entry. Another
difference from a tuple is that the enumerate values must be known at compile
time.


```
let Rgb = (
  c:u24,
  setter = mod(ref self, c) { self.c = c }
)

let Color = enum(
  Yellow:Rgb = 0xffff00,
  Red:Rgb = 0xff0000,
  Green = Rgb(0x00ff00), // alternative
  Blue = Rgb(0x0000ff)
)

var y:Color = Color.Red
if y == Color.Red {
  puts "c1:{} c2:{}\n", y, y.c  // prints: c1:Color.Red c2:0xff0000
}
```


It is also possible to support an algebraic data type with enums. This requires
each enumerate entry to have an associated type. In can also be seen as a union
type, where the enumerate has to be either of the enum entries where each is
associated to a type.

```
let ADT = enum(
  Person:(eats:string) = _,
  Robot:(charges_with:string) = _
)

let nourish = fun(x:ADT) {
  match x {
    == ADT.Person { puts "eating:{}", x.eats }
    == ADT.Robot { puts "charging:{}", x.charges_with }
  }
}

test "my main" {
  (_:Person="pizza", _:Robot="electricity").each(nourish)
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


In fact, internally Pyrope only tracks the `max` and `min` value. When the
`sbits/ubits` is used, it is converted to a `max/min` range. Pyrope code can
set or access the bitwidth attributes for each integer variable.

* `max`: the maximum number
* `min`: the minimum number
* `sbits`: the number of bits to represent the value
* `ubits`: the number of bits. The variable must be always positive or a compile error.


Internally, Pyrope has 2 sets of `max/min`. The constrained and the current.
The constrained is set during type declaration. The current is computed based
on the possible max/min value given the current path/values. The current should
never exceed the constrained or a compile error is generated. Similarly, the
current should be bound to a given size or a compile error is generated.


The constrained does not need to be specifed. In this case, the hardware will
use whatever current value is found. This allows to write code that adjust to
the needed number of integer bits.

When the attributes are read, it reads the current. it does not read the constrained.

```pyrope
var val:u8 = 0   // designer constraints a to be between 0 and 255
assert val.[sbits] == 0

val = 3          // val has 3 bits (0sb011 all the numbers are signed)

val = 300        // compile error, '300' overflows the maximum allowed value of 'val'

val = 1          // max=1,min=1 sbits=2, ubits=1
assert val.[ubits] == 1 and val.[min] == 1 and val.[max] == 1 and val.[sbits] == 2

val::[wrap] = 0x1F0 // Drop bits from 0x1F0 to fit in constrained type
assert val == 240 == 0xF0

val = u8(0x1F0)    // same
assert val == 0xF0
```

Pyrope leverages LiveHD bitwidth pass to compute the maximum and minimum value
of each variable. For each operation, the maximum and minimum are computed. For
control-flow divergences, the worst possible path is considered.

```
var a = 3                  // a: current(max=3,min=3) constrain()
var c:int(0..=10) = _      // c: current(max=0,min=0) constrain(max=10,min=0)
if b {
  c = a + 1                // c: current(max=4,min=4) constrain(max=10,min=0)
} else {
  c = a                    // c: current(max=3,min=3) constrain(max=10,min=0)
}
                           // c: current(max=4,min=3) constrain(max=10,min=0)

var e::[sbits = 4] = _     // e: current(max=0,min=0) constrain(max=7,min=-8)
e = 2                      // e: current(max=2,min=2) constrain(max=7,min=-8)
var d = c                  // d: current(max=4,min=3) constrain()
if d == 4 {
  d = e + 1                // d: current(max=3,min=3) constrain()
}
var g:u3 = d               // g: current(max=4,min=3) constrain(max=7,min=0)
var h = c#[0, 1]           // h: current(max=3,min=0) constrain()
```


Bitwidth uses narrowing to converge (see
[internals](10-internals.md/#type-synthesis)). The GCD example does not specify
the input/output size, but narrowing allows it to work without typecasts.  To
understand, the comments show the max/min bitwidth computations.

```
if cmd? {
  (x, y) = cmd  // x.max=cmd.a.max; x.min = 0 (uint) ; ....
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
In this case, the programmer must insert a typecast or operation to constrain
the bitwidth by typecasting. For example, this could work:

```
reg x = 0
reg y = 0
if cmd? {
  (x, y) = cmd
} elif x > y {
  x = x - y
} else {
  y = y - x
}
x:cmd.a:[wrap] = x  // use cmd.a type for x, and drop bits as needed
y = cmd.b(y)        // typecast y to cmd.b type (this can add a mux)
```


Pyrope uses signed integers for all the operations and transformations, but
when the code is optimized it does not need to waste bits when the most
significant bit is known to be always zero (positive numbers like u4). The
verilog code generation or the synthesis netlist uses the bitwidth pass to
remove the extra unnecessary bit when it is guaranteed to be zero. This
effectively "packs" the encoding.


## Variants


A Pyrope variant is the equivalent of an union type. A variant type spifices a
set of types allowed for a given variable. In Pyrope, a variant looks like a
tuple where each entry has a different type. Unlike tuples all the "space" or
bits used are shared because the tuple can have only one entry with data at a
given time.


Pyrope supports variants but not unions. The difference between typical (like
C++) `union` and `variant` is that union can be used for a typecast to convert
between values, the variant is the same but it does not allow bit convertion.
It tracks the type from the assignment, and an error is generated if the
incorrect type is accesed. Pyrope requires explicit type conversion with
bitwise operations.


Variant shares syntax with enums declaration, but the usage and functionality
is quite different. Enums do not allow to update values and variants are tuples
with multiple labels sharing a single storage location.


The main advantage of variant is to save space. This means that the most
typical use is in combination with registers or memories, when alternative
types can be stored across cycles.


```
let e_type = enum(str:String = "hello", num=22)
let v_type = variant(str:String, num:int) // No default value in variant

var vv:v_type = (num=0x65)
cassert vv.num == 0x65
let xx = vv.str                         // compile or simulation error
```


The variant variable allows to explicitly or implicitly access the subtype.
Variants may not be solved at compile time, and the error will be a simulation
error. A `comptime` directive can force a compile time-only variant.

```
let Vtype = variant(str:String, num:int, b:bool)

let x1a:Vtype = "hello"                 // implicit variant type
let x1b:Vtype = (str="hello")           // explicit variant type

var x2:Vtype:[comptime] = "hello"       // comptime

cassert x1a.str == "hello" and x1a == "hello"
cassert x1b.str == "hello" and x1b == "hello"

let err1 = x1a.num                      // compile or simulation error
let err2 = x1b.b                        // compile or simulation error
let err3 = x2.num                       // compile error
```

As a reference, `enums` allow to compare for field but not update enum entries.

```
var ee = e_type
ee.str = "new_string"       // compile error, enum is immutable

match ee {
 == e_type.str { }
 == e_type.num { }
}
```


## Typecasting


To convert between tuples, an explicit setter is needed unless the tuple fields
names, order, and types match.

```
let at = (c:string, d:u32)
let bt = (c:string, d:u100)

let ct = (
  d:u32 = _,
  c:string = _
)
// different order
let dt = (
  d:u32 = _,
  c:string = _,
  setter = mod (ref self, x:at) { self.d = x.d; self.c = x.c }
)

var b:bt = (c="hello", d=10000)
var a:at = _

a = b          // OK c is string, and 10000 fits in u32

var c:ct = a   // OK even different order because all names match

var d:dt = a   // OK, call initial to type cast
```

* To string: The `format` allows to convert any type/tuple to a string.
* To integer: `variable#[..]` for string, range, and bool, union otherwise.
* `union` allows to convert across types by specifying the size explicitly.

## Introspection

Introspection is possible for tuples.

```
a = (b=1, c:u32=2)
var b = a
b.c = 100

assert a equals b
assert a.size == 2
assert a['b'] == 1
assert a['c'] equals u32

assert a has 'c'
assert !(a has 'foo')

assert a.[id] == 'a'
assert a.0.[id] == ':0:b' and a.b.[id] == ':0:b'
assert a.1.[id] == ':1:c' and a.c.[id] == ':1:c'
```

Function definitions allocate a tuple, which allows to introspect the
function but not to change the functionality. Functions have 3 fields `inputs`,
`outputs`, `where`. The `where` is a function that always returns true if unset
at declaration.

```
let fu = fun(a, b=2) -> (c) where a > 10 { c = a + b }
assert fu.[inp] equals ('a', 'b')
assert fu.[out] equals ('c')
assert fu.[where](a=200) and !fu.[where](a=1)
```

This means that when ignoring named vs unnamed calls, overloading behaves like
this:

```
let x:u32 = fn(a1, a2)

let model_poly_call = fun(fn, ...args) -> (out) {
  for f in fn {
     continue unless f.[inp] does args
     continue unless f.[out] does out
     return f(args) when f.[where](args)
  }
}
let x:u32 = model_poly_call(fn, a1, a2)
```

There are several uses for introspection, but for example, it is possible to build a
function that returns a randomly mutated tuple.

```
let randomize::[debug] = fun(ref self) {
  let rnd = import("prp/rnd")
  for i in ref self {
    if i equals _:int {
      i = rnd.between(i.[max], i.[min])
    } elif i equals _:bool {
      i = rnd.boolean()
    }
  }
  self
}

let x = (a=1, b=true, c="hello")
let y = x.randomize()

assert x.a == 1 and x.b == true and x.c == "hello"
cover y.a != 1
cover y.b != true
assert y.c == "hello"  // string is not supposed to mutate in randomize()
```


## Global scope

There are no global variables or functions in Pyrope. Variable scope is
restricted by code block `{ ... }` and/or the file. Each Pyrope file is a
function, but they are only visible to the same directory/project Pyrope files.


There are only two ways to access variables outside Pyrope file. The `import`
statement allows referencing public lambdas from other files. The register
declarations allow to assign an ID, and other files can access the register by
"reference".


### import


`import` keyword allows to access functions not defined in the current file.
Any call to a function or tuple outside requires a prior `import` statement.


```
// file: src/my_fun.prp
fun fun1(a, b) { a + b }
fun fun2(a) {
  let inside = fun() { 3 }
  a
}
fun another(a) { a }

let mytup = (
  call3 = fun() { puts "call called" }
)
```

```
// file: src/user.prp
a = import("my_fun/*fun*")
a.fun1(a=1, b=2)        // OK
a.another(a=1, 2)       // compile error, 'another' is not an imported function
a.fun2.inside()         // compile error, `inside` is not in top scope variable

let fun1 = import("my_fun/fun1")
lec fun1, a.fun1

x = import("my_fun/mytup")

x.call3()               // prints call called
```

The `import` points to a file [setup code](06b-instantiation.md#setup-code)
list of public variables or types. The setup code corresponds to the "top" scope
in the imported file. The import statement can only be executed during the
setup phase. The import allows for cyclic dependencies between files as long as
there is no true cyclic dependency between variables. This means that "false"
cyclic dependencies are allowed but not true ones.


The import behaves like cut and pasting the imported code. It is not a
reference to the file, but rather a cut and paste of functionality. This means
that when importing a variable, it creates a copy. If two files import the same
variable, they are not referencing the same variable, but each has a separate
copy.


The import is delayed until the imported variable is used in the local file.
There is no order guarantee between imported files, just that the code needed
to compute the used imported variables is executed before.


The import statement is a filename or path without the file extension.
Directories named `code`, `src`, and `lib` are skipped. No need to add them in
the path. `import` stops the search on the first hit. If no match happens, a
compile error is generated.


`import` allows specialized libraries per subproject.  For example, xx/yy/zz can
use a different library version than xx/bb/cc if the library is provided by yy,
or use a default one from the xx directory.

```
let a = import("prj1/file1")
let b = import("file1")       // import xxx_fun from file1 in the local project
let c = import("file2")       // import the functions from local file2
let d = import("prj2/file3")  // import the functions from project prj2 and file3
```

Many languages have a "using" or "import" or "include" command that includes
all the imported functions/variables to the current scope. Pyrope does not
allow that, but it is possible to use a mixin to add the imported functionality
to a tuple.

```
let b = import("prp/Number")
var a = import("fancy/Number_mixin")

let Number = b ++ a // patch the default Number class

var x:Number = 3
```

### Register reference


While import "copies" the contents, `regref` or Register reference allows to
reference (not copy) an existing register in the call hierarchy.


The syntax of `regref` is similar to `import` but the semantics are very different.
While `import` looks through Pyrope files, `regref` looks through the instantiation
hierarchy for matching register names. `regref` only can get a reference to a
register, it can not be used to import functions or variables.


```
mod do_increase() {
  reg counter = 0

  counter:u32:[wrap] = counter + 1
}

mod do_debug() {
  let cntr = regref("do_increase/counter")

  puts "The counter value is {}", cntr
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

```
// file remote.prp

mod xxx(some, code) {
  reg uart_addr:u32 = _
  assert 0x400 > uart_addr >= 0x300
}

// file local.prp
mod setup_xx() {
  var xx = regref("uart_addr") // match xxx.uart_addr if xxx is in hierarchy
  var index = 0
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


### Mocking library

One possible use of the register reference is to create a "mocking" library. A
mocking library instantiates a large design but forces some subblocks to
produce some results for testing. The challenge is that it needs undriven
registers. During testing, the `peek`/`poke` is more flexible and it can
overwrite an existing value. The peek/poke use the same reference as `import`
or register reference.

```
let bpred = ( // complex predictor
  taken = fun() { self.some_table[som_var] >= 0 }
)

test "mocking taken branches" {
  poke "bpred_file/taken", true

  var l = core.fetch.predict(0xFFF)
}
```

## Operator overloading

There is no operator overload in Pyrope. `+` always adds Numbers, `++` always
concatenates a tuple or a String, `and` is always for boolean types,...


## Getter/Setter method

Pyrope tuples can use the same syntax as a lambda call or a direct assignment.
Both the assignment and the lambda call follow the same rules for ambiguity as
the default lambda calls. This means that fields must be named unless single
character names, or variable name matches argument name, or there is no type
ambiguity.

```
let Typ1 = (
  a:string = "none",
  b:u32 = 0
)

let w = Typ1(a="foo", b=33)       // OK
let x:Typ1 = (a="foo", b=33)      // OK, same as before

let v:Typ1 = Typ1(a="foo", b=33)  // OK, but redundant Typ1
let y:Typ1 = ("foo", 33)          // OK, because no conflict by type

var z:Typ1 = _                    // OK, default field values
cassert z.a == "none" and z.b == 0
z = ("foo", 33)

cassert v == w == x == y == z
```

Pyrope allows a setter method to intercept assignments or construction. The same
setter method is called in all the previous cases.

The setter method can use single character arguments for array index, but they must
respect the declaration order.


```
let Typ2 = (
  a:string = "none",
  b:u32 = 0,
  setter = mod(ref self, a, b) { self.a = a; self.b = b }
)

var x:Typ2 = (a="x", b=0)
var y:Typ2 = (a="x", b=0)

x["hello"] = 44
y = ("hello", 44)
cassert x == y
```

Tuples can be multi-dimensional, and the index can handle multiple indexes at once.

```
let Matrix8x8 = (
  data:[8][8]u16 = _,
  setter = fun(ref self, x:int(0, 7), y:int(0, 7), v:u16) {
    self.data[x][y] = v
  } ++ fun(ref self, x:int(0, 7), v:u16) {
    for ent in ref data[x] {
      ent = v
    }
  } ++ fun(ref self) { // default initialization
    for ent in ref data {
      ent = 0
    }
  }
)

let m:Matrix8x8 = _
cassert m.data[0][3] == 0

m[1, 2] = 100
cassert m.data[1][2] == 100
m[1] = 3
cassert m.data[1][2] == 3
m[4][5] = 33
cassert m.data[4][5] == 33

m[1] = 40
cassert m[1] == (3, 40, 3, 3, 3, 3, 3, 3)
```

The default `getter`/`setter` allows for indexing each of the dimentions and returns
a slice of the object. Since they can be overwritten, the explicit overload selects
which to pick.

```
let Matrix2x2 = (
  data:[2][2]u16 = _,
  getter = fun(ref self, x:int(0, 2), y:int(0, 2)) {
    self.data[x][y] + 1
  }
)

let n:Matrix2x2 = _
n.data[0][1] = 2      // default setter

cassert n[0][1] == 3  // getter does + 1
cassert n[0] == (0, 3) // compile error, no getter for fun(ref self, x)
```

The symmetric getter method is called whenever the tuple is read. Since each
variable or tuple field is also a tuple, the getter/setter allow to intercept
any variable/field. The same array rule applies to the getter.

```
let My_2_elem = (
  data:[2]string = _,
  setter = mod(ref self, x:uint(0..<2), v:string) {
    self.data[x] = v
  } ++ mod(ref self, v:My_2_elem) {
    self.data = v.data
  } ++ mod(ref self) { // default _ assignment
    self.data = _
  },
  getter = fun(self) { self.data }
        ++ fun(self, i:uint) { self.data[i] }
)

var v:My_2_elem = _
var x:My_2_elem = _

v = (x=0, "hello")
v[1] = "world"

cassert v[0] == "hello"
cassert v == ("hello", "world")  // not

let z = v
cassert z !equals v   // v has v.data, z does not
```


The getter/setter can also be used to intercept and/or modify the value
set/returned.


```
let some_obj = (
  a1:string,
  a2 = (
    _val:u32 = _,                              // hidden field
    getter = fun(self) { self._val + 100 },
    setter = mod(ref self, x) { self._val = x + 1 }
  ),
  setter = mod(ref self, a, b) {                 // setter
    self.a1 = a
    self.a2._val = b
  }
)

var x:some_obj = ("hello", 3)

assert x.a1 == "hello"
assert x.a2 == 103
x.a2 = 5
```


The getter method can be [overloaded](06-functions.md#Overloading). This allows
to customize by return type:

```
let showcase = (
  ,v:int = _
  ,getter = fun(self)->(_:string) where self.i>10 {
    format("this is a big {} number", self.v)
  } ++ fun(self)->(_:int) {
    self.v
  }
)

var s:showcase = _
s.v = 3
let r1:string = s // compile error, no matching getter
let r2:int    = s // OK

s.v = 100
let r3:string = s // OK
cassert r3 == "this is a bit 100 number"
```

Like all the lambdas, the getter method can also be overloaded on the return type.
In this case, it allows building typecast per type.

```
let my_obj = (
  ,val:u32 = _
  ,getter = fun(self)->(_:string ){ string(self.val) }
       ++ fun(self)->(_:bool){ self.val != 0    }
       ++ fun(self)->(_:int    ){ self.val         }
)
```

### Attribute setter/getter value

The setter/getter can also access attributes:

```
var obj1::[attr1] = (
  ,data:int = _
  ,setter = fun(ref self, v) {
    if v.[attr2] {
      self.data.[attr3] = 33
    }
    cassert self.[attr1]
  }
)
```

### Default setter value

All the variable declarations need a explicit assigned value. The `_` allows to
pick the default value based on the type. If the type is an integer, the `_` is equivalent
to a zero. If the type is a boolean, the default or `_` is false. For more complicated
tuple types, the setter will be called without any value.


```
let fint:int = _
cassert fint == 0

var fbool:bool = _
cassert fbool == 0

let Tup = (
  ,v:string = _  // default to empty
  ,setter = fun(ref self) { // no args, default setter for _
     cassert self.v == ""
     self.v = "empty33"
  } ++ fun(ref self, v) {
     self.v = v
  }
)

var x:Tup = _
cassert x.v == "empty33"

x = "Padua"
cassert x.v == "Padua"

var y = Tup()
cassert y.v == "empty33"

y = "ucsc"
cassert y.v == "ucsc"
```

### Array/Tuple getter/setter

Array index also use the setter or getter methods.

```
var my_arr = (
  ,vector:[16]u8 = 0
  ,getter = fun(self, idx:u4) {
     self.vector[idx]
  }
  ,setter = proc(ref self, idx:u4, val:u8) {
     self.vector[idx] = val
  } ++ proc(ref self) {
     // default constructor declaration
  }
)

my_arr[3] = 300           // calls setter
my_arr.3  = 300           // calls setter
cassert my_add[3] == 300  // calls getter
cassert my_add.3  == 300  // calls getter
```

Unlike languages like C++, the setter is only called if there is a new value
assigned. This means that the index must always be in the left-hand-side of an
assignment.


If the getter/setter uses a string argument, this also allows to access tuple fields.

```
let Point = (
  ,priv_x:int:[private] = 0
  ,priv_y:int:[private] = 0

  ,setter = proc(ref self, x:int, y:int) {
    self.priv_x = x
    self.priv_y = y
  }

  ,getter = proc(self, idx:string) {
    match idx {
     == 'x' { self.priv_x }
     == 'y' { self.priv_y }
    }
  }
)

let p:Point = (1,2)

cassert p['x'] == 1 and p['y'] == 2
cassert p.x == 1 and p.y == 2          // compile error
```

## Compare method


The comparator operations (`==`, `!=`, `<=`,...) need to be overloaded for most
objects. Pyrope has the `lt` and `eq` methods to build all the other
comparators. When non-provided the `lt` (Less Than) is a compile error, and the
`eq` (Equal) compares that all the tuple fields are equal.


```
let t=(
  ,v:string = _
  ,setter = proc(ref self) { self.v = a }
  ,lt = fun(self,other)->(_:bool){ self.v  < other.v }
  ,eq = fun(self,other)            { self.v == other.v } // infer return
)

var m1:t = 10
var m2:t = 4
assert m1 < m2 and !(m1==m2)
assert m1 <= m2 and m1 != m2 and m2 > m1 and m2 >= m1
```


The default tuple comparator (`a == b`) compares values, not types like `a does
b`, but a compile error is created unless `a equals b` returns true. This means
that a comparison by tuple position suffices even for named tuples.

```
let t1=(
  ,long_name:string = "foo"
  ,b=33
)
let t2=(
  ,b=33
  ,long_name:string = "foo"
)
let t3=(
  ,33
  ,long_name:string = "foo"
)

cassert t1==t2
cassert t1 !equals t3
let x = t1==t3           // compile error, t1 !equals t3
```

The comparator `a == b` when `a` or `b` are tuples is equivalent to:
```
cassert (a==b) == ((a in b) and (b in a))
cassert a equals b
```

With the `eq` overload, it is possible to compare named and unnamed tuples.

```
let t1=(
  ,long_name:string = "foo"
  ,b=33
)
let t2=(
  ,xx_a=33
  ,yy_b = "foo"
  ,eq = fun(self, o:t1) {
    return self.xx_a == o.b and self.xx_y == o.long_name
  } ++ fun(self, o:t2) {
    return self.xx_a == o.xx_a and self.xx_y == o.xx_y
  }
)

cassert t1==t2 and t2==t1
```

Since `a == b` can compare two different objects, it is not clear if `a.eq` or `b.eq` method
is called. Pyrope has the following rule:

* If only one of the two has a defined method, that method is called.
* If both have defined methods, they should have the same set of `eq` methods or a compile error is created.


It is also possible to provide a custom `ge` (Greater Than). The `ge` is redundant
with the `lt` and `eq` (`(a >= b) == (a==b or b<a)`) but it allows to have more
efficient implemetations:

For integer operations, the Pyrope should result to the following equivalent Lgraph:

* `a == b` is `__eq(a,b)`
* `a != b` is `__not(__eq(a,b))`
* `a  < b` is `__lt(a,b)`
* `a  < b` is `__lt(b,a)`
* `a <= b` is `__lt(a,b) | __eq(a,b)` (without `ge`) or `__ge(b,a)`
* `a >= b` is `__lt(b,a) | __eq(a,b)` (without `ge`) or `__ge(a,b)`


## Non-Pyrope (C++) calls

Calling C++ or external code is still fully synthesizable if the code is
available at compile time. An example could be calling a C++ API to read a json
file during the setup phase to decide configuration parameters.


```
let cfg = __read_json()

let ext = if cfg.foo.bar == 3 {
   foo
}else{
   bar
}
```


Non-Pyrope calls have the same procedure/function distinction and use the same
Pyrope lambda definition but they do not have the `where` clause.


If no type is provided, a C++ call assumes a `proc(...inp)->(...out)` type is
can pass many inputs/outputs and has permission to mutate values. Any call to a
method with two underscores `__` is either a basic gate or a C++ function.

```
let __my_typed_cpp:fun(a,b)->(e) = _
```

Type defining non-Pyrope code is good to catch errors and also because declaring
`function` allows to handle several cases of circular dependencies not possible with `procedure` [import section](10-internals.md)

