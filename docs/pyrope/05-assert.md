# Verification

Verification covers the language constructs and special support to ease design verification.



## Assertions

Assertions are considered debug statements. This means that they can not
have side effects on non-debug statements.

Pyrope supports a syntax close to Verilog for assertions. The language is
designed to have 3 levels of assertion checking: compilation time,
simulation runtime, and formal verification time.

There are 5 main verification statements:

* `assert/cassert`: The condition should be true at runtime. If `cassert`, the
  condition must be true at compile time.

* `optimize/coptimize`: Similar to assert, but allows the tool to simplify code
  based on it (it has optimization side-effects).

* `verify`: Similar to assert, but it is potentially slow to check, so it is
  checked only when formal verification is enabled. Simulation can also check
  for this, but because it is slow, it may not be active by default.

* `assume`: Constraints or restricts beyond to check a subset of the valid
  space. It only affects the `verify` and `assert` command, not the `optimize`.
  The `assume` command accepts a list of conditions to restrict.

The `cassert` are syntax suggar for a defined comptime assert. Since it is so
common, it is part of the basic syntax like `assert`.

```pyrope
let cassert::[comptime] = assert
let coptimize::[comptime] = optimize
```

```pyrope
a = 3
assert a == 3          // checked at runtime (or compile time)
cassert a == 3         // checked at compile time

verify a < 4           // checked at runtime and verification
optimize b > 3         // may optimize and perform a runtime check

assume "cond1" where foo < 1 and foo >3 {
   verify bar == 4  // only checked at verification, restricting conditions
}
```

A whole statement is conditionally executed using the `when`/`unless` gate expression.
This is useful to gate verification statements (`assert`, `optimize`, `verify`)
that can have spurious error messages under some conditions.


```pyrope
a = 0
if cond {
  a = 3
}
assert cond implies a == 3, "the branch was taken, so it must be 3??"
assert a == 3, "the same error" when   cond
assert a == 0, "the same error" unless cond
```


The recommendation is to write as many `assert` and `optimize` as possible. If
something can not happen, writing the `optimize` has the advantage of allowing
the synthesis tool to generate more efficient code.

In a way, most type checks have equivalent `cassert` checks.

## LEC

The `lec` command is a formal verification step that checks that all the
arguments are logically equivalent. The difference with `verify` is that it
also accepts functions (only). `lec` does not include the reset state. The
first argument is the gold model, the rest are implementation. This matters
because the gold model unknown output bit checks against any value for the
equivalent implementation bit.


!!! NOTE
    The recommendation is to use `optimize` and `assert` frequently, but
    clearly to check preconditions and postconditions of methods. The 1949
    Turing quote of how to write assertions and programs is still valid "the
    programmer should make a numner of definite assertions which can be checked
    individually, and from which the correctness of the whole program easily
    follows."

```
let fun1 = fun(a,b) { a | b}
let fun2 = fun(a,b) { ~(~a | ~b) }
lec fun1, fun2
```

In addition, there is the `lec_valid` command. It is similar to `lec` but it
checks the optional or valid (`::[valid]`) from the output. It can take several
cycles to show the same result.

```
let mul2 = proc(a,b) -> (reg out) {
  reg pipe1 = _

  out = pipe1

  pipe1 = a*b
}

let mul0 = fun(a,b)->(out) { out = a*b }

lec_valid mul0, mult2
```

## Coverage

A bit connected with the assertion is coverage. The goal of an assertion is to be
true all the time. The goal of a coverage point is to be true at least once
during testing.


There are two directives `cover` and `covercase`. The names are similar to the
System Verilog `coverpoint` and `covergroup` but the meaning is not the same.

* `cover cond [, message]` the boolean expression `cond` must evaluate true
  sometime during the verification or the tool can prove that it is true at
  compile time.

* `covercase grp, cond [,message]` is very similar to cover but it has a `grp`
  group. There can be one or more covers for a given group. The extra check is
  that one of the `cond` in the cover case must be true each time.


```pyrope
// coverage case NUM group states that random should be odd or even
covecase NUM,   random&1 , "odd number"
covecase NUM, !(random&1), "even number"

covercase COND1, reset, "in reset"
covercase COND1, val>3, "bigger than 3"

assert((!reset and val>3) or reset)  // less checks than COND1

cover a==3, "at least a is 3 once in a while"
```

