# Type system

Type system assign types for each variable (type synthesis) and check that each
variable use/expression respect the allowed types (type check). Additionally, a
language can also use the type synthesis results to implement polymorphism.


Most HDLs do not have modern type systems, but they could benefit like in other
software domains. Unlike software, in hardware we do not need to have many integer
size because hardware can implement any size. This simplifies the type system
allowing unlimited precision integers but it needs a bitwidth inference mechanism.


Additionally, in hardware it makes sense to have different implementations that
adjust for performance/constrains like size, area, FPGA/ASIC. Type systems
could help on these areas.


## Types vs `comptime assert`

To understand the type check, it is useful to see an equivalent `comptime
assert` translation. The type system has two components: type synthesis and
type check. The type check can be understood as a `comptime assert`.


After type synthesis, each variable has an associated type. In Pyrope, each
assignment, the type checks that the left hand side (lhs) has the same type as
the right hand side (rhs) of the expression. Additional type checks happen when
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
constrains from the type system. Pyrope type system constructs to handle types:

* `type` keyword allows to declare types.

* `a does b`: Checks 'a' is a superset or equal to 'b'. In the future, the
  unicode character "\u02287" could be used as an alternative to `does` (`a`
&#8839 `b`). The 

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

While `var` statement declares a new variable instance which can also have an
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
type at:int=33..     // number bigger than 32
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
entries are ignored, but the type of the entry is considered.

```
assert      (a=3     ,:string) does (a:int,"hello")
assert      (a={3}   ,:string) does (a:int,"hello")
assert not ((a=3     ,:string) does (b:int,"hello"))
assert not ((a="foo" ,:string) does (a:int,"hello"))
assert not ((a={|| 3},:string) does (a:int,"hello"))
```

The `does` keyword checks that functions have a "compatible" arguments.

```
assert      {||    3 } does {|(a)| 3 }
assert not ({|(a)| 3 } does {|(a)| 3 })

assert not ({|(a,b)| 3 } does {|(a)   3})
assert not ({|(a)|   3 } does {|(a,b) 3})

assert     ({|(a)|     3 } does {|(a:string) 3})
assert not ({|(a:int)| 3 } does {|(a:string) 3})
```

Ignoring the value is what makes `equals` different from `==`. As a result
different functionality functions could be `equals`. 

```
a = {|| return 1 }
b = {|| return 2 }
assert a equals {|| }
assert a != b
assert a equals b
assert a not equals {|(x)| return 1 } // different arguments
```

Some languages use an `is` keyword but Pyrope uses `does` or `equals` because
in English "a is b" is not clear ("a is same as b" vs "a is subtype of b"). 

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

Enums can handle complex types:

```
type Rgb = (
  ,let color:u24
  ,let set = {|(self,x)->(self)| self.color = x:u24 }
)

enum Color:Rgb = (
  ,Yellow   = 0xffff00
  ,Red:Rgb  = 0xff0000      // alternative redundant syntax
  ,Green    = Rgb(0x00ff00) // alternative redundant syntax
  ,Blue:Rgb = Rgb(0x0000ff) // alternative redundant syntax
)


var y:Color = Color.Red
if y == Color.Red {
  puts "c1:{} c2:{}\n", y, y.color  // prints: c1:Color.Red c2:0xff0000
}
```

## Bitwidth

Integers can be constrained based on the maximum and minimum value (not by
number of bits).

Pyrope automatically infers the maximum and minimum value for each numeric
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

val := 0x1F0       // Drop bits from 0x1F0 to fit in maximum 'val' allowed bits
assert val == 240

val = u8(0x1F0)    // same
assert val == 0xF0

val = :val(0x1F0)  // same
assert val == 0xF0
```

External libraries could be created to handle saturated operations. E.g:

```pyrope
saturated = {||
  if $1 > $0.__max {
    return $0.__max
  }elif $1 < $0.__min{
    return $0.__min
  }else{
    return $1
  }
}
  
var v:u8
v = v.saturated(1+300)  // 255
```

Pyrope leverages LiveHD bitwidth pass [stephenson_bitwidth] to compute the maximum and minimum
value of each variable. For each operation, the maximum and minimum is computed. For control
flow divergences, the worst possible path is considered.

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
understand, the commens show the max/min bitwidth computations.

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
x:cmd.a := x  // use cmd.a type for x, and drop bits as needed
y = cmd.b(y)  // typecast y to cmd.b type (this can add a mux)
```

## Typecasting


Typecasting is the process of changing from one type to other. The Number/int
type  allows to specify the maximum/minimum value per bit, this is not
considered a new type.  Since bitwidth pass adjust/computes the maximum/minimum
range for each Number type, as long as precision is not lost, type casting
between Numbers is done automatically.


When the precision can not be preserved in a Number, a `:=` or a typecast could
be used.  The `lhs := rhs` statement drops the bits in the `rhs` to fit on the
`lhs`. An alternative method to typecase is to call the constructor, for the Number
class, this does not drop bits, but keeps the maximum/minimum allowed value.

```
var a:u32=100
var b:u10
var c:u5
var d:u5

b = a     // OK done automatically. No precision lost
c = a     // compile error, '100' overflows the maximum allowed value of 'c'
c:= a     // OK, same as c = a@[0..<5] (Since 100 is 0b1100100, c==4)
c = u5(a) // OK, c == 31
c = 31
d = c + 1 // compile error, '32' overflows the maximum allowed value  of 'd'
d:= c + 1   // OK d == 0
d = u5(c+1) // OK, d==31
d = :d(c+1) // OK, d==31
```

To convert between tuples, a explicit typecast is needed unless all the tuple
fields match and field can be automatically typecasted without loss of precision.

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
  ,let set = {|mut (self,x:at)| self.d = x.d ; self.c = x.c }
  ) // different order

