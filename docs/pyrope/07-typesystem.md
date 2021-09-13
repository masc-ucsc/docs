# Type system

Type systems are quite similar to sets. A main difference is that type systems
may not be as accurate as a set system, and it may not allow the same
expressiveness because some type of set properties may not be allowed to be
specified. 


Most HDLs do not have modern type systems, but they could benefit like in other
software domains. Additionally, in hardware it makes sense to have different
implementations that adjust for performance/constrains like size, area,
FPGA/ASIC. Type systems could help on these areas.


## Types vs `comptime assert`

Pyrope has support for different types of assertions (`assert`, `comptime
assert`, `assume`, `comptime assume`, `verify`).  The type system checks, not
the function overloading, can be translated to a set of `comptime assert`
statements. Pyrope type checks can be translated to compile time assertion
checks, but the type related language syntax makes it more readable/familiar
with programmers.


To understand the type check, it is useful to see an equivalent `comptime assert`
translation. Each variable can have a type attached once. Each time that the
variable is modified a `comptime assert` statement could check that the variable is
compatible with the assigned type. From a practical perspective, the Pyrope
type system works this way when variables are modified.

=== "Snippet with types"

    ```
    var b = "hello"

    var a:u32

    mut a += 1

    mut a = b // fails type check
    ```

=== "Snippet with comptime assert"

    ```
    var b = "hello"



    mut a += 1
    comptime assert a does u32
    mut a = b 
    comptime assert a does u32 // fails type check
    ```

The compiler handles automatically, but control flow instructions affect the
equivalent assert statement.

```
var a:type1

if $runtime {
  var b:type2

  a = yyy      // comptime assert $runtime implies yyy does :type1
  b = xxx      // comptime assert $runtime implies xxx does :type2
}

a = zzz        // comptime assert zzz does :type1
```

## Building types

Each variable can be a basic type like String, Boolean, Number, or a bundle. In
addition, each variable can have a set of constrains from the type system. 


Although it is possible to declare just the `comptime assert` for type checks,
the recommendation is to use the explicit Pyrope type syntax because it is more
readable and easier to optimize.


Pyrope type constructs:

