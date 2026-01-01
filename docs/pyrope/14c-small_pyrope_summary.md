# Small Pyrope - Summary

This document provides essential guidance for LLMs generating Small Pyrope code, highlighting unique syntax and semantics that differ from mainstream programming languages.

## Core Language Identity

Small Pyrope is a **hardware description language** with these fundamental characteristics:

* **Everything is a tuple** - the core data structure

* **Structural typing only** - no nominal types in Small Pyrope

* **Compile-time elaboration** for all control flow

* **Explicit timing model** with cycles for hardware simulation

## Critical Syntax Differences from Mainstream Languages

### 1. Storage Classes (NOT variable mutability)
```pyrope
let my_constant = 42    // Compile-time constant (immutable)
var my_wire = 0         // Combinational (no persistence across cycles)
reg my_state = 0        // Register (persistent across cycles)
```
**LLM Pitfall**: Don't confuse with `const`/`let`/`var` from JavaScript. These represent **hardware storage types**.

### 2. Function Types are Hardware Semantics
```pyrope
comb add(a:u8, b:u8) -> (result:u8) { result = a + b } // Combinational logic
pipe counter() -> (reg count:u8) { count += 1 }        // Pipelined with registers
flow alu(in1, in2) -> (out) { /* explicit timing */ }  // Dataflow with timing
```
**LLM Pitfall**: `comb`/`pipe`/`flow` are NOT just function modifiers - they define **hardware implementation strategy**.

### 3. Bit Selection Syntax
```pyrope
var value = 0b1010_1100
var bits = value#[3..=6]        // Extract bits 3-6 (NOT array indexing)
value#[3] = 0                   // Set bit 3 (NOT array assignment)
```
**LLM Pitfall**: `#[...]` is bit selection, NOT array/hash access. Use `[...]` for array indexing.

### 4. Tuple-Centric Everything
```pyrope
var point = (x=10, y=20)        // Named tuple (like struct)
var array = (1, 2, 3, 4)        // Indexed tuple (like array)
var mixed = (x=1, 2, y=3)       // Mixed named/indexed

// Access patterns
assert point.x == 10            // Named access
assert array[2] == 3            // Array-style access
```
### 5. Ranges with Multiple Operators
```pyrope
var range1 = 1..=5              // Inclusive: 1,2,3,4,5
var range2 = 0..<4              // Exclusive: 0,1,2,3
var range3 = 2..+3              // Size-based: 2,3,4 (3 elements starting at 2)
```
**LLM Pitfall**: Three different range operators with different semantics. `..+` is size-based, not addition.

### 6. Type Annotations and Attributes
```pyrope
var data:u32:[max=1000, min=0] = 0          // Type with constraints
reg counter:[reset_pin=rst] = 0             // Hardware attributes
assert value::[comptime]                    // Attribute checking (double colon!)
```
**LLM Pitfall**: `::` (double colon) for attribute access, single `:` for type annotation.

### 7. Assignment Operators in Hardware Context
```pyrope
reg counter = 0
counter += 1                    // Immediate update
counter::[next] += 1           // Deferred to end of cycle
```
**LLM Pitfall**: Register updates can be immediate or deferred - crucial for hardware timing.

### 8. Memory Declaration Syntax
```pyrope
reg memory:[256]u32 = 0                     // Simple memory
reg dual_port:[1024]u16:[                   // Complex memory with attributes
  rdport=(0,1),
  wrport=(2),
  latency=1
] = 0
```
**LLM Pitfall**: Memory attributes go AFTER the type, using `:[...]` syntax.

## Hardware-Specific Semantics

### Cycle-Based Execution
- `step` advances simulation by one clock cycle
- Register updates happen at cycle boundaries
- Combinational logic (`var`) updates immediately
- Pipeline functions have implicit cycle delays

### No Runtime Loops
```pyrope
// This is COMPILE-TIME elaboration, not runtime loop
for i in 0..=7 {
    memory[i] = init_value
}
```
**LLM Pitfall**: Loops must be compile-time bounded and are unrolled, not runtime constructs.

### Testing and Assertions
```pyrope
assert condition               // Runtime assertion (hardware check)
cassert compile_time_expr      // Compile-time assertion
test "description" {           // Test block with simulation
    step                       // Advance clock cycle
}
```

## Common LLM Mistakes to Avoid

1. **Don't use familiar keywords incorrectly**:
   - `class` doesn't exist - use tuples
   - `function` doesn't exist - use `comb`/`pipe`/`flow`
   - `while`/`for` are compile-time only

2. **Don't assume array-like syntax everywhere**:
   - `arr#[i]` for bit selection
   - `arr[i]` for element access
   - `tuple.field` or `tuple.0` for tuple access

3. **Don't ignore storage classes**:
   - Always use `let`/`var`/`reg` appropriately
   - Understand hardware implications

4. **Don't forget hardware timing**:
   - Use `step` in tests
   - Understand register vs. wire behavior
   - Consider cycle boundaries

5. **Don't use mainstream patterns**:
   - No classes, inheritance, or OOP
   - No runtime dynamic allocation
   - No exception handling

## Quick Reference for Common Patterns

### Variable Declaration
```pyrope
let PI = 3.14                   // Compile-time constant
var temp = calculation()        // Combinational
reg accumulator = 0            // Persistent register
```

### Function Definition
```pyrope
comb pure_function(x:u8) -> (y:u8) { y = x + 1 }
pipe stateful_function() -> (reg counter:u8) { counter += 1 }
```

### Memory Operations
```pyrope
reg ram:[64]u32 = 0
ram[addr] = data               // Write
var read_data = ram[addr]      // Read
```

### Control Flow
```pyrope
if condition { /* ... */ }     // Standard conditional
match value {                  // Pattern matching
  == 0 { /* ... */ }
  else { /* ... */ }
}
```

### Testing
```pyrope
test "my test" {
    var result = my_function(input)
    assert result == expected
    step                       // Advance simulation
}
```

## Key Takeaway for LLMs

Small Pyrope looks like a software language but has **hardware semantics**. Every construct maps to actual hardware - registers, wires, memories, and logic gates. Generate code thinking about **digital circuits**, not software programs.
