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
let a_3   = {   3 }     // just scope, not a lambda. Scope is evaluate now
let a_fun = fun() { 4 } // local function, when just_4 is called 4 is returned

pub let fun3 = fun(){ 5 } // public lambda that can be imported by other files

let x = a_3()             // compile error, explicit call not posible in scope
let x = a_fun()           // OK, explicit call

assert a_3 equals 3
assert a_fun equals :fun()
assert a_fun() == 4       // calls to eval the function
```

The lambda definition has the following fields:

```txt
[GENERIC] [CAPTURE] [INPUT] [-> OUTPUT] [where COND] |
```

+ `GENERIC` is an optional comma separated list of names between `<` and `>` to
  use as generic types in the lambda.

+ `CAPTURE` has the list of capture variables for the lambda. If no capture is
  provided, no local variable can be captured by value which is equivalent to
  an empty list (`[]`), The captures are by value only, no capture by reference
  is allowed. Unlike most languages, capture must be comptime. Section
  [Closures](10-internals.md#Closures) has more details.

+ `INPUT` has a list of inputs allowed with optional types. `()` indicates no
  inputs. `(...args)` allow to accept a variable number of arguments.

+ `OUTPUT` has a list of outputs allowed with optional types. `()` indicates no
  outputs.

+ `COND` is the condition under which this statement is valid. The `COND` can
  use the inputs, outputs, and `self` to evaluate. If the outputs are used in
  the `COND`, the lambda must be immutable (`fun`). This means that the method
  is called when the condition could evaluate true depending on its execution,
  but being immutable there are no side effects. Section
  [overload](07b-structtype.md#lambda_overloading) has more details.

```
var add
add = fun (...x) { x.0+x.1+x.2 }       // no IO specified
add = fun (a,b,c){ a+b+c }            // constrain inputs to a,b,c
add = fun (a,b,c){ a+b+c }            // same
add = fun (a:u32,b:s3,c){ a+b+c }     // constrain some input types
add = fun (a,b,c) -> (x:u32){ a+b+c } // constrain result to u32
add = fun (a,b,c) -> (res){ a+b+c }   // constrain result to be named res
add = fun (a,b:a,c:a){ a+b+c }        // constrain inputs to have same type
add = fun <T>(a:T,b:T,c:T){ a+b+c }   // same

x = 2
var add2
add2 = fun       (a){   x + a }    // compile error, undefined 'x'
add2 = fun[     ](a){   x + a }    // compile error, undefined 'x'
add2 = fun[x    ](a){   x + a }    // explicit capture x
add2 = fun[foo=x](a){ foo + a }    // capture x but rename to something else

var y = (
  ,val:u32 = 1
  ,inc1 = fun (ref self) { self.val = u32(self.val + 1) }
)

debug let my_log = fun (...inp) {
  print "loging:"
  for i in inp {
    print " {}", i
  }
  puts
}

let f = fun<X>(a:X,b:X){ ret a+b }   // enforces a and b with same type
assert f(33:u22,100:u22)

my_log a, false, x+1
```

## Arguments

Lambda calls only pass arguments by value. Unlike most software languages,
there is no way to pass by reference.

Input arguments must be named. E.g: `fcall(a=2,b=3)` There are the following
exceptions that avoid naming arguments:

* If the argument is a single letter, it does not need to be names

* If the type system can distinguish between unnamed arguments

* The calling variable name has the same as an argument


There are several rules on how to handle arguments.

* Calls use the Uniform Function Call Syntax (UFCS) when a `self` is defined as
  first argument. `(a,b).f(x,y) == f((a,b),x,y)`

* Pipe `|>` concatenated inputs: `(a,b) |> f(x,y) == f(x,y,a,b)`

* Function calls with arguments do not need parenthesis after newline or a
  variable assignment: `a = f(x,y)` is the same as `a = f x,y`

* Functions explicitly declared without arguments, do not need parenthesis in
  function call.

Pyrope uses a Uniform Function Call Syntax (UFCS) when the first argument is
`self`. It resembles Nim or D UFCS but it can be different from the order in
other languages. Notice the different order in UFCS vs pipe, and also that in
the pipe the argument tuple is concatenated.

```
div  = fun (a,b) { a / b }        // named input tuple
div2 = fun (...x){ x.0 / x.1 }    // unnamed input tuple

noarg = fun () { ret 33 }         // explicit no args

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


The UFCS allows to have `lambdas` to call any tuple, but if the called tuple
has a lambda defined with the same name a compile error is generated. Like with
variables, Pyrope does not allow `lambda` call shadowing. Polymorphism is allowed
but only explicit one as explained later.

```
var tup = (
  ,let f1 = fun(self) { ret 1 }
)

let f1 = fun (self){ ret 2 }
let f2 = fun (self){ ret 3 }

assert f1()     == 2
assert f1(tup)  == 2
assert 4.f1()   == 2  // compile error, shadowing between tuple and lambda
assert 4.f2()   == 3  // UFCS call
assert tup.f1() == 1
```

The keyword `self` is used to indicate that the function is accessing a tuple.
It is usually passed as the first argument, an output `self` is needed for methods
that can mutate the tuple state.

