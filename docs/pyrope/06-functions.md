# Functions and methods


Hardware description languages specify a tree-like structure of modules or
functions. Usually, there is a top module that instantiates several
sub-modules. The difference between module and function is mostly what is
visible/left after synthesis. We call module any function call left visible in
the generated netlist as a separate entity. If a function is inlined in the
caller module, we do not call it module. By this definition, a function is a
super-set of modules.


Functions also can be classified in three cathegories based on the outputs:
pure combinational, synchronous combinational, and pipelined:

+ A pure combinational output does not use a clock and all the outputs are as a
  combinational result of the inputs. 

+ A synchronous output uses some register or memory to keep state across
  functions but the output is still combinational as a result of inputs and/or
  internal registers. 

+ A pipelined output does not have any combinational path to any of the inputs
  that does not pass through a register or memory.


!!!Note
    Pyrope only supports a restricted amount of recursion. Recursion is only allowed when it can be unrolled at compile time.

## Function definition

All the functions are lambdas that must passed as arguments or assigned to a
given variable. There is no global scope for variables or functions.

```
a_3   = {   3 } // just scope, not a function. Scope is evaluate now
a_fun = {|| 4 } // function, when just_4 is called 4 is returned

let x = a_3()             // compile error, explicit call not posible in scope
let x = a_fun()           // OK, explicit call

assert a_3 equals 3
assert a_fun equals {|| }
assert a_fun() == 4       // calls to eval the function
```

The simplest function resembles a scope with at `{` followed by a sequence of
statements where the last statement can be an expression before the closing
`}`.

The difference between a function and a normal scope is the function definition
enclosed between pipes (`|`).

```txt
[ATTRIBUTES] | [CAPTURE] [INPUT] [-> OUTPUT] [where COND] |
```

+ ATTRIBUTES are optional method modifiers like:
    - `comptime`: function should be computed at compile time
    - `debug`   : function is for debugging, not side effects in non-debug statements

+ META are a list of type identifiers or type definitions.

+ CAPTURE has the list of capture variables for the function. If no capture is
  provided, any local variable can be captured. An empty list (`[]`), means no
  captures allowed.

+ INPUT has a list of inputs allowed with optional types. If no input is provided, the `$` bundle is used as input.

+ OUTPUT has a list of outputs allowed with optional types. If no output is provided, the `%` bundle is used as output.

+ COND is the condition under which this statement is valid.

```
var add
add = {|| $a+$b+$c }              // no IO specified
add = {|a,b,c| a+b+c }            // constrain inputs to a,b,c
add = {|(a,b,c)| a+b+c }          // same
add = {|(a:u32,b:s3,c)| a+b+c }   // constrain some input types
add = {|(a,b,c) -> :u32| a+b+c }  // constrain result to u32
add = {|(a,b,c) -> (res)| a+b+c } // constrain result to be named res
add = {|(a:T,b:T,c:T)| a+b+c }    // constrain inputs to have same type

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

let my_log = {|debug|
  print "loging:"
  for i in $ {
    print " {}", i
  }
  puts
}

my_log a, false, x+1
```

## Implicit input/output tuple

The inputs and outputs on the current function can have an associated variable
with the function definition, but it is always possible to access the inputs
and outputs with the input tuple ($) and the output tuple (%). This allows
variable size arguments and simpler code for small code snippets.

```
let fun = {|(in1,in2)->(out1,out2)
  assert in1 == $.in1 and in2 == $.in2

  out1 = in1 + $in1
  out2 = out1 + in2 + $in2

  assert out1 == $.out1 and out2 == $.out2
}
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
languages.  A function is a code block that has an input tuple (`$`) performs
some statements and returns an output tuple (`%`). 

* Arguments can be named. E.g: `fcall(a=2,b=3)`
* There can be many return values. E.g: `return (a=3,b=5)`
* Inputs can be accessed with the bundle. E.g: `return $1 + $.arg_2 + $arg3`

There are several rules on how to handle function arguments.

* Calls use the Uniform Function Call Syntax (UFCS). `(a,b).f(x,y) == f((a,b),x,y)`
* Pipe |> concatenated inputs: `(a,b) |> f(x,y) == f(x,y,a,b)`
* Function calls with arguments do not need parenthesis after newline or a variable assignment: `a = f(x,y)` is the same as `a = f x,y`

Pyrope uses a uniform function call syntax (UFCS) like other languages (Nim or
D) but it can be different from the order in other languages. Notice the
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

Pyrope functions only pass arguments by value. This looks like a problem if we
implement a typical method. A method is a function associated to a tuple.  The
method can access the parent bundle fields and potentially update some of them.
To be consistent with the UFCS syntax, the tuple is passed as an input the
first argument (`self`). This works directly when the method does not update or
mutate the bundle contents. To allow updates the an output should have `self`.

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

A difference a method and a UFCS call is that the method has higher priority to
match.


```
var counter = (
  ,var val:i32
  ,let inc = {|(self, v)->(self) self.var += v }
)

