
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
`unique` if/elif sequence, one of the options in the match must be true. The
difference is that one of the entries must be truth or an error is generated.
This makes the `match` statement a replacement for the common "unique parallel
case" Verilog directive.


In addition to functionality, the syntax is different to avoid redundancy.
`match` joins the match expression with the beginning of the match entry must
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

## Gate statements (`when`/`unless`)

Simple statement like assignments, variable/type definitions, and function
calls can be gated or not executed with a `when` or `unless` statement. This is
similar to an `if` statement, but the difference is that the statement is in
the current scope, not creating a new scope.

```
var a = 3
a += 1 when false             // never executes 
assert a == 3
assert a == 1000 when a > 10  // assert never executed either
```

Complex assignments like `a |> b(1) |> c` can not be gated because it is not
clear if the gated applies to the last call or the whole pipeline sequence.
Similarly, gating ifs/match statements does not make much sense. As a result,
`when`/`unless` can only be applied to assignments, function calls, and scope
control statements (`return`, `break`, `continue`).

## Loop (`for`)

The `for` iterates over the first level elements in a bundle or the values in a
range.  In all the cases, the number of loop iterations must be known at
compile time. The loop exit condition can not be run-time data dependent.

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


The `for` can also be used in an expression which allows to build
comprehensions to initialize arrays.

```
var c = for i in 0..<5 { i }
assert c == (0,1,2,3,4)
```

## Scope control (`break`, `continue`, `return`)

Pyrope has scopes and lambdas. The scopes are used by statements like `for` and
`if`, the lambdas are assigned to variables or passes as arguments. A `return`
statement exits or terminates the current lambda. The `break` statement exists or
terminates the current scope. If the scope was used by another statement, the `break`
exists the associated scope.


The `continue` starts to evaluate the current scope. When used in a `for`
statement, the `continue` will perform the next loop iteration. In other
statements, the statement will be re-evaluated and re-execute potentially
creating a loop condition.

```
var total
for a in 1..=10 {
  continue when a == 2
  total ++= a
  break when a == 3      // exit for scope
}
assert total == (1,3)

a = 3
var total2
if a>0 {
  total2 ++= a
  break when a == 2  // exit if scope
  a = a - 1
  continue
  assert false       // never executed
}
assert total2 == (3,2)
```

In addition, the three statements can have a bundle. This is only useful when
the statements are used in an expression.

```
total = for i in 1..=9 {
  continue i+10 when i < 3
  break    i+20 when i > 5
}
assert total == (11, 12, 3, 4, 5, 26)

v = if total[0] == 11 {
  break 4 
  assert false
} else { 
  0 
}
assert v == 4
```

A scope has a `break` when the last statement in the scope is an expression. If
the return value is not the last expression in the scope, the `break` statement
should be used. Notice that a `return` statement will exit the lambda not the
current scope.

## defer

A `defer` keyword can be added before assignments or function calls. This
keyword effectively means that the statement right hand side reads the last
values from the end of the cycle. This is needed if we need to have any loop in
connecting blocks. It is also useful for delaying assertion checks to the end
of the function.

```
var c = 10
defer assert b == 33    // behaves like a postcondition
defer b = c
assert b == 33
c += 20
c += 3
```

To connect `ring` function calls in a loop.
```
defer f1 = ring($a, f4)
f2 = ring($b, f1)
f3 = ring($c, f2)
f4 = ring($d, f3)
```

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

## Delay to next cycle (`step`/`yield`)

Both `step` and `yield` break down the program in the statements before and after. The
statements after the `step`/`yield` statement will be executed in future cycles.

The difference is that `step` has the number of cycles to wait, and the `yield` has the condition
that must be satisfied to continue. In a way, both build a small state machine.


=== "`step`"

    ```
    a = 1 + $input
    puts "printed every cycle input={}", a
    step 1
    puts "also every cycle a={}",a  // printed on cycle later
    ```

=== "custom FSM version"

    ```
    a = 1 + $input
    puts "printed every cycle input={}", a

    if #step_cycle {
      puts "also every cycle a={}",#step_a
    }
    #step_a      = a
    #step_cycle  = true
    ```

The `yield` has a slightly different FSM with a supporting FIFO structure.
Unlike the `step`, the `yield` is potentially unconstrained. This is why the
`yield` must also provide the  maximum  number of outstanding waiting
conditions.

=== "`yield`"

    ```
    total = 3
    yield 5, a_cond  // wait until a_cond is true
    assert total == 3 and a_cond
    ```

=== "custom FSM version"

    ```
    total = 3
    if a_cond {
      local_total = #fifo.pop()
      assert local_total == 3
    }
    #fifo.push(total)
    ```

Currently, the `yield` and `step` statements can not be used in loop constructs.

## try

Reserved for fluid

## while

Reserved for future use with HLS
