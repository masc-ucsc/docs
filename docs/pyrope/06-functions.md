# Lambdas


A `lambda` consists of a sequence of statements that can be bound to a variable.
The variable can be copied and called as needed. Unlike most languages, Pyrope
only supports anonymous lambdas. The reason is that without it lambdas would be
assigned to a namespace. Supporting namespaces would avoid aliases across
libraries, but Pyrope allows different versions of the same library at
different parts of the project. This will effectively create a namespace alias.
The solution is to not have namespaces but relies upon variable scope to decide
which lambda to call.


!!! Observation

    Allowing multiple version of the same library/code is supported by Pyrope.
    It looks like a strange feature from a software point of view, but it is
    common in hardware to have different blocks designed/verified at different
    times. The team may not want to open and modernize a block. In hardware, it
    is also common to have different blocks to be compiled with different
    compiler versions. These are features that Pyrope enables.


Pyrope divides the lambdas into four categories: `comb`, `pipe`, `flow`, and `mod`.

- `comb` operates only over combinational logic. The outputs are purely a
  function of the inputs — no registers, no state, no cycle-level side effects.
  Any external call inside a `comb` can only affect debug statements (e.g.,
  `puts`), not synthesizable code. `comb` can use `ref` arguments to modify
  tuples; `ref` is equivalent to having the argument as both input and output,
  which is still purely combinational. `comb` resembles `pure functions` in
  normal programming languages.

- `pipe` is a Moore machine — outputs always go through flops (at least 1
  stage, never `pipe[0]`). The latency is written as an argument to the
  keyword: `pipe[3] foo(...)` is fixed 3-cycle, `pipe[1..=3] foo(...)` lets
  the caller pick within a range, and bare `pipe foo(...)` leaves the
  latency fully flexible for the caller to specify via `await[N]` inside a
  `flow`. The tool may retime logic for performance, but the behavior is
  equivalent to a `comb` with N flops appended at the outputs. `pipe` can use
  `reg` for internal storage, but besides storage, it behaves like a `comb`
  with pipelined outputs.

- `flow` connects `comb`, `pipe`, or other `flow` blocks with explicit timing
  control. Inside a `flow`, a declaration modifier `await[N]` requests N
  cycles of pipelining for the whole RHS, and `:@[N]` on any variable is a
  pure timing type check. This gives the designer full control over where
  pipeline stages are placed. `flow` can also use `reg` for persistent state
  across cycles.

- `mod` has no constraints on how registers and outputs are used. Unlike `pipe`
  (Moore machine with registered outputs), `mod` can have combinational or
  registered outputs in any arrangement. `mod` operates cycle by cycle with
  explicit register reads and writes.

Methods are `comb`/`pipe`/`flow`/`mod` lambdas that have `self` as the first
argument, which allows operating on tuples.

=== "Combinational (comb)"
    ```
    const add = comb(a, b) -> (result) {
      result = a + b
    }

    comb add(a, b) -> (result) {  // Same as const add = comb(a, b) -> (result)
      result = a + b
    }
    ```

=== "Pipeline (pipe)"
    ```
    pipe[3] multiply(a, b) -> (result) {          // fixed 3-cycle latency
      result = a * b
    }

    pipe[1..=3] add_pipe(a, b) -> (result) {      // caller picks 1-3 cycles
      result = a + b
    }

    pipe flexible_mul(a, b) -> (result) {         // bare: caller picks via await[N]
      result = a * b
    }
    ```

=== "Flow (flow)"
    ```
    pipe mul(a, b) -> (c) { c = a * b }
    pipe add(a, b) -> (c) { c = a + b }

    flow multiply_add(in1, in2) -> (out) {
      await[3] tmp      = mul(in1, in2)
      await[3] in1_d    = in1
      await[1] out:@[4] = add(tmp:@[3], in1_d:@[3])
    }

    flow accum(in1, in2) -> (out) {
      reg total = 0                             // flow can use reg
      await[3] tmp = mul(in1, in2)
      total::[defer] = add(total, tmp:@[3])
      out = total
    }
    ```

=== "Module with registers (mod)"
    ```
    mod counter(enable) -> (reg count) {
      count += 1 when enable
    }

    mod add_reg(a, b) -> (reg result) {
      result = a + b
    }
    ```

