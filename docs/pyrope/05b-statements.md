
# Statements

## Conditional (`if`/`elif`/`else`)


Pyrope uses a typical `if`, `elif`, `else` sequence found in most languages.
Before the if starts, there is an optional keyword `unique` that enforces that
a single condition is true in the if/elif chain. This is useful for synthesis
which allows a parallel mux. The `unique` is a cleaner way to write an
`optimize` statement.

The `if` sequence can be used in expressions too.

```
a = unique if x1 == 1 {
    300
  }elif x2 == 2 {
    400
  }else{
    500
  }

var x = _
if a { x = 3 } else { x = 4 }
```

The equivalent code with an explicit `optimize`, but unlike the `optimize`, the
`unique` will guarantee to generate the `hotmux` statement.

```
optimize !(x1==1 and x2==2)
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


```
var tmp = x+1

if var x1=x+1; x1 == tmp {
   puts "x1:{} is the same as tmp:{}", x1, tmp
}elif var x2=x+2; x2 == tmp {
   puts "x1:{} != x2:{} == tmp:{}", x1, x2, tmp
}
```


## Unique parallel conditional (`match`)

The `match` statement is similar to a chain of unique if/elif, like the `unique
if/elif` sequence, one of the options in the match must be true. The difference
is that one of the entries must be truth or an error is generated. This makes
the `match` statement a replacement for the common "unique parallel case"
Verilog directive. The `match` statement behaves like also having an `optimize`
statement which allows for more efficient code generation than a sequence of
`if/else`.


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
    == 0sb001 { a }
    == 0sb010 { b }
    == 0sb100 { c }
  }

// Equivalent
optimize (x==0sb001 or x==0sb010 or x==0sb100)
var hot2 = __hotmux(x, a, b, c)

assert hot==hot2
```

Like the `if` statement, a sequence of statements and declarations are possible in the match statement.

```
match let one=1 ; one ++ (2) {
  == (1,2) { puts "one:{}", one }      // should always hit
}
```

Since the `==` is the most common condition in the `match` statement, it can be
omitted.

```
for x in 1..=5 {
  let v1 = match x {
    3 { "three" }
    4 { "four" }
    else { "neither"}
  }

  let v2 = match x {
    == 3 { "three" }
    == 4 { "four" }
    else { "neither"}
  }
  cassert v1 == v2
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

reg my = 3 when some_condition  // no register declared otherwise

return "fail" unless success_condition
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
it has several differences. In lambdas, (1) variables defined in upper scopes
are accessed inside as immutable copies only when captured by scope; (2) inputs
and outputs could be constrained, and (3) the `return` statement finishes a
lambda not a code block.


The main features of code blocks:

* Code blocks define a new scope. New variable declarations inside are not visible outside it. 

* Code blocks do not allow variable declaration shadowing.

* Expressions can have multiple code blocks but they are not allowed to have
  side-effects for variables outside the code block. The [evaluation
  order](02-basics.md#evaluation-order) provides more details on expressions
  evaluation order.

* When used in an expression or lambda, the last statement in the lambda code
  block can be an expression. It is not needed to add the `return` keyword in
  this case.

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

let doit = fun(f,a) {
  let x = f(a)
  assert x == 7
  return 3
}

let z3 = doit(fun(a) { 
  assert a!=0
  return 7             // exist the current lambda
  100                  // never reached statement
}, 33)
cassert z3 == 3
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
for (index,i) in bund.enumerate() {
  assert bund[j] == i
}
```

```
let b = (a=1,b=3,c=5,7,11)
assert b.keys() == ('a', 'b', 'c', '', '')
assert b.enumerate() == ((0,1), (1,3), (2,5), (3,7), (4,11))
let xx= zip(b.keys(), b.enumerate()) 
cassert xx == (('a',0,a=1), ('b',1,b=3), ('c',2,c=5), ('',3,7), ('',4,11))

for (key,index,i) in zip(keys(b),b.enumerate()) {
  assert i==1  implies (index==0 and key == 'a')
  assert i==3  implies (index==1 and key == 'b')
  assert i==5  implies (index==2 and key == 'c')
  assert i==7  implies (index==3 and key == '' )
  assert i==11 implies (index==4 and key == '' )
}

let c = ((1,a=3), b=4, c=(x=1,y=6))
assert c.enumerate() == ((0,(1,a=3)), (1,b=4), (2,c=(x=1,y=6)))
```

The `for` can also be used in an expression that allows building comprehensions
to initialize arrays. Pyrope uses a comprehension similar to Julia or Python.

