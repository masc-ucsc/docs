
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

var x = _
if a { x = 3 } else { x = 4 }
```

Like several modern programming languages, there can be a list of expressions
in the evaluation condition. If variables are declared, they are restricted to
the remaining if/else statement blocks.


```
var tmp = x+1

if var x1=x+1; x1 == tmp {
   puts "x1:{} is the same as tmp:{}", x1, tmp
}elif var x2=x+2; x2 == tmp {
   puts "x1:{} != x2:{} == tmp:{}", x1, x2, tmp
}
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

Like the `if` statement, a sequence of statements and declarations are possible in the match statement.

```
match let one=1 ; one ++ (2) {
  == (1,2) { puts "one:{}", one }      // should always hit
}
```

## Gate statements (`when`/`unless`)

A simple statement like assignments, variable declarations, and function calls
and returns can be gated or not executed with a `when` or `unless` statement.
This is similar to an `if` statement, but the difference is that the statement
is in the current scope, not creating a new scope. This allows cleaner more
compact syntax.

```
var a = 3
a += 1 when false             // never executes 
assert a == 3
assert a == 1000 when a > 10  // assert never executed either

var my:reg = 3 when some_condition  // no register declared otherwise

ret "fail" unless success_condition
```

Complex assignments like `a |> b(1) |> c` can not be gated because it is not
clear if the gated applies to the last call or the whole pipeline sequence.
Similarly, gating ifs/match statements do not make much sense. As a result,
`when`/`unless` can only be applied to assignments, function calls, and code
block control statements (`return`, `break`, `continue`).


## Code block

A code block is a sequence of statements delimited by `{` and `}`. The
functionality is the same as in other languages. Variables declared within
a code block are not visible outside the code block. In other words, code block
variables have scope from definition until the end of the code block.


Code blocks are different from lambdas. A lambda consists of a code block but
it has several differences. In lambdas, variables defined in upper scopes are
accessed inside as immutable copies only when captured by scope, inputs and
outputs could be constrained, and the `ret`/`return` statements finish a lambda
not a code block.


The main features of code blocks:

* Code blocks define a new scope. New variable declarations inside are not visible outside it. 

* Code blocks do not allow variable declaration shadowing.

