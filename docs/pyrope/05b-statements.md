
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
break and continue
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

Every statement can be gated or not executed with a `when` or `unless` statement.

```
var a = 3
a += 1 when false             // never executes 
assert a == 3
assert a == 1000 when a > 10  // assert never executed either
```

## defer

Every statement can have a `defer` keyword at the end. This keyword effectively
means that the statement right hand side reads the last values from the end of
the cycle. This is needed if we need to have any loop in connecting blocks.

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

## test

## debug

## step

## return

## fail

Expect a failure. This is use mostly for compiler testing

## try

Reserved for fluid

## while

Reserved for future use with HLS
