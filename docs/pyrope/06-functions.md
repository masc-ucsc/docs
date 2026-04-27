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


Pyrope divides the lambdas into three categories: `comb`, `pipe`, and `mod`.

- `comb` is pure combinational logic. The outputs are purely a function of
  the inputs — no registers, no state, no cycle-level side effects. Any
  external call inside a `comb` can only affect debug statements (e.g.,
  `puts`), not synthesizable code. `comb` can use `ref` arguments to modify
  tuples; `ref` is equivalent to having the argument as both input and
  output, which is still purely combinational. `comb` resembles `pure
  functions` in normal programming languages.

- `pipe` is a Moore machine — every output goes through at least one flop.
  The latency is written as an argument to the keyword: `pipe[3] foo(...)`
  is fixed 3-cycle, `pipe[1..=3] foo(...)` lets the caller pick within a
  range, and bare `pipe foo(...)` leaves the latency fully flexible for the
  caller to specify via `await[N]` at the call site. The tool may retime
  logic for performance, but the behavior is equivalent to a `comb` with N
  flops appended at the outputs. `pipe` can use `reg` for internal storage;
  besides storage, it behaves like a `comb` with pipelined outputs.

- `mod` has no constraints on registers or outputs. It can be combinational,
  Mealy, Moore, or a pipeline orchestrator. When a `mod` calls `pipe`
  lambdas and needs to align their outputs with other signals, it uses the
  `await[N]` declaration modifier and the `@[N]` cycle type check (these
  constructs used to belong to the separate `flow` category, which has
  been merged into `mod`).

Methods are `comb`/`pipe`/`mod` lambdas that have `self` as the first
argument, which allows operating on tuples.

=== "Combinational (comb)"
    ```
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

=== "Module with pipeline orchestration (mod)"
    ```
    pipe mul(a, b) -> (c) { c = a * b }
    pipe add(a, b) -> (c) { c = a + b }

    mod multiply_add(in1, in2) -> (out) {
      await[3] tmp      = mul(in1, in2)
      await[3] in1_d    = in1
      await[1] out@[4] = add(tmp@[3], in1_d@[3])
    }

    mod accum(in1, in2) -> (out) {
      reg total = 0                             // mod can use reg
      await[3] tmp = mul(in1, in2)
      total.[defer] = add(total, tmp@[3])
      out = total
    }
    ```

=== "Module with registered outputs (mod)"
    ```
    mod counter(enable) -> (reg count) {
      count += 1 when enable
    }

    mod add_reg(a, b) -> (reg result) {
      result = a + b
    }
    ```

## Declaration

There are two interchangeable forms for declaring a lambda. The **kind-first
declaration form** is preferred — it matches the rest of Pyrope's grammar,
where every declaration starts with a kind keyword (`const`/`mut`/`reg` for
data, `comb`/`pipe`/`mod` for lambdas):

```
comb get_five() -> (v) { v = 5 }              // kind-first form
```

Both forms are legal at top level, inside tuple literals, and inside code
blocks. The kind-first form is shorter, reads like a method declaration in
most languages, and lets an agent scan for all lambda declarations with a
single pattern. Lambdas are always immutable.

Only anonymous lambdas are supported — there is no global scope for
functions, procedures, or modules. The only way for a file to access a
lambda is to have access to a local variable with a definition or to
"import" a variable from another file.

```
const a_3 = { 3 }             // just scope, not a lambda. Scope is evaluated now
comb a_lambda() -> (v) { v = 4 }   // kind-first form

comb get_five() -> (v) { v = 5 }   // public lambda that can be imported by other files

const x = a_3()             // error: explicit call not possible in scope
const x = a_lambda()        // OK, explicit call needed when no arguments

