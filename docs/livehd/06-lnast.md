
# LNAST


LNAST stands for Language-Neutral Abstract Syntax Tree, which is constituted of
Lnast_nodes and indexed by a tree structure.

LiveHD has two main data structures: LNAST and LGraph. The LNAST is the higher
level representation with a tree structure. The LGraph is the lower level
representation with a graph structure.  Each node in LGraph has a LNAST
equivalent node, but LNAST is more high level and several nodes in LNAST may
not have a one-to-one mapping to LGraph.

Since the HHDS migration, a LNAST rides on `hhds::Tree`: the node type
(`Lnast_ntype`) is stored directly in the tree slot, names and source
locations are per-node attributes, and many LNAST units (one per elaborated
function/module) ride one `hhds::Forest`. The `hhds::Forest::save` directory
is the `ln:` kind of the [lhd](02-usage.md) command line, and
`Lnast::dump`/`Lnast::read` provide a round-trippable text form (the
`lnast-dump:` emit kind).

The authoritative list of node types is
[`lnast/lnast_nodes.def`](https://github.com/masc-ucsc/livehd/blob/main/lnast/lnast_nodes.def)
(an X-macro file included by `lnast/lnast_ntype.hpp`).

## Constructing nodes

Structural nodes are inserted with an explicit type. A detached `Lnast_node`
value is only used for `ref`/`const` leaves that must be carried around before
their insertion point is known:

```cpp
// C++
auto stmts_idx = lnast->add_child(parent_idx, Lnast_ntype::create_stmts());
auto store_idx = lnast->add_child(stmts_idx,  Lnast_ntype::create_store());
lnast->add_child(store_idx, Lnast_node::create_ref("foo"));
lnast->add_child(store_idx, Lnast_node::create_const("0x1234"));
lnast->add_child(store_idx, Lnast_node::create_const(42));      // int64_t overload
```

Source position is a separate per-node payload, set/read independently of the
name/type:

```cpp
lnast->set_loc(nid, Lnast::Loc{pos1, pos2, line, tok});
auto loc = lnast->get_loc(nid);
lnast->set_fname(nid, "foo.prp");
```

Navigation and iteration go through the `Lnast` forwarders
(`get_parent`, `get_first_child`, `children(parent)`,
`depth_preorder(start)`, ...) which operate on `Lnast_nid`
(= `hhds::Tree::Node_class`).

## LNAST Node Types

|                 |                 |                 |                 |                 |
|:---------------:|:---------------:|:---------------:|:---------------:|:---------------:|
| [`top`](#scope)                    | [`stmts`](#scope)                  | [`if`](#if)                        | [`for`](#for)                      | [`while`](#while)                  |
| [`func_call`](#func_call)          | [`func_def`](#func_def)            | [`io`](#func_def)                  | [`func_does`](#pseudo-functions)   | [`func_equals`](#pseudo-functions) |
| [`func_in`](#pseudo-functions)     | [`func_has`](#pseudo-functions)    | [`func_case`](#pseudo-functions)   | [`func_break`](#pseudo-functions)  | [`func_continue`](#pseudo-functions) |
| [`func_return`](#pseudo-functions) | [`declare`](#declare)              | [`store`](#store)                  | [`dp_assign`](#dp_assign)          | [`delay_assign`](#delay_assign)    |
| [`bit_and`](#n-ary-expressions)    | [`bit_or`](#n-ary-expressions)     | [`bit_not`](#unary-expressions)    | [`bit_xor`](#n-ary-expressions)    | [`red_or`](#unary-expressions)     |
| [`red_and`](#unary-expressions)    | [`red_xor`](#unary-expressions)    | [`popcount`](#unary-expressions)   | [`log_and`](#n-ary-expressions)    | [`log_or`](#n-ary-expressions)     |
| [`log_not`](#unary-expressions)    | [`plus`](#n-ary-expressions)       | [`minus`](#n-ary-expressions)      | [`mult`](#n-ary-expressions)       | [`div`](#n-ary-expressions)        |
| [`mod`](#binary-expressions)       | [`shl`](#binary-expressions)       | [`sra`](#binary-expressions)       | [`sext`](#bit-manipulation)        | [`set_mask`](#bit-manipulation)    |
| [`get_mask`](#bit-manipulation)    | [`is`](#binary-expressions)        | [`ne`](#binary-expressions)        | [`eq`](#binary-expressions)        | [`lt`](#binary-expressions)        |
| [`le`](#binary-expressions)        | [`gt`](#binary-expressions)        | [`ge`](#binary-expressions)        | [`ref`](#ref)                      | [`const`](#const)                  |
| [`range`](#range)                  | [`tuple_concat`](#tuple_concat)    | [`tuple_add`](#tuple_add)          | [`tuple_get`](#tuple_get)          | [`attr_set`](#attr_set)            |
| [`attr_get`](#attr_get)            | [`cassert`](#cassert)              | [`type_spec`](#type_spec)          | [types](#types)                    |                                    |

Notable deletions relative to older drafts of this document: `assign` and
`tuple_set` were replaced by the single [`store`](#store) write node;
`type_def` and the `attr_set(type)+type_spec` declaration triple were replaced
by [`declare`](#declare); `uif`, `enum_add`, `err_flag`, `phi`, `hot_phi`, and
the `mask_and`/`mask_popcount`/`mask_xor` ops are gone; `break`, `continue`,
`return`, `has`, `in`, `does`, `case`, and `equals` are now the
[pseudo-function](#pseudo-functions) nodes; `assert` became
[`cassert`](#cassert). `nil` and `0sb?`-style unknown literals are plain
`const` strings.

### Scope

#### `top`
Every LNAST has a `top` node as the root, holding the statement sequences.

#### `stmts`
A `stmts` node represents a sequence of statements.

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

#### `for`
Loop over the elements of an iterable.

#### `while`
A `while` node represents a loop guarded by a boolean condition.

```
<while> --| <ref/const> : loop condition
          | <stmts>     : loop body
```

#### Pseudo-functions

`func_does`, `func_equals`, `func_in`, `func_has`, `func_case`, `func_break`,
`func_continue`, and `func_return` are pseudo-functions emitted by the Pyrope
producer (`inou/prp`) for keywords that share the `func_call` shape but want a
distinct dispatch tag instead of a `const(name)` first child. `has`/`in`/
`does` are folded by the constant-propagation upass; `case`/`break`/
`continue`/`return` are emitted verbatim.

#### `func_def`
A `func_def` node represents a functional block (a Pyrope `comb`/`pipe`/`mod`
lambda). The signature parameters live under an `io` subtree, and each
input/output signature parameter is a [`store`](#store) node. After the SSA
upass runs, the declared I/O is also summarized in the `Lnast::io_meta()`
side-channel (name, bits, sign, `ref` write-back flag), which is what the
`upass/tolg` lowering reads to build the LGraph I/O.

#### `func_call`
A `func_call` node represents an instantiation of a functional block.

```
<func_call> --| <ref/const> : Lvalue
              | <ref>       : function reference
              | <ref/const> : input arguments
```

#### `declare`
The declaration statement node. It replaces the old statement-level
`attr_set(type)` + `attr_set(comptime)` + `type_spec` declaration triple:

```
<declare> --| <ref>       : variable
            | <type-node> : type_decl (prim_type_*/comp_type_*, a ref to a
            |               named type, or prim_type_none when no `:type`)
            | <const>     : qualifier — space-joined tokens, storage first
            |               (e.g. "mut", "const", "mut comptime", "mut wrap")
            | <...>       : optional init value (absent for bare `var x:u8`)
```

A `type Foo = ...` statement is a `declare` with type mode (there is no
separate `type_def` node).

#### `store`
The single write/bind node. Statement scalar writes (the old `assign`),
field-path writes (the old `tuple_set`), tuple-literal field payloads
(`(x=v)`), `func_def`/`io` signature params, and typed binds `name=value:type`
are all `store`, disambiguated by parent context:

```
<store> --| <ref>        : variable
          | <ref/const>  : level-0 selection   \  0..N path levels
          | ...                                /  (0 levels == scalar write)
          | <ref/const>  : value
```

#### `dp_assign`
The "lhs := rhs" assignment is like the `store` assignment but there is no
check for overflow: if the rhs has more bits than the lhs, the upper bits are
dropped.

#### `delay_assign`
Deferred / past-cycle read.

```
<delay_assign> --| <ref>   : dst (fresh tmp)
                 | <ref>   : src (declared variable, pre-SSA name)
                 | <const> : offset (comptime int)
```

`offset` is a comptime constant integer: positive = future / next-cycle (for a
`reg`, the D pin; for a wire, the settled end-of-block value), `0` = the flop
`Q` pin (only valid when `src` is a `reg`), negative = past cycle.

### Primitives
#### `const`
Constant value.

```
<const> "0x1234"
```

`nil` and every `0sb?`-style unknown literal (`0sb?`, `0ub010?11??00`, ...)
are plain `const` nodes carrying the literal text.

#### `ref`
Variable.

```
<ref> "variable_name"
```

#### `range`
Range. The optional third child is the step (defaults to 1).

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
Nominal type check. True iff R-1 and R-2 share the same `typename` attribute.
(The structural checks `has`/`in`/`does`/`equals`/`case` are
[pseudo-functions](#pseudo-functions), not comparison nodes.)

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
R-1 minus summation of R-2 to R-N.
#### `mult`
Product of R-1 to R-N.
#### `div`
R-1 divided by product of R-2 to R-N

### Bit Manipulation
Same shape as above. Number of Rvalues is specific to each op.

#### `sext`
Sign-extend R-1 to the bit-width specified by R-2.
#### `set_mask`
Write the value into the bits of R-1 selected by the mask
(`set_mask(a, mask, value)`).
#### `get_mask`
Extract the bits of R-1 selected by the mask R-2 (`get_mask(a, mask)`).
`get_mask(x, mask)` both ANDs and shifts the selected bits down to bit 0, so
`get_mask(a, 0xF0) == (a & 0xF0) >> 4`.

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
              | <store> --| <ref>       \ Field 0
                          | <ref/const> /
              | ...
              | <store> --| <ref>       \ Field N
                          | <ref/const> /
```

#### `tuple_get`
```
<tuple_get> --| <ref>       : Lvalue
              | <ref>       : Rvalue (selected from this value)
              | <ref/const> : 1st-level selection   \
              | ...                                  1..N selections
              | <ref/const> : Nth-level selection   /
```

Statement-level field *writes* are [`store`](#store) nodes (a `store` with ≥3
children walks the path; with ≤2 it is a scalar write). There is no
`tuple_set` node.

### Attributes

Attributes are side-table facts attached to a declaration (e.g., bit-width,
direction, storage class, reset pin). They are accessed through the
`attr_set` / `attr_get` node pair. The intermediate children are always
`const` strings naming a field path.

#### `attr_set`
Writes `value` into attribute `root.p1.p2...pN` on the declared variable
referenced by `root`.

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
Compiler-internal assertion. Its single condition child must hold; it is used
to materialize checks the producer or the upasses synthesize (e.g., the
non-overlap guard of a tuple concat).

#### `type_spec`
Annotates a variable with a type (checked at compile time).

```
<type_spec> --| <ref>  : variable
              | <type> : type expression
```

### Types

Type nodes describe the shape of a value at compile time. They appear as the
type child of a [`declare`](#declare) / [`type_spec`](#type_spec) or inside
`comp_type_*` composite types. A *named* type in a type position is a plain
`ref` (there is no `expr_type` node).

| Node                 | Meaning                                                                  |
|----------------------|--------------------------------------------------------------------------|
| `prim_type_none`     | The single "no / inferred / unresolved type" sentinel.                   |
| `prim_type_int`      | The canonical integer type — `prim_type_int([max],[min])` with two OPTIONAL const children (absent ⇒ unbounded). Sign and bits are DERIVED from the range, never stored. (The legacy width-based `prim_type_uint`/`prim_type_sint` were deleted; `uN`/`sN` sugar lowers to this.) |
| `prim_type_range`    | Integer range.                                                           |
| `prim_type_string`   | String literal type.                                                     |
| `prim_type_bool`     | Boolean.                                                                 |
| `comp_type_tuple`    | Tuple of other types. Children are the component type nodes.             |
| `comp_type_array`    | `array(elem_type, size)`.                                                |
| `comp_type_lambda`   | `lambda(arg_type, ret_type)`.                                            |

# Module Input, Output, and Register Declaration

In the tree, input/output/register references carry a prefix in the `ref`
name: `$` stands for input, `%` stands for output, and `#` stands for
register.

After the SSA upass runs (`ssa:1`), the declared I/O of each unit is also
available in the `Lnast::io_meta()` side-channel (`Lnast_io_entry`: name
without the prefix, bits, sign, `ref` write-back flag, scalar kind), and the
bitwidth upass fills `Lnast::bw_meta()` with the per-name `[min,max]` ranges.
The `upass/tolg` LNAST→LGraph lowering reads both side-channels rather than
re-walking the tree.

# Compiler Temporaries

Compiler-generated temporary variables use the canonical `___<n>` prefix
(three underscores followed by a counter). `Lnast::is_tmp(name)` is the single
predicate for this check; producers should allocate tmps via their own counter
rather than hand-constructing `___<n>` strings at call sites. Tmp variables
are single-assignment by construction.

# Printing, dumping, and reading

* `lnast->print()` — pretty box-drawing tree for humans (not round-trippable).
* `lnast->dump()` / `Lnast::read()` — structured text that round-trips
  (per-node loc/fname ride along). `lhd --emit-dir lnast-dump:DIR/` writes one
  `<unit>.lnast` per unit in this form.
* `lnast->export_into(forest)` / `Lnast::adopt(forest, name)` — the binary
  `hhds::Forest` interchange used by the `ln:` directories.

# Pyrope → LNAST

The LNAST node set is intentionally small: most Pyrope surface forms
(`match`, `for`-comprehensions, compound assignments, negated operators,
bit-selection sugar, string interpolation, ...) are expanded by the producer
(`inou/prp`, prp2lnast) into the primitives above before any consumer sees
them. The [Pyrope documentation](../pyrope/00-intro.md) describes the surface
language; `inou/prp` is the authoritative reference for the exact lowerings.
