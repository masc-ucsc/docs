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
assignment, the type checks that the left-hand side (LHS) has a compatible type with
the right-hand side (RHS) of the expression. Additional type checks happen when
variables have a type check explicitly set (`var:type`) in the rhs expression.


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



While the `var` statement declares a new variable instance that can also have
an associated type, the `type` statement declares a type without any instance.

```
type a1 = u32                 // same as 'type a1:u32'
type a2 = int(max=33,min=-5)  // same as 'type a2:int(-5,33)'
type a3 = (
    ,var name:string
    ,var age:u8
    )
```

The puts command understands types.

```
type at=int(33..)     // number bigger than 32
type bt=(
  ,var c:string
  ,var d=100
  ,let set = fun(ref self, ...args) { self.c = args }
)

var a:at=40
var v:bt="hello"
puts "a:{} or {}", a, at // a:40 or 33
puts "b:{}", b           // b:(c="hello",d=100)
```

### Type equivalence


The `does` operator is the base to compare types. It follows structural typing rules. 
These are the detailed rules for the `a does b` operator depending on the `a` and `b` fields:


* false when `a` and `b` are different basic types (`boolean`, `fun`,
  `integer`, `proc`, `range`, `string`, `enums`).

* true when `a` and `b` are `boolean` or `string`.

* true when `a` and `b` are `enum` and `a` has all the possible enumerates
  fields in `b` with the same value.

* `a.max>=b.max and a.min<=b.min` when `a` and `b` are integers

* `(a@[] & b@[]) == b@[]` when `a` and `b` are `range`. This means that the `a`
  range has at least all the values in `b` range.

* There are two cases for tuples. If all the tuple entries are named, `a does
  b` is true if for all the root fields in `b` the `a.field does b.field`.
  When either `a` or `b` have unnamed fields, for each field in `b` the name
  and also position should match. The conclusion is that if the field has no name, only position should match.

* `a does b` is false if the explicit array size of `a` is smaller than the explicit array size of `b`. If the size check is true, the array entry type is checked. `:x[] does :y[]` is false when `x does y` is false.

* The lambdas have a more complicated set of rules explained later. It
  distinguishes between lambda call and lambda reference.

```
assert     (a:int(max=33,min=0) does (a:int(20,5)))
assert not (a:int(max=33,min=0) does (a:int(50,5)))

assert     (a:string,b:int) does (a:"hello", b:33)
assert not ((b:int,a:string) does (a:"hello", b:33)) // order maters in tuples

assert      :fun(x,xxx2)->(y,z) does :fun(x     )->(y,z)
assert not (:fun(x     )->(y,z) does :fun(x,xxx2)->(y,z))
```

For named tuples, this code shows some of the corner cases:

```
type t1 = (a:string, b:int)
type t2 = (b:int, a:string)

var a:t1  = ("hello", 3)     // OK
var a1:t1 = (3, "hello")     // compile error, positions do not match
var b:t1  = (a="hello", 3)   // OK
var b1:t1 = (3, a="hello")   // compile error, positions do not match
var c:t1  = (a="hello", b=3) // OK
var c1:t1 = (b=3, a="hello") // OK

var d:t2 = c                 // OK, both fully named
assert d.0 == c.1 and c.0 == d.1
assert d.a == c.a and d.b == c.b
```

Ignoring the value is what makes `equals` different from `==`. As a result
different functionality functions could be `equals`.

```
let a = fun() { ret 1 }
let b = fun() { ret 2 }
assert a equals :fun()
assert a != b
assert a equals b
assert not (a equals fun() { ret 1 }) // different arguments
```


## Nominal type check


Pyrope has structural type checking, but there is a keyword `is` that allows to
check that the type name matches `a is b` returns true if the type of `a` has
the same name as the type of `b`. This can be used in places like function
calls to check that the type name matches. Instrad of `v:tp`, Pyrope also
accepts `v is tp`. `:` checks that `v` has structural type compatible with
`tp`. `is` checks that `v` has exactly the type `tp`.

```
type X1 = (b:u32)
type X2 = (b:u32)

let t1 = (b=3):X1  // OK
let t2 = (b=3):X2  // OK
let t3 = (b=3) is X2  // compile error
let t4:X1 = (b=3)

y1 = t4:X1    // OK
y2 = t4:X2    // OK
y3 = t4 is X1 // OK
y4 = t4 is X2 // compile error
```

## Enums with types

