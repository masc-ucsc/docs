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
```ebnf
// Lexical (terminals)
identifier        ::= /[\p{L}_][\p{L}\p{Nd}_$]*/ | "`" <any non-` or escaped> "`"
number            ::= dec_simple | dec_scaled | hex | dec | oct | bin
dec_simple        ::= /0|[1-9][0-9]*/
dec_scaled        ::= /(0|[1-9][0-9]*)[KMGT]/
hex               ::= /0(s|S)?(x|X)[0-9a-fA-F][0-9a-fA-F_]*/
dec               ::= /0(s|S)?(d|D)?[0-9][0-9_]*/
oct               ::= /0(s|S)?(o|O)[0-7][0-7_]*/
bin               ::= /0(s|S)?(b|B)[0-1\?][0-1_\?]*/
bool              ::= "true" | "false"
string            ::= '\'' <no quote or newline>* '\''
                   | '"' (<escape> | <text> | '{' [expression] '}')* '"'

// Helpers
comma_sep         ::= "," { "," }
list<T>           ::= [comma_sep] T { [comma_sep] T } [comma_sep]

// Types
type              ::= primitive_type | array_type | function_type | expression_type
primitive_type    ::= unsized_integer | sized_integer | bounded_integer
                   | range_type | "string" | "boolean" | "type"
unsized_integer   ::= "int" | "integer" | "signed" | "uint" | "unsigned"
sized_integer     ::= /[siu][0-9]+/
bounded_integer   ::= unsized_integer '(' select_options ')'
range_type        ::= "range" '(' select_options ')'

// Type cast and attributes
type_cast         ::= ':' (type [attributes] | attributes)
attributes        ::= '::' ('[' [tuple_list] ']' | '(' [tuple_list] ')')
// NOTE: attributes use '::' to avoid conflict with ':' type casts.

typed_identifier  ::= identifier [type_cast]
```
```pyrope
// Integers (signed/unsigned with bit constraints)
var a:u8 = 100          // 8-bit unsigned
var b:i16 = -50         // 16-bit signed
var c:int = 1000        // Unlimited precision (compile-time only)

// Boolean
var flag:bool = true

// String (basic operations)
var text:string = "hello"
var combined = text ++ " world"  // String concatenation
puts "Debug: value is ", combined   // Print for debugging

// Default initialization
var x = _               // Type default (0 for int, false for bool, "" for string)
var y = 0               // Explicit value

// Verilog compatibility - '?' for unknown bits
var unknown = 0b101?    // Bit 0 is unknown (Verilog 'x')
var partial = 0b??10    // Multiple unknown bits
```

### Variable Storage Classes
```ebnf
storage_class     ::= "let" | "var" | "reg"
declaration_stmt  ::= storage_class (identifier | type_cast | type_specification) ';'
```
```pyrope
let constant = 42       // Compile-time constant (immutable)
var wire = 0            // Combinational (no persistence)
reg state = 0           // Register (persistent across cycles)
```

### Variable Scope (Simplified)
```ebnf
scope_statement   ::= '{' statement* '}'
statement         ::= scope_statement
                   | declaration_statement
                   | assignment_or_declaration_statement
                   | function_call_statement
                   | control_statement
                   | while_statement | for_statement | loop_statement
                   | function_definition_statement
                   | enum_assignment_statement
                   | expression_statement

control_statement ::= "continue" | "break" | "return" [expression_list] ';'
// NOTE: Expressions may appear as statements (with ';'). Some dialects also
//       treat the last expression (without ';') in a block as an implicit return.
```
```pyrope
// Code block scope
var a = 3
{
    assert a == 3       // Visible from outer scope
    var b = 4           // Local to this block
    // let a = 33       // Error: no shadowing allowed
}
// assert b == 4       // Error: 'b' not visible outside block

// Functions have their own scope (no lambda capture in Small Pyrope)
comb example() {
    var local = 5       // Function-local variable
    local + 1
}
```

### Tuples (Core Data Structure)
```ebnf
tuple             ::= '(' [tuple_list] ')'
tuple_sq          ::= '[' [tuple_list] ']'
tuple_list        ::= list<tuple_item>
tuple_item        ::= ref_identifier
                   | expression_with_comprehension
                   | simple_assignment
                   | function_inline scope_statement

ref_identifier    ::= "ref" complex_identifier
function_inline   ::= ("fun"|"comb"|"pipe"|"flow") identifier
                       ['<' typed_identifier_list '>']
                       [arg_list] ["->" arg_list]
```
```pyrope
var point = (x=10, y=20)        // Named tuple
var array = (1, 2, 3, 4)        // Indexed tuple
var mixed = (x=1, 2, y=3)       // Mixed named/indexed

// Access
assert point.x == 10
assert array[2] == 3            // Array-style access

// Concatenation
var combined = point ++ (z=30)  // (x=10, y=20, z=30)
```

