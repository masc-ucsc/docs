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
comptime const SIZE = 16    // Compile-time constant
comptime mut counter = 0    // Mutable at compile time (elaboration)
const my_constant = 42      // Immutable after assignment (NOT compile-time)
mut my_wire = 0             // Combinational (no persistence across cycles)
reg my_state = 0            // Register (persistent across cycles)
```
**LLM Pitfall**: `const` means immutable, NOT compile-time. `comptime` is a prefix modifier (not a storage class) that can be applied to `const` or `mut`. `comptime` alone is shorthand for `comptime const`. Don't confuse with `const`/`let`/`var` from JavaScript — these represent **hardware storage types**. Semicolons are optional and behave like a newline.

### 2. Function Types are Hardware Semantics
```pyrope
comb add(a:u8, b:u8) -> (result:u8) { result = a + b } // Combinational logic
pipe[1] counter() -> (reg count:u8) { count += 1 }     // 1-cycle pipeline (count is a state register)
mod alu(in1:u16, in2:u16) -> (out:u32@[4]) { /* explicit timing */ }  // Dataflow / orchestration with timing
```
**LLM Pitfall**: `comb`/`pipe`/`mod` are NOT just function modifiers — they define **hardware implementation strategy**. `mod` is the only kind that can orchestrate pipelined calls (`stage[N]`, `@[N]`). A `comb` can never hold state — registers, `pipe`, or `mod` orchestration require the corresponding kind. The one exception is debug state marked `::[debug]`, which is not allowed to influence non-debug results. Small Pyrope does not support runtime function captures; pass runtime values as arguments. Visible comptime bindings are lexical.

### 3. Bit Selection Syntax
```pyrope
mut value = 0ub1010_1100
mut bits = value#[3..=6]        // Extract bits 3-6 (NOT array indexing)
value#[3] = 0                   // Set bit 3 (NOT array assignment)
```
**LLM Pitfall**: `#[...]` is bit selection, NOT array/hash access. Use `[...]` for array indexing.
**Literal Pitfall**: `_` is only a digit separator in numeric literals (`12_34__ == 1234`). `?` marks don't-care/unknown bits *inside* a binary literal (e.g., `0ub101?`). There is no bare `_` sink and no bare `?` default — use `nil` for unset values and `0sb?` for fully-unknown bits. Reading a `nil` value (in any expression) is a **compile error**; `nil` only documents "no value yet" and must be assigned before any use.

### 4. Tuple-Centric Everything
```pyrope
mut point = (x=10, y=20)        // Named tuple (like struct)
mut array = (1, 2, 3, 4)        // Indexed tuple (like array)
mut mixed = (x=1, 2, y=3)       // Mixed named/indexed

// Access patterns
cassert(point.x == 10)          // Named access
cassert(array[2] == 3)          // Array-style access
```
### 5. Ranges with Multiple Operators
```pyrope
mut range1 = 1..=5              // Inclusive: 1,2,3,4,5
mut range2 = 0..<4              // Exclusive: 0,1,2,3
mut range3 = 2..+3              // Size-based: 2,3,4 (3 elements starting at 2)

cassert(range1 == (1,2,3,4,5))
cassert(range2 == (0,1,2,3))
cassert(range3 == (2,3,4))
```
**LLM Pitfall**: Three different range operators with different semantics. `..+` is size-based, not addition.

### 6. Type Annotations and Attributes
```pyrope
mut data:u32:[max=1000, min=0] = 0          // Type with constraints
reg counter::[reset_pin=ref rst] = 0        // Hardware attributes
cassert(counter.[bits] == 8)                // Read and check attribute
```
Attributes are **set only at declaration** with `::[attr=value]` (or `:Type:[attr=value]`) and are **immutable** afterwards. Use `name.[attr]` to **read** attribute values. Check by comparing: `foo.[attr] == value`. Overflow behavior is **not** an attribute — it is **per-statement**: use the statement-level prefix `wrap result = a + b` or `sat result = x + y`. Every narrowing assignment must annotate locally, or the compiler rejects it.

### 7. Assignment Operators in Hardware Context
```pyrope
reg counter = 0
counter += 1                    // Register update
const peek = counter.[defer]    // Read end-of-cycle value on RHS
```
**LLM Pitfall**: A bare register name reads the current 'q' value. `.[defer]`
is **read-only on the RHS** — it returns the in-cycle accumulating value
(useful inside loops or for end-of-cycle assertions). There is no
`counter.[defer] = ...` LHS form; just write `counter = ...`. Use
`past[n](x)` to read the value `n` cycles ago. To snapshot 'q' before later
in-cycle updates, copy into a local (`const counter_q = counter`).

