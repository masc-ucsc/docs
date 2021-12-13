
# Statements

## Conditional (`if`/`elif`/`else`)


Pyrope uses a typical `if`, `elif`, `else` sequence found in most languages.
Before the if starts, there is an optional keyword `unique` that enforces that
a single condition is true in the if/elif chain. This is useful for synthesis
which allows a parallel mux.

The `if` sequence can be used in expressions too.

```
a = unique if cond == 1 {
    300
  }elif cond == 2 {
    400
  }else{
    500
  }

var x
if a { x = 3 } else { x = 4 }
```

## Unique parallel conditional (`match`)

The `match` statement is similar to a chain of unique if/elif, like the
`unique if/elif` sequence, one of the options in the match must be true. The
difference is that one of the entries must be truth or an error is generated.
This makes the `match` statement a replacement for the common "unique parallel
case" Verilog directive.


In addition to functionality, the syntax is different to avoid redundancy.
`match` joins the match expression with the beginning of the matching entry must
form a valid expression.

```
x = 1
match x {
  == 1            { puts "always true" }
  in 2,3          { puts "never"       }
}
// It is equivalent to:
unique if x == 1  { puts "always true" }
elif x in (2,3)   { puts "never"       }
else              { assert false       }
```

Like the `if`, it can also be used as an expression.

```
var hot = match x {
    == 0b001 { a }
    == 0b010 { b }
    == 0b100 { c }
  }
```

## Gate statements (`when`/`unless`)

A simple statement like assignments, variable/type definitions, and function
calls can be gated or not executed with a `when` or `unless` statement. This is
similar to an `if` statement, but the difference is that the statement is in
the current scope, not creating a new scope. This allows cleaner more compact
syntax.

```
var a = 3
a += 1 when false             // never executes 
assert a == 3
assert a == 1000 when a > 10  // assert never executed either

ret 3 when some_condition
```

Complex assignments like `a |> b(1) |> c` can not be gated because it is not
clear if the gated applies to the last call or the whole pipeline sequence.
Similarly, gating ifs/match statements do not make much sense. As a result,
`when`/`unless` can only be applied to assignments, function calls, and scope
control statements (`return`, `break`, `continue`).


## Scope

A scope is a sequence of statements delimited by `{` and `}`. The functionality
is the same as in other languages. Variables can be declared within the scope
boundary. 


Scopes are different than lambdas. A lambda consists of scope but it has
several differences: Variables defined in upper scopes are accessed inside the
lambda as immutable copies, inputs and outputs could be constrained, and the
`ret`/`return` statements finish a lambda not a scope.


From a high-level point of view, scopes are used by statements like `if` and
`for`, the lambdas are function declarations.


The main features of scopes:

* New variable declarations inside the scope are not visible outside it. 

* Variable declaration shadowing is not allowed and a compiler error is generated.

