
# LNAST


LNAST stands for Language-Neutral Abstract Syntax Tree, which is constituted of
Lnast_nodes and indexed by a tree structure.

LiveHD has two main data structures: LNAST and LGraph. The LNAST is the higher
level representation with a tree structure. The LGraph is the lower level
representation with a graph structure.  Each node in LGraph has a LNAST
equivalent node, but LNAST is more high level and several nodes in LNAST may
not have a one-to-one mapping to LGraph.


Each Lnast_node should has a specific node type and contain the following information from source code tokens

(a) line number
(b) pos_start, pos_end
(c) string_view (optional)

## Function Overloadings of Node Data Construction
Every node construction method has four function overloadings.
For example, to construct a Lnast_node with a type of reference,
we could use one of the following functions:

```cpp
// C++
auto node_ref = Lnast_node::create_ref("foo");
auto node_ref = Lnast_node::create_ref("foo", line_num);
auto node_ref = Lnast_node::create_ref("foo", line_num, pos1, pos2);
auto node_ref = Lnast_node::create_ref(token);
```

In case (1), you only knows the variable name is "foo".
In case (2), you know the variable name and the corresponding line number.
In case (3), you know the variable name, the line number, and the charactrer position.
In case (4), you are building LNAST from your HDL AST and you already have the Token.
The toke should have line number, positions, and string_view information.


## Another Example
If you don't care the string_view to be stored in the lnast node, just leave it empty for set "foo" for it.
This is true for many of the operator node, for example, to build a node with type of assign.

```cpp
// C++
auto node_assign = Lnast_node::create_assign();
auto node_assign = Lnast_node::create_assign(line_num);
auto node_assign = Lnast_node::create_assign(line_num, pos1, pos2);
auto node_assign = Lnast_node::create_assign(token); // The token is not necessary to have a string_view
```