Enumerates (enums) create a number for each entry in a set of identifiers. Pyrope
also allows associating a tuple or type for each entry. Another difference from a
tuple is that the enumerate values must be known at compile time.


```
type Rgb = (
  ,let c:u24
  ,let set = proc(ref self, c) { self.c = c }
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


## union

Union shares syntax with enums with types declaration, but the usage and
functionality is quite different. Enums do not allow to update values and
unions are tuples with multiple labels sharing a single storage location. Since
the `union` holds values, it can be used to explicitly convert between field
types.


```
enum  e_type = (str:String = "hello",num=22)
union u_type = (str:String, num:int)         // No default value in union

var uu:u_type = (str="hello2")
assert uu.str == "hello2"
assert uu.num == 0x32_6f_6c_6c_65_68 // ASCII for 2 e l l o h

uu.num = 0x65
assert uu.str == "o"
assert uu.num == 0x65
var ee:e_type
```


As a reference, `enums` allow to compare for field but not update enum entries.

```
ee = u_type.String          // OK
ee.str = "new_string"       // compile error, enum is immutable

match ee {
 == e_type.str { }
 == e_type.num { }
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
the input/output size, but narrowing allows it to work without typecasts.  To
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

The bitwidth pass may not converge to find a valid size even with narrowing.
In this case, the programmer must insert a typecast or operation to constrain
the bitwidth by typecasting. For example, this could work:

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
  ,let set = proc (ref self, x:at) { self.d = x.d ; self.c = x.c }
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
  ,let say = fun(s) { puts s }
)

type Say_hi_mixin = (
  ,let say_hi  = fun() {self.say("hi {}", self.name) }
  ,let say_bye = fun() {self.say("bye {}", self.name) }
)

type User = (
  ,var name:string
  ,let set = proc(ref self, n:string) { self.name = n }
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
  ,area         :fun (self )->(:i32)     // defined but unimplemented 
  ,increase_size:proc(ref self, x:i12)   // defined but unimplemented 

  ,set =proc(ref self, name ) { self.name = name } // implemented, use =
)

type Circle extends Shape with (
  ,set = proc(ref self) { super("circle") }
  ,increase_size = proc(ref self, x:i12) { self.rad *= x }
  ,rad:i32
  ,area = fun(self) -> (:i32) {
     let pi = import("math").pi
     ret pi * self.rad * self.rad
  }
)
```

Like most type checks, the `extends` can be translated for a `comptime
assert`. An equivalent "Circle" functionality:

```
type Circle = (
  ,rad:i32
  ,name = "Circle"
  ,area = fun() -> (:i32) {
     let pi = import("math").pi
     ret pi * self.rad * self.rad
  }
  ,increase_size = proc(ref self, a:i12) { self.rad *= a }
)
comptime assert Circle does Shape
```

The `extends` differs from a tuple concatenation (`++` or `...tup`) by
checking that the base methods are implemented. It can be seen as a syntax
sugar for `...tup` and a compile time `does` type check.


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
let fu = fun(a,b=2) -> (c) where a>10 { c = a + b }
assert fu.__inp equals (a,b)
assert fu.__out equals (c)
assert fu.__where(a=200) and !fu.__where(a=1)
```

This means that when ignoring named vs unnamed calls, overloading behaves like
this:

```
let x = fn(args)

let x = for i in fn { last i(args) when (i.__inp does :args) 
                                    and (i.__out does :x   ) 
                                    and (i.__where(args)   ) }
```

There are several uses for introspection, but for example, it is possible to build a
function that returns a randomly mutated tuple.

```
randomize = debug fun(ref self) {
  let rnd = import "prp/rnd"
  for i in ref self {
    if i equals :int {
      i = rnd.between(i.__max,i.__min)
    }elif i equals :boolean {
      i = rnd.boolean()
    }
  }
  ret self
}

let x = (a=1,b=true,c="hello")
let y = x.randomize()

assert x.a==1 and x.b==true and x.c=="hello"
cover  y.a!=1
cover  y.b!=true
assert y.c=="hello"  // string is not supposed to mutate in randomize()
```


## Global variables

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
pub let fun1    = fun(a,b) { a+b }
pub let fun2    = fun(a) {
  pub let inside = fun() { ret 3 }
  ret a
}
pub let another = fun(a) { ret a }

pub let mytup = (
  ,pub let call3 = fun() { puts "call called" }
)
```

```
// file: src/user.prp
a = import "my_fun/*fun*"
a.fun1(a=1,b=2)         // OK
a.another(a=1,2)        // compile error, 'another' is not an imported function
a.fun2.inside()         // compile error, `inside` is not in top scope variable