### 8. Memory Declaration Syntax
```pyrope
reg memory:[256]u32 = 0                     // Simple memory
reg dual_port:[1024]u16:[                   // Complex memory with attributes
  rdport=(0,1),
  wrport=(2),
  latency=1
] = 0

// Port access uses .port[] for clarity
mut out = ram.port[0][addr]::[rdport=0]     // Read port 0
```
**LLM Pitfall**: Memory attributes go AFTER the type, using `:[...]` syntax.

## Hardware-Specific Semantics

### Cycle-Based Execution
- `step` advances simulation by one clock cycle
- Register updates happen at cycle boundaries
- Combinational logic (`mut`) updates immediately
- `pipe` has a fixed latency N: outputs land exactly N cycles after the inputs, never a combinational input-to-output path. A `reg` with feedback is state (no added latency); a feedforward `reg` is an explicit pipeline stage counting toward N
- `mod` has no constraints on register use or output structure, but every output must declare its landing cycle at the interface with `@[N]` (omitting it is a compile error)
- `mod` has two pipeline-timing mechanisms: `stage[N]` (declaration modifier that pipelines the whole RHS over N cycles) and `foo@[N]` (pure timing type check, works on LHS and RHS uses)

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
assert(condition)              // Runtime assertion (hardware check)
cassert(compile_time_expr)     // Compile-time assertion
test "description" {           // Test block with simulation
    step( )// Advance clock cycle
}
```
**LLM Pitfall**: Always write explicit parentheses for calls and verification
conditions. Use `foo(x)`, `foo()`, `assert(expr)`, and `cassert(expr)`.

## Common LLM Mistakes to Avoid

1. **Don't use familiar keywords incorrectly**:
   - `class` doesn't exist - use tuples
   - `function`/`def`/`fn` doesn't exist - use `comb`/`pipe`/`mod`
   - `while`/`for` loop bounds must be `comptime` (unrolled at elaboration)
   - `%` (modulo) is debug-only (too expensive for single-cycle hardware)

2. **Don't assume array-like syntax everywhere**:
   - `arr#[i]` for bit selection
   - `arr[i]` for element access
   - `tuple.field` or `tuple.0` for tuple access

3. **Don't ignore storage classes**:
   - Always use `const`/`mut`/`reg` appropriately
   - `comptime` is a prefix modifier, not a storage class (`comptime mut` is valid)
   - Understand hardware implications

4. **Don't forget hardware timing**:
   - Use `step` in tests
   - Understand register vs. wire behavior

5. **Don't apply software intuitions to `ref`**:
   - In hardware, all signals are wires — there is no copy cost
   - `ref` exists for semantic reasons (allowing mutation), not performance
   - `comb(ref self)` is valid and still purely combinational — `ref` is just an implicit output
   - Consider cycle boundaries

5. **Don't use mainstream patterns**:
   - No classes, inheritance, or OOP
   - No runtime dynamic allocation
   - No exception handling

## Quick Reference for Common Patterns

### Variable Declaration
```pyrope
comptime const PI = 3           // Compile-time constant (no FP, so no 3.14)
mut temp = calculation()        // Combinational
reg accumulator = 0             // Persistent register
```

### Function Definition
```pyrope
comb pure_function(x:u8) -> (y:u8) { y = x + 1 }
pipe[1] stateful_function() -> (reg counter:u8) { counter += 1 }

cassert(pure_function(5) == 6)
```

### Memory Operations
```pyrope
reg ram:[64]u32 = 0
ram[addr] = data               // Write
mut read_data = ram[addr]      // Read
```

### Control Flow
```pyrope
if condition { /* ... */ }     // Standard conditional
match value {                  // Pattern matching — `else` arm is mandatory
  case 0 { /* ... */ }         // `case` is alias for `==`
  == 1 { /* ... */ }           // `==` also works
  else { /* ... */ }           // required terminator
}
```
**LLM Pitfall**: `match` *must* end with `else { ... }`. A `match` without
`else` is a parse error.

`when` / `unless` postfix gates are **compile-time only** — they include
or omit a statement based on `comptime` conditions (think `#if`, not a
runtime mux). For runtime gating, use `if` blocks or a ternary `if`
expression on the RHS.

### Testing
```pyrope
test "my test" {
    mut result = my_function(input)
    assert(result == expected)
    step( )// Advance simulation
}
```

## Key Takeaway for LLMs

Small Pyrope looks like a software language but has **hardware semantics**. Every construct maps to actual hardware - registers, wires, memories, and logic gates. Generate code thinking about **digital circuits**, not software programs.