cassert a_3 == 3
type a_lambda_type = comb()->(v)
cassert a_lambda equals a_lambda_type
cassert a_lambda() == 4
```

The lambda definition has the following fields:

```txt
[GENERIC] [COMPTIME] [INPUT] [-> OUTPUT] |
```

+ `GENERIC` is an optional comma separated list of names between `<` and `>` to
  use as generic types in the lambda.

+ `COMPTIME` has the optional list of explicit comptime parameters for the
  lambda. Each entry is a typed declaration (e.g., `n:int`) or a typed
  declaration with a default (e.g., `n:int=1`). Defaults may refer to visible
  comptime bindings from the enclosing scope. Callers can override any
  comptime parameter at the call site using the same `[...]` slot
  (`foo[N](args)`).

+ Lambdas do not have an explicit capture list. Visible comptime bindings from
  enclosing scopes, including imports and `comptime const` declarations, are
  available lexically inside the lambda body and signature. The compiler records
  those references as explicit comptime dependencies of the lambda; no capture
  syntax is written by the programmer. Runtime `const`, `mut`, and `reg`
  declarations from enclosing lambda scopes are not visible inside a nested
  lambda unless passed as normal inputs or stored in an explicit tuple/object
  that the lambda receives.

+ `INPUT` has a list of inputs allowed with optional types. `()` indicates no
  inputs. `(...args)` allow to accept a variable number of arguments.

+ `OUTPUT` has a list of outputs allowed with optional types. `()` or an
  omitted `-> (...)` indicates no outputs. Outputs are **always declared by
  name** — there are no anonymous/positional return lists. The body assigns
  to those names.

Dispatch between alternative lambdas is always explicit at the call site
using `if`/`elif` chains. Pyrope does not have a `where` clause on lambda
declarations (an earlier design did); this keeps the call flow visible and
locally readable.

```
comb add1(...x) -> (r) { r = x[0] + x[1] + x[2] }   // var-args, single output
comb add2(a, b, c) -> (r) { r = a + b + c }         // constrain inputs to a,b,c
comb add3(a, b, c) -> (r:u32) { r = a + b + c }     // constrain result to u32
comb add4(a:u32, b:s3, c) -> (r) { r = a + b + c }  // constrain some input types
comb add5(a, b:a, c:a) -> (r) { r = a + b + c }     // constrain inputs to same type
comb add6<T>(a:T, b:T, c:T) -> (r) { r = a + b + c} // generic, single output

// To overload, declare each lambda separately and gather them:
const add = [add1, add2, add3, add4, add5, add6]

const x = 2
comb addx1(a) -> (r) { r = x + a }    // error: x is runtime, not visible in lambda

/// Visible comptime bindings are available lexically:
comptime const Scale = 2
comb addx2(a) -> (r) { r = Scale + a }       // OK: Scale is comptime

/// Imports are comptime aliases:
const lib = import("lib.math")
comb is_add(op:lib.OpType) -> (r) { r = op == lib.AddOp }

/// Comptime parameters can be declared with a type and/or default:
comb scale[n:int=1](a) -> (r) { r = n * a }
cassert scale(5) == 5           // uses default n=1
cassert scale[10](5) == 50      // override n=10 at the call site

/// Defaults can use visible comptime bindings:
comptime const DefaultScale = 3
comb scale_default[n:int=DefaultScale](a) -> (r) { r = n * a }
cassert scale_default(4) == 12
cassert scale_default[100](4) == 400

mut y = (
  mut val:u32 = 1,
  comb inc1(ref self) { self.val = u32(self.val + 1) } // no outputs; mutates via ref
)

comb my_log::[debug](...inp) {       // no outputs; side-effecting print
  print "logging:"
  for i in inp {
    print " {}", i
  }
  puts
}

comb f<X>(a:X, b:X) -> (r) { r = a + b }   // enforces a and b with same type
cassert f(u22(33), u22(100)) == 133

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

* **Every lambda call requires parentheses.** `foo()`, `foo(1,2)`, and
  `x.bar(y)` are the only forms. There is no "drop parens after newline"
  or "drop parens after a pipeline operator" sugar. This keeps every call
  site unambiguously identifiable.

* Calls use the Uniform Function Call Syntax (UFCS) when `self` is defined as
  the first argument. `(a,b).f(x,y)` is equivalent to `f((a,b),x,y)`.

Pyrope uses a Uniform Function Call Syntax (UFCS) when the first argument is
`self`. It resembles Nim or D UFCS but it can be different from the order in
other languages.

```
comb div(self, b) -> (r) { r = self / b }     // named input tuple
comb div2(...x) -> (r) { r = x[0] / x[1] }    // unnamed input tuple

comb noarg() -> (r) { r = 33 }                // explicit no args

cassert 33 == noarg()             // () always required, even for no-arg calls

assert noarg                      // error: `noarg()` needed for calls

a = div(3, 4, 3)         // error: div has 2 inputs
b = div(self=8, b=4)     // OK, 2
d = (self=8).div(b=2)    // OK, 4
d = (8).div(b=2)         // OK, 4 . self does not need to be named
d = 8.div(2)             // OK, single character inputs no need to be named

h = div2(8, 4, 3)        // OK, 2 (3rd arg is not used)
i = 8.div2(4, 3)         // error: no self in div2

n = div((8, 4), 3)       // error: (8,4)/3 is undefined
o = (8, 4).div2(1)       // error: (8,4)/1 is undefined
```


