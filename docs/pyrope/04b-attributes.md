# Attributes

Attributes is the mechanism that the programmer specifies some special
checks/functionality that the compiler should perform. Attributes are
associated to variables either by setting them at declaration or by reading
their value at use sites. Some example of attribute use is to mark statements
compile time constant, read the number of bits in an assertion, give placement
hints, or even interact with the synthesis flow to read timing delays.


A key difference between attributes and tuple fields is that attributes are
always compile time and the compiler flow has special meaning functionality
for them.

Internally, types are also propagated as attributes, but basic types can only be
`integer`, `bool`, or `string`.


Pyrope does not specify all the attributes, the compiler flow specifies them.
There are some built-in required attributes like checking the number of bits.

Reading attributes should not affect a logical equivalence check. Setting
attributes can have a side-effect because it can change bits used for
wrap/saturate or change pins like reset/clock in registers. Additionally,
attributes can affect assertions, so they can stop/abort the compilation.


There are two operations that can be done with attributes: **set** and
**read**. The two operations have distinct syntax so the reader (and the
parser) can never confuse them.

* **Set** (`var::[attr]` when no explicit type; `var:Type:[attr]` when a
  type is given — the colon between the type and the attribute block is
  not doubled): only allowed at *declaration* sites — `mut`, `reg`,
  `const`, `comb`, `pipe`, `mod` — and on tuple fields at the point they
  are introduced. The set binds the attribute to all uses of the variable.
  If no value is given, the attribute is set to `true`. E.g:
  `mut foo:uint:[max=300] = 4`, `reg counter::[clock_pin=clk1] = 0`,
  `const c::[debug] = 3`, `mut x2:complex:[valid=false] = 0`.

* **Read** (`var.[attr]`): allowed everywhere a normal expression is
  allowed. Returns the attribute's current value (any type — usually
  integer, boolean, or string). If the attribute was not set, the read
  returns `nil`. E.g: `tmp.[bits] < 30`, `assert.[failed]`,
  `x.[size]`, `i.[max]`.

A small subset of attributes correspond to a *runtime* hardware signal
rather than to compile-time metadata — for example `valid` (the per-cycle
optional bit) and `defer` (the end-of-cycle register port). For these the
`.[attr]` form can also appear on the *left-hand side* of an assignment to
drive the underlying wire: `self.[valid] = v != 33`,
`reg.[defer] = rhs`. Compile-time-only attributes (`max`, `bits`,
`comptime`, `debug`, `file`, …) are read-only at use sites; bind them with
`::[…]` at the declaration.

Since attributes are always compile time, the read happens at elaboration
time. To turn a read into a check, wrap it in `cassert` (or `assert`):

```
cassert y.[comptime]            // 'y' must be comptime
cassert y.[bar] == 3            // 'y.[bar]' must equal 3
cassert tmp.[bits] < 30
```

To check whether an attribute is set at all (without caring about its
value), compare against `nil`. Inside `.[...]` reads, comparisons against
`nil` are exempt from "the attribute must be defined" — they return `true`
or `false` rather than erroring at compile time:

```
cassert foo.[attr1] != nil      // attr1 was set on 'foo'
cassert xx.[attr2] == nil       // attr2 was never set on 'xx'
cassert foo.[attr1] == 2        // value check (errors at compile time if unset)
```

Since conditional code can depend on an attribute, which results in executing a
different code sequence that can lead to the change of the attribute. This can
create a iterative process. It is up to the compiler to handle this, but the
most logical is to trigger a compile error if there is no fast convergence.


```
// comptime as prefix modifier
comptime const foo:u32 = xx     // enforce that foo is comptime constant
yyy = xx                        // yyy does not check comptime
cassert yyy.[comptime]          // now, checks that 'yyy' is comptime

// reading attributes
if bar == 3 {
  tmp = bar
  cassert bar.[comptime]
}

cassert tmp.[bits] < 30 and not tmp.[comptime]
```

Pyrope allows to assign the attribute to a variable or a function call. Not to
statements because it is confusing if applied to the condition or all the
sub-statements.

```
comptime mut z = xx            // z is a comptime variable

if cond.[comptime] {           // cond is checked to be compile time constant
  comptime const x = a + 1     // x is comptime
}else{
  comptime const x = b         // x is comptime
}


if cond.[comptime] {           // checks if cond is comptime
  const v = cond
  if cond {
    puts "cond is compile time and true"
  }
}
```


The programmer could create custom attributes but then a LiveHD compiler pass
to deal with the new attribute is needed to handle based on their specific
semantic. To understand the potential Pyrope syntax, this is a hypothetical
`poison` attribute that marks a tuple field.

```
const bad = (a=3, b::[poison=true]=4)

const b = bad.b

cassert b.[poison] and b==4
```


Attributes control fields like the default reset and clock signal. This allows
to change the control inside procedures. Notice that this means that attributes
are passed by reference. This is not a value copy, but a pass by reference.
This is needed because when connecting things like a reset, we want to connect
to the reset wire, not the current reset value.

