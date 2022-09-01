# Assertions

Assertions are considered debug statements. This means that they can not
have side effects on non-debug statements.

Pyrope supports a syntax close to Verilog for assertions. The language is
designed to have 3 levels of assertion checking: compilation time,
simulation runtime, and formal verification time.

There are 5 main verification statements:

* `assert`: The condition should be true at runtime. If `comptime assert`, the
  condition must be true at compile time.

* `assume`: Similar to assert, but allows the tool to simplify code based on it
  (it has optimization side-effects).

* `verify`: Similar to assert, but it is potentially slow to check, so it is
  checked only when formal verification is enabled. Simulation can also check
  for this, but because it is slow, it may not be active by default.

* `restrict`: Constraints or restrictions beyond to check a subset of the
  valid space. It only affects the verify command. The restrict command
  accepts a list of conditions to restrict.

* `lec`: It is a formal verification step that checks that all the arguments are
  logically equivalent. The difference with `verify` is that it also accepts
  functions (only). `lec` does not include the reset state. The first argument
  is the gold model, the rest are implementation. This matters because the gold
  model unknown output bit checks against any value for the equivalent
  implementation bit.



```pyrope
a = 3
assert a == 3          // checked at runtime (or compile time)
comptime assert a == 3 // checked at compile time

verify a < 4           // checked at runtime and verification
assume b > 3           // may optimize and perform a runtime check

restrict "cond1" when foo < 1 and foo >3 {
   verify bar == 4  // only checked at verification, restricting conditions
}

let fun1 = fun(a,b) { ret a | b}
let fun2 = fun(a,b) { ret ~(~a | ~b) }
lec fun1, fun2
```

To guard an assertion against being checked unless some condition happens, you
can use the `when/unless` statement modifier or the `implies` logic. All the
verification statements (`assert`, `assume`, `verify`) can have an error
message.

```pyrope
a = 0
if cond {
  a = 3
}
assert cond implies a == 3, "the branch was taken, so it must be 3??"
assert a == 3, "the same error" when   cond
verify a == 0, "the same error" unless cond
```


The recommendation is to write as many `assert` and `assume` as possible. If
something can not happen, writing the `assume` has the advantage of allowing
the synthesis tool to generate more efficient code.

In a way, most type checks have equivalent `comptime assert` checks.

## Asserts and reset

In hardware is common to have an undefined state during the reset period. Ideally
asserts should not be active during reset periods unless explicitly stated. The
problem is that it may not clear what is a reset period.


Pyrope by default resets all the variables, registers, and memories to zero,
but the reset logic could take several cycles to reset a memory. As such,
disabling the assertion when indexing arrays may be the best solution.

```
reg memory:u33[] = (1,2,3) // may take cycles to load this contents

assert memory[0] == 1 unless some_signal_is_reset
```


# Coverage

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