The UFCS allows to have `lambdas` to call any tuple, but if the called tuple
has a lambda defined with the same name a compile error is generated. Like with
variables, Pyrope does not allow `lambda` call shadowing. Polymorphism is allowed
but only explicit one as explained later.

```
mut tup = (
  comb f1(self) -> (r) { r = 1 }
)

comb f1(self) -> (r) { r = 2 } // error: f1 shadows tup.f1
comb f1() -> (r) { r = 3 }     // OK, no self

assert f1() != 0         // error: missing argument
assert f1(tup) != 0      // error: f1 shadowing (tup.f1 and f1)
assert 4.f1() != 0       // error: f1 can be called for tup, so shadow
assert tup.f1() != 0     // error: f1 is shadowing

comb xx(self:tup) -> (r) { r = self.f1() } // OK, explicit input restricts scope for f1
cassert xx(tup) == 1

cassert (4:tup).f1() == 1
cassert 4.f1() == 3       // UFCS call
cassert tup.f1() == 1
```

The keyword `self` is used to indicate that the function is accessing a tuple.
`self` is required to be the first argument. If the method modifies the tuple
contents, a `ref self` must be passed as input. Since `ref` is equivalent to
having the argument as both input and output, `comb` can use `ref` and still
be purely combinational. Use `mod` only when the method needs registers or
cycle-level state.


```
mut tup2 = (
  mut val:u8 = 0sb?,
  comb upd(ref self) { sat self.val += 1 },
  comb calc(self) -> (r) { r = self.val }
)
```

A lambda call always uses parentheses (`foo()` or `foo(1, 2)`). The only
exception is a variable with a getter method — reading the variable (without
parens) implicitly invokes the getter.

```
no_arg_fun()     // parentheses always required
arg_fun(1, 2)    // parenthesis required

mut intercepted:(
  mut field:u32,
  comb getter(self) -> (r) { r = self.field + 1 },
  comb setter(ref self, v) { self.field = v }
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
comb inc1(ref a) { a += 1 }

const x = 3
inc1(ref x)       // error: `x` is immutable but modified inside inc1

mut y = 3
inc1(ref y)
cassert y == 4

comb banner() { puts "hello" }
type T_noarg = comb() -> ()
comb execute_method(fn:T_noarg) {  // explicit type for fn (declared ahead)
  fn() // prints hello when banner passed as argument
}

execute_method(banner)     // OK
```

In Pyrope, to call a method, parenthesis are needed only when the method has arguments.
This is needed to distinguish for higher order functions that need to distinguish between
a function call and a pass of the lambda.

## Output tuple

Everything in Pyrope is a tuple, including the result of a lambda call. There
are three rules that work together:

1. **Outputs are always declared by name in `-> ( ... )`.** There is no
   anonymous/positional output list. A lambda with no outputs simply omits
   the `-> (...)` clause (or writes `-> ()`).

2. **The body assigns to the declared output names.** The "last expression
   is an implicit return" sugar from earlier Pyrope drafts is gone — a bare
   expression at the end of a body is a no-op unless it is the placeholder
   lambda form described below.

3. **`return` is a terminator only.** The keyword ends the current lambda
   and never carries a value (`return X` is a syntax error). Whatever has
   been assigned to the declared output names so far is what the caller
   sees. Use `return when cond` / `return unless cond` for early exits.

Callers always see a named tuple. They can read fields by name
(`r.a`, `r.b`) or destructure positionally with `const (x1, x2) = ret3()`.
A single-field output tuple auto-unwraps when used in scalar context.

```
comb ret1() -> (a:int) {
  a = 1
}

comb ret3() -> (a, b) {
  a = 3
  b = 4
}

comb early(x) -> (r) {
  r = 0
  return when x == 0       // bail out; r already assigned
  r = 100 / x
}

const a1 = ret1()
cassert a1.a == 1 and a1 == 1  // single-field tuple auto-unwraps

const a3 = ret3()
cassert a3.a == 3 and a3.b == 4

const (x1, x2) = ret3()
cassert x1 == 3 and x2 == 4
```

### Placeholder lambda (single-output `comb` only)

The fully explicit form `comb add(a, b) -> (r) { r = a + b }` is verbose
when the body is a one-liner. Pyrope offers a Scala-style **placeholder
lambda** sugar that applies *only* to combinational lambdas with exactly
one output:

* The body is written as a single expression. Its value is implicitly
  assigned to the single output.
* Inside that expression, `_0`, `_1`, ... refer to positional arguments
  (`_0` is the first arg). `_` is shorthand for `_0` when the lambda
  takes a single argument.