```
reg counter:u32 = 0

reg counter2::[clock_pin=clk1]=0
reg counter3::[reset_pin=rst2]=0

```

In the long term, the goal is to have any synthesis directive that can affect
the correctness of the result to be part of the design specification so that it
can be checked during simulation/verification.


There are 3 main classes of a attributes that all the Pyrope compilers should
always implement: Bitwidth, comptime, debug.

## Variable attribute list

In the future, the compiler may implement some of the following attributes, as
such. The attributes are by category.

Attributes are always compile time, but have the property of being sticky
(propagate across assignments and expression usage) or just being used for
checks/instantiation/hints on the assigned variable. From the following lists,
only `_debug` is a sticky, but all the "user custom" attributes can be sticky
or not. All the user attributes starting with `_` (like `_foo`) are sticky.
Otherwise, they are not sticky.

### Synthesis attribute list

There are a list of reserved attribute names for synthesis. These are hints and
can be ignored if not supported by the tool:

* `clock`: indicate a signal/input is a clock wire
* `reset`: indicate a signal/input is a reset wire
* `critical`: synthesis time criticality
* `delay`: synthesis optimization target delay hint
* `donttouch` or `keep`: do not touch/optimize away
* `inp_delay`, `out_delay`: synthesis optimizations hints
* `left_of`, `right_of`, `top_of`, `bottom_of`, `align_with`: placement hints
* `max_delay`, `min_delay`: synthesis optimizations checked at simulation
* `max_load`, `max_fanout`, `max_cap`: synthesis optimization hints

### Debug attribute list

There are a list of reserved attribute names for debug:

* `debug` and `_debug`: variable use for debug only, not synthesis allowed
* `file`: to print the file where the variable was declared
* `key`: variable/entry key name
* `loc`: line of code information
* `rand` and `crand`: simulation and compile time random number generation

### Type attribute list

* `private`: variable/field not visible to import/regref
* `comptime`: indicates that the variable should be compile time or a compile error is generated
* `const`: indicates that only one assignment to the variable can be done per cycle
* `mut`: multiple assignments to the variable can be done
* `type`: Either `integer` or `string` or `boolean` or `range` or complex tuple typename.
* `typename`: type name at variable declaration
* `size`: Number of entries in tuple or array (1 if not a multi-entry tuple)

### Integer Bitwidth attribute list

To set constraints on integer, the compiler has a set of bitwidth related
attributes. Only `max` and `min` exist internally as attributes to control bit
size, the others (`ubits`/`sbits`/`bits`) are "syntax sugar" and translated
from `max`/`min`.

* `max`: the maximum value allowed
* `min`: the minimum value allowed
* `ubits`: Maximum number of bits to represent the unsigned value. The number must be positive or zero
* `sbits`: Maximum number of bits, and the number can be negative
* `bits`: read-only; returns the number of bits currently required to
  represent the variable's value (`var.[bits]` in assertions)
* `wrap`: allows to drop bits that do not fit on the left-hand side. It performs sign
  extension if needed.
* `saturate` keeps the maximum or minimum (negative integer) that fits on the
  left-hand side.

### Registers and pipestage attribute list

Registers have the following attributes:

