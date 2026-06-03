
# Statements

## Conditional (`if`/`elif`/`else`)


Pyrope uses a typical `if`, `elif`, `else` sequence found in most languages.
Before the if starts, there is an optional keyword `unique` that enforces that
a single condition is true in the if/elif chain. This is useful for synthesis
which allows a parallel mux. The `unique` is a cleaner way to write an
`optimize` statement.

The `if` sequence can be used in expressions too.

```pyrope
a = unique if x1 == 1 {
    300
  }elif x2 == 2 {
    400
  }else{
    500
  }

mut x = nil
if a { x = 3 } else { x = 4 }
```

The equivalent code with an explicit `optimize`, but unlike the `optimize`, the
`unique` will guarantee to generate the `hotmux` statement. EDA tools can also
optimize `unique if` to tri-state buffers when the conditions are mutually
exclusive, providing the same behavior as a hardware bus without needing a
separate `bus` construct.

```pyrope
optimize(!(x1==1 and x2==2))
a = if x1 == 1 {
    300
  }elif x2 == 2 {
    400
  }else{
    500
  }
```

Like several modern programming languages, there can be a list of expressions
in the evaluation condition. If variables are declared, they are restricted to
the remaining if/else statement blocks.


```pyrope
mut tmp = x+1

if mut x1=x+1; x1 == tmp {
   puts("x1:{} is the same as tmp:{}", x1, tmp)
}elif mut x2=x+2; x2 == tmp {
   puts("x1:{} != x2:{} == tmp:{}", x1, x2, tmp)
}
```


## Unique parallel conditional (`match`)

The `match` statement is similar to a chain of unique if/elif, like the
`unique if/elif` sequence. The `match` statement is a replacement for the
common "unique parallel case" Verilog directive, and behaves like also
having an `optimize` statement, which allows for more efficient code
generation than a sequence of `if/else`.

Every `match` **must end with an `else` arm** — omitting it is a parse
error. This guarantees there is always exactly one matching branch,
removes the silent "no-case-matched" failure mode, and gives a single
place to put a catch-all (`cassert(false`, a default value, etc.).)

In addition to functionality, the syntax is different to avoid redundancy.
`match` joins the match expression with the beginning of the matching
entry to form a valid expression.

```pyrope
const x = 1
match x {
  == 1            { puts("always true") }
  in (2,3)        { puts("never")       }
  else            { cassert(false)      }
}
// It is equivalent to:
unique if x == 1  { puts("always true") }
elif x in (2,3)   { puts("never")       }
else              { cassert(false)      }
```

Like the `if`, it can also be used as an expression.

```pyrope
mut hot = match x {
    == 0sb001 { a }
    == 0sb010 { b }
    == 0sb100 { c }
    else      { cassert(false); 0 }
  }

// Equivalent
optimize (x==0sb001 or x==0sb010 or x==0sb100)
mut hot2 = __hotmux(x, a, b, c)

assert(hot==hot2)
```

Like the `if` statement, a sequence of statements and declarations are possible in the match statement.

```pyrope
match const one=1 ; one ++ (2) {
  == (1,2) { puts("one:{}", one) }      // should always hit
  else     { cassert(false) }
}
```

Since the `==` is the most common condition in the `match` statement, it can be
omitted.

```pyrope
for x in 1..=5 {
  const v1 = match x {
    3 { "three" }
    4 { "four" }
    else { "neither"}
  }

  const v2 = match x {
    == 3 { "three" }
    == 4 { "four" }
    else { "neither"}
  }
  cassert(v1 == v2)
}
```


## Gate statements (`when`/`unless`)

A simple statement can be conditionally **included or omitted at
elaboration** by appending `when cond` or `unless cond` at the end. These
are compile-time gates — think `#if` / `#ifndef`. The condition must be
`comptime`; a runtime condition is a compile error. The statement stays
in the current scope (no new scope is created), which makes them ideal
for conditional declarations, conditional assertions, and conditionally
omitted statements driven by compile options.

```pyrope
comptime const DEBUG = true
mut a = 3

a += 1 when false              // omitted: statement does not exist
cassert(a == 3)
assert(a == 1000) when DEBUG   // included only when DEBUG is true

reg my = 3 when some_comptime  // register exists only when some_comptime is true

return unless DEBUG            // omitted when DEBUG is true
```

