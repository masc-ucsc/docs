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
    mut b = "hello"

    mut a:u32 = 0

    a += 1

    a = b                       // incorrect


    mut dest:u32 = 0

    dest = foo:u16 + v:u8
    ```

=== "Snippet with comptime assert"

    ```
    mut b = "hello"

    mut a:u32 = 0

    a += 1
    cassert a does u32
    a = b                       // incorrect
    cassert b does u32  // fails

    mut dest:u32 = 0
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
const t1 = (a:int=1, b:string)
const t2 = (a:int=100, b:string)
mut v1 = (a=33, b="hello")

const f1 = comb() {
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
const At:int(33..) = ?      // number bigger than 32
const Bt = (
  c:string = ?,
  d = 100,
  setter = comb(ref self, ...args) { self.c = args }
)

mut a:At = 40
mut a2 = At(40)
cassert a == a2

mut b:Bt = "hello"
mut b2 = Bt("hello")
cassert b == b2

puts "a:{} or {}", a, at // a:40 or 33
puts "b:{}", b           // b:(c="hello",d=100)
```

### Type equivalence


The `does` operator is the base to compare types. It follows structural typing rules.
These are the detailed rules for the `a does b` operator depending on the `a` and `b` fields:


* false when `a` and `b` are different basic types (`boolean`, `comb`,
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

assert _:comb(x, xxx2) -> (y, z) does _:comb(x) -> (y, z)
assert (_:comb(x) -> (y, z) !does _:comb(x, xxx2) -> (y, z))
```

For named tuples, this code shows some of the corner cases:

```
const t1 = (a:string, b:int)
const t2 = (b:int, a:string)

mut a:t1 = ("hello", 3)     // OK
mut a1:t1 = (3, "hello")     // compile error, positions do not match
mut b:t1 = (a="hello", 3)   // OK
mut b1:t1 = (3, a="hello")   // compile error, positions do not match
mut c:t1 = (a="hello", b=3) // OK
mut c1:t1 = (b=3, a="hello") // OK

mut d:t2 = c                 // OK, both fully named
assert d[0] == c[1] and c[0] == d[1]
assert d.a == c.a and d.b == c.b
```

Ignoring the value is what makes `equals` different from `==`. As a result
different functionality functions could be `equals`.

```
const a = comb() { 1 }
const b = comb() { 2 }
assert a equals _:comb()    // 1 !equals :comb()

assert a() != b()              // 1 != 2
assert a() equals b()          // 1 equals 2

assert _:a equals _:comb()
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
const a = 3
const b = 200
cassert a is b

const c:u32 = 10
cassert a !is c
cassert a::[typename] == "int" and c::[typename] == "u32"

const d:u32 = nil
cassert c is d

const e = (a:u32=1)
const f:(a:u32) = 33
cassert e is f
```

Since it checks equivalence, when `a is b == b is a`.

```
const X1 = (b:u32)
const X2 = (b:u32)

const t1:X1 = (b=3)
const t2:X2 = (b=3)
assert (b=3) !is X2  // same as (b=3) !is X2
assert t1 equals t2
assert t1 !is t2

const t4:X1 = (b=5)

assert t4 equals t1
assert t4 is t1
assert t4 !is t2

const f2 = comb(x) where x is X1 {
  x.b + 1
}
```

## Enums with types

Enumerates (enums) create a number for each entry in a set of identifiers.
Pyrope also allows associating a tuple or type for each entry. Another
difference from a tuple is that the enumerate values must be known at compile
time.


```
const Rgb = (
  c:u24,
  setter = mod(ref self, c) { self.c = c }
)

const Color = enum(
  Yellow:Rgb = 0xffff00,
  Red:Rgb = 0xff0000,
  Green = Rgb(0x00ff00), // alternative
  GBlue = Rgb(0x0000ff)
)

mut y:Color = Color.Red
if y == Color.Red {
  puts "c1:{} c2:{}\n", y, y.c  // prints: c1:Color.Red c2:0xff0000
}
```


It is also possible to support an algebraic data type with enums. This requires
each enumerate entry to have an associated type. In can also be seen as a union
type, where the enumerate has to be either of the enum entries where each is
associated to a type.

```
const ADT = enum(
  Person:(eats:string) = ?,
  Robot:(charges_with:string) = ?
)

const nourish = comb(x:ADT) {
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
mut val:u8 = 0   // designer constraints a to be between 0 and 255
assert val::[sbits] == 0

val = 3          // val has 3 bits (0sb011 all the numbers are signed)

val = 300        // compile error, '300' overflows the maximum allowed value of 'val'

val = 1          // max=1,min=1 sbits=2, ubits=1
assert val::[ubits] == 1 and val::[min] == 1 and val::[max] == 1 and val::[sbits] == 2

val::[wrap] = 0x1F0 // Drop bits from 0x1F0 to fit in constrained type
assert val == 240 == 0xF0

val = u8(0x1F0)    // same
assert val == 0xF0
```

Pyrope leverages LiveHD bitwidth pass to compute the maximum and minimum value
of each variable. For each operation, the maximum and minimum are computed. For
control-flow divergences, the worst possible path is considered.

```
mut a = 3                  // a: current(max=3,min=3) constrain()
mut c:int(0..=10) = ?      // c: current(max=0,min=0) constrain(max=10,min=0)
if b {
  c = a + 1                // c: current(max=4,min=4) constrain(max=10,min=0)
} else {
  c = a                    // c: current(max=3,min=3) constrain(max=10,min=0)
}
                           // c: current(max=4,min=3) constrain(max=10,min=0)

mut e::[sbits = 4] = ?     // e: current(max=0,min=0) constrain(max=7,min=-8)
e = 2                      // e: current(max=2,min=2) constrain(max=7,min=-8)
mut d = c                  // d: current(max=4,min=3) constrain()
if d == 4 {
  d = e + 1                // d: current(max=3,min=3) constrain()
}
mut g:u3 = d               // g: current(max=4,min=3) constrain(max=7,min=0)
mut h = c#[0, 1]           // h: current(max=3,min=0) constrain()
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
const e_type = enum(str:String = "hello", num=22)
const v_type = variant(str:String, num:int) // No default value in variant

mut vv:v_type = (num=0x65)
cassert vv.num == 0x65
const xx = vv.str                         // compile or simulation error
```


The variant variable allows to explicitly or implicitly access the subtype.
Variants may not be solved at compile time, and the error will be a simulation
error. A `comptime` directive can force a compile time-only variant.

```
const Vtype = variant(str:String, num:int, b:bool)

const x1a:Vtype = "hello"                 // implicit variant type
const x1b:Vtype = (str="hello")           // explicit variant type

mut x2:Vtype:[comptime=true] = "hello"       // comptime

cassert x1a.str == "hello" and x1a == "hello"
cassert x1b.str == "hello" and x1b == "hello"

const err1 = x1a.num                      // compile or simulation error
const err2 = x1b.b                        // compile or simulation error
const err3 = x2.num                       // compile error
```

As a reference, `enums` allow to compare for field but not update enum entries.

```
mut ee = e_type
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
const at = (c:string, d:u32)
const bt = (c:string, d:u100)

const ct = (
  d:u32 = ?,
  c:string = ?
)
// different order
const dt = (
  d:u32 = ?,
  c:string = ?,
  setter = comb(ref self, x:at) { self.d = x.d; self.c = x.c }
)

mut b:bt = (c="hello", d=10000)
mut a:at = ?

a = b          // OK c is string, and 10000 fits in u32

mut c:ct = a   // OK even different order because all names match

mut d:dt = a   // OK, call initial to type cast
```

* To string: The `format` allows to convert any type/tuple to a string.
* To integer: `variable#[..]` for string, range, and bool, union otherwise.
* `union` allows to convert across types by specifying the size explicitly.

## Introspection

Introspection is possible for tuples.

```
a = (b=1, c:u32=2)
mut b = a
b.c = 100

assert a equals b
assert a.size == 2
assert a['b'] == 1
assert a['c'] equals u32

assert a has 'c'
assert !(a has 'foo')

assert a::[id] == 'a'
assert a[0]::[id] == ':0:b' and a.b::[id] == ':0:b'
assert a[1]::[id] == ':1:c' and a.c::[id] == ':1:c'
```

Function definitions allocate a tuple, which allows to introspect the
function but not to change the functionality. Functions have 3 fields `inputs`,
`outputs`, `where`. The `where` is a function that always returns true if unset
at declaration.

```
const fu = comb(a, b=2) -> (c) where a > 10 { c = a + b }
assert fu::[inp] equals ('a', 'b')
assert fu::[out] equals ('c')
assert fu::[where](a=200) and !fu::[where](a=1)
```

This means that when ignoring named vs unnamed calls, overloading behaves like
this:

```
const x:u32 = fn(a1, a2)

const model_poly_call = comb(fn, ...args) -> (out) {
  for f in fn {
     continue unless f::[inp] does args
     continue unless f::[out] does out
     return f(args) when f::[where](args)
  }
}
const x:u32 = model_poly_call(fn, a1, a2)
```

There are several uses for introspection, but for example, it is possible to build a
function that returns a randomly mutated tuple.

```
const randomize::[debug] = comb(ref self) {
  const rnd = import("prp/rnd")
  for i in ref self {
    if i equals _:int {
      i = rnd.between(i::[max], i::[min])
    } elif i equals _:bool {
      i = rnd.boolean()
    }
  }
  self
}

const x = (a=1, b=true, c="hello")
const y = x.randomize()

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
comb fun1(a, b) { a + b }
comb fun2(a) {
  const inside = comb() { 3 }
  a
}
comb another(a) { a }

const mytup = (
  call3 = comb() { puts "call called" }
)
```

```
// file: src/user.prp
a = import("my_fun/*comb*")
a.fun1(a=1, b=2)        // OK
a.another(a=1, 2)       // compile error, 'another' is not an imported function
a.fun2.inside()         // compile error, `inside` is not in top scope variable

const fun1 = import("my_fun/fun1")
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
const a = import("prj1/file1")
const b = import("file1")       // import xxx_fun from file1 in the local project
const c = import("file2")       // import the functions from local file2
const d = import("prj2/file3")  // import the functions from project prj2 and file3
```

Many languages have a "using" or "import" or "include" command that includes
all the imported functions/variables to the current scope. Pyrope does not
allow that, but it is possible to use a mixin to add the imported functionality
to a tuple.

```
const b = import("prp/Number")
mut a = import("fancy/Number_mixin")

const Number = b ++ a // patch the default Number class

mut x:Number = 3
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
  const cntr = regref("do_increase/counter")

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
  reg uart_addr:u32 = ?
  assert 0x400 > uart_addr >= 0x300
}

// file local.prp
mod setup_xx() {
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


### Mocking library

One possible use of the register reference is to create a "mocking" library. A
mocking library instantiates a large design but forces some subblocks to
produce some results for testing. The challenge is that it needs undriven
registers. During testing, the `peek`/`poke` is more flexible and it can
overwrite an existing value. The peek/poke use the same reference as `import`
or register reference.

```
const bpred = ( // complex predictor
  taken = comb() { self.some_table[som_var] >= 0 }
)

test "mocking taken branches" {
  poke "bpred_file/taken", true

  mut l = core.fetch.predict(0xFFF)
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
const Typ1 = (
  a:string = "none",
  b:u32 = 0
)

const w = Typ1(a="foo", b=33)       // OK
const x:Typ1 = (a="foo", b=33)      // OK, same as before

const v:Typ1 = Typ1(a="foo", b=33)  // OK, but redundant Typ1
const y:Typ1 = ("foo", 33)          // OK, because no conflict by type

mut z:Typ1 = ?                    // OK, default field values
cassert z.a == "none" and z.b == 0
z = ("foo", 33)

cassert v == w == x == y == z
```

Pyrope allows a setter method to intercept assignments or construction. The same
setter method is called in all the previous cases.

The setter method can use single character arguments for array index, but they must
respect the declaration order.


```
const Typ2 = (
  a:string = "none",
  b:u32 = 0,
  setter = mod(ref self, a, b) { self.a = a; self.b = b }
)

mut x:Typ2 = (a="x", b=0)
mut y:Typ2 = (a="x", b=0)

x["hello"] = 44
y = ("hello", 44)
cassert x == y
```

Tuples can be multi-dimensional, and the index can handle multiple indexes at once.

```
const Matrix8x8 = (
  data:[8][8]u16 = ?,
  setter = comb(ref self, x:int(0, 7), y:int(0, 7), v:u16) {
    self.data[x][y] = v
  } ++ comb(ref self, x:int(0, 7), v:u16) {
    for ent in ref data[x] {
      ent = v
    }
  } ++ comb(ref self) { // default initialization
    for ent in ref data {
      ent = 0
    }
  }
)

const m:Matrix8x8 = ?
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
const Matrix2x2 = (
  data:[2][2]u16 = ?,
  getter = comb(ref self, x:int(0, 2), y:int(0, 2)) {
    self.data[x][y] + 1
  }
)

const n:Matrix2x2 = ?
n.data[0][1] = 2      // default setter

cassert n[0][1] == 3  // getter does + 1
cassert n[0] == (0, 3) // compile error, no getter for comb(ref self, x)
```

The symmetric getter method is called whenever the tuple is read. Since each
variable or tuple field is also a tuple, the getter/setter allow to intercept
any variable/field. The same array rule applies to the getter.

```
const My_2_elem = (
  data:[2]string = ?,
  setter = mod(ref self, x:uint(0..<2), v:string) {
    self.data[x] = v
  } ++ mod(ref self, v:My_2_elem) {
    self.data = v.data
  } ++ mod(ref self) { // default _ assignment
    self.data = ?
  },
  getter = comb(self) { self.data }
        ++ comb(self, i:uint) { self.data[i] }
)

mut v:My_2_elem = ?
mut x:My_2_elem = ?

v = (x=0, "hello")
v[1] = "world"

cassert v[0] == "hello"
cassert v == ("hello", "world")  // not

const z = v
cassert z !equals v   // v has v.data, z does not
```


The getter/setter can also be used to intercept and/or modify the value
set/returned.


```
const some_obj = (
  a1:string,
  a2 = (
    _val:u32 = ?,                              // hidden field
    getter = comb(self) { self._val + 100 },
    setter = mod(ref self, x) { self._val = x + 1 }
  ),
  setter = mod(ref self, a, b) {                 // setter
    self.a1 = a
    self.a2._val = b
  }
)

mut x:some_obj = ("hello", 3)

assert x.a1 == "hello"
assert x.a2 == 103
x.a2 = 5
```


The getter method can be [overloaded](06-functions.md#Overloading). This allows
to customize by return type:

```
const showcase = (
  ,v:int = ?
  ,getter = comb(self)->(_:string) where self.i>10 {
    format("this is a big {} number", self.v)
  } ++ comb(self)->(_:int) {
    self.v
  }
)

mut s:showcase = ?
s.v = 3
const r1:string = s // compile error, no matching getter
const r2:int    = s // OK

s.v = 100
const r3:string = s // OK
cassert r3 == "this is a bit 100 number"
```

Like all the lambdas, the getter method can also be overloaded on the return type.
In this case, it allows building typecast per type.

```
const my_obj = (
  ,val:u32 = ?
  ,getter = comb(self)->(_:string ){ string(self.val) }
       ++ comb(self)->(_:bool){ self.val != 0    }
       ++ comb(self)->(_:int    ){ self.val         }
)
```

### Attribute setter/getter value

The setter/getter can also access attributes:

```
mut obj1::[attr1] = (
  ,data:int = ?
  ,setter = comb(ref self, v) {
    if v::[attr2] {
      self.data::[attr3] = 33
    }
    cassert self::[attr1]
  }
)
```

### Default setter value

All the variable declarations need a explicit assigned value. The `_` allows to
pick the default value based on the type. If the type is an integer, the `_` is equivalent
to a zero. If the type is a boolean, the default or `_` is false. For more complicated
tuple types, the setter will be called without any value.


```
const fint:int = ?
cassert fint == 0

mut fbool:bool = ?
cassert fbool == 0

const Tup = (
  ,v:string = ?  // default to empty
  ,setter = comb(ref self) { // no args, default setter for _
     cassert self.v == ""
     self.v = "empty33"
  } ++ comb(ref self, v) {
     self.v = v
  }
)

mut x:Tup = ?
cassert x.v == "empty33"

x = "Padua"
cassert x.v == "Padua"

mut y = Tup()
cassert y.v == "empty33"

y = "ucsc"
cassert y.v == "ucsc"
```

### Array/Tuple getter/setter

Array index also use the setter or getter methods.

```
mut my_arr = (
  ,vector:[16]u8 = 0
  ,getter = comb(self, idx:u4) {
     self.vector[idx]
  }
  ,setter = pipe(ref self, idx:u4, val:u8) {
     self.vector[idx] = val
  } ++ pipe(ref self) {
     // default constructor declaration
  }
)

my_arr[3] = 300           // calls setter
cassert my_add[3] == 300  // calls getter
```

Unlike languages like C++, the setter is only called if there is a new value
assigned. This means that the index must always be in the left-hand-side of an
assignment.


If the getter/setter uses a string argument, this also allows to access tuple fields.

```
const Point = (
  ,priv_x:int:[private] = 0
  ,priv_y:int:[private] = 0

  ,setter = pipe(ref self, x:int, y:int) {
    self.priv_x = x
    self.priv_y = y
  }

  ,getter = pipe(self, idx:string) {
    match idx {
     == 'x' { self.priv_x }
     == 'y' { self.priv_y }
    }
  }
)

const p:Point = (1,2)

cassert p['x'] == 1 and p['y'] == 2
cassert p.x == 1 and p.y == 2          // compile error
```

## Compare method


The comparator operations (`==`, `!=`, `<=`,...) need to be overloaded for most
objects. Pyrope has the `lt` and `eq` methods to build all the other
comparators. When non-provided the `lt` (Less Than) is a compile error, and the
`eq` (Equal) compares that all the tuple fields are equal.


```
const t=(
  ,v:string = ?
  ,setter = pipe(ref self) { self.v = a }
  ,lt = comb(self,other)->(_:bool){ self.v  < other.v }
  ,eq = comb(self,other)            { self.v == other.v } // infer return
)

mut m1:t = 10
mut m2:t = 4
assert m1 < m2 and !(m1==m2)
assert m1 <= m2 and m1 != m2 and m2 > m1 and m2 >= m1
```


The default tuple comparator (`a == b`) compares values, not types like `a does
b`, but a compile error is created unless `a equals b` returns true. This means
that a comparison by tuple position suffices even for named tuples.

```
const t1=(
  ,long_name:string = "foo"
  ,b=33
)
const t2=(
  ,b=33
  ,long_name:string = "foo"
)
const t3=(
  ,33
  ,long_name:string = "foo"
)

cassert t1==t2
cassert t1 !equals t3
const x = t1==t3           // compile error, t1 !equals t3
```

The comparator `a == b` when `a` or `b` are tuples is equivalent to:
```
cassert (a==b) == ((a in b) and (b in a))
cassert a equals b
```

With the `eq` overload, it is possible to compare named and unnamed tuples.

```
const t1=(
  ,long_name:string = "foo"
  ,b=33
)
const t2=(
  ,xx_a=33
  ,yy_b = "foo"
  ,eq = comb(self, o:t1) {
    return self.xx_a == o.b and self.xx_y == o.long_name
  } ++ comb(self, o:t2) {
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
const cfg = __read_json()

const ext = if cfg.foo.bar == 3 {
   foo
}else{
   bar
}
```


Non-Pyrope calls have the same procedure/function distinction and use the same
Pyrope lambda definition but they do not have the `where` clause.


If no type is provided, a C++ call assumes a `pipe(...inp)->(...out)` type is
can pass many inputs/outputs and has permission to mutate values. Any call to a
method with two underscores `__` is either a basic gate or a C++ function.

```
const __my_typed_cpp:comb(a,b)->(e) = ?
```

Type defining non-Pyrope code is good to catch errors and also because declaring
`function` allows to handle several cases of circular dependencies not possible with `procedure` [import section](10-internals.md)