var b:bt=(c="hello", d=10000)
var a:at

a = b // OK c is string, and 10000 fits in u32

var c:ct
c = a // compile error, different order

var d:dt
d = a // OK, call intitial to type cast
```


## Traits and mixin

There is no object inheritance in Pyrope, but tuples allow to build mixin and composition with traits.

A mixin is when an object or class can add methods and the parent object can access them. In several languages
there are different constructs to build them (E.g: an include inside a class in Ruby). Since Pyrope tuples
are not immutable, new methods can be added like in mixin.

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
  ,let set = {|mut (self,n:string)| self.name = n }
)

type Mixing_all = Say_mixin ++ Say_hi_mixin ++ User

var a:Mixing_all("Julius Caesar")
a.say_hi() 
```

Mixin are very expressive by allowing to redefine methods. If two tuples have
the same field a tuple with the concatenated values will be created. This is
likely an error with basic types but useful to handle explicit method overload.


In a way, mixin just adds methods from two tuples to create a new tuple. In
programming languages with object oriented programming (OOP) there are many
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
concatenated with `++` the methods are overrided when declared with `var`.
Neither is the expected solution.  A smaller issue with mixins is that
`comptime assert X implements Y` should be inserted when implementing an
interface.


Without supporting OOP, but providing a more familiar abstract or trait
interface, Pyrope provides the `implements` keyword. It checks that the new
type implements the functionality undefined and allows to use methods defined.
The constructor (`set`) can call the parent constructor with the `super` keyword.

This is effectively a mixin with checks that some methods should be
implemented.

```
type Shape = (
  ,name:string
  ,area          = {|    (self,     )->:i32  |}
  ,increase_size = {|mut (self,_:i12)->(self)|} // same as {|mut| assert $1:i12}
  ,set           = {|mut name| self.name = name }
)

type Circle = implements Shape with (
  ,set = {|mut | super("circle") }
  ,increase_size = {|mut (self,_:i12)| self.rad *= $1 }
  ,rad:i32
  ,area = {|(self) -> :i32   |
     let pi = import "math.pi"
     return pi * self.rad * self.rad
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
     let pi = (import "math").pi
     return pi * self.rad * self.rad
  }
  ,increase_size = {|mut (self,_:i12)| self.rad *= $1 }
)
comptime assert Circle does Shape
```

Another way to have the same functionality as the implements is to use the conditional
type system.

```
type x1 = implements yyy with zzz               // use implements keyword

type x2 = if yyy does zzz { zzz  }else{ nil }   // use conditional typing

comptime assert x1 equals x2
```

## Explicit function overloading

Pyrope has types and functions. There is also function overloading, but unlike
most languages it has explicit function overloading.  With explicit, the
programmer sets an ordered list of methods, and the first that satisfies the
type check is called. The check to decide if a function satisfies is `does`. Specifically, 
it checks if the function definition argument types  do the calling argument.

```
bool_to_string = {|(b:boolean) -> :string| if b { "true" } else { "false" } }
int_to_string  = {|(b:int)     -> :string| }

to_string = bool_to_string ++ int_to_string
let s = to_string(3)
```

Since functions allow instrospect, the previous `to_string(3)` call approximately behaves like:

```
for i in to_string {
  if i.inputs does 3 {
    i(3)
    break
  }
}
```

Liquid types or logically qualified types further constraint some types. In a
way, the maximum/minimum constrain on numbers is already a logically qualified
constrain, but Pyrope allows a `where` keyword when building function types.

Types must be decided at compile time. Some times like in the maximum/minimum
range, the estimation can be conservative. The `where` keyword can use compile
time conditions, but it can also use run-time decisions like values on the
inputs.

When combined with liquid types, it is possible to specialize the functionality
based on targets and/or functionality. Like in the adder example:

```
add_plus_one = {|(a,b) where b == 1 or a == 1|}
fast_csa     = {|(a,b) where min(a.__sbits, b.__sbits)>40|}
default_adder= {|(a,b)|}

my_add = add_plus_one ++ fast_csa ++ default_adder

assert $foo.__sbits < 10   // foo has less than 10 bits
assert $bar.__sbits > 40   // bar has more than 40 bits

result = my_add($foo,$foo) // calls default_adder
result = my_add($bar,$bar) // calls fast_csa
result = my_add($foo,1)    // calls add_plus_one
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

Function definitions allocate a tuple, which allows to instrospect the
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

let x = for i in fun { break i(args) when (i.inputs does args) and i.where(args) }
```