```
var tup = (
  ,var x = 3
  ,let f1 = fun(self, ...rest) { assert rest.size == 0 ; ret self.x }
)

let fun2 = fun(self){ ret self.x       }
let fun3 = fun(self,z){ ret self.x + z }

assert tup.f1() == 3   // tup.fun call
assert tup.f1 == 3     // explicit no args, so () is optional in call
assert fun2(tup) == 3
assert tup.fun2() == 3  // UFCS

assert fun3(tup) == 3   // compile error, missing b arg
assert tup.fun3() == 3  // compile error, missing b arg
assert fun3(tup,2) == 5
assert tup.fun3(2) == 5
```

## Pass by Reference and alias

Pyrope arguments are by value, unless the `ref` keyword is used. Pass by
reference is needed in three main cases: (1) allow methods to update the object
instance; (2) pass variables to functions without needing to copy values like
registers; (3) avoid function calls when passed as argument.

In all those cases, the pass by reference behaves like if the calling lambda
were inlined in the caller lambda. The `ref` keyword must be explicit in the
lambda input definition but also in the lambda call. The lambda outputs can not
have a `ref` modifier.


```
let inc1 = fun(ref a) { a += 1 }

let x = 3
inc1(ref x)       // compile error, no mutable access to x inside inc1

var y = 3
inc1(ref y)
assert y == 4

let banner = fun() { puts "hello"  }
let execute_method = fun(ref fn) {
  fn() // prints hello
}

execute_method(ref banner) // OK
execute_method(banner)     // compile error, ref explicitly expected
```

A lambda will be called whenever referenced. When calling a method, a `ref` can
be added before to avoid the lambda call. A related issue is when a lambda must
be assigned to another variable without calling. In a way, it is an alias or
reference creation. Because it is more intuitive to see it as an alias, the
`alias` keyword is used in this case, but it has the same meaning.

```
let f1 = fun() { puts "here" }

let f2 = f1 // prints here

alias f3 = f1
f3          // prints here
```

### Output tuple

Pyrope everything is a tuple, even the output or return from a lambda. When a
single element is returned, it can be an unnamed tuple by omiting parenthesis.

```
let ret1 = fun()->(a:int) { // named
  a = 1
}

let ret2 = fun()->a:int {   // unnamed
  a = 2
}

let ret3 = fun()->(a,b) {   // named
  a = 3
  b = 4
}

let a1 = ret1()
assert a1.a == 1 // NOT a1 == 1

let a2 = ret2()
assert a2 == 1   // NOT a2.a == 1

let a3 = ret3()
assert a3.a == 3 and a2.b == 4

let x1,x2 = ret3()
assert x1 == 3 and x2 == 4
```
## Methods

Pyrope arguments are by value, unless the `ref` keyword is used. `ref` is
needed when a method intends to update the tuple contents. In this case, `ref
self` argument behaves like a pass by reference in non-hardware languages. This
means that the tuple fields are updated as the method executes, it does not
wait until the method finishes execution. A method without the `ref` keyword is
a pass by value call. Since all the inputs are immutable by default (`let`),
any `self` updates should generate a compile error.

```
type Nested_call = (
  ,var x = 1
  ,let outter= proc(ref self) {  self.x = 100 ; self.inner(); self.x = 5 }
  ,let inner = fun(self) { assert self.x == 100 }
  ,let faulty = proc(self) { self.x = 55 } // compile error, immutable self
)
```

`self` can also be returned but this behaves like a normal copy by value
variable return.

```
var a_1 = (
  ,x:u10
  ,let f1 = fun(ref self,x)->(self) { // BOTH ref self and return self is OK
    self.x = x 
    ret self
  }
)

a_1.f1(3)
var a_2 = a_1.f1(4)  // a_2 is updated, not a_1
assert a_1.x == 3 and a_2.x == 4

// Same behavior as in a function with UFCS
fun2 = fun (ref self, x) { self.x = x }

a_1.fun2(10)    
var a_3 = a_1.fun2(20)
assert a_1 == 10 and a_3 == 20
```

Since UFCS does not allow shadowing, a wrapper must be built or a compile error is generated.

```
var counter = (
  ,var val:i32
  ,let inc = fun (ref self, v){ self.var += v }
)

assert counter.val == 0
counter.inc(3)
assert counter.val == 3

let inc = fun (ref self, v) { self.var *= v } // NOT INC but multiply
counter.inc(2)             // compile error, multiple inc options
assert 44.inc(2) == 8

counter.val = 5
alias mul = inc
counter.mul(2)   // call the new mul method with UFCS
assert counter.val == 10

mul(counter, 2) // also legal
assert counter.val == 20
```


For `type` and `var`, it is possible to add new methods after the type declaration.

```
type t1 = (a:u32)

var x:t1 = (a=3)
x.double // compile error, double method does not exit

t1.double = proc(ref self) { self.a *= 2 }
// previous is exactly the same as:
// t1 = t1 ++ (double = proc(ref self) { self.a *= 2 })

var y:t1 = (a=3)
y.double // OK
assert y.a == 6
```

## Arguments

Arguments can constrain the inputs and input types. Unconstrained input types
allow for more freedom and a potentially variable number of arguments generics, but
it can be error-prone.

=== "unconstrained declaration"
    ```
    foo = fun () { puts "fun.foo" }
    a = (
      ,foo = fun () {
         bar = fun() { puts "bar" }
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
    a.foo 3   // compile error: parenthesis needed (hierarchical function call)
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
    foo = fun (self){ puts "fun.foo" }  // explicit self
    a = (
      ,foo = fun (){                    // implicit self 
         bar = fun (){ puts "bar" }
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