* Expressions can have multiple scopes but they are not allowed to have
  side effects for variables outside the scope or scope state. The [evaluation
  order](02-basics.md#evaluation-order) provides more details on expressions
  evaluation order.

* When used in an expression or lambda, the last statement in the scope can be
  an expression.

* An expression scope, not lambda, can be terminated with the `break` statement
  that can also return a value. A `return` statement terminates the lambda
  scope, not the expression scope.

```
{
  var x=1
  var z
  {
    z = 10
    var x             // compile error, `x` shadows an upper scope
  }
  assert z == 10 
}
let zz = x            // compile error, `x` is out of scope

var yy = {let x=3 ; 33/3} + 1
assert yy == 12
let xx = {yy=1 ; 33}  // compile error, 'yy' has side effects

if {let a=1+yy; 13<a} {

}

let z3 = 1 + { if true { break 3  } else { assert false } }
assert z4 == 4
```

## Loop (`for`)

The `for` iterates over the first-level elements in a tuple or the values in a
range.  In all the cases, the number of loop iterations must be known at
compile time. The loop exit condition can not be run-time data-dependent.

The loop can have an early exit when calling `break` and skip of the current
iteration with the `continue` keyword.

```
for i in 0..<100 {
}

var bund = (1,2,3,4)
for i,index in bund {
  assert bund[j] == i
}


for mut i in bund {
  i += 1
}
assert bund == (2,3,4,5)
```

```
b = (a=1,b=3,c=5,7,11)

for i,index,key in b {
  assert i==1  implies (index==0 and key == 'a')
  assert i==3  implies (index==1 and key == 'b')
  assert i==5  implies (index==2 and key == 'c')
  assert i==7  implies (index==3 and key == '' )
  assert i==11 implies (index==4 and key == '' )
}
```

The `for` can also be used in an expression that allows building comprehensions
to initialize arrays. To indicate the values to add in the comprehensions there
are `cont`, `last`, or the last expression in the `for` scope.

```
var c = for i in 0..<5 { var xx = i }  // compile error, no expression
var c = for i in 0..<5 { cont i }
var d = for i in 0..<5 { i }
var 2 = for i in 0..<5 { last i }
assert c == (0,1,2,3,4) == d
assert e == (0)
```


### Scope control

Scope control statements allow changing the control flow for `lambdas`, `for`,
and `while` statements. When the control flow is changed, some allow scope
control allows to return a value (`ret`, `last`, `cont`) and others do not
(`return`, `break`, `continue`).


* `return` exits or terminates the current lambda. The current output variables
  are provided as the `lambda` output.

* `ret` behaves like `return` but requires a tuple. The tuple is the returned
  value, the output variables are not used. When a `method` calls `ret` the
  `self` is implicit.

* `break` terminates the closest higher scope that belongs to an expression, a
  `for`, or a `while`. If neither is found, a compile error is generated.

* `last` behaves like `break` but a return tuple is provided. This is maybe
  needed when the `for` or `while` is used in an expression. In addition, the
  `last` can be used in expression scopes. The `last` is equivalent to a `ret`
  but terminates the closest expression scope.

* `continue` looks for the closest upper `for` or `while` scope. The `continue`
  will perform the next loop iteration. If no upper loop is found, a compile
  error is generated.

* `cont` behaves like the `continue` but a tuple is provided. The `cont` is
  used with comprehensions, and the tuple provided is added to the
  comprehension result.


```
var total
for a in 1..=10 {
  continue when a == 2
  total ++= a
  break when a == 3    // exit for scope
}
assert total == (1,3)

if true {
  continue             // compile error, no upper loop scope
}

a = 3
var total2
if a>0 {
  total2 ++= a
  break when a == 2    // exit if scope
  a = a - 1
  continue
  assert false         // never executed
}
assert total2 == (3,2)
```

`ret`, `last`, and `cont` statements can have a tuple. This is only useful when
the statements are used in an expression.

```
total = for i in 1..=9 {
  cont  i+10 when i < 3
  last  i+20 when i > 5
}
assert total == (11, 12, 3, 4, 5, 26)

let v = {|| ret 4 }
assert v == 4

let y = {         // expr scope1
  var d=1 
  last {          // start expr scope2, last finishes scope1
    if true { 
      last 33     // finishes scope2
      assert false 
    } else { 
      last d
      assert false 
    }
  } + 200 
  assert false
}
assert y == (33+200)
```

## defer 

A `defer_read` keyword can be added before assignments or function calls. This
keyword effectively means that the statement on the right-hand side reads the last
values from the end of the current cycle. This is needed if we need to have any
loop in connecting blocks. It is also useful for delaying assertion checks to
the end of the function.

```
var c = 10
defer_read assert b == 33    // behaves like a postcondition
defer_read b = c
assert b == 33
c += 20
c += 3
```

To connect the `ring` function calls in a loop.
```
defer_read f1 = ring($a, f4)
f2 = ring($b, f1)
f3 = ring($c, f2)
f4 = ring($d, f3)
```

If the intention is to read the result after being a flop, there is no need to
use the `defer_read`, a normal register access could do it. If the read
variables are registers, the `defer_read ... = var` and the `var#[0]` is
equivalent. The difference is that defer_read does not insert a register.


```
reg counter:u32

let counter_m1 = counter#[-1] // last cycle
let counter_0  = counter#[0] // current cycle 
let counter_1  = counter#[1] // last cycle
let counter_2  = counter#[2] // last last cycle cycle 

defer_read deferred = counter

if counter < 100 {
  counter += 1
}else{
  counter = 0
}

if counter == 10 {
  assert deferred   == 10
  assert counter_0  == 10
  assert counter_1  ==  9
  assert counter_2  ==  8
  assert counter_m1 ==  9
}
```

The `defer_write` delays the write/updates to the end of the cycle but uses
the current value.

```
var a = 1
var x = 100
defer_write x = a
a = 200

comptime assert x == 100
defer_read comptime assert x == 1
```

## always block

Tuples can also have 3 special field entries: `always_before`, `always_after`,
and `always_reset`. These entries can point to methods that have
reserved functionality:

* `always_before` is executed every cycle BEFORE any method to a tuple is called.
  This method is called even when reset is set active. This means that the
  always_before is called even before the variable is initialized if there is a
  setter.

* `always_after` is similar to the `always_before` but the method is called after all the other methods to the tuple are called.

* `always_reset` is only called when the reset for the tuple is high. This
  means that it is valid only if the tuple is being instantiated as a `reg`.
  If called, it is called after the `always_after` so that their values can not
  be overridden by other methods.

## restrict/test/fail

These three very different statements have the same structure: `keyword <id> [when condition] { stmts+ }`.

The `id` is a string to identify/report when needed. The optional condition is when the statement is active.
For example, the `test` statement:

```pyrope
test "my test 1" when size > 10 {
  assert size>10
}
```

* `test` is active only during testing.
* `restrict` is used for formal verification to restrict a testing case with the `when` condition.
* `fail` is used to indicate that an expected test failure is expected. This can be a parse or assert failure.

In all the cases, the statements inside the code block can not have any effect outside.

## debug/comptime


Pyrope can assign/read compile attributes to variables, but two keywords and special access (`debug` and
`comptime`). Either of them can be placed at the beginning of the statement for
function calls and assignments. It is also possible to place them before code
blocks to indicate that all the statements inside the code block are either
`debug` or `comptime` constants.


```
let c = 3
comptime let x = c 

if runtime == 1 comptime {
  // all the values should be comptime
  xx = 3
}
```

## Test only (`step`/`waitfor`)

`test` code blocks are allowed to use special statements not available outside
testing blocks:


* `step [ncycles]` advances the simulation for several cycles. The local variables
will preserve the value, the inputs may change value.

* `waitfor condition` is a syntax sugar to wait for a condition to be true.

=== "`step`"

    ```
    test "wait 1 cycle" {
      let a = 1 + $input
      puts "printed every cycle input={}", a
      step 1
      puts "also every cycle a={}",a  // printed on cycle later
    }
    ```

=== "synthesizable equivalent"

    ```
    test "wait 1 cycle" {
      {
        pub let a = 1 + $input
        puts "printed every cycle input={}", a
      } #> {
        puts "also every cycle a={}",a  // printed on cycle later
      }
    }
    ```

The `waitfor` command is equivalent to a `while` with a `step`.

=== "`waitfor`"

    ```
    total = 3

    waitfor a_cond  // wait until a_cond is true

    assert total == 3 and a_cond
    ```

=== "equivalent Pyrope"

    ```
    total = 3

    while !a_cond {
      step
    }

    assert total == 3 and a_cond
    ```

The main reason for using the `step` is that the equivalent `#>` does not work
in loops.


## while

`while cond { [stmts]+ }` is a typical while loop found in most programming
languages.  The only difference is that like with loops, the while must be fully
unrolled at compilation time.