There are several uses for instrospection, but for example it is possible to build a
function that returns a randomly mutated tuples.

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
  return self
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
`import` statement allows to reference functions from other files.


### import


`import` keyword allows to access functions not defined in the current file.
Any call to a function or tuple outside requires a prior `import` statement.


```
// file: src/my_fun.prp
pub fun1    = {|a,b|  }
pub fun2    = {|a|
     pub inside = {|| }
  }
}
pub another = {|a|  }

pub mytup = (
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


All the variables at the top scope declared with `pub` are visible to the
`import` statement. The import creates a "copy" of the variable. This means
that if the imported variable can not be modified from the importing file.

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

The import statement uses a shell like file globbing.

* `*` matches zero or more characters
* `?` matches exactly one character

The globbing starts at the current directory, and keeps trying upper
directories until it reaches the project root. Directories named `code` or
`src` are skipped. No need to add them in globbing pattern. It stops the search
on the first hit. If no match happens, a compile error is generated. 


Globbing search pattern allows to have specialized libraries per subproject.
For example xx/yy/zz can use a different library version than xx/bb/cc if the
library is provided by yy, or use a default one from the xx directory.

```
a = import "prj1/file?/*something*"
b = import "file1/xxx_fun"   // import xxx_fun from file1 in the local project
c = import "file2"           // import the functions from local file2
d = import "prj2/file3"      // import the functions from project prj2 and file3
```

Many languages have a "using" or "import" or "include" command that includes
all the imported functions/variables to the current scope. Pyrope does not
allow that, but it is possible to use mixin to add the imported functionality
to a tuple.

```
b = import "prp/Number"
a = import "fancy/Number_mixin"

type Number = b ++ a // patch the default Number class

var x:Number = 3
```

#### Import properties

* The `import` statement must be assigned to a variable.
* The `import` statement can use a typical file globbing that traverses
  directories to find a match or the project root.
* Imported only allows to import top level defined functions. This means that
  nested functions can not be imported, and that imported functions can not be
  re-imported.

### punch

The `punch` statement allows to access variables from other modules. It can be
seen as an `import` but only applicable to read/write variables instead of
functions. In some systems it is known as soft connections.

Maybe the best way to understand the `punch` is to see the differences with the `import`:

* variables vs functions
  + `punch` connects variables (inputs,outputs,registers) which create wires between functions/modules. 
  + `import` brings or copies functions.
* Instantiation vs File hierarchy
  + `punch` traverses the instantiation hierarchy to find matches.
  + `import` traverses the file/directory hierarchy to find matches.
* Succcess vs Failure
  + `punch` keeps going to find all the matches, and it is possible to have a zero matches
  + `import` stops at the first match, and a compile error is generated if there is no match.
* Regex vs Globbing
  + `punch` uses a more powerful regex to match instance hierarchy.
  + `import` uses a simple globbing to match file/function names.


The instantiation hierarchy looks like a tree with a root at the top function.
Given a instantiation hierarchy, the tree traversal starts by visiting all the
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
current module (`punch_from`) and the other that creates outputs (`punch_to`).
`punch_from` can connect to any flop or module output, `punch_to` can only
connect to undriven nets in flops or inputs.

The modifier (`$`,`%`,`#`) does not need to be included in the search. As a
result of connecting through the hierarchy instantiation, the `punch` command
will add input/outputs through the hierarchy, The left hand side can be an
input (`$`) for `punch_from`, an output (`%`) for `punch_to`. In both cases, it
can be a local variable but effectively it will show in the input or output
tuple. The regex can include tree hierarchy. E.g:

```
%a = punch_to "module1/mod2/foo"

%b = punch_to "uart_addr" // any module that has an input $uart_addr
%b[0] = 0x100
%b[1] = 0x200

%b = punch_to "foo.*/uart_addr" // modules named foo.* that have uart_addr as input

$c = punch_from "bar/some_output"
$d = punch_from "bar/some_register"
```


## Operator overloading

There is no operator overload in Pyrope. `+` always adds Numbers, `++`
always concatenates a tuple or a String, `[]` always indexes a tuple.


## Getter/Setter

The only thing that looks like operator overload (but it is not) is the `=`
because it can be used to initialize objects.

```
var f1:XXX = 3,2
var f2:XXX = XXX(3,2)
Var f3:XXX

f3 = 3,2
assert f3 == f2 == f1
```


Encapsulation can be achieved with methods, but to have a more familiar
getter/setter syntax, it is possible to create a tuple where the
initialization is the setter (`set`) and the default method is the getter
(`get`). 


```
type some_obj = (
  ,a1:string
  ,a2 = (
    ,get={|| self._val + 100 }       // getter
    ,_val:u32                        // hidden field
    ,set={|mut x| self._val = x+1 }  // setter
  )
  ,set = {|mut a,b|
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

