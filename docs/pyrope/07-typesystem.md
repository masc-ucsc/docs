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


## Types vs `comptime assert`

To understand the type check, it is useful to see an equivalent `comptime
assert` translation. The type system has two components: type synthesis and
type check. The type check can be understood as a `comptime assert`.


After type synthesis, each variable has an associated type. In Pyrope, for each
assignment, the type checks that the left-hand side (LHS) has the same type as
the right-hand side (RHS) of the expression. Additional type checks happen when
variables have a type check explicitly set (`var:type`) in rhs expressions.


Although the type system is not implemented with asserts, it is an equivalent
way to understand the type system "check" behavior.  Although it is possible to
declare just the `comptime assert` for type checks, the recommendation is to
use the explicit Pyrope type syntax because it is more readable and easier to
optimize.


=== "Snippet with types"

    ```
    var b = "hello"

    var a:u32

    a += 1

    a = b                       // incorrect


    var dest:u32

    dest = foo:u16 + v:u8
    ```

=== "Snippet with comptime assert"

    ```
    var b = "hello"

    var a:u32

    a += 1
    comptime assert a does u32
    a = b                       // incorrect
    comptime assert a does u32

    var dest:u32
    comptime assert (dest does u32) and (foo does u16) and (v does u8)
    dest = foo:u16 + v:u8
    ```


## Building types

Each variable can be a basic type. In addition, each variable can have a set of
constraints from the type system. Pyrope type system constructs to handle types:

* `type` keyword allows declaring types.

