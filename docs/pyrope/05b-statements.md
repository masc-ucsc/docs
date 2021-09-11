
# Statements

## if


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

## for

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

## match

The `match` statement is similar to a chain of unique if/elif. Unlike in the
if/elif sequence, one of the options in the match must be true, and like the
unique, there should be no overlap.


Joining the match expression with the beginning of the match entry must form a
valid expression.

```
x = 1
match x {
  == 1   { puts "always true" }
  in 2,3 { puts "never"       }
}
// It is equivalent to:
unique if x == 1      { puts "always true" }
elif x in (2,3)       { puts "never"       }
else                  { assert false       }
```

Like the `if`, it can also be used as an expression.

## when/unless

Simple statement like assignments, variable/type definitions, and function
calls can be gated or not executed with a `when` or `unless` statement.

```
var a = 3
a += 1 when false             // never executes 
assert a == 3
assert a == 1000 when a > 10  // assert never executed either
```

Complex assignments like `a |> b(1) |> c` can not be gated because it is not
clear if the gated applies to the last call or the whole pipeline sequence.
Similarly, gating ifs/match statements does not make much sense.


## defer

A `defer` keyword can be added at the end of simple assignments or function
calls. This keyword effectively means that the statement right hand side reads
the last values from the end of the cycle. This is needed if we need to have
any loop in connecting blocks.

```
var c = 10
b = c defer
assert b == 33
c += 20
c += 3
```

To connect `ring` function calls in a loop.
```
f1 = ring($a, f4) defer
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



## step

## return


## try

Reserved for fluid

## while

Reserved for future use with HLS