* The sugar is *only* legal when the lambda is a `comb` and has one
  output. `pipe` and `mod`, multi-output combs, and bodies that need
  more than one statement use the explicit form.

```
comb add(a, b) -> (r) { _0 + _1 }     // sugar: equivalent to { r = a + b }
comb inc(a)    -> (r) { _ + 1 }       // sugar: equivalent to { r = a + 1 }

// Anonymous lambdas use the same placeholder syntax — args and the single
// output are inferred from the placeholders used:
const my_tup = (myinc = _ + 1, mut 3)   // myinc is comb(x) -> (r) { r = x + 1 }
mymap.each(_0 + 1)                       // each() receives a comb(x) -> (r) { r = x + 1 }
```

Which form to pick:

* **Use the explicit form** for any `pipe`/`mod`, anything with multiple
  outputs, anything that needs more than one statement, or anywhere
  clarity matters more than brevity.
* **Use the placeholder form** for short combinational helpers and
  one-liner lambdas passed to higher-order calls (`map`, `each`,
  `reduce`, ...).

## Attributes

Variables can have attributes. Attributes can only be `integer`, `bool`, or
`string`. Depending on the type, they are initialized to `0`, `false`, or `""`.

Stateful behavior can be modeled as a tuple with fields and methods. The tuple
fields hold the state, and the methods operate on it via `ref self`.

=== "Explicit call"
    ```
    mut p1 = (
      mut found_once:bool = false,
      mod call(ref self, a) -> (result) {
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
      mod setter(ref self, a) {
        self.found_once or= (a == 0)
        self._result = a + 1
      },
      mut _result = 0,
      comb getter(self) -> (r) { r = self._result }
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
  comb outter(ref self) { self.x = 100; self.inner(); self.x = 5 },
  comb inner(self)      { assert self.x == 100 },
  comb faulty(self)     { self.x = 55 }, // error: immutable self
  comb okcall(ref self) { self.x = 55 }
)
```

`self` can also be returned but this behaves like a normal copy by value
variable return.

```
mut a_1 = (
  mut x:u10,
  comb f1(ref self, x) -> (self) { // output named `self` mirrors the ref input
    self.x = x                     // mutates the ref; output `self` reflects the new value
  }
)

a_1.f1(3)
mut a_2 = a_1.f1(4)  // a_2 is updated, not a_1
cassert a_1.x == 3 and a_2.x == 4

// Same behavior as in a function with UFCS
comb set_x(ref self, x) { self.x = x }

a_1.set_x(10)
mut a_3 = a_1.set_x(20)
cassert a_1.x == 10 and a_3.x == 20
```

Since UFCS does not allow shadowing, a wrapper must be built or a compile error is generated.

```
mut counter = (
  ,mut val:i32 = 0
  ,comb inc(ref self, v) { self.var += v }
)

assert counter.val == 0
counter.inc(3)
assert counter.val == 3

comb inc(ref self, v) { self.var *= v } // NOT INC but multiply
counter.inc(2)             // error: multiple inc options
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
const t1 = (mut a:u32)

mut x:t1 = (a=3)

comb t1_do_double(ref self) { self.a *= 2 }
t1.double = t1_do_double

mut y:t1 = (a=3)
x.double             // error: double method does not exit
y.double             // OK
assert y.a == 6
```

### Constraining arguments

Arguments can constrain the inputs and input types. Unconstrained input types
allow for more freedom and a potentially variable number of arguments generics, but
it can be error-prone.

=== "unconstrained declaration"
    ```
    comb foo(self) { puts "comb.foo" }
    const a = (
      ,comb foo() -> (r) {
         comb bar() { puts "bar" }
         puts "mem.foo"
         r = (bar=bar)
      }
    )
    const b = 3
    const c = "string"

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
    comb foo(self:int) { puts "comb.foo" }
    const a = (
      ,comb foo() -> (r) {
         comb bar() { puts "bar" }
         puts "mem.foo"
         r = (bar=bar)
      }
    )
    const b = 3
    const c = "string"

    b.foo         // prints "comb.foo"
    b.foo()       // prints "comb.foo"
    const x = a.foo     // prints "mem.foo"
    const y = a.foo()   // prints "mem.foo"
    x()           // prints "bar"

    a.foo.bar()   // prints "mem.foo" and then "bar"
    a.foo().bar() // prints "mem.foo" and then "bar"
    a.foo().bar   // prints "mem.foo" and then "bar"

    c.foo         // error: undefined 'foo' field/call
    ```