## Declaration

Only anonymous lambdas are supported, this means that there is no global scope
for functions, procedures, or modules. The only way for a file to access a
lambda is to have access to a local variable with a definition or to "import" a
variable from another file. The more familiar `comb name` or `pipe name`
declaration is also valid, but it is syntax sugar and equivalent to `const name =
comb`.

```
const a_3 = { 3 }            // just scope, not a lambda. Scope is evaluate now
const a_lambda = comb() { 4 } // when a_lambda is called 4 is returned

const get_five = comb() { 5 } // public lambda that can be imported by other files

const x = a_3()            // compile error, explicit call not possible in scope
const x = a_lambda()       // OK, explicit call needed when no arguments

assert a_3 == 3
assert a_lambda equals _:comb()
assert a_lambda() == 4
```

The lambda definition has the following fields:

```txt
[GENERIC] [CAPTURE] [INPUT] [-> OUTPUT] [where COND] |
```

+ `GENERIC` is an optional comma separated list of names between `<` and `>` to
  use as generic types in the lambda.

+ `CAPTURE` has the list of **comptime parameters** for the lambda. Each entry
  may be a bare name (which captures a same-named value from the enclosing
  scope as its default), a typed declaration (e.g., `n:int`), or a typed
  declaration with a default (e.g., `n:int=1`). If no capture list is
  provided, no local variable can be captured by value which is equivalent to
  an empty list (`[]`). Captures are by value only; no capture by reference is
  allowed, and all capture values must be comptime. Callers can **override**
  any comptime parameter at the call site using the same `[...]` slot
  (`foo[N](args)`). Section [Closures](10-internals.md#Closures) has more
  details.

+ `INPUT` has a list of inputs allowed with optional types. `()` indicates no
  inputs. `(...args)` allow to accept a variable number of arguments.

+ `OUTPUT` has a list of outputs allowed with optional types. `()` indicates no
  outputs.

+ `COND` is the condition under which this statement is valid. The `COND` can
  use the inputs, outputs, and `self` to evaluate. If the outputs are used in
  the `COND`, the lambda must be immutable (`comb`). This means that the method
  is called when the condition could evaluate true depending on its execution,
  but being immutable there are no side effects. Section
  [overload](07b-structtype.md#lambda_overloading) has more details.

```
mut add:comb(...x) = ?
add = comb(...x) { x[0] + x[1] + x[2] }     // no IO specified
add = comb(a, b, c) { a + b + c }        // constrain inputs to a,b,c
add = comb(a, b, c) { a + b + c }        // same
add = comb(a:u32, b:s3, c) { a + b + c } // constrain some input types
add = comb(a, b, c) -> (x:u32) { a + b + c } // constrain result to u32
add = comb(a, b, c) -> (result) { a + b + c } // constrain result to be named result
add = comb(a, b:a, c:a) { a + b + c }    // constrain inputs to have same type
add = comb<T>(a:T, b:T, c:T) { a + b + c } // same

const x = 2
mut add2:comb(a) = ?
add2 = comb       (a) { x + a }    // compile error, undefined 'x'
add2 = comb[     ](a) { x + a }    // compile error, undefined 'x'
add2 = comb[x    ](a) { x + a }    // explicit capture x (default = enclosing x)
add2 = comb[foo=x](a) { foo + a }  // capture x but rename to something else

// Comptime parameters can be declared with a type and/or default:
const scale = comb[n:int=1](a) { n * a }
assert scale(5) == 5           // uses default n=1
assert scale[10](5) == 50      // override n=10 at the call site

// Captures can also be overridden at the call site:
const y = 3
const addy = comb[y](a) { y + a }
assert addy(4) == 7            // uses captured y=3
assert addy[100](4) == 104     // override y=100 at the call site

mut y = (
  val:u32 = 1,
  inc1 = comb (ref self) { self.val = u32(self.val + 1) }
)

const my_log::[debug] = comb (...inp) {
  print "logging:"
  for i in inp {
    print " {}", i
  }
  puts
}

const f = comb<X>(a:X, b:X) { a + b }   // enforces a and b with same type
assert f(33:u22, 100:u22) == 133

my_log(a, false, x + 1)
```

## Argument naming

Input arguments must be named. E.g: `fcall(a=2,b=3)` There are the following
exceptions that avoid naming arguments:

* If the type system can distinguish between unnamed arguments (no ambiguity)

* If there is an argument/call match. The calling variable name has the same as an argument

* If the argument is a single letter, and there is no name match, only position is used

* `self` does not need to be named (first argument position)


There are several rules on how to handle arguments.

* Calls use the Uniform Function Call Syntax (UFCS) but only when `self` is defined as
  first argument. `(a,b).f(x,y) == f((a,b),x,y)`

* Pipe `|>` concatenated inputs: `(a,b) |> f(x,y) == f(x,y,a,b)`

* Function calls with arguments do not need parenthesis after newline or a
  variable assignment: `a = f(x,y)` is the same as `a = f x,y`

* Functions without arguments, need explicit parenthesis in function call.

Pyrope uses a Uniform Function Call Syntax (UFCS) when the first argument is
`self`. It resembles Nim or D UFCS but it can be different from the order in
other languages. Notice the different order in UFCS vs pipe, and also that in
the pipe the argument tuple is concatenated.

```
const div  = comb (self, b) { self / b }  // named input tuple
const div2 = comb (...x) { x[0] / x[1] }    // unnamed input tuple

const noarg = comb () { 33 }         // explicit no args

assert 33 == noarg()              // () needed to call

assert noarg // compile error, `noarg()` needed for calls without arguments

a = div(3, 4, 3)         // compile error, div has 2 inputs
b = div(self=8, b=4)     // OK, 2
c = div(self=8, b=4)     // compile error, parenthesis needed for complex call
d = (self=8).div(b=2)    // OK, 4
d = (8).div(b=2)         // OK, 4 . self does not need to be named
d = 8.div(2)             // OK, single character inputs no need to be named
e = (self=8).div(b=2)    // compile error, parenthesis needed for complex call

h = div2(8, 4, 3)        // OK, 2 (3rd arg is not used)
i = 8.div2(4, 3)         // compile error, no self in div2

j = (8, 4) |> div2       // OK, 2, same as div2(8,4)
j = (8, 4) |> div2()     // OK, 2, same as div2(8,4)
k = (4) |> div2(8)       // OK, 2, same as div2(8,4)
l = (4, 33) |> div2(8)   // OK, 2, same as div2(8,4,33)
m = 4 |> div2(8)         // compile error, parenthesis needed for complex call

n = div((8, 4), 3)       // compile error: (8,4)/3 is undefined
o = (8, 4).div2(1)       // compile error: (8,4)/1 is undefined
```


The UFCS allows to have `lambdas` to call any tuple, but if the called tuple
has a lambda defined with the same name a compile error is generated. Like with
variables, Pyrope does not allow `lambda` call shadowing. Polymorphism is allowed
but only explicit one as explained later.

```
mut tup = (
  f1 = comb(self) { 1 }
)

const f1 = comb (self) { 2 } // compile error, f1 shadows tup.f1
const f1 = comb () { 3 }      // OK, no self

assert f1() != 0         // compile error, missing argument
assert f1(tup) != 0      // compile error, f1 shadowing (tup.f1 and f1)
assert 4.f1() != 0       // compile error, f1 can be called for tup, so shadow
assert tup.f1() != 0     // compile error, f1 is shadowing

const xx = comb[tup] { tup.f1() } // OK, function restricted scope for f1
assert xx() == 1

assert (4:tup).f1() == 1
assert 4.f1() == 3        // UFCS call
assert tup.f1() == 1
```

The keyword `self` is used to indicate that the function is accessing a tuple.
`self` is required to be the first argument. If the method modifies the tuple
contents, a `ref self` must be passed as input. Since `ref` is equivalent to
having the argument as both input and output, `comb` can use `ref` and still
be purely combinational. Use `mod` only when the method needs registers or
cycle-level state.


```
mut tup2 = (
  val:u8 = ?,
  upd = comb(ref self) { self.val::[saturate] += 1 },
  calc = comb(self) { self.val }
)
```

A lambda call uses parenthesis (`foo() or foo(1,2)`). The parenthesis can be
avoid in tree conditions: (1) arguments are passed in a simple function call
statement; (2) after a pipeline directive; (3) the variable has a getter method
(`get`).

```
no_arg_fun()     // must use explicit parenthesis/called
arg_fun(1, 2)    // parenthesis recommended
arg_fun(1, 2)    // OK too
(1, 2) |> arg_fun // OK too, it is after |>

mut intercepted:(
  field:u32,
  getter = comb(self) { self.field + 1 },
  setter = comb(ref self, v) { self.field = v }
) = 0

cassert intercepted == 1  // will call getter method without explicit call
cassert intercepted.field == 0
```

## Pass by reference

Pyrope is an HDL, and as such, there are not memory allocation issues. This
means that all the arguments are pass by value and the language has value
semantics. In other words, there is not need to worry about ownership or
move/forward semantics like in C++/Rust. All the arguments are always by value.
Nevertheless, sometimes is useful to pass a reference to an array/register so
that it can be updated/accessed on different lambdas.


Pyrope arguments are by value, unless the `ref` keyword is used. Pass by
reference is needed to avoid the copy by value of the function call. Unlike
non-hardware languages, there is no performance overhead in passing by value.
The reason for passing as reference is to allow the lambda to operate over the
passed argument. If modified, it behaves like if it were an implicit output.
This is quite useful for large objects like memories to avoid the copy.


The pass by reference behaves like if the calling lambda were inlined in the
caller lambda while still respecting the lambda scope. The `ref` keyword must
be explicit in the lambda input definition but also in the lambda call. The
lambda outputs can not have a `ref` modifier.


No logical or arithmetic operation can be done with a `ref`. As a result, it is
only useful for lambda input arguments.


```
const inc1 = comb(ref a) { a += 1 }

const x = 3
inc1(ref x)       // compile error, `x` is immutable but modified inside inc1

mut y = 3
inc1(ref y)
assert y == 4

const banner = comb() { puts "hello" }
const execute_method = comb(fn:comb() -> ()) {  // example with explicit type for fn
  fn() // prints hello when banner passed as argument
}

execute_method(banner)     // OK
```

In Pyrope, to call a method, parenthesis are needed only when the method has arguments.
This is needed to distinguish for higher order functions that need to distinguish between
a function call and a pass of the lambda.

## Output tuple

Pyrope everything is a tuple, even the output or return from a lambda. The
output type always uses parenthesis.

```
const ret1 = comb() -> (a:int) {
  a = 1
}

const ret3 = comb() -> (a, b) {
  a = 3
  b = 4
}

const a1 = ret1()
assert a1.a == 1 and a1 == 1  // single-field tuple auto-unwraps

const a3 = ret3()
assert a3.a == 3 and a3.b == 4

const (x1, x2) = ret3()
assert x1 == 3 and x2 == 4
```

## Attributes

Variables can have attributes. Attributes can only be `integer`, `bool`, or
`string`. Depending on the type, they are initialized to `0`, `false`, or `""`.

Stateful behavior can be modeled as a tuple with fields and methods. The tuple
fields hold the state, and the methods operate on it via `ref self`.

=== "Explicit call"
    ```
    mut p1 = (
      mut found_once:bool = false,
      call = mod(ref self, a) -> (result) {
        self.found_once or= (a == 0)
        result = a + 1
      }
    )

    mut p2 = p1       // copy
    mut p3 = ref p1   // reference

    test "testing p1" {
      assert p1.found_once == false
      assert p2.found_once == false

      cassert p1.call(3) == 4
      assert p1.found_once == false

      cassert p1.call(0) == 1
      assert p1.found_once == true

      cassert p1.call(50) == 51
      assert p1.found_once == true
      assert p2.found_once == false
      assert p3.found_once == true
    }
    ```

=== "With getter/setter"
    ```
    mut p1 = (
      mut found_once:bool = false,
      setter = mod(ref self, a) {
        self.found_once or= (a == 0)
        self._result = a + 1
      },
      mut _result = 0,
      getter = comb(self) { self._result }
    )

    mut p2 = p1       // copy
    mut p3 = ref p1   // reference

    test "testing p1" {
      assert p1.found_once == false
      assert p2.found_once == false

      p1 = 3                         // calls setter
      cassert p1 == 4                // calls getter
      assert p1.found_once == false

      p1 = 0
      cassert p1 == 1
      assert p1.found_once == true

      p1 = 50
      cassert p1 == 51
      assert p1.found_once == true
      assert p2.found_once == false
      assert p3.found_once == true
    }
    ```

## Methods

Pyrope arguments are by value, unless the `ref` keyword is used. `ref` is
needed when a method intends to update the tuple contents. In this case, `ref
self` argument behaves like a pass by reference in non-hardware languages. This
means that the tuple fields are updated as the method executes, it does not
wait until the method finishes execution. A method without the `ref` keyword is
a pass by value call. Since all the inputs are immutable by default (`const`),
any `self` updates should generate a compile error.

```
const Nested_call = (
  mut x = 1,
  outter = comb(ref self) { self.x = 100; self.inner(); self.x = 5 },
  inner = comb(self) { assert self.x == 100 },
  faulty = comb(self) { self.x = 55 }, // compile error, immutable self
  okcall = comb(ref self) { self.x = 55 }
)
```

`self` can also be returned but this behaves like a normal copy by value
variable return.

```
mut a_1 = (
  x:u10,
  f1 = comb(ref self, x) -> (self) { // BOTH ref self and return self is OK
    self.x = x
    self
  }
)

a_1.f1(3)
mut a_2 = a_1.f1(4)  // a_2 is updated, not a_1
assert a_1.x == 3 and a_2.x == 4

// Same behavior as in a function with UFCS
const set_x = comb (ref self, x) { self.x = x }

a_1.set_x(10)
mut a_3 = a_1.set_x(20)
assert a_1 == 10 and a_3 == 20
```

Since UFCS does not allow shadowing, a wrapper must be built or a compile error is generated.

```
mut counter = (
  ,mut val:i32 = 0
  ,const inc = comb (ref self, v){ self.var += v }
)

assert counter.val == 0
counter.inc(3)
assert counter.val == 3

const inc = comb (ref self, v) { self.var *= v } // NOT INC but multiply
counter.inc(2)             // compile error, multiple inc options
assert 44.inc(2) == 8

counter.val = 5
const mul = inc
counter.mul(2)             // call the new mul method with UFCS
assert counter.val == 10

mul(counter, 2)            // also legal
assert counter.val == 20
```


It is possible to add new methods after the type declaration. In some
languages, this is called extension functions.

```
const t1 = (a:u32)

mut x:t1 = (a=3)

t1.double = comb(ref self) { self.a *= 2 }  // extension function
// previous is exactly the same as:
// t1 = t1 ++ (double = comb(ref self) { self.a *= 2 })

mut y:t1 = (a=3)
x.double             // compile error, double method does not exit
y.double             // OK
assert y.a == 6
```

### Constraining arguments

Arguments can constrain the inputs and input types. Unconstrained input types
allow for more freedom and a potentially variable number of arguments generics, but
it can be error-prone.

=== "unconstrained declaration"
    ```
    foo = comb (self) { puts "comb.foo" }
    a = (
      ,foo = comb () {
         bar = comb() { puts "bar" }
         puts "mem.foo"
         return (bar=bar)
      }
    )
    b = 3
    c = "string"

    b.foo         // prints "comb.foo"
    b.foo()       // prints "comb.foo"
    x = a.foo     // prints "mem.foo"
    y = a.foo()   // prints "mem.foo"
    x()           // prints "bar"

    a.foo.bar()   // prints "mem.foo" and then "bar"
    a.foo().bar() // prints "mem.foo" and then "bar"
    a.foo().bar   // prints "mem.foo" and then "bar"

    c.foo         // prints "comb.foo"
    ```

=== "constrained declaration"

    ```
    foo = comb (self:int) { puts "comb.foo" }
    a = (
      ,foo = comb () {
         bar = comb() { puts "bar" }
         puts "mem.foo"
         return (bar=bar)
      }
    )
    b = 3
    c = "string"

    b.foo         // prints "comb.foo"
    b.foo()       // prints "comb.foo"
    x = a.foo     // prints "mem.foo"
    y = a.foo()   // prints "mem.foo"
    x()           // prints "bar"

    a.foo.bar()   // prints "mem.foo" and then "bar"
    a.foo().bar() // prints "mem.foo" and then "bar"
    a.foo().bar   // prints "mem.foo" and then "bar"

    c.foo         // compile error, undefined 'foo' field/call
    ```