* `type` keyword allows to declare types.
* `a does b`: Checks 'a' is a superset or equal to 'b'. In the future, the
  unicode character "\u02287" could be used as an alternative to `does` (`a`
&#8839 `b`);
* `a:b` is equivalent to `a does b` or `comptime assert a does b` check.
* `:b` returns the "type of" `b` when used in an expression.
* `a equals b`: Checks that `a does b` and `b does a`. Effectively checking
  that they have the same type.


While `var` statement declares a new variable instance which can also have an
associated type, the `type` statement declares a type without any instance.
The `type` keyword also allows for expressions to build more complex types.
All the elements in the type expression are treated as "type of". E.g: `type x
= a or 1..=3` is equivalent to write `type x = :a or :(1..=3)` 

```
type a1 = u32       // type a1 = :u32 is also valid syntax
type a2 = int(max=33,min=-5)
type a3 = (
    ,var name:string
    ,var age:u8
    )

type b1 = a1 or  a2 // same as type b1 = -5..<4G
type b2 = a1 and a2 // same as type b2 = 0..=33

type b3 = a1 or a3  // compile error: unclear how to combine type 'a1' and 'a2'
```

The puts command understands types.

```
type at=33..   // number bigger than 32
type bt=(
  ,var c:string
  ,var d=100
  ,let init = {|| self.c = $ }
)

var a:at=40
var v:bt="hello"
puts "a:{} type:{} or {}", a, :a, at  // a:40 type:Number(33..) or Number(33..)
puts "b:{} type:{}", b, :b  // b:(c="hello",d=100) type:(c:string,d=100)"
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

type big = x or y or z or :(d:u33)
assert   big does x
assert   big does y
assert   big does z
assert   big does :(d:u20)
assert !(big does :(d:u40))
```

## Bundle concatenation

Bundles are the basic building block for complex types, fields can be added
and bundles which allows to create more complex types.

There are three main ways to add fields to a bundle: `set`, `++`, and `...`.

The `set` directly adds a field at a time over a given bundle. The bundle must
be mutable (`var`) and the `set` must be used to index the new field. The `mut`
is not enough because it checks that the field already exists. The `set` allows
to mutate and/or add a new field.


The `++` concatenates two bundles. Bundles can be in three categories (just
ordered, just named, or ordered/named). `++` will preserve the category of both
input bundles have the same category. When mixing categories, it will create an
ordered bundle. The order for the just named bundle will be the lexicographical
order or the named fields. This means that `++` will create a just named bundle only if both input
bundles are just named. If the same named field name exists in both bundles,
only one of the bundle fields (the right hand side one) is used. The field
position is recomputed based on the relative order.


The `...` also concatenates, but it is an "inline concatenate". Since it
inlines a bundle in an ordered bundle, the result is always an ordered bundle.
The only difference with `++` is that it triggers a compile error if the same
named entry already exists.

```
var base1 = (var a, var b)  // ordered and named
var base2 = (var c, var d)  // ordered and named
var ordered = (33,44)       // just ordered

var named
set named.y = 1
set named.a = 2             // directly add var fields

var x = base1 ++ base2
assert x equals :(var a,var b,var c,var d)
assert x not equals :(base2 ++ base1) // (c,d,a,b)

assert x equals :(...base1, ...base2)

assert (1,3,5) == (...(1,3), 5)
assert (1,3,5) == (1, ...3, 5)
assert (1,3,5) == 1 ++ 3 ++ 5
assert (1,3,5) == 1 ++ (3, 5)
assert (1,3,5) == (...(1, 3, 5))

var y = base1 ++ base1      // same bundle twice!!
assert y equals base1

e1 = (...base1, ...base1) // compile error, redefined 'a' and 'b' field
e2 = base1 ++ named       // compile error, can not join ordered and unordered
e3 = (...base1, ...named) // compile error, named is not an ordered bundle
e4 = (...named, var z)    // compile error, named is not an ordered bundle

var z1 = (a=100, y=200, z=300)    //ordered and named
let tmp1 = named ++ (var z)       // (var z) is ordered and named
assert z1 equals :tmp1
var z2 = (z=100, a=100, y=200)    //ordered and named
let tmp2 = (var z) ++ named
assert z2 equals tmp2
```

## Enums with types

The union of types is the way to implement enums in Pyrope:

```
 type color1 = RED1 or BLUE1 or GREEN1 // enum just a unique ID

 type Rgb = (
    ,init = {mut |x| self.color:u24 = x }
 )

 type Red2:Rgb  = 0xff0000
 type Green2    = Rgb(0x00ff00) // alternative syntax
 type Blue2:Rgb = Rgb(0x0000ff) // alternative redundant syntax
 type color2 = Red2 or Green2 or Blue2

 var x:color1 = RED1 // only in local module

 if x does RED1 { // "x does RED1" is the same as "x equals RED1"
   puts "color1:{}\n", :x // prints "color1:RED1"
 }

 var y:color2 = Red2
 if y does Red2 { // in this case "y does RED" is the same as "y equals RED"
   // prints "color:Red2 c1:Red2(color=0xff0000) c2:0xff0000"
   puts "color:{} c1:{} c2:{}\n", :y, y, y.color 
 }
```


## Bitwidth for numbers

Number basic type can be constrained based on the maximum and minimum value
(not by number of bits).

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

To convert between bundles, a explicit typecast is needed unless all the bundle
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
  ,let init = {mut |(x:at)| self.d = x.d ; self.c = x.c }
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

There is no object inheritance in Pyrope, but bundles allow to build mixin and composition with traits.

A mixin is when an object or class can add methods and the parent object can access them. In several languages
there are different constructs to build them (E.g: an include inside a class in Ruby). Since Pyrope bundles
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
  ,let init = {mut |n| self.name = n }
)

type Mixing_all = Say_mixin ++ Say_hi_mixin ++ User

var a:Mixing_all("Julius Caesar")
a.say_hi() 
```

Mixin are very expressive by allowing to redefine methods. If two bundles have
the same field a bundle with the concatenated values will be created. This is
likely an error with basic types but useful to handle explicit method overload.


In a way, mixin just adds methods from two bundles to create a new bundle. In
programming languages with object oriented programming (OOP) there are many
keywords (`virtual`, `final`, `override`, `static`...) to constrain how methods can be
updated/changed. In Pyrope, the `let` and `var` keywords can be added to any bundle
field. The `let` makes the entry immutable when applied to a method, it behaves like
a `final` keyword in most languages.


There are also two ways to concatenate bundles in Pyrope. `bun1 ++ bun2` and
`(...bun1, ...bun2)`. The difference is that `++` concatenates and replaces any
not `let` field. The `...` concatenates and but triggers a compile error if the
same field appears twice.


An issue with mixin is when more than one bundle has the `init` method. If the
bundles are concatenated with `...` and error is triggered, if the bundles are
concatenated with `++` the methods are overrided when declared with `var`.
Neither is the expected solution.  A smaller issue with mixins is that
`comptime assert X implements Y` should be inserted when implementing an
interface.


Without supporting OOP, but providing a more familiar abstract or trait
interface, Pyrope provides the `implements` keyword. It checks that the new
type implements the functionality undefined and allows to use methods defined,
and creates a wrapper to the init method calling both init methods if needed. 

HERE (same call order as swifth/rust/scala??)

This is effectively a mixin with checks that some methods should be
implemented.

```
type Shape = (
  ,name:string
  ,area          = {   |(     ) -> :i32 |}
  ,increase_size = {mut|(_:i12) -> ()   |}
)

