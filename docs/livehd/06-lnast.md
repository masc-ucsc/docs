
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
| [`func_call`](#func_call)          | [`func_def`](#func_def)            | [`assign`](#assign)                | [`dp_assign`](#dp_assign)          | [`mut`](#mut)                      |
| [`bit_and`](#bit_and)              | [`bit_or`](#bit_or)                | [`bit_not`](#bit_not)              | [`bit_xor`](#bit_xor)              | [`reduce_or`](#reduce_or)          |
| [`logical_and`](#logical_and)      | [`logical_or`](#logical_or)        | [`logical_not`](#logical_not)      | [`plus`](#plus)                    | [`minus`](#minus)                  |
| [`mult`](#mult)                    | [`div`](#div)                      | [`mod`](#mod)                      | [`shl`](#shl)                      | [`sra`](#sra)                      |
| [`sext`](#sext)                    | [`set_mask`](#set_mask)            | [`get_mask`](#get_mask)            | [`mask_and`](#mask_and)            | [`mask_popcount`](#mask_popcount)  |
| [`mask_xor`](#mask_xor)            | [`is`](#is)                        | [`ne`](#ne)                        | [`eq`](#eq)                        | [`lt`](#lt)                        |
| [`le`](#le)                        | [`gt`](#gt)                        | [`ge`](#ge)                        | [`ref`](#ref)                      | [`const`](#const)                  |
| [`range`](#range)                  | [`tuple_concat`](#tuple_concat)    | [`tuple_add`](#tuple_add)          | [`tuple_get`](#tuple_get)          | [`tuple_set`](#tuple_set)          |
| [`attr_set`](#attr_set)            | [`attr_get`](#attr_get)            | [`err_flag`](#err_flag)            | [`phi`](#phi)                      | [`hot_phi`](#hot_phi)              |
| [`invalid`](#invalid)              |||||

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
<stmts> --| <assign>
          | <plus>
          | <func_def>
          | ...
```

### Statements

#### `if`
An `if` node represents a conditional branch, which can be a statement or an
expression.

```
<if> --| <stmts>  : if condition computation
       | <ref>    : if condition variable
       | <stmts>  : if branch

       | <stmts>  : elif condition computation (can be empty stmts)    \
       | <const>  : elif condition variable    (can be constant)        0..N times
       | <stmts>  : elif branch                                        /
       
       | <stmts>  : else branch
```

#### `uif`
Unique `if`. Similar to `if`, but add additional assertions to check if at most one condition
is true.

```
<uif> --| <stmts>  : if condition computation
        | <ref>    : if condition variable
        | <stmts>  : if branch
 
        | <stmts>  : elif condition computation (can be empty stmts)    \
        | <const>  : elif condition variable    (can be constant)        0..N times
        | <stmts>  : elif branch                                        /
        
        | <stmts>  : else branch
```

#### `for`
A `for` node represents a for-loop over a `range` or `tuple`. Note that the loop
must be unrolled during compilation.

```
<for> --| <stmts> : setup code
        | <ref>   : iterator variable
        | <ref>   : iterated variable (tuple or range)
        | <stmts> : for-loop body
```

#### `func_def`
A `func_def` node represents a functional block with input/output arguments.

```
<func_def> --| <stmts>  : setup code  \
             | <ref>    : argument     \
             | <ref>    : argument      Mixing setup codes/arguments
             | <stmts>  : setup code   /
             | <ref>    : argument    /

             | <stmts>  : function body
```

#### `func_call`
A `func_call` node represents an instantiation of a functional block. 

```
<func_call> --| <stmts> : setup code  \
              | <ref>   : argument     \
              | <stmts> : setup code    Mixing setup codes/arguments
              | <ref>   : argument     /
              | <ref>   : argument    /
```

#### `assign`
An `assign` node represents a variable assignment. Note that the Rvalue can only
be a `const` or `ref`.

```
<assign> --| <ref>            : Rvalue
           | <ref> or <const> : Lvalue

           | <ref> or <const> : delay   - optional
```

#### `dp_assign`
the "lhs := rhs" assignment (dp_assign) is like the "=" assignment but there is no check
for overflow. If the rhs has more bits than the lhs, the upper bits will be
dropped.



```
<dp_assign> --| <ref>            : Rvalue
              | <ref> or <const> : Lvalue
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
<op> --| <ref>            : Rvalue
       | <ref> or <const> : Lvalue
```
#### `bit_not`
Bitwise not. Flip all Lvalue bits.
#### `reduce_or`
Or all Lvalue bits.
#### `logical_not`
Logical Not. Flip Lvalue where Lvalue must be a boolean.

### Binary Expressions

```
<op> --| <ref>            : Rvalue
       | <ref> or <const> : L-1
       | <ref> or <const> : L-2
```

#### `mod`
Modulo of L-1 over L-2.
#### `shl`
Left-shift L-1 by L-2.
#### `sra`
Right-shift L-1 by L-2.
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
<op> --| <ref>            : Rvalue
       | <ref> or <const> : L-1     \
       | <ref> or <const> : L-2      \
       | <ref> or <const> : L-3       2 or more values
       | ...                         /
       | <ref> or <const> : L-N     /
```

#### `bit_and`
Bitwise and.
#### `bit_or`
Bitwise or.
#### `bit_xor`
Bitwise xor.
#### `plus`
Summation of L's.
#### `minus`
L-1 minus summation of L-2 to L-N.
#### `mult`
Product of L's.
#### `div`
L-1 divided by product of L-2 to L-N

### Tuples
#### `tuple_concat`
```
<tuple_concat> --| <ref> : Rvalue
                 | <ref> : L-1 (tuple)
                 | <ref> : L-2 (tuple)
```

#### `tuple_add`
```
<tuple_add> --| <ref> : Rvalue
              | <assign> --| <ref>    \ Field 0
                           | <ref>    /
              | <assign> --| <ref>    \ Field 1
                           | <const>  /
              |  ...
              | <assign> --| <ref>    \ Field N
                           | <ref>    /
```

#### `tuple_set`
```
<tuple_set> --| <ref>            : Rvalue
              | <ref> or <const> : 1st-level selection   \
              | ...                                       0..N selections
              | <ref> or <const> : nth-level selection   /
              | <ref> or <const> : Lvalue
```

#### `tuple_get`
```
<tuple_get> --| <ref>            : Lvalue
              | <ref> or <const> : 1st-level selection   \
              | ...                                       0..N selections
              | <ref> or <const> : nth-level selection   /
```

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
```coffescript
// Pyrope
reg_foo
```

```verilog
// Verilog
reg reg_foo;
```

```cpp
// C++
auto node_reg = Lnast_node::create_ref("reg_foo", line_num, pos1, pos2);
```