Gating `if`/`match` statements does not make much sense. As a result,
`when`/`unless` can only be applied to assignments, function calls,
declarations, and code-block control statements (`return`, `break`,
`continue`).

For **runtime** gating (a mux or enable on a signal) use an `if` block
or an `if` expression:

```pyrope
mut x = c                      // always declared
if cond { x = other }          // runtime-gated assignment
result = if cond { other } else { c }
```


## Code block

A code block is a sequence of statements delimited by `{` and `}`. The
functionality is the same as in other languages. Variables declared within
a code block are not visible outside the code block. In other words, code block
variables have scope from definition until the end of the code block.


Code blocks are different from lambdas. A lambda consists of a code block but
it has several differences. In lambdas, (1) visible comptime bindings from
upper scopes are available lexically, but runtime upper-scope variables are not
implicitly visible; (2) inputs and outputs could be constrained, and (3) the
`return` statement finishes a lambda not a code block.


The main features of code blocks:

* Code blocks define a new scope. New variable declarations inside are not visible outside it.

* Code blocks do not allow variable declaration shadowing.

* Expressions can have multiple code blocks but they are not allowed to have
  side-effects for variables outside the code block. The [evaluation
  order](02-basics.md#evaluation-order) provides more details on expressions
  evaluation order.

* A code block used as an expression evaluates to the value of its last
  expression. This is a property of code blocks, not lambdas — see
  [lambdas](06-functions.md#output-tuple) for how lambda outputs work
  (declared by name, assigned in the body, no implicit return).

```pyrope
mut yy = 0
{
  mut x=1
  mut z=0
  {
    z = 10
    mut x=_           // error: 'x' is a shadow variable
  }
  cassert(z == 10)
  yy = x
}
const zz = x            // error: `x` is out of scope
cassert(yy == 1)

mut yy2 = {const x=3 ; 33/3} + 1
cassert(yy2 == 12)
const xx = {yy=1 ; 33}  // error: 'yy' has side effects

if {const a=1+yy2; 13<a} {
  // a is not visible in this scope
  some_code()
}

comb doit(f, a) -> (r) {
  const x = f(a)
  assert(x == 7)
  r = 3
}

comb real_doit(a) -> (r) {
  assert(a != 0)
  r = 7
  return               // exit the current lambda; later statements skipped
  r = 100              // never reached
}

const z3 = doit(real_doit, 33)
cassert(z3 == 3)
```

## Loop (`for`)

The `for` iterates over the first-level elements in a tuple or the values in a
range.  In all the cases, the number of loop iterations must be known at
compile time. The loop exit condition can not be run-time data-dependent.


The loop can have an early exit when calling `break` and skip of the current
iteration with the `continue` keyword.

```pyrope
for i in 0..<100 {
 some_code(i)
}

mut bund = (1,2,3,4)
for (index,i) in bund.enumerate() {
  assert(bund[j] == i)
}
```

```pyrope
const b = (a=1,b=3,c=5,7,11)
cassert(b.keys() == ('a', 'b', 'c', '', ''))
cassert(b.enumerate() == ((0,1), (1,3), (2,5), (3,7), (4,11)))
const xx= zip(b.keys(), b.enumerate())
cassert(xx == (('a',0,a=1), ('b',1,b=3), ('c',2,c=5), ('',3,7), ('',4,11)))

for (key,index,i) in zip(keys(b),b.enumerate()) {
  cassert(i==1  implies (index==0 and key == 'a'))
  cassert(i==3  implies (index==1 and key == 'b'))
  cassert(i==5  implies (index==2 and key == 'c'))
  cassert(i==7  implies (index==3 and key == '' ))
  cassert(i==11 implies (index==4 and key == '' ))
}

const c = ((1,a=3), b=4, c=(x=1,y=6))
cassert(c.enumerate() == ((0,(1,a=3)), (1,b=4), (2,c=(x=1,y=6))))
```

To build a tuple/array from a loop, use an explicit `for` over a `mut`
accumulator and `++=` each element. Trailing-`for` comprehensions on
expressions are not supported (they make trailing tokens of every expression
ambiguous to parse) — write the loop out instead.

```pyrope
mut d:[] = nil
for i in 0..<5 {
  d ++= i
}

mut e:[] = nil
for i in 0..<5 {
  if i {
    e ++= i
  }
}
cassert ((0,1,2,3,4) == d)
cassert(e == (1,2,3,4))
```

The iterating element is copied by value, if the intention is to iterate over a
vector or array to modify the contents, a `ref` must be used. Only the element
is mutable. When a `ref` is used, it must be a variable reference, not a
function call return (value). The mutable for can not be used in
comprehensions.

```pyrope
mut b = (1,2,3,4,5)

for x in ref b {
  x += 1
}
cassert(b == (2,3,4,5,6))
```

### Code block control

Code block control statements allow changing the control flow for `lambdas` and
loop statements (`for`, `loop`, and `while`). **`return` is a terminator only
— it never carries a value.** Whatever has been assigned to the lambda's
declared output names is what the caller sees.

* `return` is for early exits — it terminates the current lambda before
  reaching the end of the body. It takes no arguments; `return X` is a
  syntax error. To return early with a specific value, assign the output
  first: `r = X; return`. The condition forms `return when cond` /
  `return unless cond` are gated terminators, not value-carrying returns.

* `break` terminates the closest inner loop (`for`/`while`/`loop`). If none is
  found, a compile error is generated.

* `continue` looks for the closest inner loop (`for`/`while`/`loop`) code
  block. The `continue` will perform the next loop iteration. If no inner loop
  is found, a compile error is generated.


```pyrope
mut total:[] = nil
for a in 1..=10 {
  if a == 2 { continue }
  total ++= a
  if a == 3 { break }    // exit for scope
}
cassert(total == (1,3))

if true {
  code(x)
  continue             // error: no upper loop scope
}

mut a = 3
mut total2:[] = nil
while a>0 {
  total2 ++= a
  if a == 2 { break }    // exit if scope
  a = a - 1
  continue
  assert(false) // never executed
}
cassert(total2 == (3,2))

mut total3:[] = nil
for i in 1..=9 {
  if i<3 {
    total3 ++= i+10
  }
}
cassert(total3 == (11, 12))
```

## while/loop

`while cond { [stmts]+ }` is a typical while loop found in most programming
languages. The only difference is that like with loops, the while must be fully
unrolled at compilation time. The `loop { [stmts]+ }` is equivalent to a `while
true { [stmts]+ }`.


Like `if`/`match`, the `while` condition can have a sequence of statements with
variable declarations visible only inside the while statements.

```pyrope
// a do while contruct does not exist, but a loop is quite clean/close

mut a = 0
loop {
  puts("a:{}",a)

  a += 1

  if a >= 10 { break }
} // do{ ... }while(a<10)
```

## Cycle access and defer

Cycle-based access to values is expressed through a small set of
constructs:

* The first bare `variable` reads before update hold the register's 'q' value:

  ```pyrope
  reg counter:u32 = 0
  const counter_q = counter         // snapshot 'q' before any updates this cycle

  if whatever {
    counter = counter + 1
  }
  ```

* `past[n:int=1](variable)` reads the value `n` cycles ago. The compiler
  inserts `n` flops automatically — the hardware cost is explicit in the
  call. `past(x)` is shorthand for `past[1](x)`. See the
  [Temporal library](09-verification.md#temporal-library).

* `variable.[defer]` is **RHS-only**: it reads the end-of-cycle value
  (after all in-cycle writes have accumulated). There is no
  `variable.[defer] = ...` write form — writes use plain `=`.

* For pipeline timing inside `mod` blocks, use `stage[N]` (declaration
  modifier that pipelines the whole RHS over `N` cycles) and `foo@[N]`
  (pure timing type check).

* For debug-only future sampling (inside `assert`, `cover`, `test`, …), use
  the temporal library — `next(x, N)`, `eventually[R](x)`, `rose[R](x)`,
  etc.

`foo@[N]` is a pure cycle-alignment type check, never a flop insertion.
`foo@[3]` checks that `foo` is 3 pipeline stages ahead of the lambda inputs.
To actually delay a value, use `stage[N] lhs = rhs`. To read past or future
cycles, use `past[N](x)` or `next[N](x)`.

The `.[defer]` attribute provides RHS-only deferred read access to a
variable — the value at the end of the current cycle. It is valid for any
variable type (`mut`, `const`, `reg`) as it refers to the final value
within the current cycle.

### Defer reads

When used to read a variable, `.[defer]` returns the last value written to the
variable at the end of the current cycle. This is needed if we need to have any
loop in connecting blocks or for delaying assertion checks to the end of the
cycle like post condition checks.

```pyrope
mut c = 10
assert(b.[defer] == 33) // behaves like a postcondition
b = c.[defer]
assert(b == 33)
c += 20
c += 3
```

To connect the `ring` function calls in a loop.
```pyrope
f1 = ring(a, f4.[defer])
f2 = ring(b, f1)
f3 = ring(c, f2)
f4 = ring(d, f3)
```

If the intention is to read the result after being a flop, there is no need to
use the `defer`, a normal register access could do it. A bare `reg`
reference reads the value before any update (the 'q' value), and `.[defer]`
reads the value after updates.

```pyrope
reg counter:u32 = nil

const counter_0  = counter         // current cycle (before updates)
const counter_1  = past(counter)   // last cycle (one flop)
const counter_2  = past[2](counter) // last last cycle (two flops)

mut deferred = counter.[defer]  // defer read: final value at end of cycle

if counter < 100 {
  counter += 1
}else{
  counter = 0
}

if counter == 10 {
  assert(deferred   == 10)
  assert(counter.[defer] == 10) // same as deferred, end-of-cycle value
  assert(counter_0  ==  9)
  assert(counter_1  ==  8)
  assert(counter_2  ==  7)
}
```

### `.[defer]` is RHS-only

`.[defer]` is read-only on the right-hand side. There is **no
`a.[defer] = ...` write form** — register writes always use plain `=`
(or `+=`, `&=`, …). Within a cycle, multiple writes to the same register
are accumulated in program order, and `.[defer]` reads the final
end-of-cycle value.

```pyrope
reg a:u8 = 1
if a == 1 {
  a = 200                       // register write
  assert(a == 1)                // bare 'a' still reads the current 'q' value
  assert(a.[defer] == 200)      // .[defer] sees the in-cycle write
} else {
  a = 2
  assert(a.[defer] == 2)
}
```

The same RHS-only `.[defer]` form is also useful for `mut` variables when
you want the in-cycle final value:

```pyrope
mut a = 1
mut x = 100
x = a.[defer]                   // RHS read of the eventual final value
a = 200

cassert(x == 200)
```

## Testing (`test`)

The test statement requires a text identifier to notify when the test fails.
The `test` is similar to a `puts` statement followed by a scope (`test <str>
[,args] { stmts+ }`). The statements inside the code block can not have any
effect outside.


```pyrope
test "my test {}", 1 {
  assert(true)
}
```

Each `test` can run in parallel, to increase the throughput, putting the
randomization outside the test statement increases the number of tests:


=== "Parallel tests"
    ```pyrope
    comb add(a,b) -> (r) { r = a + b }

    for i in 0..<10 { // 10 tests
      const a = (-30..<100).rand
      const b = (-30..<100).rand

      test "test {}+{}",a,b {
        assert(add(a,b) == (a+b))
      }
    }
    ```

=== "Single test"
    ```pyrope
    comb add(a,b) -> (r) { r = a + b }

    test "test 10 additions" {
      for i in 0..<10 { // 10 tests
        const a = (-30..<100).rand
        const b = (-30..<100).rand

        assert(add(a,b) == (a+b))
      }
    }
    ```

### Test only statements

`test` code blocks are allowed to use special statements not available outside
testing blocks:

* `step [ncycles]` advances the simulation for several cycles. The local variables
will preserve the value, the inputs may change value.

* `waitfor condition` is a syntax sugar to wait for a condition to be true.


```pyrope
test "wait 1 cycle" {
  const a = 1 + input
  puts("printed every cycle input={}", a)
  step(1)
  puts("also every cycle a={}",a)  // printed on cycle later
}
```


The `waitfor` command is equivalent to a `while` with a `step`.

=== "`waitfor`"

    ```pyrope
    total = 3

    waitfor(a_cond)  // wait until a_cond is true

    assert(total == 3 and a_cond)
    ```

=== "equivalent Pyrope"

    ```pyrope
    total = 3

    while !a_cond {
      step
    }

    assert(total == 3 and a_cond)
    ```

The main reason for using the `step` is that the "equivalent" `#>[1]` is a more
structured construct. The `step` behaves more like a "yield" in that the next
call or cycle it will continue from there. The `#>[1]` directive adds a
pipeline structure which means that it can be started each cycle. Calling a
lambda that has called a `step` and still has not finished should result in a
simulation assertion failure.

* `peek` allows to read any flop, and lambda input or output

* `poke` is similar to `peek` but allows to set a value on any flop and lambda
  input/output.