* `a does b`: Checks 'a' is a superset or equal to 'b'. In the future, the
  Unicode character "\u02287" could be used as an alternative to `does` (`a`
&#8839 `b`).

* `a:b` is equivalent to `a does b` for type check, but it is also used by type
  synthesis.

* `a equals b`: Checks that `a does b` and `b does a`. Effectively checking
  that they have the same type. Notice that this is not like checking for
  logical equivalence, just type equivalence.

```
type t1 = (a:int=1  , b:string)
type t2 = (a:int=100, b:string)
var  v1 = (a=33     , b="hello")

comptime assert t1 equals t2
comptime assert t1 equals v1
```

While the `var` statement declares a new variable instance that can also have an
associated type, the `type` statement declares a type without any instance.
The `type` keyword also allows for expressions to build more complex types.
All the elements in the type expression are treated as "type of". E.g: `type x
= a or 1..=3`.

```
type a1 = u32                 // same as 'type a1:u32'
type a2 = int(max=33,min=-5)  // same as 'type a2:int(-5,33)'
type a3 = (
    ,var name:string
    ,var age:u8
    )

type b1 = a1 or  a2           // same as 'type b1:int(-5..<4G)
type b2 = a1 and a2           // same as 'type b2:int( 0..=33)

type b3 = a1 or a3  // compile error: unclear how to combine type 'a1' and 'a2'
```

The puts command understands types.

```
type at=int(33..)     // number bigger than 32
type bt=(
  ,var c:string
  ,var d=100
  ,let set = {|(self)->(self)| self.c = $[1..] } // skip first argument (self)
)

var a:at=40
var v:bt="hello"
puts "a:{} or {}", a, at // a:40 or 33
puts "b:{}", b           // b:(c="hello",d=100)
```


Both `does` and `equals` operate over types. This means that the values in the
entries are ignored, but the type of entry is considered.

```
assert      (a=3     ,:string) does (a:int,"hello")
assert      (a={3}   ,:string) does (a:int,"hello")
assert not ((a=3     ,:string) does (b:int,"hello"))
assert not ((a="foo" ,:string) does (a:int,"hello"))
assert not ((a={|| 3},:string) does (a:int,"hello"))
```

The `does` keyword checks that functions have "compatible" arguments.

```
assert      {||    3 } does {|(a)| 3 }
assert not ({|(a)| 3 } does {|(a)| 3 })

assert not ({|(a,b)| 3 } does {|(a)  | 3})
assert not ({|(a)|   3 } does {|(a,b)| 3})

assert     ({|(a)|     3 } does {|(a:string)| 3})
assert not ({|(a:int)| 3 } does {|(a:string)| 3})
```

Ignoring the value is what makes `equals` different from `==`. As a result
different functionality functions could be `equals`.

```
a = {|| ret 1 }
b = {|| ret 2 }
assert a equals {|| }
assert a != b
assert a equals b
assert not (a equals {|(x)| ret 1 }) // different arguments
```

Some languages use an `is` keyword but Pyrope uses `does` or `equals` because
in English "a is b" is not clear ("a is same as b" vs "a is a subtype of b").

```
type x = (a:string, b:int)
type y = (a:string)
type z = (a:string, b:u32, c:i8)

assert   x does y
assert   y does y
assert   z does y
assert !(x does z)
assert !(y does z)
assert !(y does x)
assert !(z does x)

type big = x or y or z or (d:u33)
assert   big does x
assert   big does y
assert   big does z
assert   big does (d:u20)
assert !(big does (d:u40))
```

## Enums with types

Enumerates (enums) create number for each entry in a set of identifiers. Pyrope
also allows to associate a tuple or type for each entry.

Enums can handle types:

```
type Rgb = (
  ,let c:u24
  ,let set = {|c| self.c = c }
)

enum Color:Rgb = (
  ,Yellow   = 0xffff00
  ,Red      = 0xff0000
  ,Green    = Rgb(0x00ff00) // alternative redundant syntax
  ,Blue     = Rgb(0x0000ff)
)

var y:Color = Color.Red
if y == Color.Red {
  puts "c1:{} c2:{}\n", y, y.c  // prints: c1:Color.Red c2:0xff0000
}
```

## Bitwidth

Integers can be constrained based on the maximum and minimum value (not by
number of bits).

Pyrope automatically infers the maximum and minimum values for each numeric
variable. If a variable width can not be inferred, the compiler generates a
compilation error. A compilation error is generated if the destination
variable has an assigned size smaller than the operand results.

The programmer can specify the maximum number of bits, or the maximum value range.
The programmer can not specify the exact number of bits because the compiler has
the option to optimize the design.

Pyrope code can set or access the bitwidth pass results for each variable.

* `__max`: the maximum number
* `__min`: the minimum number
* `__sbits`: the number of bits to represent the value
* `__ubits`: the number of bits. The variable must be always positive or a compile error.

```pyrope
var val:u8 // designer constraints a to be between 0 and 255
val = 3    // val has 3 bits (0sb011 all the numbers are signed)

val = 300  // compile error, '300' overflows the maximum allowed value of 'val'

val = 0x1F0@[0..<val.__ubits] // explicitly select bits to not overflow
assert val == 240

wrap val = 0x1F0   // Drop bits from 0x1F0 to fit in maximum 'val' allowed bits
assert val == 240

val = u8(0x1F0)    // same
assert val == 0xF0
```


Pyrope leverages LiveHD bitwidth pass [stephenson_bitwidth] to compute the
maximum and minimum value of each variable. For each operation, the maximum and
minimum are computed. For control-flow divergences, the worst possible path is
considered.

```
a = 3                      // max:3, min:3
if b {
  c = a+1                  // max:4, min:4
}else{
  c = a                    // max:3, min:3
}
e.__sbits = 4              // max:3, min:-4
e = 3                      // max:3, min:3
d = c                      // max:4, min:3
if d==4 {
  d = e + 1                // max:4, min:4
}
g = d                      // max:4, min:3
h = c@[0,1]                // max:3, min:0
```


Bitwidth uses narrowing to converge (see
[internals](10-internals.md/#type-synthesis)). The GCD example does not specify
the input/output size, but narrowing allows to work without typecasts.  To
understand, the comments show the max/min bitwidth computations.

```
if cmd? {
  x,y = cmd     // x.max=cmd.a.max; x.min = 0 (uint) ; ....
}elif x > y {
                // narrowing: x.min = y.min + 1 = 1
                // narrowing: y.max = x.min - 1
  x = x - y     // x.max = x.max - x.min = x.max - 1
                // x.min = x.min - y.max = 1
}else{          // x <= y
                // narrowing: x.max = y.min
                // narrowing: y.min = x.min
  y = y - x     // y.max = y.max - x.min = y.max
                // y.min = y.min - x.max = 0
}
                // merging: x.max = x.max ; x.min = 0
                // merging: y.max = y.max ; y.min = 0
                // converged becauze x and y is same or smaller at beginning
```

Even with narrowing, the bitwidth pass may not converge to find a valid size.
In this case, the programmer must insert a typecast or operation to constrain
the bitwidth. For example, this could work:

```
reg x,y
if cmd? {
  x,y = cmd
}elif x > y {
  x = x - y
}else{
  y = y - x
}
wrap x:cmd.a = x  // use cmd.a type for x, and drop bits as needed
y = cmd.b(y)  // typecast y to cmd.b type (this can add a mux)
```

## Typecasting


Typecasting is the process of changing from one type to other. There are 2
reserved keywords for typecasting (`saturate` and `wrap`), and an explicit
bitcast.

* `saturate` keeps the maximum or minimum (negative integer) that fits on the
  left-hand side.

* `wrap` drops the bits that do not fit on the left-hand side. It performs sign
  extension if needed.

* `lhs@[] = rhs` bit casts the RHS to the LHS as long as both have explicit bit
  sizes and the sizes are the same. Like the `tup@[]` operator in the RHS, the
  bitwidth inference is disabled and explicit bitsizes are used to avoid
  confusion.

In all the cases, there is no bitwidth of type inference between the right and
left side of the assignment. The LHS variable will be immutable (`let`) if not
defined before with a `var`. Also, in both cases, if the left-hand side is not
a boolean or an integer with a explicit type, a compile error is generated.

```
var a:u32=100
var b:u10
var c:u5
var d:u5

b = a      // OK done automatically. No precision lost
c = a      // compile error, '100' overflows the maximum allowed value of 'c'
wrap c = a // OK, same as c = a@[0..<5] (Since 100 is 0b1100100, c==4)

saturate c = a  // OK, c == 31
c = 31
d = c + 1 // compile error, '32' overflows the maximum allowed value of 'd'

wrap d = c + 1   // OK d == 0
saturate d = c+1 // OK, d==31
saturate d = c+1 // OK, d==31

saturate x:boolean = c // same as x = c!=0

var lhs:(x1:u8, x2:u12) // 9 + 13 bits in signed == 22bits
lhs@[] = 0x1FF:u22
assert lhs.x1 == 0xFF and lhs.x2==1
```

To convert between tuples, an explicit setter is needed unless the tuple fields
names, order, and types match.

```
type at=(c:string,d:u32)
type bt=(c:string,d:u100)

type ct=(
  ,var d:u32
  ,var c:string
) // different order
type dt=(
  ,var d:u32
  ,var c:string
  ,let set = {|(x:at)| self.d = x.d ; self.c = x.c }
)

var b:bt=(c="hello", d=10000)
var a:at

a = b // OK c is string, and 10000 fits in u32

var c:ct
c = a // compile error, different order

var d:dt
d = a // OK, call intitial to type cast
```


## Traits and mixin

There is no object inheritance in Pyrope, but tuples allow to build mixin and
composition with traits.

A mixin is when an object or class can add methods and the parent object can
access them. In several languages, there are different constructs to build them
(E.g: an include inside a class in Ruby). Since Pyrope tuples are not
immutable, new methods can be added like in mixin.

```
type Say_mixin = (
  ,let say = {|s| puts s }
)

type Say_hi_mixin = (
  ,let say_hi  = {|| self.say("hi {}", self.name) }
  ,let say_bye = {|| self.say("bye {}", self.name) }
)

type User = (
  ,var name:string
  ,let set = {|(self,n:string)| self.name = n }
)

type Mixing_all = Say_mixin ++ Say_hi_mixin ++ User

var a:Mixing_all("Julius Caesar")
a.say_hi()
```

Mixin is very expressive by allowing redefining methods. If two tuples have
the same field a tuple with the concatenated values will be created. This is
likely an error with basic types but useful to handle explicit method overload.


In a way, mixin just adds methods from two tuples to create a new tuple. In
programming languages with object-oriented programming (OOP), there are many
keywords (`virtual`, `final`, `override`, `static`...) to constrain how methods can be
updated/changed. In Pyrope, the `let` and `var` keywords can be added to any tuple
field. The `let` makes the entry immutable when applied to a method, it behaves like
a `final` keyword in most languages.


There are also two ways to concatenate tuples in Pyrope. `bun1 ++ bun2` and
`(...bun1, ...bun2)`. The difference is that `++` concatenates and replaces any
not `let` field. The `...` concatenates and but triggers a compile error if the
same field appears twice.


An issue with mixin is when more than one tuple has the `set` method. If the
tuples are concatenated with `...` and error is triggered, if the tuples are
concatenated with `++` the methods are overridden when declared with `var`.
Neither is the expected solution.  A smaller issue with mixins is that
`comptime assert X extends Y` should be inserted when implementing an
interface.


Without supporting OOP, but providing a more familiar abstract or trait
interface, Pyrope provides the `extends` keyword. It checks that the new
type extends the functionality undefined and allows to use of methods defined.
The constructor (`set`) can call the parent constructor with the `super` keyword.

This is effectively a mixin with checks that some methods should be
implemented.

```
type Shape = (
  ,name:string
  ,area          = {|(self,     )->:i32  |}
  ,increase_size = {|(self,_:i12)->(self)|}
  ,set           = {|name| self.name = name }
)

type Circle extends Shape with (
  ,set = {|| super("circle") }
  ,increase_size = {|(self,_:i12)| self.rad *= $1 }
  ,rad:i32
  ,area = {|(self) -> :i32   |
     let pi = import("math").pi
     ret pi * self.rad * self.rad
  }
)
```

Like most type checks, the `implement` can be translated for a `comptime
assert`. An equivalent "Circle" functionality:

```
type Circle = (
  ,rad:i32
  ,name = "Circle"
  ,area = {|(self) -> :i32|
     let pi = import("math").pi
     ret pi * self.rad * self.rad
  }
  ,increase_size = {|(self,_:i12)| self.rad *= $1 }
)
comptime assert Circle does Shape
```


The `implement` checks that the method is redefined. The reason is that the method arguments must be
preserved with a non-empty list of statements.

```
type base_abstract = (
  ,pub var fun = nil,                 // defined or error on use
  ,pub var fun2 = {|(a,b)->(c)| nil } // extended or error on use
)
```

## Instrospection

Instrospection is possible for tuples.

```
a = (b=1,c:u32=2)
var b = a
b.c=100

assert a equals b
assert a.size == 2
assert a['b'] == 1
assert a['c'] equals u32

assert   a has 'c'
assert !(a has 'foo')

assert a.__id == 'a'
assert a.0.__id == ':0:b' and a.b.__id == ':0:b'
assert a.1.__id == ':1:c' and a.c.__id == ':1:c'
```

Function definitions allocate a tuple, which allows to introspect the
function but not to change the functionality. Functions have 3 fields `inputs`,
`outputs`, `where`. The `where` is a function that always returns true if unset
at declaration.

```
fun = {|(a,b=2) -> (c) where a>10| c = a + b }
assert fun.inputs equals (a,b)
assert fun.outputs equals (c)
assert fun.where(a=200) and !fun.where(a=1)
```

This means that function overloading behaves like this:

```
let x = fun(args)

let x = for i in fun { last i(args) when (i.inputs does args) and i.where(args) }
```


There are several uses for introspection, but for example, it is possible to build a
function that returns a randomly mutated tuple.

```
randomize = debug {|(self)|
  rnd = import "prp/rnd"
  for mut i in self {
    if i equals :int {
      i = rnd.between(i.__max,i.__min)
    }elif i equals :boolean {
      i = rnd.boolean()
    }
  }
  ret self
}

x = (a=1,b=true,c="hello")
y = x.randomize()

assert x.a==1 and x.b==true and x.c=="hello"
cover  y.a!=1
cover  y.b!=true
assert y.c=="hello"
```


## Global variables

There are no global variables or functions in Pyrope. Variable scope is
restricted by code block `{ ... }` and/or the file. Each Pyrope file is a
function, but they are only visible to the same directory/project Pyrope files.


The `punch` statement allows to access variables from other files/functions. The
`import` statement allows referencing functions from other files.


### import


`import` keyword allows to access functions not defined in the current file.
Any call to a function or tuple outside requires a prior `import` statement.


```
// file: src/my_fun.prp
pub let fun1    = {|a,b|  }
pub let fun2    = {|a|
  pub let inside = {|| }
}
pub let another = {|a|  }

pub let mytup = (
  ,call = {|| puts "call called" }
)
```

```
// file: src/user.prp
a = import "my_fun/*fun*"
a.fun1(a=1,b=2)         // OK
a.another(a=1,2)        // compile error, 'another' is not an imported function
a.fun2.inside()         // compile error, `inside` is not in top scope

x = import "my_fun/mytup"

x.call()                // prints call called
```

The `import` points to a file [setup code](06b-instantiation.md#setup-code)
list of pub variables or types. The setup code corresponds to the "top" scope
in the imported file. The import statement can only be executed during the
setup phase. The import allows for cyclic dependencies between files as long as
there is no true cyclic dependency between variables. This means that "false"
cyclic dependencies are allowed but not true ones.


The import is delayed until the imported variable is used in the local file.
There is no order guarantee between imported files, just that the code needed
to compute the used imported variables is executed before.


All the variables at the top scope declared with `pub` are visible to the
`import` statement. The import is by value, this means that it creates a "copy"
of the variables imported.

```
pub fun1 = {|| }        // visible for import
pub fun2 = {||          // visible for import
   pub fun2_1 = {|| }   // visible for import
   if cond {
     pub fun2_2 = {|| } // not visible (if scope)
   }
}
{
  pub fun3 = {|| }      // not visible (scope)
}
```

The import statement is a filename or path without the file extension.
Directories named `code`, `src`, and `lib` are skipped. No need to add them in
the path. `import` stops the search on the first hit. If no match happens, a
compile error is generated.


`import` allows specialized libraries per subproject.  For example, xx/yy/zz can
use a different library version than xx/bb/cc if the library is provided by yy,
or use a default one from the xx directory.

```
a = import "prj1/file1"
b = import "file1"        // import xxx_fun from file1 in the local project
c = import "file2"        // import the functions from local file2
d = import "prj2/file3"   // import the functions from project prj2 and file3
```

Many languages have a "using" or "import" or "include" command that includes
all the imported functions/variables to the current scope. Pyrope does not
allow that, but it is possible to use a mixin to add the imported functionality
to a tuple.

```
b = import "prp/Number"
a = import "fancy/Number_mixin"

type Number = b ++ a // patch the default Number class

var x:Number = 3
```

### punch

The `punch` statement allows accessing registers, inputs, and outputs from other
instantiated modules.

Verilog has a somewhat similar semantics with the Hierarchical Reference. It
also allows to go through the module hierarchy and read/write the contents of a
variable. It is not popular for 2 main reasons: (1) It is considered "not nice"
to bypass the module interface and touch an internal variable; (2) some tools
do not support it as synthesizable.


Pyrope benefits more than Verilog from the `punch`  because it allows to punch
tuples (SystemVerilog does not allow to punch classes that do not tend to be
synthesizable anyway). Also Pyrope `punch` allows relative hierarchy reference.

Without a `punch`, the tuple could be passed in the input/outputs, but since
everything is passed by value, it will create a copy. It would not be possible
to have a memory, and then use methods to update/read the memory contents
across modules. This will be very counterintuitive for most programmers[^4].


[^4]: Although it is the thing that most Verilog coding guidelines force you to do.


The punch is a superset of these 3 different sets of tools:

* Verilog hierarchical reference. Like Verilog hier, `punch` allows to access
  variables through the hierarchy. A difference in Pyrope is that only `pub`
  registers or undriven inputs are accessible.

* Soft connections and CHISEL boring utils allow to define of a unique identifier
  and connects between the IDs. Punch also has this capability by building a
  tuple that provides name registration.

* A reference/pointer to an object. Import will create a copy, passing through
  value will create a copy too. Punch behaves like a pointer or reference to a
  remote instance. It could be seen as a pointer, but it can not pass the
  pointer. You must "find" the pointer either through the hierarchy or with a
  unique identifier.


```
// file remote.prp
punch uart_addr from "MY_ADDR" // compile error, setup code
pub let uart = {||
  punch uart_addr from "MY_ADDR" // compile error, setup code
  assert uart_addr == 300
}

// file local.prp
pub let setup_xx = {||
  punch xx to "MY_ADDR"     // creates a var that drives remote uart_addr
  xx = 300                  // sets uart_addr to 300
}
```

The `punch` connects through the hierarchy, as such, `punch` can not be called during
the setup phase because the hierarchy is still unknown. `punch` is only allowed
during reset or execution phase.


Maybe the best way to understand the `punch` is to see the differences with the `import`:

* Instantiation vs File hierarchy
  + `punch` traverses the instantiation hierarchy to find matches.
  + `import` traverses the file/directory hierarchy to find matches.
* Success vs Failure
  + `punch` keeps going to find all the matches, and it is possible to have a zero matches
  + `import` stops at the first match, and a compile error is generated if there is no match.
* Regex vs file path
  + `punch` uses a more powerful regex to match the instance hierarchy.
  + `import` uses a simple file/function names skipping some keywords (code,src,lib).
* Setup phase
  + `punch` can not be called during setup phase because hierarchy does not
    exist.
  + `import` can be called during setup, execution, and reset phases.
+ Conditionally executed
  + `punch` can no be conditionally executed. Connecting or punching is done or
    not, but it can not be based on a run-time condition.
  + `import` can happen inside a runtime condition.


```
let some = {||
  if runtime {
    let pi = import "math.PI" // OK
    puts "PI is {}", pi

    punch v to "foo/bar"      // compile error, punch must be unconditional
  }
  punch v to "foo/bar"        // OK
}

punch v to "foo/bar"          // compile error, punch not in the setup phase
```

The instantiation hierarchy looks like a tree with a root at the top function.
Given an instantiation hierarchy, the tree traversal starts by visiting all the
children, then the parents.  The traversal is similar to a post-order tree
traversal, but not the same. The post-order traversal visits a tree node once
all the children are visited. The `punch` traversal visits a tree node once all
the children AND niblings (niece of nephews from siblings) are visited.


For example, given this tree hierarchy. If the punch is called from `1/2/1` node,
it will visit nodes in this order:

```txt
            +── 1/2/1/3/1   // 5th
            |── 1/2/1/3/2   // 4th
        +── 1/2/1/1         // 3th
        ├── 1/2/1/2         // 2nd
        |── 1/2/1/3         // 1st
    +── 1/2/1               // START <--
    |   +── 1/3/1/1         // 7th
    |   |── 1/3/1/2         // 8th
    ├── 1/3/1               // 9th
    ├── 1/3/2               // 10th
    ├── 1/3/3               // 11th
    │   -── 1/4/2/1         // 12th
    |   |── 1/4/3/1         // 13th
    ├── 1/4/1               // 14th
    ├── 1/4/2               // 15th
    ├── 1/4/3               // 16th
+── 1/1                     // 17th
├── 1/2                     // 20th
├── 1/3                     // 21st
├── 1/4                     // 22nd
| 1                         // LAST
```

There are two variations of the `punch` command, one that creates inputs to the
current module (`punch ... from ...`) and the other that creates outputs
(`punch ... to ...`). `punch variable from ...` is to indicate `variable` must
be driven remotely by some `punch ... to`. `punch variable to ...` can only
connect `variable` to any `punch ... from...` or undriven registers or undriven
lambda inputs.


```
pub let mod2 = {||
  punch a to "module1/mod2/foo"

  punch b to "uart_addr" // any module that has an input $uart_addr
  b[0] = 0x100
  b[1] = 0x200

  punch b to "foo.*/uart_addr" // modules named foo.* that have uart_addr as input

  punch c from "bar/some_output"
  punch d from "bar/some_register"
}
```

### Mocking library

One possible use of the `punch` command is to create a "mocking" library. A
mocking library instantiates a large design but forces some subblocks to
produce some results for testing. The challenge is that `punch` needs undriven,
but the testing library can use the `peek`/`poke` to overwrite an existing
value. The peek/poke use the same reference as `punch`.

```
type bpred = ( // complex predictor
  ,pub let taken = {|| ret some_table[som_var] >=0 }
)

test "mocking taken branches" {
  poke "core.fetch.bpred.taken", true

  var l = core.fetch.predict(0xFFF)
}
```


Nevertheless, the `punch` must be unconditional. An alternitive allowed only
during testing is the `poke`/`peek` statements.

## Operator overloading

There is no operator overload in Pyrope. `+` always adds Numbers, `++`
always concatenates a tuple or a String, `[]` indexes a tuple.


## Properties: Getter/Setter

The getter/setter allow to have properties for each variable. The setter
is also the "constructor" for the object.


```
var f1:XXX = 3,2
var f2:XXX = XXX(3,2)
var f3:XXX

f3 = 3,2
assert f3 == f2 == f1
```

Encapsulation can be achieved with explicit methods (initialize/setXXX/getXXX).
This creates problems with overloading or exposing variables. It is possible to
create a tuple where the initialization is the setter (`set`) and the default
method is the getter (`get`).


```
type some_obj = (
  ,a1:string
  ,pub a2 = (
    ,_val:u32                            // hidden field

    ,pub var get={|| self._val + 100 }   // getter
    ,set={|x| self._val = x+1 }          // setter
  )
  ,pub var set = {|a,b|                  // setter
    self.a1      = a
    self.a2._val = b
  }
)

var x:some_obj = "hello", 3

assert x.a1 == "hello"
assert x.a2 == 103
x.a2 = 5
assert x.a2.get == 106
```


The getter method can be [overloaded](06-functions.md#Overloading). This allows
to customize by return type:

```
type showcase = (
  ,pub var v:int
  ,pub var get ++= {|(self)->(self,:string) where self.i>100|
    ret "this is a big number" ++ string(v)
  }
  ,pub var get ++= {|(self)->(self,:int)|
    ret v
  }
)

var s:showcase
s.v = 3
let foo:string = s // compile error, no matching getter
s.v = 100

let foo:string = s // compile error, no matching getter
```

Like all the lambdas, the getter method can also be overloaded on return type.
In this case it allows to build typecast per type.

```
type my_obj = (
  ,val:u32
  ,pub var get 
    = {|()->:string | ret string(self.val) }
   ++ {|()->:boolean| ret self.val != 0    }
   ++ {|()->:int    | ret self.val         }
)
```

## Compare


The comparator operations (`==`, `!=`, `<=`,...) need to be overloaded for most
objects. Pyrope has the `lt` and `eq` methods to build all the other
comparators. When non-provided the `lt` (Less Than) is a compile error, and the
`eq` (Equal) compares that all the tuple fields are equal.


```
type t=(
  ,pub var v
  ,pub let set = {|a| self.v = a }
  ,pub let lt = {|other| self.v  < other.v }
  ,pub let eq = {|other| self.v == other.v }
)

var m1:t = 10
var m2:t = 4
assert m1 < m2 and !(m1==m2)
assert m1 <= m2 and m1 != m2 and m2 > m1 and m2 >= m1
```


It is also possible to provide a custom `ge` (Greater Than). The `ge` is redundant
with the `lt` and `eq` (`(a >= b) == (a==b or b<a)`) but it allows to have more
efficient implemetations:


* `a == b` is `__eq(a,b)`
* `a != b` is `__not(__eq(a,b))`
* `a  < b` is `__lt(a,b)`
* `a  < b` is `__lt(b,a)`
* `a <= b` is `__lt(a,b) | __eq(a,b)` (without `ge`) or `__ge(b,a)`
* `a >= b` is `__lt(b,a) | __eq(a,b)` (without `ge`) or `__ge(a,b)`


