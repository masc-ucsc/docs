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

Number literals may include `_` separators with no meaning (`12_34__ == 1234`). Binary literals may include `?` bits (don't care/unknown). The `?` value also serves as the default/uninitialized value.

Attributes are set at declaration with `:[...]` and are independent of the type: `name:Type:[attr=value]`. Use `::[attr]` to read attribute values (see Attributes section).
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
puts "Debug: value is ", combined   // Print for debugging

// Default initialization
mut x = ?               // Type default (0 for int, false for bool, "" for string)
mut y = 0               // Explicit value

// '?' bits are unknown (valid but unobserved, like Verilog x)
// Arithmetic works: 0sb? + 1 = 0sb??, 0sb? | 1 = 1
mut unknown = 0b101?    // Bit 0 is unknown
mut partial = 0b??10    // Multiple unknown bits

// 'nil' is invalid (NOT unknown) — any use is an assertion error
// The compiler must prove all nil uses are eliminated or compile error
mut z = nil             // invalid, can only be copied until assigned a real value
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
    assert a == 3       // Visible from outer scope
    mut b = 4           // Local to this block
    // const a = 33     // Error: no shadowing allowed
}
// assert b == 4       // Error: 'b' not visible outside block

// Functions have their own scope (Small Pyrope does not support capture variables)
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
assert point.x == 10
assert array[2] == 3            // Array-style access

// Concatenation (++ is always tuple concatenation — strings, lambdas, tuples)
mut combined = point ++ (z=30)  // (x=10, y=20, z=30)
```

### Ranges
```pyrope
mut range1 = 1..=5              // Inclusive range: 1,2,3,4,5
mut range2 = 0..<4              // Exclusive range: 0,1,2,3
mut range3 = 2..+3              // Size-based range: 2,3,4

// Range operations
assert (1..=3) == (1,2,3)       // Range to tuple conversion
assert int(1..=3) == 0b1110     // Range to one-hot encoding
```

### Arrays and Memories
```pyrope
mut buffer:[16]u8 = ?           // Array (no persistence)
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
ram[addr1]:[wrport=2] = data1            // Write port 2
ram[addr2]:[wrport=3] = data2            // Write port 3
mut out1 = ram.port[0][addr3]:[rdport=0] // Read port 0
mut out2 = ram.port[1][addr4]:[rdport=1] // Read port 1
```

## Lambda Types: `comb`, `pipe`, `flow`, `mod`
Small Pyrope functions do not support capture variables (e.g. `comb f[a] { ... }` is not supported). Pass values explicitly as arguments.

### Combinational or Pure Functions (`comb`)

In Pyrope, a combinational or pure function is a stateless function without memory or registers. As such, it can not have side-effects.

```pyrope
comb add(a:u8, b:u8) -> (result:u8) {
    result = a + b
}

// Implicit return: last expression is the return value
comb add_simple(a:u8, b:u8) {
    a + b                       // Returns single-element tuple
}

// 'return' is only needed for early exits
comb clamp(x:i16) -> (result:u8) {
    return 0 when x < 0        // Early exit
    return 255 when x > 255    // Early exit
    result = x                  // Normal path, no return needed
}
```

### Pipeline

A pipeline is a Moore machine — outputs always go through flops. The `pipe`
declares its latency (e.g., `pipe::[3]`), and the tool may retime logic for
performance, but the behavior is equivalent to a `comb` with N flops appended
at the outputs. Pipelines can use `reg` for internal storage, but besides
storage, they behave like a `comb` with pipelined outputs.


```pyrope
pipe counter::[stages=1](enable:bool) -> (reg count:u8) {
    count += 1 when enable
}

