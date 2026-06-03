# Small Pyrope - Minimal Hardware Description Language

A minimal subset of Pyrope that can express any hardware design while being implementation-friendly. Small pyrope is designed to be the subset of Pyrope
that allows easier implementation of a first Pyrope compiler while being compatible with full Pyrope.

## Core Principles

Small Pyrope maintains Pyrope's expressiveness while reducing complexity:

* Everything is a tuple (fundamental data structure)

* Structural typing only

* Compile-time elaboration for all control flow

* Simple timing model with explicit cycles

## Types and Variables

### Basic Types
Small Pyrope supports integers (`u8`, `i16`, `int`), `bool`, and `string`. Type annotations use `:` and are optional when they can be inferred.

Number literals may include `_` separators with no meaning (`12_34__ == 1234`). Binary literals may include `?` bits (don't care/unknown). For unset variables, use the explicit `nil` placeholder; for unknown bits, use `0sb?`. There is no bare `_` or bare `?` shorthand.

`nil` marks "no value yet" — it is only legal as the *placeholder* for a not-yet-assigned variable. **Reading a `nil` value in any expression is a compile error.** Assign a real value before any use.

Attributes are set at declaration with `::[…]` (or `:Type:[…]`) and are independent of the type: `name:Type:[attr=value]`. Use `name.[attr]` to read attribute values (see Attributes section).
```pyrope
// Integers (signed/unsigned with bit constraints)
mut a:u8 = 100          // 8-bit unsigned
mut b:i16 = -50         // 16-bit signed
mut c:int = 1000        // Unlimited precision (compile-time only)

// Boolean
mut flag:bool = true

// String (basic operations)
mut text:string = "hello"
mut combined = text ++ " world"  // Tuple concatenation (strings are tuples of characters)
puts("Debug: value is ", combined)   // Print for debugging

// Initialization always requires a concrete value — no bare `_` or `?`.
mut y:int = 0           // Explicit value
mut u:int = 0sb?        // Valid, but all bits unknown
mut z:int = nil         // Placeholder; any read of `z` before assignment is a compile error

// Inside bit literals, '?' marks unknown bits (valid but unobserved, like Verilog x)
// Arithmetic works: 0sb? + 1 = 0sb??, 0sb? | 1 = 1
mut unknown = 0ub101?    // Bit 0 is unknown
mut partial = 0ub??10    // Multiple unknown bits
```

### Variable Storage Classes
Semicolons have the same behavior as a newline: they are optional, but can be used to put multiple statements on one line.
```pyrope
comptime const SIZE = 16    // Compile-time constant (shorthand for comptime const)
comptime mut counter = 0    // Mutable at compile time (updated during elaboration)
const constant = 42         // Immutable after assignment (NOT compile-time)
mut wire = 0                // Combinational (no persistence, can be reassigned)
reg state = 0               // Register (persistent across cycles)
```

Variables have two orthogonal properties: mutability (`const` vs `mut`) and
timing (`comptime` vs runtime). `const` is immutable after assignment but its
value can differ on each function call. `mut` can be reassigned. The `comptime`
prefix modifier means the value must be resolvable at compile/elaboration time.
`reg` persists across cycles. `comptime` alone is shorthand for `comptime const`.

### Variable Scope (Simplified)
```pyrope
// Code block scope
mut a = 3
{
    assert(a == 3)      // Visible from outer scope
    mut b = 4           // Local to this block
    // const a = 33     // error: no shadowing allowed
}
// assert b == 4       // error: 'b' not visible outside block

// Functions have their own runtime scope; visible comptime bindings are lexical
comb example() {
    mut local = 5       // Function-local variable
    local + 1
}
```

### Tuples (Core Data Structure)
```pyrope
mut point = (x=10, y=20)        // Named tuple
mut array = (1, 2, 3, 4)        // Indexed tuple
mut mixed = (x=1, 2, y=3)       // Mixed named/indexed

// Access
cassert(point.x == 10)
cassert(array[2] == 3)          // Array-style access

// Concatenation (++ is always tuple concatenation — strings, lambdas, tuples)
mut combined = point ++ (z=30)  // (x=10, y=20, z=30)
cassert(combined == (x=10, y=20, z=30))
```

### Ranges
```pyrope
mut range1 = 1..=5              // Inclusive range: 1,2,3,4,5
mut range2 = 0..<4              // Exclusive range: 0,1,2,3
mut range3 = 2..+3              // Size-based range: 2,3,4

// Range operations
cassert((1..=3) == (1,2,3))       // Range to tuple conversion
cassert(int(1..=3) == 0ub1110)    // Range to one-hot encoding
cassert(range1 == (1,2,3,4,5))
cassert(range2 == (0,1,2,3))
cassert(range3 == (2,3,4))
```

### Arrays and Memories
```pyrope
mut buffer:[16]u8 = nil         // Array (no persistence)
reg memory:[256]u32 = 0         // Memory (persistent)

memory[addr] = data             // Write
mut read_data = memory[addr]    // Read

// Range-based access
mut slice = buffer[1..=4]       // Extract elements 1-4

// Memory with synthesis attributes
reg ram:[1024]u32:[
  latency=1,                    // 1-cycle read latency
  fwd=true,                     // Write-to-read forwarding
  wensize=4,                    // 4-bit write enable (byte enables)
  rdport=(0,1), wrport=(2,3)    // Port assignment
] = 0

// Dual-port access (simple Pyrope requires explicit port attribute for multiport)
ram[addr1]::[wrport=2] = data1            // Write port 2
ram[addr2]::[wrport=3] = data2            // Write port 3
mut out1 = ram.port[0][addr3]::[rdport=0] // Read port 0
mut out2 = ram.port[1][addr4]::[rdport=1] // Read port 1
```

## Lambda Types: `comb`, `pipe`, `mod`
Small Pyrope functions do not support runtime capture variables and do not
include the `mod` orchestration features (`stage[N]` and `@[N]`). Visible
comptime bindings, such as imports and `comptime const` declarations, are
available lexically. Pass runtime values explicitly as arguments.

### Combinational or Pure Functions (`comb`)

In Pyrope, a combinational or pure function is a stateless function without memory or registers. As such, it can not have side-effects. A `comb` **may not** declare a `reg` (the only exception is debug state explicitly marked `::[debug]`, which is forbidden from affecting non-debug outputs). If you need state, write a `pipe` or `mod`.

```pyrope
comb add(a:u8, b:u8) -> (result:u8) {
    result = a + b
}

// 'return' is a terminator only — assign the output first, then return
comb clamp(x:i16) -> (result:u8) {
    if x < 0   { result = 0;   return }   // early exit
    if x > 255 { result = 255; return }   // early exit
    result = x                            // normal path
}

cassert(add(3, 4) == 7)
cassert(clamp(-10) == 0)
cassert(clamp(500) == 255)
cassert(clamp(42) == 42)
```

### Pipeline

A pipeline is a Moore machine — outputs always go through flops. The latency
is written as an argument to the `pipe` keyword (e.g., `pipe[3]`), and the
tool may retime logic for performance, but the behavior is equivalent to a
`comb` with N flops appended at the outputs. Pipelines can use `reg` for
internal storage, but besides storage, they behave like a `comb` with
pipelined outputs.


```pyrope
pipe[1] counter(enable:bool) -> (reg count:u8) {
    if enable { count += 1 }
}

mod fifo(push:bool, pop:bool, data_in:u18) -> (data_out:u18, full:bool, empty:bool) {
    reg buffer:[16]u18 = 0sb?
    reg head:u4 = 0
    reg tail:u4 = 0
    reg count:u5 = 0

    if push and !full {
        buffer[head] = data_in
        head = (head + 1) & 0xF
        count += 1
    }

    if pop and !empty {
        data_out = buffer[tail]
        tail = (tail + 1) & 0xF
        count -= 1
    }

    full = (count == 16)
    empty = (count == 0)
}
```

### Module (pipeline orchestration)

A `mod` connects combinational, pipeline, or other `mod` blocks with
explicit timing control, and can hold `reg` state across cycles. There are
two complementary timing mechanisms inside `mod` blocks:

* `stage[N]` as a declaration modifier: pipelines the whole RHS over N
  cycles (e.g., `stage[3] tmp = mul(a, b)`). It is the only *action* that
  inserts or chooses pipeline stages.
* `foo@[N]` on a variable (LHS or RHS): a pure timing *type check*. It
  never inserts flops; a mismatch is a compile error.

```pyrope
pipe mul(a, b) -> (c) { c = a * b }
pipe add(a, b) -> (c) { c = a + b }

mod alu(in1, in2) -> (out_pipelined, out_live) {
  stage[3] tmp              = mul(in1, in2)
  stage[3] in2_d            = in2
  stage[1] out_pipelined@[4] = add(tmp@[3], in2_d@[3])
  stage[1] out_live@[4]      = add(tmp@[3], in2_d@[3])
}

mod accum_alu(in1, in2) -> (out) {
  reg total::[init=0]
  stage[3] tmp = mul(in1, in2)
  const sum_aligned = add(total@[3], tmp@[3])  // both operands checked at cycle 3
  total = sum_aligned                          // register write
  out = total                                  // bare name reads current 'q'
}
```

Inside `mod` blocks, every RHS value at a non-zero cycle must reach it
through a `stage[N]` declaration; there is no implicit alignment. Use
`foo@[N]` on either side to document or enforce cycle expectations. Type
and attribute *binding* happen only at declarations on the left-hand side;
checks on RHS values use separate `cassert` statements.

```pyrope
cassert(b does u8)                                        // RHS type check
cassert(c.[xxx_should_be_set])                            // RHS attribute check
// Destructure by return-field name (LHS local names must match field
// names of `some_mod_call`'s return tuple, or use `field = local` to
// rename).
const (out=tmp:u32, status=tmp2:u3:[something=true]) = some_mod_call(a, b@[3], c@[2])
```


## Control Flow

### Conditionals
```pyrope
if condition {
    result = a
} else {
    result = b
}
```

Pyrope also has `when`/`unless` trailing modifiers for single-statement
**compile-time** conditionals. The condition must be `comptime`: think of
them as `#if` / `#ifndef`, not as a runtime mux. They include or omit the
statement during elaboration based on compile options, types, or other
comptime values. They do not create a new scope.

```
comptime const DEBUG = true

assert(!enable) when    DEBUG    // included only when DEBUG is true
return          unless DEBUG    // omitted when DEBUG is true
```

For *runtime* gating (a mux or enable on a signal), use an `if` block or
an `if` expression on the RHS:

```
if enable { count += 1 }         // runtime mux
result = if cond { a } else { b }
```

### Compile-Time Loops

Loop bounds must be `comptime` (known at compile time) so that loops can be
unrolled. The loop body can contain runtime logic — only the bounds are
compile-time.

```pyrope
// For loops (bounds must be comptime, body is runtime hardware)
for i in 0..=7 {
    memory[i] = init_value
}

// Range-based loops
for val in 1..<10 step 2 {  // 1,3,5,7,9
    process(val)
}
```

### Match (Pattern Matching)

`match` is always unique (mutually exclusive branches, like `unique if`). It
supports any comparison operator, not just equality. **Every `match` must
end with an `else` arm** — omitting it is a parse error.

```pyrope
match state {
    == 0 { next_state = 1 }
    == 1 { next_state = 2 }
    == 2 { next_state = 0 }
    else { next_state = 0 }   // required
}

// `case` checks structure with `does`, then checks defined values
match state {
    case 0 { next_state = 1 }
    case 1 { next_state = 2 }
    case 2 { next_state = 0 }
    else   { next_state = 0 }
}

// Other comparison operators are allowed
match value {
    < 0  { result = -1 }
    == 0 { result = 0 }
    > 0  { result = 1 }
    else { result = 0 }       // required; unreachable here, but must be written
}
```

## Enumerations

`enum` declares a set of named values. When the variants have no payload, the
representation is one-hot (one bit per value), which is ideal for FSMs. When
the variants carry payloads (per-case types), the representation packs the
shared storage as a tagged union (the equivalent of a `variant` in some
languages). Either way, only one variant is active at a time.

```pyrope
enum State = (Idle, Active, Done)       // One-hot encoding: 1, 2, 4

cassert(int(State.Idle)   == 1)
cassert(int(State.Active) == 2)
cassert(int(State.Done)   == 4)

reg current_state:State = State.Idle

match current_state {
    case State.Idle {
        if start    { current_state = State.Active }
    }
    case State.Active {
        if complete { current_state = State.Done }
    }
    case State.Done {
        current_state = State.Idle
    }
    else { /* unreachable: all states covered above */ }
}
```

## Attributes

Attributes provide compile-time metadata and constraints for variables, enabling hardware-specific optimizations and Verilog compatibility.

### Attribute Syntax

Attributes are **set only at declaration** using `::[attr=value]` (or `:Type:[attr=value]` when a type is also given). The `.[attr]` syntax is used to **read** attribute values everywhere else.

```pyrope
// Set attribute (only at declaration)
reg counter::[reset_pin=ref rst] = 0 // Set reset pin (ref connects the wire)

// Read attribute value
const num_bits = counter.[bits]     // Read number of bits

// Check attribute (read inside cassert)
cassert(counter.[bits] == 8)        // Check bit width
cassert(z.[bits] < 32)              // Check bit width constraint

// Compile-time uses the 'comptime' prefix modifier (not an attribute)
comptime const SIZE = 16
comptime mut elaboration_cnt = 0   // mutable at compile time
cassert(SIZE.[comptime])           // Can still query comptime status
```

### Common Attributes

Attributes are **immutable after declaration**. To change attributes, create a new variable.

```pyrope
// Bitwidth constraints
mut data:u32:[max=1000, min=0] = 0

// Overflow behavior — always written as a statement-level prefix
// (not an attribute). Every narrowing assignment must annotate its
// overflow choice locally, or the compiler rejects the assignment.
mut result:u8  = 0
wrap result = a + b                      // This operation wraps to u8
mut clamped:u8 = 0
sat clamped = x + y                      // This operation saturates to u8

// Typecast: call the type as a constructor
mut truncated = u8(large_val)            // Explicit typecast to u8

// Compile-time uses the 'comptime' prefix modifier
comptime const SIZE = 16                // Known at elaboration time
mut array_size = SIZE               // Uses compile-time value

// Hardware attributes
reg state::[reset_pin=ref my_reset] = 0  // Custom reset signal (ref = wire connection)
reg clocked::[clock_pin=ref fast_clk] = 0 // Custom clock signal
reg no_reset::[reset_pin=false] = 0      // Tied low (comptime value, no ref needed)
reg async_reg::[async=true] = 0      // Asynchronous reset
reg pipeline::[retime=true] = 0      // Allow synthesis retiming

// Debug attributes
mut debug_val::[debug=true] = counter // Debug-only variable
```

### Memory Attributes
```pyrope
// Single-port memory with basic attributes
reg memory:[256]u32:[latency=1, fwd=true] = 0

// Multi-port memory configuration
reg dual_port:[1024]u16:[
  rdport=(0,1),        // Ports 0,1 are read ports
  wrport=(2),          // Port 2 is write port
  latency=1,           // Read latency
  fwd=false,           // No forwarding
  wensize=4            // 4-bit write enable mask
] = 0

// Memory with custom clocking
reg async_mem:[64]u8:[
  clock=(clk1, clk2),  // Different clocks per port
  reset=mem_rst,       // Custom reset signal
  posclk=false         // Negative edge triggered
] = 0
```

## Operators

### Arithmetic
```pyrope
mut sum = a + b; mut diff = a - b; mut prod = a * b; mut div = a / b  // Basic arithmetic
mut left_shift = a << n; mut right_shift = a >> n  // Shifts
const remainder = a % b  // Modulo (debug-only: too expensive for single-cycle hardware)
```

### Bitwise
```pyrope
mut and_result = a & b; mut or_result = a | b; mut xor_result = a ^ b  // AND, OR, XOR
mut not_result = ~a             // NOT
```

### Logical
```pyrope
mut logical_and = a and b; mut logical_or = a or b  // Logical (no short-circuit)
mut logical_not = !a            // Logical NOT
```

### Comparison
```pyrope
mut equal = a == b; mut not_equal = a != b  // Equality
mut less = a < b; mut less_eq = a <= b; mut greater = a > b; mut greater_eq = a >= b  // Comparison
```

### Bit Selection and Reduction
```pyrope
mut value = 0ub1010_1100
mut bits = value#[3..=6]        // Extract bits 3-6
value#[3] = 0                   // Set 3rd bit to 0

// Reduction operators
mut or_reduce = value#|[..]     // OR-reduce all bits
mut and_reduce = value#&[..]    // AND-reduce all bits
mut xor_reduce = value#^[..]    // XOR-reduce (parity)
mut pop_count = value#+[..]     // Population count

// Sign/zero extension
mut extended = value#sext[0..=3] // Sign extend bits 0-3 (3 is sign)
mut zero_ext = value#zext[1..=5] // Zero extend bits 1-5 (no sign)

// Selectors take a single expression (bit index, range, or conditional).
// Multi-entry tuple indices like `value#[0,3,7]` are NOT allowed: the
// ordering of a bit set is ambiguous and easy to misread. To pack
// non-contiguous bits, declare a destination and assign each bit
// explicitly. Every bit must be driven exactly once or it is a compile
// error.

mut sparse:u3 = nil
sparse#[0] = value#[0]
sparse#[1] = value#[3]
sparse#[2] = value#[7]

mut rparse:u3 = nil
rparse#[0] = value#[7]
rparse#[1] = value#[3]
rparse#[2] = value#[0]

cassert(value  == 0ub1010_0100) // bit 3 was cleared above
cassert(sparse  == 0ub100)     // bit 7 of value is 1, bit 3 is 0, bit 0 is 0
cassert(rparse  == 0ub001)     // bits placed in reverse order
cassert(pop_count == 3)
cassert(or_reduce  == -1)       // any bit set
cassert(and_reduce ==  0)       // sign bit (MSB) is 0
```

## Operator Precedence

Small Pyrope follows the same precedence rules as full Pyrope for compatibility:

| Priority | Category | Operators |
|:--------:|:--------:|-----------|
| 1 | Unary | `!`, `not`, `~`, `-` |
| 2 | Multiply/Divide | `*`, `/` |
| 3 | Other Binary | `+`, `-`, `++`, `<<`, `>>`, `&`, `\|`, `^`, `..=`, `..<`, `..+` |
| 4 | Comparators | `<`, `<=`, `==`, `!=`, `>=`, `>` |
| 5 | Logical | `and`, `or`, `implies` |

```pyrope
// Explicit parentheses required for mixed precedence
mut result = (a * b) + (c & d)   // Clear precedence
// mut mixed = a * b + c & d     // error: use parentheses

// Chained comparisons allowed
assert(a <= b <= c)              // Same as: a <= b and b <= c
```

## Testing and Verification

### Assertions
```pyrope
assert(condition)              // Runtime assertion
cassert(compile_time_expr)     // Compile-time assertion

test "counter test" {
    const cnt = counter(true)
    puts("Counter value: ", cnt)   // Debug output
    step( )// Advance one cycle
    assert(cnt == 1)
    cassert(SIZE == 16)        // Compile-time constant check
}
```

### Debug Output
```pyrope
// Basic puts for debugging
puts("Hello World")            // Simple string output
puts("Value: ", variable)      // Print variable
puts("Count: ", count, " Max: ", max_val)  // Multiple values
```

## Hardware Semantics

### Register Updates
```pyrope
reg counter:u8 = 0
mut tmp:u8 = counter

counter += 1                    // Register write
tmp += 1
assert(counter == tmp)

// `.[defer]` is RHS-only — it reads the value the register will hold
// at end of cycle (after all in-cycle writes have accumulated).
assert(counter.[defer] == tmp)

// There is no LHS `.[defer] = ...` form. Just write `counter = ...`.

// Timing syntax summary:
// counter         - current value (cycle-start 'q' or in-cycle accumulator,
//                   per the register-write rules)
// counter.[defer] - end-of-cycle value (RHS read only)
// past(counter)   - value from previous cycle
// past[2](counter)- two cycles ago
```

### Reset Behavior
```pyrope
reg counter:u8 = 100            // Reset value is 100
```

## Module System

### Import (Basic)
```pyrope
// Import functions from other files
const math_ops = import("math/basic")
const result = math_ops.add(a, b)

// Import specific function
const multiply = import("math/basic/multiply")
const product = multiply(x, y)

// Import from local file
const utils = import("utils")
utils.debug_print("Hello")
```

## Complete Example

```pyrope
// Import required modules
const test_utils = import("test/helpers")

// Simple CPU register file
pipe[1] reg_file(
    clk:bool,
    we:bool,
    ra:u5,
    rb:u5,
    wa:u5,
    wd:u32
) -> (
    rd_a:u32,
    rd_b:u32
) {
    reg registers:[32]u32 = 0

    // Read ports (1st read, no forwarding)
    rd_a = if ra == 0 { 0 } else { registers[ra] }
    rd_b = if rb == 0 { 0 } else { registers[rb] }

    // Write port
    if we and wa != 0 {        // Register 0 is always 0
        registers[wa] = wd
    }
}

test "register file" {
    // Cycle 0: write 42 to register 1, read regs 3 and 1
    const rf = reg_file(we=true, ra=3, rb=1, wa=1, wd=42)
    // pipe[1] outputs are registered — these reflect the initial state (all zeros)
    assert(rf.rd_a == 0)         // reg[3] = 0 (initial), delayed 1 cycle
    assert(rf.rd_b == 0)         // reg[1] = 0 (initial), delayed 1 cycle

    step

    // Cycle 1: no write, read reg 1 (was written last cycle)
    const rf2 = reg_file(we=false, ra=1, rb=0, wa=0, wd=0)
    // Output still reflects cycle 0 reads due to pipe[1] delay
    assert(rf2.rd_a == 0)        // reg[3] still 0

    step

    // Cycle 2: pipe[1] output now reflects cycle 1 reads
    const rf3 = reg_file(we=false, ra=1, rb=0, wa=0, wd=0)
    assert(rf3.rd_a == 42)       // reg[1] = 42 (written in cycle 0, read in cycle 1, output in cycle 2)
    assert(rf3.rd_b == 0)        // reg[0] always 0
}
```


## TODO: Features to Add After Small Pyrope Implementation

This section has moved. See `new_syntax_doc/01c-small_pyrope_todo.md` for examples of planned features beyond Small Pyrope.