let fun1 = import "my_fun/fun1"
lec fun1, a.fun1

x = import "my_fun/mytup"

x.call3()                // prints call called
```

The `import` points to a file [setup code](06b-instantiation.md#setup-code)
list of pub variables or types. The setup code corresponds to the "top" scope
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

### Register reference


While import "copies" the importent contents, `regref` or Register reference
allows to reference (not copy) an existing register in the call hierarchy.


The syntax of `regref` is similar to `import` but import looks through Pyrope
files. `regref` looks through the instantiation hierarchy for matching register
names. `regdef` only can get a reference to a register, it can not be used to
import functions or variables.


```
let do_increase = proc() {
  reg counter

  wrap counter:u32 = counter + 1
}

let do_debug = proc() {
  let cntr = regref "do_increase/counter"

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
reg uart_addr:u32
assert 0x400 > uart_addr >= 0x300

// file local.prp
pub let setup_xx = proc() {
  let xx = regref "uart_addr"
  for i,index in ref xx {    // ref in for to allow element updates
    i = 0x300+index*0x10     // sets uart_addr to 0x300, 0x310, 0x320...
  }
}
```


Maybe the best way to understand the `regdef` is to see the differences with
the `import`:

* Instantiation vs File hierarchy
  + `regref` finds matches across instantiated registers.
  + `import` traverses the file/directory hierarchy to find one matche.
* Success vs Failure
  + `regref` keeps going to find all the matches, and it is possible to have a zero matches
  + `import` stops at the first match, and a compile error is generated if there is no match.


### Mocking library

One possible use of the register reference is to create a "mocking" library. A
mocking library instantiates a large design but forces some subblocks to
produce some results for testing. The challenge is that it needs undriven
registers. During testing, the `peek`/`poke` is more flexible and it can
overwrite an existing value. The peek/poke use the same reference as `import`
or register reference.

```
type bpred = ( // complex predictor
  ,pub let taken = fun(){ ret self.some_table[som_var] >=0 }
)

test "mocking taken branches" {
  poke "bpred_file/taken", true

  var l = core.fetch.predict(0xFFF)
}
```

## Operator overloading

There is no operator overload in Pyrope. `+` always adds Numbers, `++`
always concatenates a tuple or a String, `[]` indexes a tuple.


## Properties: Getter/Setter

The getter/setter allow to have properties for each variable. The setter
is also the "constructor" for the object.


```
var f1:XXX = (3,2)
var f2:XXX = XXX(3,2)
var f3:XXX

f3 = (3,2)
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
    ,_val:u32                                  // hidden field

    ,pub var get=fun(self) { self._val + 100 } // getter
    ,set=proc(ref self, x) { self._val = x+1 } // setter
  )
  ,pub var set = proc(ref self, a,b){          // setter
    self.a1      = a
    self.a2._val = b
  }
)

var x:some_obj = ("hello", 3)

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
  ,pub var get ++= fun(self)->(:string) where self.i>100 {
    ret "this is a big number" ++ string(v)
  }
  ,pub var get ++= fun(self)->(:int) {
    ret v
  }
)

var s:showcase
s.v = 3
let foo:string = s // compile error, no matching getter
s.v = 100

let foo:string = s // compile error, no matching getter
```

Like all the lambdas, the getter method can also be overloaded on the return type.
In this case, it allows building typecast per type.

```
type my_obj = (
  ,val:u32
  ,pub var get 
    = fun(self)->(:string ){ ret string(self.val) }
   ++ fun(self)->(:boolean){ ret self.val != 0    }
   ++ fun(self)->(:int    ){ ret self.val         }
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
  ,pub let set = proc(ref self) { self.v = a }
  ,pub let lt = fun(self,other)->(:boolean){ self.v  < other.v }
  ,pub let eq = fun(self,other)            { self.v == other.v } // infer ret
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


## Non-Pyrope (C++) calls

Calling C++ or external code is still fully synthesizable if the code is
available at compile time. An example could be calling a C++ API to read a json
file during the setup phase to decide configuration parameters.


```
let cfg = __read_json()

pub let ext = if cfg.foo.bar == 3 {
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
type __my_typed_cpp = fun(a,b)->(e)
```

Type defining non-Pyrope code is good to catch errors and also because declaring
`function` allows to handle several cases of circular dependencies not possible with `procedure` [import section](10-internals.md)