### Ranges
```ebnf
select            ::= '[' select_options ']'
select_options    ::= expression_list
                   | '..'                    (* open range *)
                   | expression '..'         (* from expr to open end *)
                   | ('..=' | '..<') expression

range_expr        ::= expression ('..=' | '..<' | '..+') expression
step_expr         ::= range_expr "step" expression

member_selection  ::= restricted_expression member_select
member_select     ::= select+
bit_selection     ::= restricted_expression '#' [bit_select_type] select
bit_select_type   ::= '|' | '&' | '^' | '+' | 'sext' | 'zext'
```
```pyrope
var range1 = 1..=5              // Inclusive range: 1,2,3,4,5
var range2 = 0..<4              // Exclusive range: 0,1,2,3
var range3 = 2..+3              // Size-based range: 2,3,4

// Range operations
assert (1..=3) == (1,2,3)       // Range to tuple conversion
assert int(1..=3) == 0b1110     // Range to one-hot encoding
```

### Arrays and Memories
```ebnf
array_type        ::= tuple_sq [ (primitive_type | array_type | function_type | expression_type) ]
indexing          ::= expression '[' expression_list ']'
(* NOTE: memory_decl is schematic usage; not a distinct grammar rule. *)
```
```pyrope
var buffer:[16]u8 = _           // Array (no persistence)
reg memory:[256]u32 = 0         // Memory (persistent)

memory[addr] = data             // Write
var read_data = memory[addr]    // Read

// Range-based access
var slice = buffer[1..=4]       // Extract elements 1-4

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
var out1 = ram[0][addr3]::[rdport=0]      // Read port 0
var out2 = ram[1][addr4]::[rdport=1]      // Read port 1
```

## Combinational, Pipelines, or Flows

```ebnf
function_type     ::= ("fun"|"comb"|"pipe"|"flow")
                       [ '<' typed_identifier_list '>' ]
                       [arg_list] ["->" arg_list]

function_definition_statement
                   ::= ("fun"|"comb"|"pipe"|"flow") complex_identifier function_definition

function_definition
                   ::= ['[' [capture_list] ']']
                       [ '<' typed_identifier_list '>' ]
                       [arg_list]
                       ["->" (arg_list | type_or_identifier)]
                       ["where" expression_list]
                       { ("requires" | "ensures") expression }
                       scope_statement

arg_list          ::= '(' [arg_item_list] ')'
arg_item_list     ::= list<arg_item>
arg_item          ::= [ ("..." | "ref" | "reg") ] typed_identifier ['=' expression_with_comprehension]
capture_list      ::= typed_identifier ['=' expression_with_comprehension]
                       { ',' typed_identifier ['=' expression_with_comprehension] }
```

### Combinational or Pure Functions (`comb`)

In Pyrope, a combinational or pure function is a stateless function without memory or registers. As such, it can not have side-effects.

```pyrope
comb add(a:u8, b:u8) -> (result:u8) { // fun add works too
    result = a + b
}

// Implicit return
comb add_simple(a:u8, b:u8) {
    a + b                       // Returns single-element tuple
}
```

### Pipeline
```ebnf
assignment_delay  ::= 'delay' '[' expression ']'
                    | '@' '[' expression ']'
                    | '@' constant

assignment_op     ::= '=' | '+=' | '-=' | '*=' | '/=' | '|=' | '&=' | '^=' | '<<=' | '>>=' | '++=' | 'or=' | 'and='

assignment        ::= [storage_class]
                      (identifier | type_cast | type_specification | '(' complex_identifier_list ')')
                      assignment_op [assignment_delay]
                      (expression_with_comprehension | ref_identifier | enum_definition)

simple_assignment ::= [storage_class]
                      (identifier | type_cast | type_specification)
                      assignment_op [assignment_delay] (expression_with_comprehension | ref_identifier)
```

A pipeline is a function where all the outputs are updated with the same time number of cycles with respect to the inputs.


