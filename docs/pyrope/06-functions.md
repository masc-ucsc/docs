# Functions and methods


Hardware description languages specify a tree-like structure of modules or functions. Usually, there is a top module that
instantiates several sub-modules. The difference between module and function is mostly what is visible/left after synthesis. We
call module any a function call is left visible in the generated netlist as a separate entity. If a function is inlined in the
caller module, we do not call it module. By this definition, a function is a super-set of modules.

!!!Note
    Pyrope only supports a restricted amount of recursion. Recursion is only allowed when it can be unrolled at compile time.

## Function definition

All the functions are lambdas that must passed as arguments or assigned to a given variable. There is no global scope for
variables or functions.

```
a_3      = {   3 } // just scope, not a lambda. Scope is evaluate now
a_lambda = {|| 4 } // lambda or function, when just_4 is called 4 is returned
assert a_3 equals 3
assert a_lambda equals {|| }
assert a_lambda == 4          // calls to eval the lambda
```

The simplest function resembles a scope with at `{` followed by a sequence of statements where the last statement can be an
expression before the closing `}`.

The difference between a function and a normal scope is the lambda definition enclosed between pipes (`|`).

```txt
[ATTRIBUTES] | [CAPTURE] [INPUT] [-> OUTPUT] [where COND] |
```

* ATTRIBUTES are optional method modifiers like:
    * `comptime`: function should be computed at compile time
    * `debug`   : function is for debugging, not side effects in non-debug statements
    * `mut`     : function is has an output that it is a copy of the first input argument. This is typically a method that can modify the parent bundle.
* META are a list of type identifiers or type definitions.
* CAPTURE has the list of capture variables for the function. If no capture is provided, any local variable
can be captured. An empty list (`[]`), means no captures allowed.
* INPUT has a list of inputs allowed with optional types. If no input is provided, the `$` bundle is used as input.
* OUTPUT has a list of outputs allowed with optional types. If no output is provided, the `%` bundle is used as output.
* COND is the condition under which this statement is valid.

```
add = {|| $a+$b+$c }              // no IO specified
add = {|a,b,c| a+b+c }            // constrain inputs to a,b,c
add = {|(a,b,c)| a+b+c }          // same
add = {|(a:u32,b:s3,c)| a+b+c }   // constrain some input types
add = {|(a,b,c) -> :u32| a+b+c }  // constrain result to u32
add = {|(a,b,c) -> (res)| a+b+c } // constrain result to be named res
add = {|(a:T,b:T,c:T)| a+b+c }    // constrain inputs to have same type

x = 2
add2 = {|[x](a)| x + a }           // capture x
add2 = {|[foo=x](a)| foo + a }     // capture x but rename to something else

y = (
  ,val:u32 = 1
  ,inc1 = {|mut| self.val = u32(self.val + 1) } // mut allows to change bundle
)

my_log = {|debug|
  print "loging:"
  for i in $ {
    print " {}", i
  }
  puts
}

my_log a, false, x+1
```

## Implicit function per file

Every Pyrope file creates an implicit function with the same name as the file
and visible to the other files/functions in the same directory/project.

Like any function, the input/outputs can be constrained or left to be inferred.


```
// file: src/mycall_with_def.prp
|(a,b) -> (d:u12)|  // not a compile error if beginning of the file

%d = a + $a + $b // a or $a the same due to function definition
```

```
// file: src/mycall_without_def.prp
%d = $a + $a + $b // a or $a the same due to function definition
assume %d < 4K 
```

## Arguments

Function calls only pass by value, there is no pass by reference like in most
languages.  A function is a code block that has an input bundle (`$`) performs
some statements and returns an output bundle (`%`). Since bundles can be named,
ordered or both, these are some implications:

* Arguments can be named. E.g: `fcall(a=2,b=3)`
* There can be many return values. E.g: `return (a=3,b=5)`
* Inputs can be accessed with the bundle. E.g: `return $1 + $.arg_2 + $arg3`

There are several rules on how to handle function arguments.

* Calls uses the Uniform Function Call Syntax (UFCS). `(a,b).f(x,y) == f((a,b),x,y)`
* Pipe |> concatenated inputs: `(a,b) |> f(x,y) == f(x,y,a,b)`
* No parenthesis after newline or a variable assignment: `a = f(x,y)` is the same as `a = f x,y`

Pyrope uses a uniform function call syntax (UFCS) like other languages like Nim
or D but it can be different from the order in other languages. Notice the
different order in UFCS vs pipe, and also that in pipe the argument tuple is
concatenated, but in UFCS the it is added as first argument.


```
div  = {|a,b| a / $b }   // named input bundle
div2 = {|| $0 / $1 }     // unnamed input bundle

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

## Methods

Pyrope has functions that only pass arguments by value. This presents a problem
if we implement a typical method. A method is a function associated to a bundle
which we call the parent bundle. The method can access the parent bundle fields
and potentially mutate some of them. To be consistent with the UFCS syntax, the
bundle is passed as the first argument in the input bundle. This works directly
when the method does not update or mutate the bundle contents. To allow updates
the first argument in the output bundle is the parent bundle. To indicate the
existence of the output parent bundle, the function is declared with the `mut`
keyword.


To make the code more consistent with existing languages Pyrope has the `self`
keyword that corresponds to the first entry in the input bundle or the first
element of the output bundle when the method is declared with the `mut`
keyword.

```
var a_1 = (
  ,x:u10
  ,fun = {|mut x| 
    assert $.__size == 2 // self and x
    self.x = x 
    assert %.__size == 2 // due to the mut keyword
    assert %.self.x == x
  }
)

a_1.fun(3)
assert a_1.x == 3

fun2 = {|mut (self, x)| self.x = x }
a_2 = a_1.fun2(4)
assert a_1.x == 3
assert a_2.x == 4
```

Due to the UFCS and the `self` keyword methods can be attached to bundles, but there
is a higher precedence if the bundle has a locally declared method.

```
var a = 33

foo = {|| self - 1 }

x = foo(a)
assert x == 32 and a == 33

y = a.foo()
assert y == 32 and a == 33

a.foo = {|| self + 1 }

z = a.foo()
assert z == 34 and a == 33

mut_foo = {|mut| self -= 1}
mx = mut_foo(a)
assert mx == 32 and a == 33  // output is mutabled not input

a.mut_foo()  // same as: a = mut_foo(a)
assert a == 32

a.mut_foo = {|mut| self += 100}
a.mut_foo() // same as: a = a.mut_foo(a)
assert a == 132
```

Methods allow to access parent bundle fields, but they can override previous methods. To handle
the override, Pyrope has the `super` keyword:

* `self` access the input bundle first argument or the output bundle first
  argument when the method is declared mutable (`{|mut ...}`).
* `super` provides the method before it was redefined.

```
type base1 = (
  ,fun = {|| 1 }
)
type base2 = (
  ,fun = {|| 
    a = super
    assert a == 1
    2 
  }
)

type top = base1 ++ base2 ++ (
  ,top_fun = {|| 4 }
  ,fun = {||
    a = super()          // same as a = super
    assert a == 2
    return 33
  }
)

var a3:top

assert a3.top_fun does :{||}
assert a3.top_fun() == 4
assert a3.top_fun.size == 1

assert a3.fun does :{||}
assert a3.fun.size == 1
assert a3.fun()    == 33

var a1:base1
var a2:base2
assert a1.fun() == 1
assert a2.fun() == 2
```