## LNAST Node Types
|                 |                 |                 |                 |                 |
|:---------------:|:---------------:|:---------------:|:---------------:|:---------------:|
| [`top`](#top)                      | [`stmts`](#stmts)                  | [`if`](#if)                        | [`uif`](#uif)                      | [`for`](#for)                      |
| [`while`](#while)                  | [`func_call`](#func_call)          | [`func_def`](#func_def)            | [`assign`](#assign)                | [`dp_assign`](#dp_assign)          |
| [`mut`](#mut)                      | [`delay_assign`](#delay_assign)    | [`bit_and`](#bit_and)              | [`bit_or`](#bit_or)                | [`bit_not`](#bit_not)              |
| [`bit_xor`](#bit_xor)              | [`red_or`](#red_or)                | [`red_and`](#red_and)              | [`red_xor`](#red_xor)              | [`popcount`](#popcount)            |
| [`log_and`](#log_and)              | [`log_or`](#log_or)                | [`log_not`](#log_not)              | [`plus`](#plus)                    | [`minus`](#minus)                  |
| [`mult`](#mult)                    | [`div`](#div)                      | [`mod`](#mod)                      | [`shl`](#shl)                      | [`sra`](#sra)                      |
| [`sext`](#sext)                    | [`set_mask`](#set_mask)            | [`get_mask`](#get_mask)            | [`mask_and`](#mask_and)            | [`mask_popcount`](#mask_popcount)  |
| [`mask_xor`](#mask_xor)            | [`is`](#is)                        | [`ne`](#ne)                        | [`eq`](#eq)                        | [`lt`](#lt)                        |
| [`le`](#le)                        | [`gt`](#gt)                        | [`ge`](#ge)                        | [`ref`](#ref)                      | [`const`](#const)                  |
| [`range`](#range)                  | [`tuple_concat`](#tuple_concat)    | [`tuple_add`](#tuple_add)          | [`tuple_get`](#tuple_get)          | [`tuple_set`](#tuple_set)          |
| [`attr_set`](#attr_set)            | [`attr_get`](#attr_get)            | [`cassert`](#cassert)              | [`err_flag`](#err_flag)            | [`phi`](#phi)                      |
| [`hot_phi`](#hot_phi)              | [`type_def`](#type_def)            | [`type_spec`](#type_spec)          | [types](#types)                    | [`invalid`](#invalid)              |

### Scope
#### `top`
Every LNAST has a `top` node as the root. A `top` node has one or more child
nodes, which can only be `stmts`.

```
<top> --| <stmts>
        | <stmts>
        | <stmts>
        |  ...
```

#### `stmts`
A `stmts` node represents a sequence of statements.

```
<stmts> --| <const>     : scope name
          | <assign>
          | <plus>
          | <func_def>
          | ...
```

### Statements

#### `if`
An `if` node represents a conditional branch, which can be a statement or an
expression.

```
<if> --| <ref/const> : if condition variable
       | <stmts>     : if branch
       | <ref/const> : elif condition variable  \  N times
       | <stmts>     : elif branch              /
       | <stmts>     : else branch
```

#### `uif`
Unique `if`. Similar to `if`, but add additional assertions to check if at most one condition
is true.

```
<uif> --| <ref/const> : if condition variable
        | <stmts>     : if branch
        | <ref/const> : elif condition variable  \  N times
        | <stmts>     : elif branch              /
        | <stmts>     : else branch
```

#### `for`
A `for` node represents a for-loop over a `range` or `tuple`. Note that the loop
must be unrolled during compilation.

```
<for> --| <ref>   : iterator variable
        | <ref>   : iterated variable (tuple or range)
        | <stmts> : for-loop body
```

#### `while`
A `while` node represents a `while`-loop guarded by a boolean condition. Like
`for`, the loop must be resolvable at compile time.

```
<while> --| <ref/const> : loop condition
          | <stmts>     : loop body
```

#### `func_def`
A `func_def` node represents a functional block with input/output arguments.

```
<func_def> --| <ref/const> : input arguments
             | <ref/const> : output arguments
             | <stmts>     : function body
```

#### `func_call`
A `func_call` node represents an instantiation of a functional block.

```
<func_call> --| <ref/const> : Lvalue
              | <ref>       : function reference
              | <ref/const> : input arguments
```

#### `assign`
An `assign` node represents a variable assignment. Note that the Rvalue can only
be a `const` or `ref`.

```
<assign> --| <ref>       : Lvalue
           | <ref/const> : Rvalue
```

#### `dp_assign`
the "lhs := rhs" assignment (dp_assign) is like the "=" assignment but there is no check
for overflow. If the rhs has more bits than the lhs, the upper bits will be
dropped.

```
<dp_assign> --| <ref>       : Lvalue
              | <ref/const> : Rvalue
```

#### `mut`
A `mut` node marks an assignment as a redefinition of a mutable variable
previously declared with an initial value. Shape is identical to `assign`.

```
<mut> --| <ref>       : Lvalue
        | <ref/const> : Rvalue
```

#### `delay_assign`
Deferred / past-cycle read. Models the value of a variable at a cycle other
than "now". `dst` is always a fresh compiler temporary. `src` names the
declared variable (pre-SSA). `offset` is a comptime constant integer: positive
= future / next-cycle (for a `reg`, D pin; for a wire, the settled end-of-
block value), `0` = the flop `Q` pin (only valid when `src` is a `reg`),
negative = past cycle.

```
<delay_assign> --| <ref>       : dst (fresh tmp)
                 | <ref>       : src (declared variable)
                 | <const/ref> : offset (comptime int)
```

### Primitives
#### `const`
Constant value.

```
<const> "0x1234"
```

#### `ref`
Variable.

```
<ref> "variable_name"
```

### `range`
Range.

```
<range> --| <ref> or <const> : from-value
          | <ref> or <const> : to-value
```

### Unary Expressions

```
<op> --| <ref>       : Lvalue
       | <ref/const> : Rvalue
```
#### `bit_not`
Bitwise not. Flip all Rvalue bits.
#### `red_or`
Bitwise reduction OR — true if any bit of Rvalue is set.
#### `red_and`
Bitwise reduction AND — true only if every bit of Rvalue is set.
#### `red_xor`
Bitwise reduction XOR — parity of Rvalue.
#### `popcount`
Count the number of set bits in Rvalue.
#### `log_not`
Logical Not. Flip Rvalue where Rvalue must be a boolean.

### Binary Expressions

```
<op> --| <ref>       : Lvalue
       | <ref/const> : R-1
       | <ref/const> : R-2
```

#### `mod`
Modulo of R-1 over R-2.
#### `shl`
Left-shift R-1 by R-2.
#### `sra`
Right-shift R-1 by R-2.
#### `ne`
Not equal to.
#### `eq`
Equal to.
#### `lt`
Less than.
#### `le`
Less than or equal to.
#### `gt`
Greater than.
#### `ge`
Greater than or equal to.

### N-ary Expressions

```
<op> --| <ref>       : Lvalue
       | <ref/const> : R-1     \
       | <ref/const> : R-2      \
       | <ref/const> : R-3       2 or more values
       | ...                    /
       | <ref/const> : R-N     /
```

#### `bit_and`
Bitwise and.
#### `bit_or`
Bitwise or.
#### `bit_xor`
Bitwise xor.
#### `log_and`
Logical and (boolean arguments).
#### `log_or`
Logical or (boolean arguments).
#### `plus`
Summation of R-1 to R-N.
#### `minus`
R-1 minus summation of R-2 to R-N. A unary `-x` is always lowered to the
canonical 3-child form `<minus> dst 0 x` so every `minus` node walked by a
consumer has the same shape as a binary subtraction.
#### `mult`
Product of R-1 to R-N.
#### `div`
R-1 divided by product of R-2 to R-N

### Bit Manipulation
Same N-ary shape as above. Number of Rvalues is specific to each op.

#### `sext`
Sign-extend R-1 to the bit-width specified by R-2.
#### `set_mask`
Write R-2 into the bits of R-1 selected by the mask R-3 (`set_mask(a, mask, value)`).
#### `get_mask`
Extract the bits of R-1 selected by the mask R-2 (`get_mask(a, mask)`).
#### `mask_and`
Bitwise AND with a constant mask pattern.
#### `mask_popcount`
Count the set bits under a constant mask.
#### `mask_xor`
Bitwise XOR with a constant mask pattern.

### Tuples
#### `tuple_concat`
```
<tuple_concat> --| <ref> : Lvalue
                 | <ref> : R-1 (tuple)
                 | <ref> : R-2 (tuple)
                 | ...
                 | <ref> : R-N (tuple)
```

#### `tuple_add`
```
<tuple_add> --| <ref> : Lvalue
              | <ref/const>
              | <assign> --| <ref>       \ Field 0
                           | <ref/const> /
              | <assign> --| <ref>       \ Field 1
                           | <ref/const> /
              |  ...
              | <assign> --| <ref>       \ Field N
                           | <ref/const> /
```

#### `tuple_set`
```
<tuple_set> --| <ref>        : Lvalue
              | <ref/<const> : 1st-level selection   \
              | ...                                   1..N selections
              | <ref/<const> : Nth-level selection   /
              | <ref/<const> : Rvalue
```

#### `tuple_get`
```
<tuple_get> --| <ref>       : Lvalue
              | <ref>       : Rvalue (selected from this value)
              | <ref/const> : 1st-level selection   \
              | ...                                  1..N selections
              | <ref/const> : Nth-level selection   /
```

### Attributes

Attributes are side-table facts attached to a declaration (e.g., bit-width,
direction, storage class, reset pin). They are accessed through the
`attr_set` / `attr_get` node pair. The intermediate children are always
`const` strings naming a field path.

#### `attr_set`
Writes `value` into attribute `root.p1.p2...pN` on the declared variable
referenced by `root`. For example, register declaration is modeled as
`attr_set <ref X> <const "storage"> <const "reg">`.

```
<attr_set> --| <ref>       : root (declaration being decorated)
             | <const>     : p1     \
             | ...                   0..N path elements (each const)
             | <const>     : pN     /
             | <ref/const> : value
```

#### `attr_get`
Reads the attribute `root.p1.p2...pN` into `dst`.

```
<attr_get> --| <ref>   : dst (fresh tmp)
             | <ref>   : root
             | <const> : p1   \
             | ...             0..N path elements (each const)
             | <const> : pN   /
```

### Checks and Types

#### `cassert`
Compile-time assertion. Its single child is the condition expression that
must evaluate to a non-zero comptime constant.

```
<cassert> --| <ref/const> : condition
```

#### `err_flag`
Internal marker inserted during SSA to sentinel "undefined" in phi tables.
Never emitted by producers directly.

#### `phi`
Internal SSA phi-node.

```
<phi> --| <ref>       : Lvalue
        | <ref/const> : condition
        | <ref>       : true branch dpin
        | <ref>       : false branch dpin
```

#### `hot_phi`
Same shape as `phi`; used for branches marked "likely".

#### `type_def`
Binds a name to a type expression.

```
<type_def> --| <ref>  : type name
             | <type> : type expression
```

#### `type_spec`
Annotates a variable with a type (checked at compile time).

```
<type_spec> --| <ref>  : variable
              | <type> : type expression
```

### Types

Type nodes describe the shape of a value at compile time. They appear as
the child of a `type_def` / `type_spec`, inside `comp_type_*` composite types,
or as a `func_def` signature element.

| Node                 | Meaning                                                                 |
|----------------------|-------------------------------------------------------------------------|
| `none_type`          | No type (void).                                                         |
| `prim_type_uint`     | Unsigned integer. Optional single child sets the bit-width.             |
| `prim_type_sint`     | Signed integer. Optional single child sets the bit-width.               |
| `prim_type_range`    | Integer range.                                                          |
| `prim_type_string`   | String literal type.                                                    |
| `prim_type_boolean`  | Boolean.                                                                |
| `prim_type_type`     | The type of types.                                                      |
| `prim_type_ref`      | Reference type.                                                         |
| `comp_type_tuple`    | Tuple of other types. Children are the component type nodes.            |
| `comp_type_array`    | `array(elem_type, size)`.                                               |
| `comp_type_mixin`    | Mixin / intersection of types.                                          |
| `comp_type_lambda`   | `lambda(arg_type, ret_type)`.                                           |
| `comp_type_enum`     | Enum type.                                                              |
| `expr_type`          | `expr(ref)` — type "same as this value".                                 |
| `unknown_type`       | Type to be inferred.                                                    |

# Module Input, Output, and Register Declaration
In LNAST, all input/output/register are defined in the node type reference
with differenct prefix of string_view, "$" stands for input, "%" stands for
output, and "#" stands for register.
## Input
```coffescript
// Pyrope
foo = $a
```

```verilog
// Verilog
input a;
```

```cpp
// C++
auto node_input = Lnast_node::create_ref("$a", line_num, pos1, pos2);
```


## Output
```coffescript
// Pyrope
%out
```

```verilog
// Verilog
output out;
```

```cpp
// C++
auto node_output = Lnast_node::create_ref("%out", line_num, pos1, pos2);
```

## Register
A register is declared by a sticky `attr_set <ref X> <const "storage"> <const
"reg">` statement. Uses of the register in subsequent code reference the
variable by its `#`-prefixed name (`#reg_foo` below).

```coffescript
// Pyrope
reg reg_foo
#reg_foo = 0
```

```verilog
// Verilog
reg reg_foo;
```

```cpp
// C++ — declaration
auto stmts_idx    = lnast->add_child(top, Lnast_node::create_stmts());
auto attr_set_idx = lnast->add_child(stmts_idx, Lnast_node::create_attr_set());
lnast->add_child(attr_set_idx, Lnast_node::create_ref("#reg_foo", line_num, pos1, pos2));
lnast->add_child(attr_set_idx, Lnast_node::create_const("storage"));
lnast->add_child(attr_set_idx, Lnast_node::create_const("reg"));

// C++ — subsequent reference
auto node_reg = Lnast_node::create_ref("#reg_foo", line_num, pos1, pos2);
```

# Compiler Temporaries and SSA

Compiler-generated temporary variables use the canonical `___<n>` prefix
(three underscores followed by a decimal counter). The `Lnast::is_tmp`
helper is the single predicate for this check. Producers should allocate
tmps via their own counter (e.g., `Lnast_create::create_lnast_tmp`);
don't hand-construct a `___<n>` string at a call site.

```cpp
auto tmp_name = lnast_create_obj.create_lnast_tmp();  // e.g., "___5"
auto tmp_ref  = Lnast_node::create_ref(tmp_name);
```

After SSA, non-tmp refs carry a subscript in the first-class `Lnast_node::subs`
field. `Lnast::get_sname(nid)` renders the SSA name as `name|<subs>` (pipe
separator); `Lnast::dump` uses the same `name|<subs>` form and omits the
subscript entirely when `subs == 0`. Tmp variables are never SSA-renamed
because they are single-assignment by construction.