```pyrope
pipe counter(enable:bool) -> (reg count:u8) {
    count += 1 when enable
}

pipe fifo(push:bool, pop:bool, data_in:u18) -> (data_out:u18, full:bool, empty:bool) {
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
```ebnf
timed_identifier     ::= identifier '@' ( constant | '[' expression ']' )
function_call        ::= complex_identifier tuple
simple_function_call ::= complex_identifier expression_list
```

A flow is a function that allows to connect combinational, pipeline, or flow functions but requires explicit time indication for each variable use. Each variable has a `@cycle` to indicate the expected cycle completion with respect to the `flow` inputs. The outputs do not need the explicit time annotation.

```
pipe mul(a, b) -> (c) { c = a * b }
pipe add(a, b) -> (c) { c = a + b }

flow alu(in1, in2) -> (out_pipelined, out_live) {
  let (tmp@[2+1], in2_d@[2+1]) = delay[3] (mul(in1, in2), in2)
  out_pipelined = delay[1] add(tmp@[2+1], in2_d@[2+1])
  out_live      =@[1]      add(tmp@[2+1], in2@0)  // =@[1] is the same as = delay[1]
}

flow accum_alu(in1, in2) -> (out) {
  reg total::[init=0]
  let tmp@[2+1] = delay[3] mul(in1, in2)
  let sum_aligned = add(total@0, tmp@[2+1])  // explicit timing makes alignment clear
  total::[next] =@1 sum_aligned              // =@1 same as =@[1] or =delay[1]
  out = total@0  // current register output
}
```

Inside flow blocks, the variables should have a time delay indication, but as usual they can also have
additional checks like type and attributes, but `comptime` attributes do not really care about the time delay.

```
let (tmp@0:u32, tmp2@[2]:u3:[something], x@0:i3:[comptime]) = some_flow_call(a@0, b@3:u32, c@2::[xxx_should_be_set])
```


## Control Flow
```ebnf
if_expression    ::= ['unique'] 'if' stmt_list scope_statement
                      ('elif' scope_statement)*
                      ['else' scope_statement]

while_statement  ::= 'while' stmt_list scope_statement
for_statement    ::= 'for' ( '(' typed_identifier ((',' typed_identifier)*) ')' | typed_identifier )
                      'in' (ref_identifier | expression_list) scope_statement
loop_statement   ::= 'loop' scope_statement

match_expression ::= 'match' stmt_list '{' [match_list] '}'
match_list       ::= (match_cond scope_statement)+
match_cond       ::= ( [match_operator] expression_list ) | 'else'
match_operator   ::= 'and' | '!and' | 'or' | '!or' | '&' | '^' | '|' | '~&' | '~^' | '~|'
                   | '<' | '<=' | '>' | '>=' | '==' | '!=' | 'has' | '!has' | 'case' | '!case'
                   | 'in' | '!in' | 'equals' | '!equals' | 'does' | '!does' | 'is' | '!is'

test_statement   ::= 'test' expression_list ['where' expression_list] scope_statement
```

### Conditionals
```pyrope
if condition {
    result = a
} else {
    result = b
}
```

Pyrope also has Ruby-like unless at the end of the statement that removes the statement
`unless`/`when` the condition is satisfied.
```
return when    enable
return unless !enable  // Same

assert !enable
```

### Compile-Time Loops
```pyrope
// For loops (must be compile-time bounded)
for i in 0..=7 {
    memory[i] = init_value
}

// Range-based loops
for val in 1..<10 step 2 {  // 1,3,5,7,9
    process(val)
}
```

### Match (Pattern Matching)
```pyrope
match state {
    == 0 { next_state = 1 }
    == 1 { next_state = 2 }
    == 2 { next_state = 0 }
    else { next_state = 0 }
}
```

## Enumerations
```pyrope
enum State = (Idle, Active, Done)       // One-hot encoding: 1, 2, 4
// Simplified subset of full Pyrope enum features

reg current_state:State = State.Idle

match current_state {
    == State.Idle {
        current_state = State.Active when start
    }
    == State.Active {
        current_state = State.Done when complete
    }
    == State.Done {
        current_state = State.Idle
    }
}
```

## Attributes

Attributes provide compile-time metadata and constraints for variables, enabling hardware-specific optimizations and Verilog compatibility.

### Attribute Syntax
```pyrope
// Set attribute
var foo:u32:[comptime=true] = 42    // Set comptime attribute
reg counter:[reset_pin=rst] = 0     // Set reset pin attribute

