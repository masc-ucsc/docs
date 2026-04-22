
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
| [`top`](#top)                      | [`stmts`](#stmts)                  | [`if`](#if)                        | [`uif`](#uif)                      | [`while`](#while)                  |
| [`func_call`](#func_call)          | [`func_def`](#func_def)            | [`assign`](#assign)                | [`dp_assign`](#dp_assign)          | [`delay_assign`](#delay_assign)    |
| [`break`](#break)                  | [`continue`](#continue)            | [`return`](#return)                | [`bit_and`](#bit_and)              | [`bit_or`](#bit_or)                |
| [`bit_not`](#bit_not)              | [`bit_xor`](#bit_xor)              | [`red_or`](#red_or)                | [`red_and`](#red_and)              | [`red_xor`](#red_xor)              |
| [`popcount`](#popcount)            | [`log_and`](#log_and)              | [`log_or`](#log_or)                | [`log_not`](#log_not)              | [`plus`](#plus)                    |
| [`minus`](#minus)                  | [`mult`](#mult)                    | [`div`](#div)                      | [`mod`](#mod)                      | [`shl`](#shl)                      |
| [`sra`](#sra)                      | [`sext`](#sext)                    | [`set_mask`](#set_mask)            | [`get_mask`](#get_mask)            | [`mask_and`](#mask_and)            |
| [`mask_popcount`](#mask_popcount)  | [`mask_xor`](#mask_xor)            | [`is`](#is)                        | [`has`](#has)                      | [`in`](#in)                        |
| [`does`](#does)                    | [`ne`](#ne)                        | [`eq`](#eq)                        | [`lt`](#lt)                        | [`le`](#le)                        |
| [`gt`](#gt)                        | [`ge`](#ge)                        | [`ref`](#ref)                      | [`const`](#const)                  | [`range`](#range)                  |
| [`tuple_concat`](#tuple_concat)    | [`tuple_add`](#tuple_add)          | [`tuple_get`](#tuple_get)          | [`tuple_set`](#tuple_set)          | [`enum_add`](#enum_add)            |
| [`attr_set`](#attr_set)            | [`attr_get`](#attr_get)            | [`assert`](#assert)                | [`err_flag`](#err_flag)            | [`phi`](#phi)                      |
| [`hot_phi`](#hot_phi)              | [`type_def`](#type_def)            | [`type_spec`](#type_spec)          | [types](#types)                    |                                    |

`for`, `loop`, `match`, `mut`, `cassert` from earlier drafts have been dropped —
see [Pyrope → LNAST Lowerings](#pyrope--lnast-lowerings). `invalid` is no
longer a node; `nil` and `0sb?`-style unknown literals are plain `const`
strings.

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

#### `while`
A `while` node represents a `while`-loop guarded by a boolean condition. The
loop body is exited with `break`; surface constructs `for` and `loop` lower to
`while` (see [Pyrope → LNAST Lowerings](#pyrope--lnast-lowerings)).

```
<while> --| <ref/const> : loop condition
          | <stmts>     : loop body
```

#### `break` / `continue`
Leaf control-flow nodes inside a `while` body. `break` exits the enclosing
loop; `continue` restarts the next iteration. Both have no children.

```
<break>
<continue>
```

#### `return`
Exits the enclosing `func_def`. Optionally carries a single ref naming the
value to return (the producer assigns any expression to a tmp first).

```
<return>                    // bare early exit
<return> --| <ref>          : return value (optional)
```

#### `func_def`
A `func_def` node represents a functional block. In addition to inputs/outputs
and body, it carries a `kind` (one of `"comb"`, `"pipe"`, `"mod"`), an optional
capture list (from the Pyrope `[a, b]` after the name), and an optional
generic / attribute child tuple. Pipeline depth for `pipe[N]` is emitted
separately as `attr_set <func> "pipe_depth" N` at the declaration site.

```
<func_def> --| <const>     : kind ("comb" | "pipe" | "mod")
             | <ref/const> : generics (tuple, 0 children when absent)
             | <ref/const> : captures (tuple, 0 children when absent)
             | <ref/const> : input arguments
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

#### `delay_assign`
Deferred / past-cycle read, and the lowering target for Pyrope's `await[N] dst
= rhs` form. `dst` is always a fresh compiler temporary. `offset` is a
comptime constant integer: positive = future / next-cycle (for a `reg`, D pin;
for a wire, the settled end-of-block value), `0` = the flop `Q` pin (only
valid when `src` is a `reg`), negative = past cycle. `src` names the declared
variable (pre-SSA) or an arbitrary rhs ref when lowering `await[N]`.

```
<delay_assign> --| <ref>       : dst (fresh tmp)
                 | <const/ref> : offset (comptime int)
                 | <ref>       : src (declared variable or rhs)
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
Range. The optional third child is the step (defaults to 1). Pyrope's
`..=`, `..<`, `..+`, and `step` forms all lower to this single node — see
[Ranges](#ranges).

```
<range> --| <ref> or <const> : from-value
          | <ref> or <const> : to-value
          | <ref> or <const> : step (optional, default 1)
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
#### `is`
Nominal type check. True iff R-1 and R-2 share the same `typename`
attribute.
#### `has`
True iff R-1 (a tuple / range / enum) contains the field or label R-2.
#### `in`
True iff R-1 is a member of R-2, where R-2 is a tuple, range, or enum.
Behavior varies by R-2's type: range ⇒ bounds check, tuple ⇒ membership,
enum ⇒ active-variant check.
#### `does`
Structural subtype check. True iff the tuple structure of R-1 is a subset of
R-2 (every field in R-1 exists with the same type in R-2). `a equals b` and
`a case b` are producer-level desugars over `does`.

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

#### `enum_add`
Same shape as `tuple_add`, but the resulting value is an enum bundle (one-hot
encoding for plain enums, tagged for `variant`). The producer emits `enum_add`
for `enum Name = (...)` / `variant Name = (...)` declarations and tags the
result via `attr_set` (`"type" "const"`, `"kind" "enum" | "variant"`).

```
<enum_add> --| <ref> : Lvalue (the enum bundle)
             | <assign> --| <ref>       \ Variant 0
                          | <ref/const> /
             | ...
             | <assign> --| <ref>       \ Variant N
                          | <ref/const> /
```

### Attributes

Attributes are side-table facts attached to a declaration (e.g., bit-width,
direction, storage class, reset pin). They are accessed through the
`attr_set` / `attr_get` node pair. The intermediate children are always
`const` strings naming a field path.

#### `attr_set`
Writes `value` into attribute `root.p1.p2...pN` on the declared variable
referenced by `root`. For example, register declaration is modeled as
`attr_set <ref X> <const "type"> <const "reg">`. The `type` attribute is the
canonical storage-class slot — its values are `"const"`, `"mut"`, `"reg"`, or
`"comptime"`.

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

#### `assert`
Runtime assertion. Its single child is the condition; the assertion fires
(simulation error / hardware cover miss) if the condition evaluates to zero.
Pyrope's `cassert c` is sugar for `assert c::[comptime]` — the condition must
also be comptime-resolvable.

```
<assert> --| <ref/const> : condition
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
| `comp_type_variant`  | Tagged-union / variant type. Parallel to `comp_type_enum`.              |
| `comp_type_timing`   | `@[N]` timing type — used by `cassert x does @[N]` checks.              |
| `prim_type_variadic` | Variadic function argument marker (e.g., `comb f(...args)`).            |
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
A register is declared by a sticky `attr_set <ref X> <const "type"> <const
"reg">` statement. Uses of the register in subsequent code reference the
variable by its `#`-prefixed name (`#reg_foo` below). `const`, `mut`, and
`comptime` declarations emit the same `attr_set ... "type" "const" | "mut" |
"comptime"` pattern.

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
lnast->add_child(attr_set_idx, Lnast_node::create_const("type"));
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

# Pyrope → LNAST Lowerings

The LNAST node set is intentionally small. Many Pyrope surface forms are
expanded by the producer (`inou/prp`) into the primitives defined above.
This section enumerates the canonical lowerings; consumers should never see
the surface forms directly.

Examples in this section use an **S-expression** shorthand for the LNAST
tree: `(op dst child1 child2 ...)`. Multiline forms wrap and indent; every
open paren closes on the same line or on its own matching line. This is a
documentation convenience — LNAST itself is a node tree, not text.

## Control flow

### `match` → chain of `uif`

`match` is syntax sugar; the producer lowers it into a `uif` chain, combining
the subject with each arm's operator to form a boolean condition. When the
source has no `else` arm, the producer synthesises `else { assert false }`.
Init statements (`match mut x = 2; z + x { ... }`) hoist into an outer
`stmts` scope.

```pyrope
// Pyrope
match state {
  == 0 { n = 1 }
  in 4..<6 { n = 2 }
  else { n = 0 }
}
```

```
(eq    ___c0 (ref state) (const 0))
(range ___r  (const 4) (const 4))          ; ..< → (to - 1)
(in    ___c1 (ref state) ___r)
(uif
  ___c0
  (stmts (assign (ref n) (const 1)))
  ___c1
  (stmts (assign (ref n) (const 2)))
  (stmts (assign (ref n) (const 0))))
```

### `loop`, `for`, `for`-comprehension → `while`

`loop { body }` lowers to `while const(true) { body }`. Every `for i in xs
{ body }` (including `(index, key, value)` destructuring, `enumerate(...)`,
`key(...)`, and `ref xs` mutation) is expanded by the producer into an
explicit `while` with a tmp counter, `tuple_get` / `attr_get` for element /
index / key, a `break` on size match, and a `tuple_set` back into the
iterable when `ref` is used. List-comprehensions `[e*2 for e in xs if c]`
desugar to: an empty tmp tuple, the same expanded `while`, a conditional
`tuple_concat` of the body value each iteration, and final `assign` to the
lvalue.

### `if` / `while` / `match` with init-stmts

An init-stmts prefix (`if mut x = 3; x < 3 { ... }`) hoists into an enclosing
`stmts` scope. No new child on the control-flow node.

```
(stmts
  (attr_set (ref x) (const "type") (const "mut"))
  (assign   (ref x) (const 3))
  (lt       ___c (ref x) (const 3))
  (if ___c (stmts ...)))
```

### `when` / `unless` statement gates

`stmt when cond`  →  `(if cond (stmts <stmt>))`
`stmt unless cond` → `(if (log_not t cond) (stmts <stmt>))`

When the gated statement is a declaration, the declaration is hoisted outside
the `if`, initialised to `nil`, and only the assignment goes inside the gate.

### `break` / `continue` / `return`

Emitted as the dedicated leaf / single-child nodes described above. `return
expr` assigns `expr` to a tmp first, then `(return ___t)`.

## Operators

### Compound assignment

`a OP= b` always desugars:

```
(OP ___t (ref a) (ref b))
(assign (ref a) ___t)
```

Covers `+=`, `-=`, `*=`, `/=`, `|=`, `&=`, `^=`, `<<=`, `>>=`, `++=`, `or=`,
`and=`. `++=` uses `tuple_concat` with an additional `assert` over `has` to
guard non-overlap.

### Negated operators

Every negated Pyrope operator is `op + log_not` (or `bit_not` for the `!&`
/ `!^` / `!|` bitwise cousins):

| Surface            | Lowering                                                       |
|--------------------|----------------------------------------------------------------|
| `a !and b`         | `(log_and t a b) (log_not dst t)`                              |
| `a !or b`          | `(log_or  t a b) (log_not dst t)`                              |
| `a !implies b`     | `(log_not t a) (log_or u t b) (log_not dst u)`                 |
| `a !& b`           | `(bit_and t a b) (bit_not dst t)`                              |
| `a !^ b`           | `(bit_xor t a b) (bit_not dst t)`                              |
| `a !\| b`          | `(bit_or  t a b) (bit_not dst t)`                              |
| `a !has b`         | `(has t a b) (log_not dst t)`                                  |
| `a !in b`          | `(in  t a b) (log_not dst t)`                                  |
| `a !is b`          | `(is  t a b) (log_not dst t)`                                  |
| `a !does b`        | `(does t a b) (log_not dst t)`                                 |
| `a !case b`        | `<case-desugar into t>; (log_not dst t)`                       |
| `a !equals b`      | `<equals-desugar into t>; (log_not dst t)`                     |

### Short-circuit boolean

`a and_then b` lowers to `(log_and dst a b)` **unless** `b` contains a
function call, in which case the producer emits the guarded form:

```
(log_and ___a (ref a) (const false))          ; seed with false
(if (ref a)
  (stmts (assign ___a (ref b))))              ; b only evaluated when a is true
(assign (ref dst) ___a)
```

`or_else` mirrors this with `log_or` and an inverted guard.

### `implies`

`a implies b` → `(log_not t a) (log_or dst t b)`.

### `|>` (pipe-concat) — removed

The `|>` operator is slated for removal from the grammar and has no LNAST
lowering.

### `equals`, `case`

Both are producer-level desugars over `does`:

```
; a equals b
(does t1 (ref a) (ref b))
(does t2 (ref b) (ref a))
(log_and dst t1 t2)

; a case b
(does t (ref b) (ref a))
(assert t)
(in dst (ref b) (ref a))
```

## Ranges

```
a..=b   →  (range dst a b)
a..<b   →  (minus ___t b (const 1)) (range dst a ___t)
a..+b   →  (plus  ___t a b) (minus ___t2 ___t (const 1)) (range dst a ___t2)
```

The `step` keyword (`a..<b step c`) populates the optional third child of
`range`.

```
<range> --| <ref/const> : from
          | <ref/const> : to
          | <ref/const> : step (optional, default 1)
```

## Bit selection

All modifier forms lower via `get_mask`:

| Surface           | Lowering                                                   |
|-------------------|------------------------------------------------------------|
| `a#[range]`       | `<build mask>; (get_mask dst a mask)`                      |
| `a#[i,j,k]`       | mask = `(1<<i) \| (1<<j) \| (1<<k)`; `(get_mask dst a mask)` |
| `a#sext[range]`   | `(get_mask t a mask) (sext dst t <high_bit>)`              |
| `a#zext[range]`   | `(get_mask dst a mask)` (no extension node)                |
| `a#\|[range]`     | `(get_mask t a mask) (red_or  dst t)`                      |
| `a#&[range]`      | `(get_mask t a mask) (red_and dst t)`                      |
| `a#^[range]`      | `(get_mask t a mask) (red_xor dst t)`                      |
| `a#+[range]`      | `(get_mask t a mask) (popcount dst t)`                     |

Write form `a#[range] = v`  →  `<build mask>; (set_mask (ref a) (ref a) mask v)`.

`get_mask(x, mask)` both ANDs and shifts the selected bits down to bit 0, so
`get_mask(a, 0xF0) == (a & 0xF0) >> 4`.

## Tuples

### Tuple spread `(...a, ...b)`

Lowers to `tuple_concat` with an added `assert` that the new entries don't
overlap existing fields. Plain `(x, y, z)` tuple literals use `tuple_add`
(no cassert needed). Mixed forms split per element.

### Register / memory access attributes

Declaration attrs (`latency`, `rdport`, `wrport`, `fwd`, ...) are `attr_set`
on the ram variable. Per-access attributes like `ram[addr]:[rdport=0]`
attach to the access tmp:

```
(attr_set  xx (const "rdport") (const 0))
(tuple_get xx (ref ram) (ref addr))
```

## Functions and calls

### `comb` / `pipe[N]` / `mod`

The `func_def` kind child is `"comb"`, `"pipe"`, or `"mod"`. `pipe[N]`
depth is emitted alongside as `(attr_set <func> (const "pipe_depth") (const N))`
at the declaration site (not a func_def child).

### Captures, generics, `requires` / `ensures`, `where`

Captures (`[a, b]`) and generics (`<T>`) become child tuples of `func_def`.
`where cond` on a `func_def` is deprecated and should be removed from the
grammar. `requires` / `ensures` are plain `func_call`s to stdlib builtins
inside the body (see [Built-in Functions](#built-in-functions)).

### `test`, `spawn`, `impl`, `import`

```
; test "name" { body }
(func_def ___f (const "comb") (tuple) (tuple) (tuple) (tuple) (stmts <body>))
(attr_set ___f (const "test") (const true))
(func_call _ ___f (tuple))

; spawn name = { body }
(func_def ___s (const "comb") (tuple) (tuple) (tuple) (tuple) (stmts <body>))
(attr_set ___s (const "spawn") (const true))
(func_call _ ___s (tuple))

; import X as Y
(func_call (ref Y) (const "import") (tuple (const "X")))

; impl Trait for T ( comb m(...) { body } )
(func_def ___tmp (const "comb") ... (stmts <body>))
(does    ___ok ___tmp (ref Trait))
(assert  ___ok)
(tuple_set (ref T) (const "m") ___tmp)
```

### `type Name = T`

`type` statements are aliases: `(tuple_add Name T)` (or `(assign Name T)`
for a scalar binding) followed by `(attr_set Name (const "type") (const true))`
to mark the variable as a type binding.

## Timing

| Surface                 | Lowering                                              |
|-------------------------|-------------------------------------------------------|
| `a@[N]`                 | `(delay_assign tmp (const N) (ref a))`                |
| `a@[-1]`                | `(delay_assign tmp (const -1) (ref a))`               |
| `a@[]`                  | `(delay_assign tmp (const 1) (ref a))`                |
| `a::[defer]`            | `(delay_assign tmp (const 1) (ref a))`                |
| `await[N] dst = rhs`    | `(delay_assign (ref dst) (const N) (ref rhs))`        |
| `x:@[N]`                | `(does t x @[N]) (assert t::[comptime])`              |

`@[N]` is an LNAST timing type (`comp_type_timing`); it is never a flop
insertion request on its own — only `await[N]` and `::[defer]` actually
insert delay.

## Constants and unknown values

`nil` and every `0sb?`-style literal (`0sb?`, `0ub010?11??00`, `0sb1?1`, ...)
are plain `const` nodes carrying the literal text. They are never special
LNAST nodes.

```
(const "nil")
(const "0sb1?1")
```

## Typecasts

`(expr):T:[attrs]` (expression-level typecast) lowers by: producer creates a
tmp, emits `(type_spec tmp <type>)` as a compile-time check, and one
`(attr_set tmp (const "key") (const value))` per attribute.

# Built-in Functions

Pyrope relies on a small stdlib of functions that the producer lowers to
plain `func_call` nodes. Consumers recognise them by name — they are not
LNAST primitives, but every backend should handle them (or skip / strip them
in non-simulation builds).

| Function             | Surface form                      | Purpose                                                                  |
|----------------------|-----------------------------------|--------------------------------------------------------------------------|
| `assert`             | `assert cond`                     | Runtime assertion (LNAST primitive — *not* a `func_call`; see [`assert`](#assert)). |
| `always_assert`      | `always assert cond`              | Runtime assertion checked every cycle, not gated by surrounding control flow. |
| `assume`             | `assume cond`                     | Formal verification axiom — solver treats `cond` as guaranteed true.    |
| `cover`              | `cover cond`                      | Coverage point — tooling records whether `cond` was ever observed true.  |
| `optimize`           | `optimize cond`                   | Optimisation hint — `cond` is guaranteed to hold; synth may exploit it.  |
| `peek`               | `peek(path.to.signal)`            | Probe an internal signal from a test-bench context.                      |
| `poke`               | `poke(path.to.reg, value)`        | Force an internal register/signal from a test-bench context.             |
| `puts`               | `puts arg1, arg2, ...`            | Simulation print with trailing newline. Strings must be comptime.        |
| `print`              | `print arg1, arg2, ...`           | Simulation print without trailing newline.                               |
| `format`             | `format(fmt, args...)`            | Compile-time `fmt::format`-style string formatter. Returns a string.     |
| `import`             | `import X as Y`                   | Module import. `Y` receives the imported module value.                   |
| `requires`           | `requires cond` in `func_def`     | Function precondition. Checked at every call site.                       |
| `ensures`            | `ensures cond` in `func_def`      | Function postcondition. Checked on return.                               |
| `step`               | `step` (inside `test { ... }`)    | Advance simulation by one cycle.                                         |
| `test`               | `test "name" { body }`            | Sugar: `func_def` + `attr_set "test" true` + `func_call` (see [Lowerings](#test-spawn-impl-import)). |
| `spawn`              | `spawn name = { body }`           | Sugar: `func_def` + `attr_set "spawn" true` + `func_call` (see [Lowerings](#test-spawn-impl-import)). |

**String interpolation** (`"value={x}"`) is desugared at the producer into a
`format("value={}", x)` call — a regular `func_call` to `format`.

**Naming convention:** all built-ins emit as `func_call` with a `(ref
<name>)` function reference (e.g., `(ref puts)`). The producer never mangles
these names; consumers can predicate on the exact string to recognise them.
