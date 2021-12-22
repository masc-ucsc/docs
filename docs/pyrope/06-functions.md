# Lambdas


A `lambda` consists of a sequence of statements that can be bound to a variable.
The variable can be copied and called as needed. Unlike most languages, Pyrope
only supports anonymous lambdas. The reason is that without it lambdas would be
assigned to a namespace. Supporting namespaces would avoid aliases across
libraries, but Pyrope allows different versions of the same library at
different parts of the project. This will effectively create a namespace alias.
The solution is to not have namespaces but relies upon variable scope to decide
which lambda to call.


Pyrope divides the lambdas into two categories: `functions` and `procedures`.
Functions operate only over combinational logic. They can not have any
synthesis side-effect. This means the function outputs are only a function of
the function inputs. Any external call can only affect `debug` statements not
the synthesizable code. `functions` resemble `pure functions` in normal
programming languages, but they are allowed to have side effects on
non-synthesizable code.


Non-function lambdas are called `procedures` or `methods`. The only difference
between `procedures` and `methods` is that a `method` has `self` as the first
argument in the output which allows to mutable the called tuple.


Lambdas also can be divided into `modules` and non-`modules`. A `module` is a
lambda visible at synthesis call hierarchy. A `non-module` is an inlined or
flattened `lambda`.


## definition

Only anonymous lambdas are supported, this means that there is no global
scope for functions, procedures, or modules. The only way for a file to access
a lambda is to have access to a local variable with a definition or to "import"
a variable from another file.

```
let a_3   = {   3 } // just scope, not a lambda. Scope is evaluate now
let a_fun = {|| 4 } // local function, when just_4 is called 4 is returned

pub let fun3 = {|| 5 }    // public lambda that can be imported by other files

let x = a_3()             // compile error, explicit call not posible in scope
let x = a_fun()           // OK, explicit call

assert a_3 equals 3
assert a_fun equals {|| }
assert a_fun() == 4       // calls to eval the function
```

The simplest lambda resembles a scope with at `{` followed by a sequence of
statements before the closing `}`. Like scopes, it is possible to have a single
expression instead of a sequence of statements. The difference between a lambda
and a normal scope is the lambda definition enclosed between pipes (`|`).


```txt
[GENERIC] [CAPTURE] [INPUT] [-> OUTPUT] [where COND] |
```

+ `GENERIC` is an optional comma separated list of names between `<` and `>` to
  use as generic types in the lambda.

+ `CAPTURE` has the list of capture variables for the lambda. If no capture
  is provided, any local variable can be captured. An empty list (`[]`), means
  no captures allowed. The captures are by value only, no capture by reference
  is allowed.

+ `INPUT` has a list of inputs allowed with optional types. If no input is
  provided, the `$` input tuple can be used. `()` indicates no inputs.

+ `OUTPUT` has a list of outputs allowed with optional types. If no output is
  provided, the `%` output tuple can be used. `()` indicates no outputs.

