# Modules


A module consists of sequence of statements which is a superset of functions,
procedures, and methods. Modules may not be visible when inlined.


In Pyrope, we call a function a sequence of code statements that do not read
or write from registers or memories. As a result, functions are pure
combinational code blocks.  A procedure is a function that reads and/or writes
registers/memories. Notice that a procedure may still have the outputs
connected through a combinational path to the inputs.  Methods are procedures
that operate over a given tuple. Functions, procedures, and method may have
return values.


## module definition

Modules are like programming language lambdas that must be passed as arguments
or assigned to a given variable[^3]. There is no global scope for variables or
modules. The only way for a file to access a module is to have access to a
local variable with a module definition or to "import" a variable from another
top level file.

```
let a_3   = {   3 } // just scope, not a module. Scope is evaluate now
let a_fun = {|| 4 } // local function, when just_4 is called 4 is returned

pub let fun3 = {|| 5 }    // public module that can be imported by other files

let x = a_3()             // compile error, explicit call not posible in scope
let x = a_fun()           // OK, explicit call

assert a_3 equals 3
assert a_fun equals {|| }
assert a_fun() == 4       // calls to eval the function
```

The simplest module resembles a scope with at `{` followed by a sequence of
statements where the last statement can be an expression before the closing
`}`.  The difference between a function and a normal scope is the function
definition enclosed between pipes (`|`).

[3]: Since modules are only accesible afterwards when assigned to variables, Pyrope
can not allow module hosting because it is assigned to a normal variable.


```txt
[CAPTURE] [INPUT] [-> OUTPUT] [where COND] |
```

+ `CAPTURE` has the list of capture variables for the function. If no capture
  is provided, any local variable can be captured. An empty list (`[]`), means
  no captures allowed. The captures are by value only, no capture by reference
  is allowed.

+ `INPUT` has a list of inputs allowed with optional types. If no input is
  provided, the `$` input tuple can be used. `()` indicates no inputs.

+ `OUTPUT` has a list of outputs allowed with optional types. If no output is
  provided, the `%` output tuple can be used. `()` indicates no outputs.