type Circle implements Shape = (
  ,rad:i32
  ,init = {mut || self.name = "circle" }
  ,area = {|() -> :i32   |
     let pi = import "math.pi"
     return pi * self.rad * self.rad
  }
  ,increase_size = {mut|(_:i12) -> ()| self.rad *= $1 }
)
```

Like most typechecks, the `implement` can be translated for a `comptime
assert`. An equivalent "Circle" functionality:

```
type Circle = (
  ,rad:i32
  ,name = "Circle"
  ,area = {|() -> :i32|
     let pi = import "math.pi"
     return pi * self.rad * self.rad
  }
  ,increase_size = {mut|(_:i12) -> ()| self.rad *= $1 }
)
comptime assert Circle does Shape
```

## Explicit function overloading

Pyrope has types and functions. There is also function overloading, but unlike
most languages it has explicit function overloading.  With explicit, the
programmer sets an ordered list of methods, and the first that satisfies the
type check is called.

```
bool_to_string = {|(b:boolean) -> :string| if b { "true" } else { "false" } }
int_to_string  = {|(b:int)     -> :string| }

to_string = bool_to_string ++ int_to_string
let s = to_string(3)
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

## Global variables

There are no global variables or functions in Pyrope. Variable scope is
restricted by code block `{ ... }` and/or the file. Each Pyrope file is a
function, but they are only visible to the same directory/project Pyrope files.


The `punch` statement allows to access variables from other files/functions. The
`import` statement allows to reference functions from other files.


### import

Each file can have several functions in addition to itself. All the functions
are visible to the `import` statement, but it is a good etiquette not to import
functions that start with underscore, but sometimes it is useful for debugging,
and hence allowed.

```
// file: src/my_fun.prp
fun1    = {|a,b|  }
fun2    = {|a|  }
another = {|a|  }
_fun3   = {|a|  }
```

```
// file: src/user.prp
a = import "my_fun/*fun*"
a.fun1(a=1,b=2)         // OK
a.another(a=1,2)        // compile error, 'another' is not an imported function
a._fun3(a=1,2)          // OK but not nice
```

The import statement uses a shell like file globbing with an optional "project".

* `*` matches zero or more characters
* `?` matches exactly one character

The globbing starts at the current directory, and keeps trying upper
directories until it reaches the project root. Directories named `code` or
`src` are skipped. No need to add them in globbing pattern. It stops the search
on the first hit. If no hit happens, a compile error is generated. This allows
to have specialized libraries per subproject. For example xx/yy/zz can use a
different library version than xx/bb/cc if the library is provided by yy, or
use a default one from the xx directory.

```
a = import "prj1/file?/*something*"
b = import "file1/xxx_fun"   // import xxx_fun from file1 in the local project
c = import "file2"           // import the functions from local file2
d = import "prj2/file3"      // import the functions from project prj2 and file3
```


Many languages have a "using" or "import" or "include" command that includes
all the imported functions/variables to the current scope. Pyrope does not
allow that, but it is possible to use mixin to add the imported functionality
to a bundle.

```
b = import "prp/Number"
a = import "fancy/Number_mixin"

type Number = b ++ a // patch the default Number class

var x:Number = 3
```


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
bundle. The regex can include tree hierarchy. E.g:

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
always concatenates a Bundle or a String, `[]` always indexes a bundle.

The only thing that looks like operator overload (but it is not) is the `=`
because it can be used to initialize objects.

```
var f1:XXX = 3,2
var f2:XXX = XXX(3,2)
Var f3:XXX

f3 = 3,2
assert f3 == f2 == f1
```


Encapsulation can be achieved with methods, but to have a more familiar getter/setter
syntax, it is possible to create a bundle where the initialization is the setter
and the default method is the getter.


```
type some_obj = (
  ,_field:string
  ,direct:u30
  ,enc.init = {mut |x| _field = x }  // setter
  ,enc = {|| self._field }                     // getter
  ,init = {|a,b|
    self._field = a
    self.direct = b
  }
)

var x:some_obj = "hello", 3

assert x.direct == "hello"
assert x.enc()  == 3
x.enc = 5
assert x.enc()  == 5
```