mod fifo(push:bool, pop:bool, data_in:u18) -> (data_out:u18, full:bool, empty:bool) {
    reg buffer:[16]u18 = _
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

### Flow (Connecting Blocks)

A flow connects combinational, pipeline, or other flow blocks with explicit
timing control. Flows can also use `reg` for persistent state across cycles.
There are three complementary timing mechanisms inside `flow` blocks:

* `delay[N]` on operations: specifies that an operation takes N cycles.
* `var@[N]` on uses (RHS): specifies which cycle to read the value at. The
  compiler inserts alignment delays if needed.
* `:@[N]` on declarations (LHS): optional timing type check. The compiler
  verifies the computed cycle matches N.

```pyrope
pipe mul(a, b) -> (c) { c = a * b }
pipe add(a, b) -> (c) { c = a + b }

flow alu(in1, in2) -> (out_pipelined, out_live) {
  const (tmp, in2_d) = delay[3] (mul(in1@[0], in2@[0]), in2)
  out_pipelined@[4]  = delay[1] add(tmp@[3], in2_d@[3])
  out_live           = delay[1] add(tmp@[3], in2@[0])
}

flow accum_alu(in1, in2) -> (out) {
  reg total:[init=0]
  const tmp = delay[3] mul(in1@[0], in2@[0])
  const sum_aligned = add(total@[0], tmp@[3])  // explicit timing makes alignment clear
  total@[1] = sum_aligned                       // @[1] defers write to end of cycle
  out = total@[0]  // current register output
}
```

Inside flow blocks, variable uses on the right-hand side should have a `@[N]`
time annotation for the compiler to check alignment. The left-hand side can
optionally use `:@[N]` as a timing type check. As usual, variables can also
have type and attribute checks.

```pyrope
const (tmp:u32, tmp2:u3:[something=true]) = some_flow_call(a@[0], b@[3]:u32, c@[2]::[xxx_should_be_set=true])
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
conditionals. `when cond` executes the statement only if `cond` is true;
`unless cond` executes only if `cond` is false. Unlike `if` blocks, these do
not create a new scope — the statement stays in the current scope. They can be
applied to assignments, function calls, assertions, and control statements
(`return`, `break`, `continue`).
```
return when    enable
return unless !enable  // Same

assert !enable
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
supports any comparison operator, not just equality.

```pyrope
match state {
    == 0 { next_state = 1 }
    == 1 { next_state = 2 }
    == 2 { next_state = 0 }
    else { next_state = 0 }
}

// `case` is an alias for `==` in match statements
match state {
    case 0 { next_state = 1 }
    case 1 { next_state = 2 }
    case 2 { next_state = 0 }
    else   { next_state = 0 }
}

// Other comparison operators are allowed
match value {
    < 0   { result = -1 }
    == 0  { result = 0 }
    > 0   { result = 1 }
}
```

## Enumerations

`enum` uses one-hot encoding (each value maps to a single bit), which is ideal
for FSMs in hardware. `variant` is a tagged union that shares bits between
entries for more compact representation. Both allow only one entry to be active
at a time.

```pyrope
enum State = (Idle, Active, Done)       // One-hot encoding: 1, 2, 4

reg current_state:State = State.Idle

match current_state {
    case State.Idle {
        current_state = State.Active when start
    }
    case State.Active {
        current_state = State.Done when complete
    }
    case State.Done {
        current_state = State.Idle
    }
}
```

## Attributes

Attributes provide compile-time metadata and constraints for variables, enabling hardware-specific optimizations and Verilog compatibility.

### Attribute Syntax

Attributes are **set only at declaration** using `:[attr=value]`. The `::[]` syntax is **only for reading** attribute values.

```pyrope
// Set attribute (only at declaration)
reg counter:[reset_pin=ref rst] = 0 // Set reset pin (ref connects the wire)

// Read attribute value
const num_bits = counter::[bits]    // Read number of bits

// Check attribute (read and compare)
cassert counter::[bits] == 8        // Check bit width
cassert z::[bits] < 32              // Check bit width constraint

// Compile-time uses the 'comptime' prefix modifier (not an attribute)
comptime const SIZE = 16
comptime mut elaboration_cnt = 0   // mutable at compile time
cassert SIZE::[comptime] == true   // Can still query comptime status
```

### Common Attributes

Attributes are **immutable after declaration**. To change attributes, create a new variable.

```pyrope
// Bitwidth constraints
mut data:u32:[max=1000, min=0] = 0

// Overflow behavior (set at declaration - applies to all operations)
mut counter_wrap:u8:[wrap=true] = 0      // Always wraps on overflow
mut counter_sat:u8:[saturate=true] = 0   // Always saturates on overflow

// One-off overflow behavior (typecast with attributes)
mut result = (a + b):u8:[wrap=true]      // This operation wraps to u8
mut clamped = (x + y):u8:[saturate=true] // This operation saturates to u8

// Typecast without attributes
mut truncated = (large_val):u8           // Explicit typecast to u8

// Compile-time uses the 'comptime' prefix modifier
comptime const SIZE = 16                // Known at elaboration time
mut array_size = SIZE               // Uses compile-time value

// Hardware attributes
reg state:[reset_pin=ref my_reset] = 0  // Custom reset signal (ref = wire connection)
reg clocked:[clock_pin=ref fast_clk] = 0 // Custom clock signal
reg no_reset:[reset_pin=false] = 0      // Tied low (comptime value, no ref needed)
reg async_reg:[async=true] = 0      // Asynchronous reset
reg pipeline:[retime=true] = 0      // Allow synthesis retiming

// Debug attributes
mut debug_val:[debug=true] = counter // Debug-only variable

// To "change" attributes, create a new variable
mut new_data:[wrap=true] = data     // new_data has wrap, data unchanged
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
mut value = 0b1010_1100
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

// Non-contiguous bit selection is a short-cut for bit selection and tuple typecast
// Careful to avoid endian confusion (think about tuple order)

mut sparse1 = (value#[0], value#[3], value#[7])#[..]
mut sparse2 = value#[0,3,7]      // Select bits 0, 3, and 7

mut rparse1 = (value#[7], value#[3], value#[0])#[..]
mut rparse2 = value#[7,3,0]      // Select bits 7, 3, and 0

assert value  == 0b1010_1100
assert sparse2== 0b1____1__0
assert rparse2== 0b011           // reverse order of bits (LSB-first packing)
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
// mut mixed = a * b + c & d     // Error: use parentheses

// Chained comparisons allowed
assert a <= b <= c               // Same as: a <= b and b <= c
```

## Testing and Verification

### Assertions
```pyrope
assert condition               // Runtime assertion
cassert compile_time_expr      // Compile-time assertion

test "counter test" {
    const cnt = counter(true)
    puts "Counter value: ", cnt   // Debug output
    step                      // Advance one cycle
    assert cnt == 1
    cassert SIZE == 16         // Compile-time constant check
}
```

### Debug Output
```pyrope
// Basic puts for debugging
puts "Hello World"            // Simple string output
puts "Value: ", variable      // Print variable
puts "Count: ", count, " Max: ", max_val  // Multiple values
```

## Hardware Semantics

### Register Updates
```pyrope
reg counter:u8 = 0
mut tmp:u8 = counter

counter += 1                    // Immediate update
tmp += 1
assert counter == tmp

counter@[1] += 1                // Defer write to end of cycle
assert counter == tmp
tmp += 1

assert counter != tmp
assert counter::[defer] == tmp  // Read deferred value (end of cycle)
assert counter@[1] == tmp       // OK in assert (debug): @[1] == ::[defer] for registers

// Timing syntax summary:
// counter@[0]  - current value (same as just 'counter')
// counter@[]   - deferred value (end of current cycle)
// counter@[-1] - value from previous cycle
// counter@[1]  - next cycle value (compile error unless debug context)
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
pipe reg_file::[stages=1](
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
    if we {
        registers[wa] = wd when (wa != 0)  // Register 0 is always 0
    }
}

test "register file" {
    // Cycle 0: write 42 to register 1, read regs 3 and 1
    const rf = reg_file(we=true, ra=3, rb=1, wa=1, wd=42)
    // pipe::[1] outputs are registered — these reflect the initial state (all zeros)
    assert rf.rd_a == 0          // reg[3] = 0 (initial), delayed 1 cycle
    assert rf.rd_b == 0          // reg[1] = 0 (initial), delayed 1 cycle

    step

    // Cycle 1: no write, read reg 1 (was written last cycle)
    const rf2 = reg_file(we=false, ra=1, rb=0, wa=0, wd=0)
    // Output still reflects cycle 0 reads due to pipe::[1] delay
    assert rf2.rd_a == 0         // reg[3] still 0

    step

    // Cycle 2: pipe::[1] output now reflects cycle 1 reads
    const rf3 = reg_file(we=false, ra=1, rb=0, wa=0, wd=0)
    assert rf3.rd_a == 42        // reg[1] = 42 (written in cycle 0, read in cycle 1, output in cycle 2)
    assert rf3.rd_b == 0         // reg[0] always 0
}
```


## TODO: Features to Add After Small Pyrope Implementation

This section has moved. See `new_syntax_doc/01c-small_pyrope_todo.md` for examples of planned features beyond Small Pyrope.