assert counter.val == 0
counter.inc(3)
assert counter.val == 3

let inc = {|(self, v)->(self) self.var *= v } // NOT INC but multiply
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

Methods can access the tuple fields, it can also access the method previously
declared before override. To handle the override, Pyrope has the `super` keyword:

* `self` is an input and/or output but also a reserved word. It could be a
  tuple first input argument or the first output argument

* `super` provides access to the method before it was redefined


```
type base1 = (
  ,var fun = {|| 1 }
)
type base2 = (
  ,var fun = {|| 
    a = super
    assert a == 1
    2                    // last statement expression does not need a return
  }
)

type top = (
  ,let top_fun = {|| 4 }
  ,var fun = {||
    a = super()          // same as a = super
    assert a == 2
    return 33
  }
) ++ base2 ++ base1

var a3:top

assert a3.top_fun does :{||}
assert a3.top_fun() == 4
assert a3.top_fun.size == 1

assert a3.fun does :{||}
assert a3.fun.size == 3
assert a3.fun()    == 33

var a1:base1
var a2:base2
assert a1.fun() == 1
assert a2.fun() == 2
assert a1.fun.size == 1
assert a2.fun.size == 1
```


## Function call order


A functions can be added to an unamed tuple. Those functions can have different
number of arguments. When calling the tuple, the first function that matches
the number or aguments is called. The function call order also considers types,
this is addressed in the [07-typesystem](07-typesystem.md) section.


```
var fun_list = {|(a,b)| return a+b}
fun_list ++= {|(a,b,c)| return a+b+c }
fun_list ++= {|(a,b,c,d)| return a+b+c+d }

assert fun_list.size()

assert fun_list(1,2) == 3
assert fun_list(1,2,4) == 7
assert fun_list(1,2,4,5) == 12
assert fun_list(1,2,4,5,6) == 18 // compile error, no function with 5 args


fun_list ++= {|(a,b)| return 100}
assert fun_list(1,2) == 3

fun_list = {|(a,b)| return 200} ++ fun_list
assert fun_list(1,2) == 200
```


There are several ways to define functions, and there is a call order. First,
it tries to find an entry in the bundle that matches the function call. If it
does not exist, it looks for methods in the current function. It is not
possible to define custom methods per scope.


```
type T1 = (
  ,a:u32  // implicit a=0 initialization
)

inc = {|mut (self:T1)| self.a = u32(self.a+1) }

var x:T1
inc(x)
assert x.a == 1
x.inc()
assert x.a == 2

type T2 = T1 ++ (
  ,inc = {|mut (self:T2)| self.a = u32(self.a+2) }
)

var y:T2
assert y.a==0
inc(y)
assert y.a==1
y.inc()
assert y.a==3
```


Functions and methods can constrain the inputs and input types.
Unconstrained input types allow for more freedom and potential
variable number of arguments generics, but it can be error prone.

=== "unconstrained function declaration"
    ```
    foo = {|| puts "fun.foo" }
    a = (
      ,foo = {||
         bar = {|| puts "bar" }
         puts "mem.foo"
         return bar=bar
      )
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

=== "constrained function declaration"

    ```
    foo = {|(self)| puts "fun.foo" }  // explicit self
    a = (
      ,foo = {|()|                    // implicit self 
         bar = {|()| puts "bar" }
         puts "mem.foo"
         return bar=bar
      )
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