+ `COND` is the condition under which this statement is valid. The `COND` can
  use the inputs AND outputs to evaluate. If the `COND` evaluates false
  statement is not evaluated. When (explicit method
  overload)[07-typesystem.md#explicit-function-overloading] is used a false
  `COND` means that the next statement should be tried.

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

my_log a, false, x+1
```

## Implicit input/output tuple

The inputs and outputs on the current function can have an associated variable
with the function definition, but it is always possible to access the inputs
and outputs with the input tuple (`$`) and the output tuple (`%`). This allows
variable size arguments and simpler code for small code snippets. It also
simplifies instrospection since all the inputs are in `$` and all the outputs
are in `%`.

```
let fun = {|(in1,in2)->(out1,out2)|
  assert in1 == $.in1 and in2 == $.in2

  out1 = in1 + $in1
  out2 = out1 + in2 + $in2

  assert out1 == $.out1 and out2 == $.out2
}
```

## Arguments

Module calls only pass arguments by value. Unlike most software languages,
there is no pass by reference.

* Arguments can be named. E.g: `fcall(a=2,b=3)`
* There can be many return values. E.g: `return (a=3,b=5)`
* Inputs can be accessed with the `$` tuple. E.g: `return $1 + $.arg_2 + $arg3`

There are several rules on how to handle arguments.

* Calls use the Uniform Function Call Syntax (UFCS). `(a,b).f(x,y) == f((a,b),x,y)`

* Pipe |> concatenated inputs: `(a,b) |> f(x,y) == f(x,y,a,b)`

* Function calls with arguments do not need parenthesis after newline or a
  variable assignment: `a = f(x,y)` is the same as `a = f x,y`

Pyrope uses a uniform function call syntax (UFCS) like Nim or D but it can be
different from the order in other languages. Notice the different order in
UFCS vs pipe, and also that in the pipe the argument tuple is concatenated,
but in UFCS is added as the first argument.

```
div  = {|a,b| a / $b }   // named input tuple
div2 = {|| $0 / $1 }     // unnamed input tuple

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

## Setup vs Reset vs Execution

In a normal programming language, when the code is executed is clear. There
may be a macro or template system executed at compile time, the rest of the
code is called explicitly when the function is called. One difference between
HDLs and non-HDLs is that hardware tends to have 3 sections of code:


* Setup: This is code executed to setup the hierarchies, parameters, read
  configuration setups... It is usually executed at compile time. In Verilog
  these are the pre-processor directives and the generate statements.  In
  CHISEL, the scala is the setup code.

* Reset: Hardware starts in an undefined/inconsistent state. Usually, a reset
  signal is enabled several cycles and the associated reset logic configures
  the system to a given state.

* Execution: This is the code executed every cycle after reset. The reset
  logic activation can happen at any time, and parts of the machine maybe in
  reset mode while others are not.


In addition, some languages like Verilog have "initialization" code that is
executed before reset. This is usually done for debugging, and it is not
synthesizable. Pyrope does not have such simulation only code.


Pyrope aims to have the setup, reset, and execution specified.

### Setup code

Compiling a Pyrope program requires to specify a "top" file. The top file is
executed only once. The top file may "import" other files. Each of the imports
is executed only once too. The imported files are executed before the current
file is executed. This is applied recursively but no loops are supported in
import dependence chains.


During setup, each file can have a list of `pub` variables. Those are
variables that can be used by importing modules. The `pub` in the top file are
simulation of synthesis targets.


It is important to point that `comptime` may be used during setup but also in
non-setup code. `comptime` just means that the associated variables are known
at compile time. This is quite useful during reset and execution too.


### Reset


The most common reset logic is associated with registers and memories. The
assignment to `reg` variable declaration is the reset code. It will be called
for as many cycles are the reset is held active.  The `reg` assignment can be
a constant or a call to `conf` that can provide a runtime file with the values
to start the simulation/synthesis.


```
reg r:u16 = 3 // reset sets r to 3
r = 2         // non-reset assignment

reg array:u16[] = (1,2,3,4)  // reset values

reg r2:u128 = conf.get("my_data.for.r2")

reg array:[] = cong.get("some.conf.hex.dump")
```

When a state machine is needed to execute for several cycles a tuple with an
`always_reset` must be created and assigned to the register[s] that use it.

```
reg array:tag[1024] = (
  ,clock=my_clock

  ,always_reset = {|(self)->(self)|
     reg reset_iter:u10 = (reset="") // no reset flop

     self[reset_iter].state = I

     reset_iter = u10(reset_iter + 1)
  }
)
```


### Execution

HDLs specify a tree-like structure of modules. Usually, there is a top module
that instantiates several sub-modules. Pyrope Setup phase is to create such
hierarchical structures.


The hierarchy is achieved with modules calling other modules. The top file can
have one or more modules.

The following Verilog hierarchy can be encoded with the equivalent Pyrope:

=== "Verilog"

    ```verilog
    module inner(input z, input y, output a, output h);
      assign a =   y & z;
      assign h = !(y & z);

    endmodule

    module top2(input a, input b, output c, output d);

    inner foo(.y(a),.z(b),.a(c),.h(d));

    endmodule
    ```

=== "Pyrope equivalent"


    ```
    pub let inner = {|(z,y)->(a,h)|
      a =   y & z
      h = !(y & z)
    }

    pub let top2 = {|(a,b)->(c,d)|
      let x= inner(y=a,z=b)
      c = x.a
      d = x.h
    }
    ```

=== "Pyrope alternative"

    ```
    type inner_t = (
      ,pub set = {|(z,y)->(self)|
        self.z = z
        self.y = y
      }
      ,always_after = {||
        self.a =   self.y & self.z
        self.h = !(self.y & self.z)
      }
    )

    pub let top2 = {|(a,b)->(c,d)|
      let foo:inner_t = (y=a,z=b)
      c = foo.a
      d = foo.h
    }
    ```


The top level module `top2` must be a module, but as the alternative Pyrope
syntax shows, the inner modules may be in tuples or direct module calls. The
are advantages to each approach but the code quality should be the same.


## Methods

Pyrope methods only pass arguments by value. This looks like a problem if we
implement a typical method. A method is a function associated with a tuple.
The method can access the parent tuple fields and potentially update some of
them.  To be consistent with the UFCS syntax, the tuple is passed as input the
first argument (`self`). This works directly when the method does not update
or mutate the tuple contents. To allow updates the output should have `self`.

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

A difference between a method and a UFCS call is that the method has a higher priority to
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

`self` is an input and/or output but also a reserved word. It could be a tuple
first input argument or the first output argument

!!!NOTE
    To avoid verbose `self` in methods, the compiler automatically inserts a
    `self` as the first entry in the input tuple if the `self` variable is ever
    read in the method. Similartly, it inserts in the output tuple if it is
    every written in the method.

    ```
    // equivalent code due to automatic `self` insertion
    let fun1 = {|(self,a)->(self)| self.foo = self.bar + a}
    let fun2 = {|(a     )->(self)| self.foo = self.bar + a}
    let fun3 = {|(self,a)->()    | self.foo = self.bar + a}
    let fun4 = {|(a     )->()    | self.foo = self.bar + a}
    ```

## Arguments


Arguments can constrain the inputs and input types. Unconstrained input types
allow for more freedom and potential variable number of arguments generics, but
it can be error-prone.

=== "unconstrained declaration"
    ```
    foo = {|| puts "fun.foo" }
    a = (
      ,foo = {||
         bar = {|| puts "bar" }
         puts "mem.foo"
         return (bar=bar)
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
         return (bar=bar)
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

## Method overloading

When overloading, methods are typically added at the end `++=` of the tuple.
This means that it is NOT overwriting an existing functionality, but providing
a new call capability.

If the intention is to redefine or intercept, the method must be added at the
head of the tuple.

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

A more traditional "overload" calling the is possible by calling the method directly:

```
type x extends base with (
  ,pub var fun1 = {|| base.fun1() + 100 }
)
```

To allow overloading the base method must be declared as `var`. The result is
that API methods should have a `pub var` API.


## Overloading call order


Multiple modules can be added to the same variable, effectively creating an
unnamed tuple with a module per tuple entry. When calling the tuple the
following rule applies:


* If the caller uses "unnamed arguments", look for the first entry has the same
  number of arguments and where each argument type is compatible[^2]. If none
  found, then look for a function without argument constrains.

* If the caller uses "named arguments", pick the first module that has an exact
  match in the named tuple and the types are compatible. If none found, apply
  the "unnamed arguments" rule.

* Once a module is found, evaluate the `COND`. If the `COND` is not comptime,
  call the module and look for the next module that may also satisfy the
  arguments constrains. If a `COND` is comptime true (or no `COND`), stop
  selecting additional modules. If `COND` is comptime false remove from list
  and continue. All the selected modules will be executed, but the output will
  be selected based in priority order based on the `COND` result.



[2]: The type match is addressed in the [07-typesystem](07-typesystem.md)
section.


For unnamed argument calls:

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

For named argument calls:

```
var fun = {|(a,b)| return a+b+100 }
  fun ++= {|(x,y)| return x+y+200 }

assert fun(a=1,b=2) == 103
assert fun(x=1,y=2) == 203
assert fun(  1,  2) == 103  // first in list
```

For conditional argument calls:

```
var fun = {|(a,b)      where a>40    | return b+100 }
  fun ++= {|(a,b)->(x) where x > 300 | return b+200 } // output x
  fun ++= {|(a,b)->(a) where $.a > 20| return b+300 } // input a
  fun ++= {|(a,b)->(a) where %.a > 10| return b+400 } // output a
  fun ++= {|(a,b)                    | return a+b+1000 } // default

var fun_manual = {|(a,b)|
  if a>40 {
    return b+100
  }
  let x = b + 200
  if x>300 {
    return (x=x)
  }
  if a>20 {
    return b+300
  }
  let tmp = a + b
  if tmp >10 {
    return (a=tmp)
  }
  return a+b+1000
}

test "check equiv" {
  for a in -100..=100 {
    for b in -100..=100 {
      assert fun(a,b) == fun_manual(a,b)
    }
  }
}
```