The `covercase` is similar to writing the assertions, but it checks that all
the conditions happen through time or a low coverage is reported. In the
`COND1` case, the assertion does not check that sometimes reset is set, and
others the value is bigger than 3.  The assertion will succeed if reset is always
set, but the covercase will fail because the "bigger than 3" case will not be
tested.


The `cover` allows to not be true a given cycle. To allow the same in a
`covercase`, the designer can add `coverase GRP, true`. This is a true always
cover point for the indicated cover group.


## Reset, optional, and verification

In hardware is common to have an undefined state during the reset period. To
avoid unnecessary assertion failures, if any of the inputs depends on a
register directly or indirectly, the assertion is not checked when the reset is
high for the given registers. In Pyrope, the registers and memory contents
outputs are "invalid" (`::[valid]` attribute). `assert` and `optimize` will not
check when any of the signals are invalid. This is useful to avoid unnecessary
assert checks during reset or when the lambda is called with invalid data.


Adding the `always` modifier before the assert/coverage keywords guarantees
that the check is performed every cycle independent of the valid attribute.

To provide assert/optimize during reset, Pyrope provides a `always assert`,
`always cassert`, `always optimize`, `always coptimize`, `always covercase`, and
`always cover`.

```
reg memory:[]u33 = (1,2,3) // may take cycles to load this contents

assert memory[0] == 1 // not checked during reset

always assert memory[1] == 2 // may fail during reset
always assert memory[1] == 2 unless memory.reset  // should not fail
```

## Random

Random number generation are quite useful for verification. Pyrope provides
easy interfaces to generate "compile time" (`::[crand]`) and "simulation time"
random number (`::[rand]`) generation.


```
let x:u8 = _

for i in 1..<100 {
  cassert 0 <= x.[crand]  <= 255
}

let get_rand_0_2556 = fun(a:u8) {
  a.[rand]
}
```

Both rand and crand look at the set type max/min value and create a randon value
between them. rand picks randomly in boolean and enumerate types, but it triggers
a compile error for string, range, and lambda types.

When applied to a tuple, it randomly picks an entry from the tuple.

```
let a = (1,2,3,b=4)
let x = a.[rand]

cassert x==1 or x==2 or x==3 or x==4
cassert x.b==4 when x==4
```

The simulation random number is considered a `::[debug]` statement, this means
that it can not have an impact on synthesis or a compile error is generated.

## Test

Pyrope has the `test [message [,args]+] ( [stmts+] }`. 

=== "Many parallel tests"
    ```
    let add = fun(a,b) { a+b }

    for a in 0..=20 {
      for b in 0..=20 {
        test "checking add({},{})", a,b {
           cassert a+b == add(a,b)
        }
      }
    }
    ```

=== "Single large test"
    ```
    let add = fun(a,b) { a+b }

    test "checking add" {
      for a in 0..=20 {
        for b in 0..=20 {
           cassert a+b == add(a,b)
        }
      }
    }
    ```


The `test` code block also accepts the keyword `step` that advances one clock
cycle, and the test continues from that given point. This is useful for when a
lambda is instantiated and we want to check/update the inputs/outputs.

```
let counter = proc(update)->(value) {
  reg count:u8:[wrap] = 0

  value = count

  count += 1 when update
}

test "counter through several cycles" {
 
  var inp = true
  let x = counter(inp.[defer])  // inp contents at the end of each cycle 

  assert x == 0 // x.value == 0
  assert inp == true

  step

  assert x == 1
  inp = false

  step

  assert x == 1
  assert inp == false
  inp = true

  assert inp == true
  assert x == 1

  step

  assert inp == true
  assert x == 2
}
```

During `test` simulation, all the assertions are checked but the test does not
stop with a failure until the end. Sometimes it is useful to write tests to
check that assertions fail. Assertion failures will be printed but the test
will continue and fail only if the `assert.[failed]` is true. The `test` code
block also accepts to read and/or clear failed attribute.

```
test "assert should fail" {

 let n = assert.[failed] 
 assert n == false

 assert false // FAILS

 assert assert.[false]

 assert.[failed] = false // disable test failures done when it finishes
}
```

## Monitor

TODO