+ `COND` is the condition under which this statement is valid. The `COND` can
  use the inputs, outputs, and `self` to evaluate. If the outputs are used in
  the `COND`, the lambda must be immutable. This means that the method is
  called when the condition could evaluate true depending on its execution, but
  being immutable there are no side effects. The
  [overload](06-functions.md#overloading) section has more details.

```
var add
add = {|| $a+$b+$c }              // no IO specified
add = {|a,b,c| a+b+c }            // constrain inputs to a,b,c
add = {|(a,b,c)| a+b+c }          // same
add = {|(a:u32,b:s3,c)| a+b+c }   // constrain some input types
add = {|(a,b,c) -> :u32| a+b+c }  // constrain result to u32
add = {|(a,b,c) -> (res)| a+b+c } // constrain result to be named res
add = {|(a,b:a,c:a)| a+b+c }      // constrain inputs to have same type

x = 2
var add2
add2 = {|       (a)|   x + a }    // implicit capture x
add2 = {|[x    ](a)|   x + a }    // explicit capture x
add2 = {|[     ](a)|   x + a }    // compile error, undefined 'x'
add2 = {|[foo=x](a)| foo + a }    // capture x but rename to something else

var y = (
  ,val:u32 = 1
  ,inc1 = {|(self)->(self)| self.val = u32(self.val + 1) }
)

debug let my_log = {||
  print "loging:"
  for i in $ {
    print " {}", i
  }
  puts
}

let fun = {|<X>(a:X,b:X)| a+b }   // enforces a and b with same type
assert fun(33:u22,100:u22)

my_log a, false, x+1
```

## Implicit input/output tuple

The inputs and outputs on the current lambda can have an associated variable
with the lambda definition, but it is always possible to access the inputs
and outputs with the input tuple (`$`) and the output tuple (`%`). This allows
variable size arguments and simpler code for small code snippets. It also
simplifies introspection since all the inputs are in `$` and all the outputs
are in `%`.

```
let fun = {|(in1,in2)->(out1,out2)|
  assert in1 == $.in1 and in2 == $.in2

  out1 = in1 + $in1
  out2 = out1 + in2 + $in2

  assert out1 == $.out1 and out2 == $.out2
}

let fun2 = {|(a1,...rest)|
  assert a1   == $.0
  assert rest == $[1..]
}
```

## Arguments

Lambda calls only pass arguments by value. Unlike most software languages,
there is no way to pass by reference.

* Arguments can be named. E.g: `fcall(a=2,b=3)`
* There can be many return values. E.g: `ret (a=3,b=5)`
* Inputs can be accessed with the `$` tuple. E.g: `ret $1 + $.arg_2 + $arg3`

There are several rules on how to handle arguments.

* Calls use the Uniform Function Call Syntax (UFCS). `(a,b).f(x,y) == f((a,b),x,y)`

* Pipe `|>` concatenated inputs: `(a,b) |> f(x,y) == f(x,y,a,b)`

* Function calls with arguments do not need parenthesis after newline or a
  variable assignment: `a = f(x,y)` is the same as `a = f x,y`

* Functions explicitly declared without arguments, do not need parenthesis in
  function call.

Pyrope uses a Uniform Function Call Syntax (UFCS) like Nim or D but it can be
different from the order in other languages. Notice the different order in
UFCS vs pipe, and also that in the pipe the argument tuple is concatenated,
but in UFCS is added as the first argument.

```
div  = {|a,b| a / $b }   // named input tuple
div2 = {|| $0 / $1 }     // unnamed input tuple

noarg = {|()| ret 33 }   // explicit no args

assert noarg == 33 == noarg()

a=div(3  , 4  , 3)       // compile error, div has 2 inputs
b=div(a=8, b=4)          // OK, 2
c=div a=8, b=4           // compile error, parenthesis needed for complex call
d=(a=8).div(b=2)         // OK, 4
e=(a=8).div b=2          // compile error, parenthesis needed for complex call

h=div2(8, 4, 3)          // OK, 2 (3rd arg is not used)
i=8.div2(4,3)            // OK, same as div2(8,4,2)

j=(8,4)  |> div2         // OK, 2, same as div2(8,4)
k=(4)    |> div2(8)      // OK, 2, same as div2(8,4)
l=(4,33) |> div2(8)      // OK, 2, same as div2(8,4,33)
m=4      |> div2 8       // compile error, parenthesis needed for complex call

n=div2((8,4), 3)         // compile error: (8,4)/3 is undefined
o=(8,4).div2(1)          // compile error: (8,4)/1 is undefined
```


The UFCS allows to have `functions` to call any tuple, but if the called tuple
has a lambda defined with the same name, the tuple lambda has a higher priority.

```
var tup = (
  ,let fun = {|| ret 1 }
)

let fun = {|(b)| ret 2 }

assert fun()    == 2
assert fun(tup) == 2
assert 4.fun()  == 2
assert tup.fun() == 1
```

The keyword `self` is used to indicate that the function is accessing a tuple.
It is also passed as the first argument (`$[0] == self`). As a syntax sugar,
when no inputs are specified, the `self` can be from the input list when it is
read by any expression.

```
var tup = (
  ,var x = 3
  ,let fun = {|()| assert $.size == 1 ; ret self.x }
)

let fun2 = {|(b)| ret b.x             } // no self, but it is the same
let fun3 = {|(self,b)| ret self.x + b }

assert tup.fun() == 3   // tup.fun call
assert tup.fun == 3     // explicit no args, so () is optional in call
assert fun2(tup) == 3
assert tup.fun2() == 3  // UFCS

assert fun3(tup) == 3   // compile error, missing b arg
assert tup.fun3() == 3  // compile error, missing b arg
assert fun3(tup,2) == 5
assert tup.fun3(2) == 5
```

## Methods

Pyrope lambdas only pass arguments by value. This looks like a problem if we
implement a typical `method`. The `method` accesses the parent tuple fields and
updates some of them. 


Updates to tuples needed by `methods` are allowed when the first output of the
lambda is a `self` keyword. Although not required, `methods` tend to also have
`self` as the first input argument.

```
var a_1 = (
  ,x:u10
  ,let fun = {|(self,x)->(self)| 
    assert $.__size == 2 // self and x
    self.x = x 
    assert %.__size == 2 // due to the mut keyword
    assert %.self.x == x
  }
)

a_1.fun(3)
assert a_1.x == 3

fun2 = {|(self, x)->(self)| self.x = x }
a_2 = a_1.fun2(4)
assert a_1.x == 3
assert a_2.x == 4
```

A difference between a method and a UFCS call is that the method has a higher
priority to match. Like in the input syntax sugar, if no output is specified
and there is an update to a `self` variable, the compiler assumes `(self)` as
output tuple.


```
var counter = (
  ,var val:i32
  ,let inc = {|(self, v)| self.var += v }
)

assert counter.val == 0
counter.inc(3)
assert counter.val == 3

let inc = {|(self, v)->(self)| self.var *= v } // NOT INC but multiply
counter.inc(2)
assert counter.val == 5

let mul = inc
counter = counter.mul(2)   // call the new mul method with UFCS
assert counter.val == 10

let other = counter.mul(2) // UFCS no self update return
assert counter.val == 10
assert other.val   == 20

mul(counter, 2) // also legal, but no self update
assert counter.val == 20
```

`self` is an input and/or output but also a reserved word. It could be a tuple
first input argument or the first output argument

!!!NOTE
    To avoid verbose `self` in methods, the compiler automatically inserts a
    `self` as the first entry in the input tuple if the `self` variable is ever
    read in the method and no input/output was defined.

    ```
    // equivalent code due to automatic `self` insertion
    let fun1 = {|(self)->(self)| self.foo = self.bar + 1}
    let fun2 = {|      ->(self)| self.foo = self.bar + 1}
    let fun3 = {|(self)        | self.foo = self.bar + 1}
    let fun4 = {|              | self.foo = self.bar + 1}

    // NOT equivalent because () means no input/output
    let non2 = {|()    ->(self)| self.foo = self.bar + 1}
    let non3 = {|(self)->()    | self.foo = self.bar + 1}
    ```

## Arguments

Arguments can constrain the inputs and input types. Unconstrained input types
allow for more freedom and a potentially variable number of arguments generics, but
it can be error-prone.

=== "unconstrained declaration"
    ```
    foo = {|| puts "fun.foo" }
    a = (
      ,foo = {||
         bar = {|| puts "bar" }
         puts "mem.foo"
         ret (bar=bar)
      }
    )
    b = 3

    puts "start"
    b.foo     // compile error: parenthesis needed
    b.foo()   // prints "fun.foo"
    a.foo     // compile error: parenthesis needed (no arguments passed)
    a.foo()   // prints "mem.foo"
    a.foo 3   // prints "mem.foo", arg passed (but not used by foo)
    a.foo(3)  // prints "mem.foo", arg passed (but not used by foo)
    x = a.foo // Nothing printed, just lambda in x
    y = x()   // prints "foo"
    y()       // prints "bar"
    z = y     // nothing printed

    a.foo.bar()   // prints "bar", passes a.foo as argument to bar
    a.foo().bar() // prints "mem.foo" (foo gets a) and then "bar" (has no input)

    b.foo().bar() // compile error, no bar method
    foo()         // prints "fun.foo"
    b.foo()       // prints "fun.foo"
    ```

=== "constrained declaration"

    ```
    foo = {|(self)| puts "fun.foo" }  // explicit self
    a = (
      ,foo = {|()|                    // implicit self 
         bar = {|()| puts "bar" }
         puts "mem.foo"
         ret (bar=bar)
      }
    )
    b = 3

    puts "start"
    b.foo     // compile error: parenthesis needed
    b.foo()   // prints "fun.foo"
    a.foo     // compile error: parenthesis needed (no arguments passed)
    a.foo()   // prints "mem.foo"
    a.foo 3   // compile error
    a.foo(3)  // compile error
    x = a.foo // Nothing printed, just lambda in x
    y = x()   // prints "foo"
    y()       // prints "bar"
    z = y     // nothing printed

    a.foo.bar()   // compile error
    a.foo().bar() // prints "mem.foo" and then "bar"

    b.foo().bar() // compile error, no bar method
    foo()         // compile error
    b.foo()       // prints "fun.foo"
    ```

## Overloading

Pyrope does not have global scope for defined lambdas. Instead, all the lambda
must reside in a local variable or must be "imported". Nevertheless, a local
variable can have multiple lambdas. It is similar to Odin's "explicit procedure
overloading". This section explains how is the overloading selection in this
case.

When overloading, lambdas are typically added at the end `++=` of the tuple.
This means that it is NOT overwriting an existing functionality, but providing
a new call capability.

If the intention is to intercept, the lambda must be added at the head of the
tuple entry.

```
type base = (
  ,pub var fun1 = {|| 1 }         // catch all
  ,pub var fun2 = {|| 2 }         // catch all
  ,pub var fun3 = {|| 3 }         // catch all
)
type ext extends base with (
  ,pub var fun1 =   {|(a,b)| 4 }  // overwrite allowed with extends
  ,pub var fun2 ++= {|a,b|   5 }  // append
  ,pub var fun2 ++= {||      6 }  // append
  ,pub var fun3 =   {|a,b|   7 } ++ base.fun3 // prepend
  ,pub var fun3 =   {||      8 } ++ base.fun3 // prepend
)

var t:ext

// t.fun1 only has ext.fun1
assert t.fun1(a=1,b=2) == 4
t.fun1()                 // compile error, no option without arguments

// t.fun2 has base.fun2 and then ext.fun2
assert t.fun2(1,2) == 5  // EXACT match of arguments has higher priority
assert t.fun2() == 2     // base.fun2 catches all ahead of ext.fun2

// t.fun3 has ext.fun3 and then base.fun3
assert t.fun3(1,2) == 7  // EXACT match of arguments has higher priority
assert t.fun3() == 8     // ext.fun3 catches all ahead of ext.fun3
```

A more traditional "overload" calling the is possible by calling the lambda directly:

```
type x extends base with (
  ,pub var fun1 = {|| ret base.fun1() + 100 }
)
```

To allow overloading the base `lambda` as `var`. By concatenating lambdas to a
variable, we effectively create an unnamed tuple with multiple entries. Since
all the variables are tuples of size one too, the following rules apply to any
lambda call:

* If the caller uses "named arguments", pick all the modules that have an
  exact match in the named tuple and the types are compatible[^2]. If the
  module used output has a known type (no output use is a known type too), the
  output type is used in the match. If no `lambda` match is found, apply the
  "unnamed arguments" rule.

* If the caller uses "unnamed arguments" (or no match in "named arguments"),
  look for all the modules that have the same number of arguments and where each
  argument type is compatible[^2] and at least one of the input/outputs in the
  lambda definition is typed. If the module used output has a known type (no
  output use is a known type too), the output type is used in the match. If no
  lambda is found, then look for a module where none of the inputs/outputs have
  type constraints (untyped inputs/outputs). 

* If the list is empty, generate a compile error (no possible lambda to call).

* Once a list of ordered modules is found, evaluate the `COND`. `COND` can
  include inputs, self, and outputs. If a `COND` is comptime true (no
  `COND` is the same as `true`), stop selecting additional modules. If `COND`
  is comptime `false` remove from the list and continue. All the selected modules
  will be executed, but the output will be selected based on priority order
  based on the `COND` result.


The previous rules imply that Pyrope has some type of dynamic dispatch. The
types for the inputs and outputs must be known at compile time (static
dispatch) but the `where` condition may be known at run-time as long as the
module is immutable.


It is important to notice that a lambda overload can have multiple
`procedures`. If the where COND is not comptime, several procedures can be
called. The order of evaluation is defined because the tuple is ordered. This
is still considered a defined expression.


[2]: The type match is addressed in the [07-typesystem](07-typesystem.md)
section.


For untyped unnamed argument calls:

```
var fun_list = {|(a,b)| ret a+b}
fun_list ++= {|(a,b,c)| ret a+b+c }
fun_list ++= {|(a,b,c,d)| ret a+b+c+d }

assert fun_list.size()

assert fun_list(1,2) == 3
assert fun_list(1,2,4) == 7
assert fun_list(1,2,4,5) == 12
assert fun_list(1,2,4,5,6) == 18 // compile error, no function with 5 args


fun_list ++= {|(a,b)| ret 100}
assert fun_list(1,2) == 3

fun_list = {|(a,b)| ret 200} ++ fun_list
assert fun_list(1,2) == 200
```

For untyped named argument calls:

```
var fun = {|(a,b)| ret a+b+100 }
  fun ++= {|(x,y)| ret x+y+200 }

assert fun(a=1,b=2) == 103
assert fun(x=1,y=2) == 203
assert fun(  1,  2) == 103  // first in list
```

For typed calls:

```
var fun = {|(a:int,b:string)->:bool  | ret true    }
fun ++=   {|(a:int,b:int   )->:bool  | ret false   }
fun ++=   {|(a:int,b:int   )->:string| ret "hello" }

let a = fun(3,hello)
assert a == true

let b = fun(3,300)        // first in list return bool
assert b == false

let c:int = fun(3,300)    // compile error, no method fulfills constrains
let c:string = fun(3,300)
assert c == "hello"
```

For conditional argument calls:

```
var fun = {|(a,b)      where a>40    | ret b+100 }
  fun ++= {|(a,b)->(x) where x > 300 | ret b+200 } // output x
  fun ++= {|(a,b)->(a) where $.a > 20| ret b+300 } // input a
  fun ++= {|(a,b)->(a) where %.a > 10| ret b+400 } // output a
  fun ++= {|(a,b)                    | ret a+b+1000 } // default

var fun_manual = {|(a,b)|
  if a>40 {
    ret b+100
  }
  let x = b + 200
  if x>300 {
    ret (x=x)
  }
  if a>20 {
    ret b+300
  }
  let tmp = a + b
  if tmp >10 {
    ret (a=tmp)
  }
  ret a+b+1000
}

test "check equiv" {
  for a in -100..=100 {
    for b in -100..=100 {
      assert fun(a,b) == fun_manual(a,b)
    }
  }
}
```


