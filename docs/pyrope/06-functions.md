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
  provided, any local variable can be captured by value. An empty list (`[]`),
  means no captures allowed. The captures are by value only, no capture by
  reference is allowed.

+ `INPUT` has a list of inputs allowed with optional types. `()` indicates no
  inputs. `(...args)` allow to accept a variable number of arguments.

+ `OUTPUT` has a list of outputs allowed with optional types. `()` indicates no
  outputs. `(...out)` will expand the out tuple as individual outputs.

+ `COND` is the condition under which this statement is valid. The `COND` can
  use the inputs, outputs, and `self` to evaluate. If the outputs are used in
  the `COND`, the lambda must be immutable (`fun`). This means that the method
  is called when the condition could evaluate true depending on its execution,
  but being immutable there are no side effects. The
  [overload](07b-structtype.md#lambda_overloading) section has more details.

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
add2 = fun       (a){   x + a }    // implicit capture x
add2 = fun[x    ](a){   x + a }    // explicit capture x
add2 = fun[     ](a){   x + a }    // compile error, undefined 'x'
add2 = fun[foo=x](a){ foo + a }    // capture x but rename to something else

var y = (
  ,val:u32 = 1
  ,inc1 = fun (self)->(self){ self.val = u32(self.val + 1) }
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

* Arguments can be named. E.g: `fcall(a=2,b=3)`
* There can be many return values. E.g: `ret (a=3,b=5)`

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
div  = fun (a,b) { a / b }          // named input tuple
div2 = fun (...x){ x.0 / x.1 }   // unnamed input tuple

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


The UFCS allows to have `functions` to call any tuple, but if the called tuple
has a lambda defined with the same name, the tuple lambda has a higher priority.

```
var tup = (
  ,let f1 = fun() { ret 1 }
)

let f1 = fun (b){ ret 2 }

assert f1()     == 2
assert f1(tup)  == 2
assert 4.f1()   == 2
assert tup.f1() == 1
```

The keyword `self` is used to indicate that the function is accessing a tuple.
It is also passed as the first argument. As a syntax sugar, when no inputs are
specified, the `self` can be from the input list when it is read by any
expression, but it is not added to the input tuple unless `self` is explicitly
listed. The output `self` is always needed if a mutable method is the
intention.

```
var tup = (
  ,var x = 3
  ,let f1 = fun(...rest){ assert rest.size == 0 ; ret self.x }
)

let fun2 = fun(b){ ret b.x             } // no self, but it is the same
let fun3 = fun(self,b){ ret self.x + b }

assert tup.f1() == 3   // tup.fun call
assert tup.f1 == 3     // explicit no args, so () is optional in call
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


Updates to tuples needed by `methods` are allowed when the output of the lambda
is a `self` keyword. Although not required, `methods` tend to also have `self`
as the first input argument.


For a method to update the tuple, the return value must be assigned to the
calling variable. As a syntax sugar, if the call does not have an assignment,
the same tuple assign is created.

```
var a_1 = (
  ,x:u10
  ,let f1 = fun(self,x)->(self) {
    self.x = x 
  }
)

a_1.f1(3)            // syntax sugar for a_1 = a_1.f1(3)
var a_2 = a_1.f1(4)  // a_2 is updated, not a_1
assert a_1.x == 3 and a_2.x == 4

// Same behavior as in a function with UFCS
fun2 = fun (self, x)->(self){ self.x = x }

a_1.fun2(10)    
var a_3 = a_1.fun2(20)
assert a_1 == 10 and a_3 == 20
```

A difference between a method and a UFCS call is that the method has a higher
priority to match. Like in the input syntax sugar, if no output is specified
and there is an update to a `self` variable, the compiler assumes `(self)` as
output tuple.


```
var counter = (
  ,var val:i32
  ,let inc = fun (self, v){ self.var += v }
)

assert counter.val == 0
counter.inc(3)
assert counter.val == 3

let inc = fun (self, v)->(self){ self.var *= v } // NOT INC but multiply
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
    let fun1 = proc(self)->(self){ self.foo = self.bar + 1}
    let fun2 = proc(    )->(self){ self.foo = self.bar + 1}
    let fun3 = proc(self)        { self.foo = self.bar + 1}
    let fun4 = proc(    )        { self.foo = self.bar + 1}

    // NOT equivalent because () means no input/output
    let non2 = proc()    ->(self){ self.foo = self.bar + 1}
    let non3 = proc(self)->()    { self.foo = self.bar + 1}
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