// Check attribute
assert value::[comptime]            // Check if compile-time constant
cassert z::[bits]<32                // Check bit width constraint

// Read attribute
assert counter::[bits] == 8         // Read number of bits
```

### Common Attributes
```pyrope
// Bitwidth constraints
var data:u32:[max=1000, min=0] = 0
var constrained:[wrap] = 0          // Allow bit overflow wrapping
var limited:[saturate] = 0          // Saturate on overflow

// Compile-time attributes
let SIZE::[comptime] = 16           // Compile-time constant
var array_size = SIZE               // Uses compile-time value

// Hardware attributes
reg state:[reset_pin=my_reset] = 0  // Custom reset signal
reg clocked:[clock_pin=fast_clk] = 0 // Custom clock signal
reg async_reg:[async=true] = 0      // Asynchronous reset
reg pipeline:[retime=true] = 0      // Allow synthesis retiming

// Debug attributes
var debug_val:[debug] = counter     // Debug-only variable
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
var sum = a + b; var diff = a - b; var prod = a * b; var div = a / b  // Basic arithmetic
var left_shift = a << n; var right_shift = a >> n  // Shifts
```

### Bitwise
```pyrope
var and_result = a & b; var or_result = a | b; var xor_result = a ^ b  // AND, OR, XOR
var not_result = ~a             // NOT
```

### Logical
```pyrope
var logical_and = a and b; var logical_or = a or b  // Logical (no short-circuit)
var logical_not = !a            // Logical NOT
```

### Comparison
```pyrope
var equal = a == b; var not_equal = a != b  // Equality
var less = a < b; var less_eq = a <= b; var greater = a > b; var greater_eq = a >= b  // Comparison
```

### Bit Selection and Reduction
```pyrope
var value = 0b1010_1100
var bits = value#[3..=6]        // Extract bits 3-6
value#[3] = 0                   // Set 3rd bit to 0

// Reduction operators
var or_reduce = value#|[..]     // OR-reduce all bits
var and_reduce = value#&[..]    // AND-reduce all bits
var xor_reduce = value#^[..]    // XOR-reduce (parity)
var pop_count = value#+[..]     // Population count

// Sign/zero extension
var extended = value#sext[0..=3] // Sign extend bits 0-3 (3 is sign)
var zero_ext = value#zext[1..=5] // Zero extend bits 1-5 (no sign)

// Non-contiguous bit selection
var sparse = value#[0,3,7]      // Select bits 0, 3, and 7
var rparse = value#[7,3,0]      // Select bits 0, 3, and 7

assert value == 0b1010_1100
assert sparse== 0b1____1__0
assert rparse== 0b011           // reverse of sparse
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
var result = (a * b) + (c & d)   // Clear precedence
// var mixed = a * b + c & d     // Error: use parentheses

// Chained comparisons allowed
assert a <= b <= c               // Same as: a <= b and b <= c
```

## Testing and Verification

### Assertions
```pyrope
assert condition               // Runtime assertion
cassert compile_time_expr      // Compile-time assertion

test "counter test" {
    let cnt = counter(true)
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
var tmp:u8 = counter

counter += 1                    // Immediate update unless next
tmp += 1
assert counter == tmp

counter::[next] += 1           // Defer write to end of cycle
assert counter == tmp
tmp += 1

assert counter != tmp
assert counter::[next] == tmp  // Defer read to end of cycle
```

### Reset Behavior
```pyrope
reg counter:u8 = 100            // Reset value is 100
```

## Module System

### Import (Basic)
```pyrope
// Import functions from other files
let math_ops = import("math/basic")
let result = math_ops.add(a, b)

// Import specific function
let multiply = import("math/basic/multiply")
let product = multiply(x, y)

// Import from local file
let utils = import("utils")
utils.debug_print("Hello")
```

## Complete Example

```pyrope
// Import required modules
let test_utils = import("test/helpers")

// Simple CPU register file
pipe reg_file(
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
    let rf = reg_file(we=true, ra=3, rb=1, wa=1, wd=42)
    assert rf.rd_a == 0
    assert rf.rd_b == 0 // no fwd
    step
    let rf2 = reg_file(we=false, ra=1, rb=0, wa=0, wd=0)
    assert rf2.rd_a == 42
    assert rf2.rd_b == 0
}
```


## TODO: Features to Add After Small Pyrope Implementation

This section has moved. See `new_syntax_doc/01c-small_pyrope_todo.md` for examples of planned features beyond Small Pyrope.