* `valid`, `retry`: for elastic pipelines
* `sync`: true by default, when false selects an asynchronous reset (posedge only)
* `initial`: reset value when reset is high
* `clock`: connected to `clock` by default
* `reset`: connected to `reset` by default
* `negreset`: active low reset signal
* `posclk`: true by default, selects a posedge or negnedge flop
* `retime`: allow to retime across the register
* `defer`: read or write the end-of-cycle value. `reg.[defer] = rhs` delays
  the write until the end of the current cycle (becomes the next cycle's 'q').
  `reg.[defer]` on the RHS reads the final value at the end of the current
  cycle. See [Pipelining](06c-pipelining2.md).

Pipestage accept the same register attributes but also two more:

* `lat`: latency for the pipestage
* `num`: maximum number of units allowed

### Memories attribute list

Memories are arrays with persistence like registers. As such, some of the attributes
are similar to registers, but unlike registers they can have multiple clocks.

* `addr`: Tuple of address ports for the memory.
* `bits`: The number of bits for each memory entry
* `size`: The number of entries. Total size in bits is $size x bits$.
* `clock`: Optional clock pin, `clock` by default. A tuple is possible to specify the clock for each address port.
* `din`: Tuple for memory data in port. The read ports must be hardwired to `0`.
* `enable`: Tuple for each memory port. Write or read enable (read ports can have enable too).
* `fwd`: Forwarding guaranteed (true/false). If fwd is false, there is no guarantee, it can have fwd or not.
* `latency`: Number of cycles (`0` or `1`) when the read is performed
* `wensize`: Write enable size allows to have a write mask. The default value
  is 1, a wensize of 2 means that there are 2 bits in the `enable` for each
  port. a wensize 2 with 2 ports has a total of 2+2+2 enable bits. Bit 0 of the
  enable controls the lower bits of the memory entry selected.
* `rdport`: Indicates which of the ports are read and which are written ports.
* `posclk`: Positive edge clock memory for all the memory clocks. The default is `true` but it can be set to `false`.

### Lambda attribute list

Lambda attributes allow [Introspection](07-typesystem.md#Introspection) which requires some attributes.

* `inputs`: returns the input tuple from the lambda
* `outputs`: returns the output tuple from the lambda


## Debug and verification attribute list

The following attributes are debug-only — they are elided from synthesis and
only valid inside `assert`, `cover`, `test`, and `waitfor` contexts:

* `rising`: true on the cycle where the signal transitions from 0/false to
  non-zero/true (same as `rose(sig)` from the temporal library)
* `falling`: true on the cycle where the signal transitions from
  non-zero/true to 0/false (same as `fell(sig)`)
* `changed`: true on any cycle where the signal differs from its previous
  value (same as `changed(sig)`)
* `timeout`: interpreted only by `waitfor`; bounds the wait to `N` cycles
  (e.g., `waitfor(ref done_rising, timeout=1000)` after binding
  `mut done_rising = done.[rising]`)

See [Verification](09-verification.md) for the full temporal library and
debug constructs.


The integer type constructor allows to use a range to set max/min, but it is
syntax sugar for direct attribute set.

```
opt1:uint:[max=300] = 0
opt2:int:[min=0,max=300] = 0  // same
opt3::[min=0,max=300] = 0     // same
opt4:int:[range=0..=300] = 0  // same

cassert opt1.[ubits] == 0    // opt1 initialized to 0, so 0 bits
opt1 = 200
cassert opt1.[ubits] == 8    // last assignment needs 9 sbits or 8 ubits
```

`wrap` and `saturate` control how the right-hand side of an assignment
narrows into the left-hand side when the value would otherwise overflow.
Two forms are supported:

* **Sticky** — set as an attribute at declaration. Every assignment to that
  variable is then wrapped (or saturated) automatically.
* **Per-statement** — use `wrap` or `sat` as a statement-level prefix
  modifier (similar to `comptime` or `debug`). The modifier controls the
  narrowing for that single assignment.

```
a:u32 = 100
b:u10 = 0
c:u5  = 0
d:u5  = 0
w:u5:[wrap] = 0     // sticky: every assignment to 'w' wraps

b = a               // OK, no precision lost
wrap c = a          // OK, same as c = a#[0..<5] (since 100 is 0ub1100100, c==4)
c = a               // error: 100 overflows the maximum value of 'c'
w = a               // OK, 'w' has a wrap set at declaration

sat c = a           // OK, c == 31
c = 31
d = c + 1           // error: '32' overflows the maximum value of 'd'

wrap d = c + 1      // OK, d == 0
sat  d = c + 1      // OK, d == 31
sat  d += 1         // OK, compound assignment

sat x:bool = c      // error: saturate only allowed in integers
```

The prefix is part of the assignment statement; it controls the narrowing
of the final RHS into the LHS. To narrow individual sub-expressions
independently, factor them into intermediate variables with their own
sticky `::[wrap]` or `::[saturate]`.

## comptime modifier

Pyrope borrows the `comptime` functionality from Zig. `comptime` is a prefix
modifier that can be applied to `const` or `mut` to indicate that the variable
must be resolvable at compile/elaboration time. `comptime` alone is shorthand
for `comptime const`.

```
comptime const SIZE = 16
comptime const a = 1        // same as above
comptime mut counter = 0    // mutable at compile time (updated during elaboration)
comptime const b = a + 2    // OK, comptime const
comptime c = rand           // error: 'c' is not resolvable at compile time

cassert SIZE == 16
cassert b == 3
```

The `comptime` status can still be queried with `.[comptime]`:

```
cassert a.[comptime]
```

To avoid too frequent comptime directives, Pyrope treats all the variables that
start with uppercase as compile time constants.

```
comptime const Xconst1 = 1    // obvious comptime
comptime const Xvar2 = rand   // error: 'Xvar2' is not compile time constant
```

## debug attribute

In software and more commonly in hardware, it is common to have extra
statements and state to debug the code. These debug functionality can be more
than plain assertions, they can also include code.


The `debug` attribute marks a mutable or immutable variable. At synthesis, all
the statements that use a `debug` can be removed. `debug` variables can read
from non debug variables, but non-debug variables can not read from `debug`.
This guarantees that `debug` variables, or statements, do not have any
side-effects beyond debug statements.

```
mut a = (b::[debug]=2, c = 3) // a.b is a debug variable
const c::[debug] = 3
```

Assignments to debug variables also bypass protection access. This means that
private variables in tuples can be accessed (read-only). Since `assert` marks
all the results as debug, it allows to read any public/private variable/field.


```
x:(_priv=3, zz=4) = ?

const tmp = x._priv         // error:
const tmp::[debug] = x.priv // OK

assert x._priv == 3    // OK, assert is a debug statement
```