```
var c = for i in 1..<5 { var xx = i }  // compile error, no expression
var d = i for i in 0..<5 
var e = i for i in 0..<5 if i
assert (0,1,2,3,4) == d
assert e == (1,2,3,4)
```

The iterating element is copied by value, if the intention is to iterate over a
vector or array to modify the contents, a `ref` must be used. Only the element
is mutable. When a `ref` is used, it must be a variable reference, not a
function call return (value). The mutable for can not be used in
comprehensions.

```
b = (1,2,3,4,5)

for x in ref b {
  x += 1
}
assert b == (2,3,4,5,6)
```

### Code block control

Code block control statements allow changing the control flow for `lambdas` and
loop statements (`for`, `loop`, and `while`). `return` can have a value.

* `return` exits or terminates the current lambda. The current output variables
  are provided as the `lambda` output. If a tuple is provided, the tuple is the
  returned value, the output variables are not used.

* `break` terminates the closest inner loop (`for`/`while`/`loop`). If none is
  found, a compile error is generated.

* `continue` looks for the closest inner loop (`for`/`while`/`loop`) code
  block. The `continue` will perform the next loop iteration. If no inner loop
  is found, a compile error is generated.


```
var total:[] = _
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
var total2:[] = _
while a>0 {
  total2 ++= a
  break when a == 2    // exit if scope
  a = a - 1
  continue
  assert false         // never executed
}
assert total2 == (3,2)

total = i+10 for i in 1..=9 if i<3
assert total == (11, 12)
```

## while/loop

`while cond { [stmts]+ }` is a typical while loop found in most programming
languages. The only difference is that like with loops, the while must be fully
unrolled at compilation time. The `loop { [stmts]+ }` is equivalent to a `while
true { [stmts]+ }`.


Like `if`/`match`, the `while` condition can have a sequence of statements with
variable declarations visible only inside the while statements.

```
// a do while contruct does not exist, but a loop is quite clean/close

var a = 0
loop {
  puts "a:{}",a

  a += 1

  break unless a < 10 
} // do{ ... }while(a<10)
```

## defer 

A `defer` attribute can be applied to variables. When used to read a variable,
it returns the last values written to the variable the end of the current
cycle. This is needed if we need to have any loop in connecting blocks. The
`defer` applied to a write, delays the write update to the end of the cycle.
The delayed writes happen before the delayed reads. This is also for delaying
assertion checks to the end of the cycle like post condition checks.

```
var c = 10
assert b.[defer] == 33    // behaves like a postcondition
b = c.[defer]
assert b == 33
c += 20
c += 3
```

To connect the `ring` function calls in a loop.
```
f1 = ring(a, f4.[defer])
f2 = ring(b, f1)
f3 = ring(c, f2)
f4 = ring(d, f3)
```

If the intention is to read the result after being a flop, there is no need to
use the `defer`, a normal register access could do it. If the read
variables are registers, the `flop#[0]` is not the same as `defer`. The `flop#[0]`
reads the value before any update, the `defer` read, gets values after updates.

```
reg counter:u32 = _

let counter_m1 = counter#[1]  // compile error, #[1] only allowed for debug
let counter_0  = counter#[0]  // current cycle 
let counter_1  = counter#[-1] // last cycle
let counter_2  = counter#[-2] // last last cycle cycle 

var deferred = counter.[defer]

if counter < 100 {
  counter += 1
}else{
  counter = 0
}

if counter == 10 {
  assert deferred   == 10
  assert counter_0  ==  9
  assert counter_1  ==  8
  assert counter_2  ==  7
}
```

The `defer` can also be applied to write/updates to the end of the cycle but
uses/reads the current value. In a way, the assignment is delayed to the end of
the current cycle. If there are many defers to the same variable, they are
ordered in program order.

```
var a = 1
assert a == 1 and a.[defer] == 200

a::[defer] = 100
assert a == 1 and a.[defer] == 200

a::[defer] = 200
assert a == 1 and a.[defer] == 200
```

If there are `defer` reads and `defer` assignments, the defered writes are
performed before the defered reads.

```
var a = 1
var x = 100
x::[defer] = a
a = 200

cassert x == 100
assert x.[defer] == 1
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
    let add = fun(a,b) { a+b }

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
    let add = fun(a,b) { a+b }

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

The main reason for using the `step` is that the "equivalent" `#>[1]` is a more
structured construct. The `step` behaves more like a "yield" in that the next
call or cycle it will continue from there. The `#>[1]` directive adds a
pipeline structure which means that it can be started each cycle. Calling a
lambda that has called a `step` and still has not finished should result in a
simulation assertion failure.

* `peek` allows to read any flop, and lambda input or output

* `poke` is similar to `peek` but allows to set a value on any flop and lambda
  input/output.