* Expressions can have multiple code blocks but they are not allowed to have
  side-effects for variables outside the code block. The [evaluation
  order](02-basics.md#evaluation-order) provides more details on expressions
  evaluation order.

* When used in an expression or lambda, the last statement in the code block
  can be an expression.

* `brk/break` vs `ret/return`: Some code blocks, not lambda, can be terminated
  with the `brk/break` statement. A `ret/return` statement terminates the
  lambda, not the expression code block.

```
{
  var x=1
  var z=_
  {
    z = 10
    var x=_           // compiler error, 'x' is a shawdow variable
  }
  assert z == 10 
}
let zz = x            // compile error, `x` is out of scope

var yy = {let x=3 ; 33/3} + 1
assert yy == 12
let xx = {yy=1 ; 33}  // compile error, 'yy' has side effects

if {let a=1+yy; 13<a} {
  // a is not visible in this scope
  some_code()
}

let z3 = 1 + { if true { brk 3  } else { assert false } }
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
 some_code(i)
}

var bund = (1,2,3,4)
for i,index in bund {
  assert bund[j] == i
}
```

```
let b = (a=1,b=3,c=5,7,11)

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
are `cont`, `brk`, or the last expression in the `for` code block.

```
var c = for i in 1..<5 { var xx = i }  // compile error, no expression
var c = for i in 0..<5 { cont i }
var d = for i in 0..<5 { i }
var 2 = for i in 0..<5 { brk i }
assert c == (0,1,2,3,4) == d
assert e == (0)
```

The iterating element is copied by value, if the intention is to iterate over a
vector or array to modify the contents, a `ref` must be used. Only the element
is mutable, the index or key are always immutable. The mutable for can not be
used in comprehensions.

```
b = (1,2,3,4,5)

for x in ref b {
  x += 1
}
assert b == (2,3,4,5,6)
```

### Code block control

Code block control statements allow changing the control flow for `lambdas`,
`for`, and `while` statements. When the control flow is changed, some allow
returning a value (`ret`, `brk`, `cont`) and others do not (`return`, `break`,
`continue`).


* `return` exits or terminates the current lambda. The current output variables
  are provided as the `lambda` output.

* `ret` behaves like `return` but requires a tuple. The tuple is the returned
  value, the output variables are not used.

* `break` terminates the closest higher code block that belongs to an
  expression, a `for`, or a `while`. If neither is found, a compile error is
  generated.

* `brk` behaves like `break` but a return tuple is provided. This is maybe
  needed when the `for` or `while` is used in an expression or comprehension.
  In addition, the `brk` can be used in expression code blocks. The `brk` is
  equivalent to a `ret` but terminates the closest `for`/`while` code block.

* `continue` looks for the closest `for`/`while` code block. The `continue`
  will perform the next loop iteration. If no upper loop is found, a compile
  error is generated.

* `cont` behaves like the `continue` but a tuple is provided. The `cont` is
  used with comprehensions, and the tuple provided is added to the
  comprehension result.


```
var total = ()
for a in 1..=10 {
  continue when a == 2
  total ++= a
  break when a == 3    // exit for scope
}
assert total == (1,3)

if true {
  code(x)
  continue             // compile error, no upper loop scope
}

a = 3
var total2 = ()
while a>0 {
  total2 ++= a
  break when a == 2    // exit if scope
  a = a - 1
  continue
  assert false         // never executed
}
assert total2 == (3,2)
```

`ret`, `brk`, and `cont` statements can have a tuple. This is only useful when
the statements are used in an expression.

```
total = for i in 1..=9 {
  cont  i+10 when i < 3
  brk  i+20 when i > 5
}
assert total == (11, 12, 3, 4, 5, 26)

let v = fun() { ret 4 }
assert v == 4

let y = {         // expr scope1
  var d=1 
  brk {          // start expr scope2, brk finishes scope1
    if true { 
      brk 33     // finishes scope2
      assert false 
    } else { 
      brk d
      assert false 
    }
  } + 200 
  assert false
}
assert y == (33+200)
```

## while

`while cond { [stmts]+ }` is a typical while loop found in most programming
languages. The only difference is that like with loops, the while must be fully
unrolled at compilation time.


Like `if`/`match`, the `while` condition can have a sequence of statements with
variable declarations visible only inside the while statements.

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
defer_read f1 = ring(a, f4)
f2 = ring(b, f1)
f3 = ring(c, f2)
f4 = ring(d, f3)
```

If the intention is to read the result after being a flop, there is no need to
use the `defer_read`, a normal register access could do it. If the read
variables are registers, the `defer_read ... = var` and the `var#[0]` is
equivalent. The difference is that defer_read does not insert a register.


```
var counter:reg u32 = _

let counter_m1 = counter#[-1] // last cycle
let counter_0  = counter#[0]  // current cycle 
let counter_1  = counter#[1]  // last cycle
let counter_2  = counter#[2]  // last last cycle cycle 

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

$(comptime) assert x == 100
defer_read assert x == 1
```

## Testing (`test`)

The test statement requires a text identifier to notify when the test fails.
The `test` is similar to a `puts` statement followed by a scope (`test <str>
[,args] { stmts+ }`). The statements inside the code block can not have any
effect outside. 


```pyrope
test "my test {}", 1 {
  assert true
}
```

Each `test` can run in parallel, to increase the throughput, putting the
randomization outside the test statement increases the number of tests:


=== "Parallel tests"
    ```
    let add = fun(a,b) { ret a+b }

    for i in 0..<10 { // 10 tests
      let a = (-30..<100).rand
      let b = (-30..<100).rand

      test "test {}+{}",a,b {
        assert add(a,b) == (a+b)
      }
    }
    ```

=== "Single test"
    ```
    let add = fun(a,b) { ret a+b }

    test "test 10 additions" {
      for i in 0..<10 { // 10 tests
        let a = (-30..<100).rand
        let b = (-30..<100).rand

        assert add(a,b) == (a+b)
      }
    }
    ```

### Test only statements

`test` code blocks are allowed to use special statements not available outside
testing blocks:


* `step [ncycles]` advances the simulation for several cycles. The local variables
will preserve the value, the inputs may change value.

* `waitfor condition` is a syntax sugar to wait for a condition to be true.

=== "`step`"

    ```
    test "wait 1 cycle" {
      let a = 1 + input
      puts "printed every cycle input={}", a
      step 1
      puts "also every cycle a={}",a  // printed on cycle later
    }
    ```

=== "synthesizable equivalent"

    ```
    test "wait 1 cycle" {
      {
        let a = 1 + input
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

* `peek` allows to read any flop, and lambda input or output

* `poke` is similar to `peek` but allows to set a value on any flop and lambda
  input/output.


