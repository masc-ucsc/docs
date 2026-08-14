# LGraph

!!! Warning
    LiveHD is beta under active development and we keep improving the
    API. Semantic versioning is a 0.+, significant API changes are expect.



The LGraph is built directly through LNAST to LGraph translations
(`upass/tolg`) or from the Yosys-based Verilog readers. Understanding the
LGraph is needed if you want to build a LiveHD pass.


LGraph is a graph or netlist where each vertex is called a node, and it has a
cell type and a set of input/output pins. Since the HHDS migration, a LGraph
*is* an `hhds::Graph`: LiveHD layers on top of it the cell-type metadata
(`Ntype_op` in `graph/cell.hpp` and `graph/cell.cpp`), the attribute tags
(`graph/attrs.hpp`), and a set of free-function helpers
(`graph/node_util.hpp`, namespace `livehd::graph_util`). A design (one graph
per module) is stored/loaded as an `hhds::GraphLibrary` directory — the `lg:`
kind of the [lhd](02-usage.md) command line.


## API

A single LGraph represents a single netlist module. LGraph is composed of
nodes (`hhds::Node_class`), node pins (`hhds::Pin_class`), edges, cell types,
and attributes. An LGraph node is affiliated with a cell type and each type
defines different amounts of input (sink) and output (driver) pins. Every pin
has a `hhds::Port_id`; sink pins additionally have LiveHD names ("a", "din",
"clock_pin", ...) translated through `Ntype`.

A pair of driver pin and sink pin constitutes an edge. The bitwidth of the
driver pin determines the edge bitwidth.

HHDS reserves three singleton built-in nodes per graph: `INPUT_NODE`,
`OUTPUT_NODE` (the graph I/O, declared through `hhds::GraphIO`), and
`CONST_NODE` (all constants hang off it as pins). Passes that walk-and-delete
must skip them (`graph_util::is_builtin_node`).

### Node, pin, and constant construction

- create a node with a cell type:

```cpp
#include "node_util.hpp"
using namespace livehd::graph_util;

auto node = create_typed_node(g, Ntype_op::Sum);          // type set
auto node = create_typed_node(g, Ntype_op::Sum, bits);    // + port-0 driver bits
auto node = create_node_on(origin_node, Ntype_op::Not);   // same graph as origin
```

- change/read the cell type of a node (the `Ntype_op` encoding bakes the HHDS
  `is_loop_last` low bit, so it round-trips without shifts):

```cpp
set_type_op(node, Ntype_op::And);
Ntype_op op = type_op_of(node);
```

- create a constant. Constants are pins on the `CONST_NODE` singleton; small
  integers in `[-16, 15]` are encoded directly in the port id, larger values
  carry a serialized payload (the value type is `Dlop` from the hlop library —
  unlimited precision):

```cpp
auto cpin  = create_const(g, value);     // create-or-find canonical const pin
Const v    = hydrate_const(cpin);        // decode it back
```

- sink pins are looked up / created by their LiveHD name. For `Sub` nodes the
  name comes from the sub-graph's `GraphIO`; for every other cell type it is
  the `Ntype` convention (see the cell tables below, and
  [cell.cpp](https://github.com/masc-ucsc/livehd/blob/main/graph/cell.cpp)
  for the authoritative list):

```cpp
auto spin = setup_sink_by_name(node, "a");      // create-if-missing
auto spin = find_sink_pin(node, "din");         // invalid pin when not connected
auto dpin = get_driver_of_sink_name(node, "a"); // the (single) driver feeding it
auto dpins = inp_drivers_of(node, "b");         // all drivers (multi-driver sinks)
```

- driver pins are created/fetched by port id. In general nodes have a single
  output (port 0); only `IO`, `Sub`, and `Memory` have multiple driver pins:

```cpp
auto dpin = node.create_driver_pin(0);   // find-or-create
auto dpin = node.get_driver_pin(0);
```

- iterate edges and get node/pin information:

```cpp
for (const auto &e : node.inp_edges()) {
  auto dpin = e.driver;
  auto spin = e.sink;
  auto pid  = spin.get_port_id();
  auto name = debug_name(dpin.get_master_node());
}
for (const auto &e : node.out_edges()) { /* ... */ }
```

- iterate all the nodes of a graph:

```cpp
for (auto node : graph->fast_class()) { ... }   // unordered, fast
```

- graph inputs/outputs are declared through `hhds::GraphIO`:

```cpp
auto gio = graph->get_io();
for (const auto &d : gio->get_input_pin_decls())  { /* d.name, d.bits, d.port_id */ }
for (const auto &d : gio->get_output_pin_decls()) { /* ... */ }
auto ipin = graph->get_input_pin("a");
auto opin = graph->get_output_pin("out");
```

- debug information of a node:

```cpp
debug_name(node);             // "<cell>_<nid>[:name]"
default_instance_name(node);  // user name, or "<cell>_<nid>"
wire_name(pin);               // name cgen would give this driver pin
```

- hierarchy: a `Sub` node instantiates another module graph. Its sink/driver
  pins are resolved by the sub-module's `GraphIO` names
  (`node.get_subnode_io()`).

## Attributes

Design attributes (bitwidth, names, placement, source location, ...) are no
longer dense side tables; each one is an HHDS attribute tag declared in
`graph/attrs.hpp` and accessed uniformly through `node.attr(tag)` /
`pin.attr(tag)` with `set/get/has/del`:

| Tag | On | Meaning |
|-----|----|---------|
| `hhds::attrs::name` | node | user-assigned node name |
| `livehd::attrs::bits` | pin | driver-pin bit width (0/absent = unspecified) |
| `livehd::attrs::pin_name` | pin | user-assigned pin/wire name |
| `livehd::attrs::pin_signed` | pin | presence = signed; absence = unsigned |
| `livehd::attrs::pin_offset` | pin | offset for `Get_mask`/`Set_mask`/`Sext` positional ops |
| `livehd::attrs::pin_delay` | pin | wire delay |
| `livehd::attrs::color` | node | pass diagnostic taint |
| `livehd::attrs::place`, `livehd::attrs::loc`, `livehd::attrs::source` | node | placement / source line / source file |
| `livehd::attrs::const_value`, `livehd::attrs::pin_const_value` | node / pin | serialized constant payload |
| `livehd::attrs::lut` | node | LUT contents |

`graph/node_util.hpp` provides convenience wrappers (`bits_of`, `set_bits`,
`is_unsign`, `set_pin_name`, `node_name_of`, `set_source`, `set_loc1`, ...).

## Cell type

For each LGraph node, there is a specific cell type. This section explains the
operation to perform for each node. It includes a precise way to compute the
maximum and minimum value for the output.


In LGraph, the cell types operate like having unlimited precision with signed
numbers. Most HDL IRs have a type for signed inputs and another for unsigned.
LiveHD handles the superset (sign and unlimited precision) with a single node.
In LGraph, an unsigned value is signed value that is always positive. This
simplifies the mixing and conversions which simplifies the passes. The drawback
is that the export may have to convert back to signed/unsigned for some
languages like Verilog.


Maybe even more important is that most LGraph cell types generate the same
result if the input is sign-extended. This has the advantage of simplifying the
decisions of when to drop bits in a value. It also makes it easier to guarantee
no loss of precision. Any drop of precision requires explicit handling with
operations like and-gate with masks or Shifts.

`Concat` is the one deliberate exception, and the exception is instructive. A
concatenation's result *does* depend on its inputs' sizes — widening a lane
shifts every lane above it — so a cell whose lane widths were read off the
input pins would silently change meaning whenever bitwidth inference narrowed
one of them. LiveHD therefore does not read them off the pins: each lane's
window width is an explicit comptime operand, frozen from the source's
*declared* type when the cell is built and never re-derived. The cell's sinks
are interleaved `(value, width)` pairs, MSB-first, and its result is the
non-negative sum-of-windows value, so it composes with the sign-extension rule
above like every other cell.

The alternative — spelling a concatenation as an `Or` of shifted, masked chunks
or as a chain of `Set_mask` writes — is what LiveHD did before, and it cost
more than it saved: three subsystems each re-derived the lane structure with
their own pattern matcher and their own bailouts, a Set_mask chain smeared
unknowns across the whole plane rather than per lane, and the SMT encoders
turned a native `concat` into dozens of nested store-selects.


The document also explains corner cases in relationship to Verilog and how to
convert to/from Verilog semantics. These are corner cases to deal with sign and
precision. Each HDL may have different semantics, the Verilog is to showcase
the specifics because it is a popular HDL.


All the cell types are in `graph/cell.hpp` and `graph/cell.cpp`. The type
enumerate is called `Ntype_op`. In general the nodes have a single output
(driver port 0) with the exception of complex nodes (`IO`, `Sub`, `Memory`).
Some sink pins accept a single driver, others accept many edges — the
per-cell tables below state it. The historic "to positive" cell
(`Ntype_op::Tposs`) no longer exists; a `Get_mask` with mask `-1` plays that
role (`get_mask(a,-1) == zext(a)`).

The full list of cell types:

| Ntype_op | Sinks | Functionality |
|----------|-------|---------------|
| `Sum` | `a` (added, multi), `b` (subtracted, multi) | `Y = Σa − Σb` |
| `Mult` | `a` (multi) | n-ary product |
| `Div` | `a`, `b` | `Y = a / b` |
| `And`, `Or`, `Xor` | `a` (multi) | n-ary bitwise op |
| `Ror` | `a` (multi) | reduce OR (`Y = (a != 0)`) |
| `Not` | `a` | bitwise not |
| `Get_mask` | `a`, `mask` | extract the bits selected by mask |
| `Set_mask` | `a`, `mask`, `value` | replace the bits selected by mask |
| `Sext` | `a`, `b` | sign-extend from bit position `b` |
| `LT`, `GT`, `EQ` | `a` (multi), `b` (multi; EQ has only `a`) | comparators |
| `SHL` | `a`, `b` (multi) | shift left; multiple amounts OR (one-hot builder) |
| `SRA` | `a`, `b` | arithmetic shift right |
| `LUT` | `p0`...`pN` | look-up table (`livehd::attrs::lut`) |
| `Mux` | `s`, `p1`...`pN` | multiplexer (`s==0 → p1`, `s==1 → p2`, ...) |
| `Hotmux` | `s`, `p1`...`pN` | one-hot select mux |
| `IO` | `p0`...`pN` | graph input or output |
| `Memory` | see below | SRAM-like structures and arrays |
| `Flop` | see below | flop with sync or async reset |
| `Latch` | `din`, `enable`, `posclk` | latch |
| `Fflop` | see below | fluid flop |
| `Sub` | sub-module GraphIO names | sub module instance |
| `Nconst` | — | constant (no sinks) |
| `AttrSet` | `parent`, `value`, `field` | leftover attribute set (cleanup by bitwidth) |

The encoding of `Ntype_op` reserves bit 0 of the underlying value as
`is_loop_last`, matching the bit HHDS reserves on its node type. The
pipeline-breaking cells (`IO`, `Memory`, `Flop`, `Latch`, `Fflop`, `Sub`) are
*loop last* (odd values); `Nconst` and `IO` are *loop first*. Passes use this
to break cyclic traversals at registers/IO without special-casing.

Each cell type can be called directly with Pyrope using a low level RTL syntax
(`__sum`, `__and`, ... matching the lower-case cell names in `cell.cpp`).
This is useful for debugging not for general use as it can result in less
efficient LNAST code.

An example of a multi-driver sink pin is the `Sum` cell which can do
`Y=3+20+a0+a3` with four drivers connected to sink `a`. An example of single
driver sink pins is the `SRA` cell which can do `Y=20>>3` with one driver on
`a` and one on `b`.

The section includes description on how to compute the maximum (`max`) and
minimum (`min`) allowed result range. This is used by the bitwidth inference
pass. To ease the explanation, a `sign` value means that the result may be
negative (`a.sign == a.min<0`). `known` is true if the result sign is known
(`a.known == a.max<0 or a.min>=0`), either positive or negative (`neg ==
a.max<0`). The cells explanation also requires the to compute the bit mask
(`a.mask == (1<<a.bits)-1`).

For any value (`a`), the number of bits required (`bits`) is `a.bits = log2(absmax(a.max,a.min))+1`.

### Sum

Addition and substraction node is a single cell Ntype that performs
2-complement additions and substractions with unlimited precision. Every
driver connected to sink `a` is added; every driver connected to sink `b` is
subtracted.

``` mermaid
graph LR
    cell  --Y--> c(fa:fa-spinner)
    a(fa:fa-spinner) --a--> cell[Sum]:::cell
    b(fa:fa-spinner) --b--> cell
    classDef cell stroke-width:3px
```

If the inputs do not have the same size, they are sign extended to all have the
same length.

**Forward Propagation**

- Value:
```
%Y = a.reduce('+') - b.reduce('+')
```
- Max/min:
```
%max = 0
%min = 0
for x in a {
  %max += x.max
  %min += x.min
}
for x in b {
  %max -= x.min
  %min -= x.max
}
```

**Backward Propagation**

Backward propagation is possible when all the inputs but ONE are known. The
algorithm can check and look for the inputs that have more precision than
needed and reduce the max/min backwards.

For example, if and all the inputs but one in `a` are known (max/min has the
max/min computed for all the inputs but the unknown one)

```
a_{unknown}.max = Y.max - max
a_{unknown}.min = Y.min - min
```

If the unknown is in port `b`:

```
b_{unknown}.max = min - Y.min
b_{unknown}.min = max - Y.max
```

**Verilog Considerations**

In Verilog, the addition is unsigned if any of the inputs is unsigned. If any
input is unsigned. all the inputs will be "unsigned extended" to match the
largest value. This is different from `Sum` semantics were each input is
signed or unsigned extended independent of the other inputs. To match the
semantics, when mixing signed and unsigned, all the potentially negative inputs
must be converted to unsigned with a `Get_mask(x,-1)`.

```verilog
logic signed [3:0] a = -1
logic signed [4:0] c;

assign c = a + 1'b1;
```

The previous Verilog example extends everything to 5 bits (c) UNSIGNED extended
because one of the inputs is unsigned (1b1 is unsigned in verilog, and 2sb1 is
signed +1). LGraph semantics are different, everything is signed.

```verilog
c = 5b01111 + 5b0001 // this is the Verilog semantics by matching size
c == -16 (!!)
```

The Verilog addition/substraction output can have more bits than the inputs.
This is the same as in LGraph `Sum`. Nevertheless, Verilog requires to specify
the bits for all the input/outputs. This means that whenever Verilog drops
precision an AND gate must be added (or a SEXT for signed output). In the
following examples only the 'g' and 'h' variables needed.

```verilog
  wire [7:0] a;
  wire [7:0] b;
  wire [6:0] c;
  wire [8:0] f = a + b; // f = __sum(a,b)  // a same size as b
  wire [8:0] f = a + c; // f = __sum(a,__get_mask(c,-1))
  wire [7:0] g = a + b; // g = __and(__sum(a,b),0x7F)
  wire [6:0] h = a + b; // h = __and(__sum(a,b),0x3F)
```

**Peephole Optimizations**

- `Y = x-0+0+...` becomes `Y = x+...`
- `Y = x-x+...` becomes `Y = ...`
- `Y = x+x+...` becomes `Y = (x<<1)+...`
- `Y = (x<<n)+(y<<m)` where m>n becomes `Y = (x+y<<(m-n)<<n`
- `Y = (~x)+1+...` becomes `Y = ...-x`
- `Y = a + (b<<n)` becomes `Y = {(a>>n)+b, a&n.mask}`
- `Y = a - (b<<n)` becomes `Y = {(a>>n)-b, a&n.mask}`
- If every x,y... lower bit is zero `Y=x+y+...` becomes `Y=((x>>1)+(y>>1)+..)<<1`


### Mult

Multiply operator. All the drivers connect to the single sink `a` (input order
does not matter). There is no cell type that combines multiplication and
division. The reason is that with integers the order of
multiplication/division changes the result even with unlimited precision
integers (`a*(b/c) != (a*b)/c`).

``` mermaid
graph LR
    cell  --Y--> c(fa:fa-spinner)
    a(fa:fa-spinner) --a--> cell[Mult]:::cell
    classDef cell stroke-width:3px
```

**Forward Propagation**

- Value:
```
Y = a.reduce('*')
```
- Max/min:
```
var tmax = 1
var tmin = 1
var sign  = 0
for i in a {
  tmax *= maxabs(i.max, i.min)
  tmin *= minabs(i.max, i.min)
  known = false                when i.min<0 and i.max>0
  sign += 1                    when i.max<0
}
if known { // sign is known
  if sign & 1 { // negative
    %max = -tmin
    %min = -tmax
  }else{
    %max = tmax
    %min = tmin
  }
}else{
  %max =  tmax
  %min = -tmax
}
```


**Backward Propagation**

If only one input is missing, it is possible to infer the max/min from the
output and the other inputs. Like in the `Sum` case, if all the inputs but one
and the output is known, it is possible to backward propagate to further
constraint the unknown input.

```
a_{unknown}.max = Y.max / a.min
a_{unknown}.min = Y.min / a.max
```

**Verilog Considerations**

Unlike the `Sum`, the Verilog 2 LiveHD translation does not need to extend the
inputs to have matching sizes. Multiplying/dividing signed and unsigned numbers
has the same result. The bit representation is the same if the result was
signed or unsigned.

LiveHD mult node result (Y) number of bits can be more efficient than in
Verilog. E.g: if the max value of A0 is 3 (2 bits) and A1 is 5 (3bits). If the
result is unsigned, the maximum result is 15 (4 bits). In Verilog, the result
will always be 5 bits. If the Verilog result was to an unsigned variable.
Either all the inputs were unsigned, or there should pass to an `get_mask` to
force the MSB as positive. This extra bit will be simplified but it will notify
LGraph that the output is to be treated as unsigned.

**Peephole Optimizations**

- `Y = a*1*...` becomes `Y=a*...`
- `Y = a*0*...` becomes `Y=0`
- `Y = power2a*...` becomes `Y=(...)<<log2(power2a)`
- `Y = (power2a+power2b)*...` becomes `tmp=... ; Y = (tmp+tmp<<power2b)<<(power2a-power2b)` when power2a>power2b
- `Y = (power2a-power2b)*...` becomes `tmp=... ; Y = (tmp-tmp<<power2b)<<(power2a-power2b)` when power2a>power2b

### Div

Division operator. The division operation is quite similar to the inverse of
the multiplication, but a key difference is that only one driver is allowed
for each input.

``` mermaid
graph LR
    cell  --Y--> c(fa:fa-spinner)
    a(fa:fa-spinner) --a--> cell[Div]:::cell
    b(fa:fa-spinner) --b--> cell
    classDef cell stroke-width:3px
```

**Forward Propagation**

- Value:
```
Y = a/b
```
- Max/min:
```
%max = a.max/b.min
%min = a.min/b.max

for i in a.max,a.min {
  for j in b.max,b.min {
     next        when j == 0
     tmp = i / j
     %max = tmp   when tmp > max
     %min = tmp   when tmp < min
  }
}
```

**Backward Propagation**

The backward propagation from the division can extracted from the forward
propagation. It is a simpler case of multiplication backward propagation.

**Verilog Considerations**

The same considerations as in the multiplication should be applied.

**Peephole Optimizations**

- `Y = a/1` becomes `Y=a`
- `Y = 0/b` becomes `Y=0`
- `Y = a/power2b` becomes `Y=a>>log2(power2b)` if `Y.known and !Y.neg`
- `Y = a/power2b` becomes `Y=1+~(a>>log2(power2b))` if `Y.known and Y.neg`
- `Y = (x*c)/a` if c.bits>a.bits becomes `Y = x * (c/a)` which should be a smaller division.
- If b is a constant and `Y.known and !Y.neg`. From the hackers delight, we
- know that the division can be changed for a multiplication
- `Y=(a*(((1<<(a.bits+2)))/b+1))>>(a.bits+2)` If a sign is not `known`. Then `Y
- = Y.neg? (~Y_unsigned+1):Y_unsigned`

### Modulo (how to model)

There is no mod cell in LGraph. The reason is that a modulo different from a
power of 2 is very rare in hardware. If the language supports modulo
operations, they must be translated to division/multiplication.

```
y = a mod b
```

It is the same as:

```
y = a-b*(a/b)
```

If b is a power of 2, the division optimization will transform the modulo operation to:

```
y = a - (a>>n)<<n
```

The add optimization should reduce it to:

```
y = a & n.mask
```

### Not

Bitwise Not operator

``` mermaid
graph LR
    cell  --Y--> c(fa:fa-spinner)
    a(fa:fa-spinner) --a--> cell[Not]:::cell
    classDef cell stroke-width:3px
```

**Forward Propagation**

- Value:
```
Y = ~a
```
- Max/min:
```
%max = max(~a.max,~a.min)
%min = min(~a.max,~a.min)
```

**Backward Propagation**

```
a.max = max(~Y.max,~Y.min)
a.min = min(~Y.max,~Y.min)
```

**Verilog Considerations**

Same semantics as verilog

**Peephole Optimizations**

No optimizations by itself, it has a single input. Other operations like `Sum`
can optimize when combined with `Not`.

### And, Or, Xor

`And` is a typical AND gate with multiple inputs. All the inputs connect to
the single sink `a` because input order does not matter. The result is always
a signed number. `Or` and `Xor` follow the same n-ary single-sink structure.

#### Forward Propagation

- $Y = \forall_{i=0}^{\infty} Y \& a_{i}$
- $m = \forall_{i=0}^{\infty} min(m,a_{i}.bits)$
- $Y.max = (1\ll m)-1$
- $Y.min = -Y.max-1$

#### Backward Propagation

The And cell has a significant backpropagation impact. Even if some inputs had
more bits, after the And cell the upper bits are dropped. This allows the back
propagation to indicate that those bits are useless.

- $a.max = Y.max $
- $a.min = -Y.max-1 $

### Ror

Reduce OR: `Y = (a != 0) ? 1 : 0` over all the drivers connected to sink `a`.
This is a bit different from the LNAST `red_or` (LNAST uses masks). There are
no reduce-AND/reduce-XOR cells; they are built from other cells (e.g., reduce
AND is an equality against `-1`, reduce XOR is a XOR chain or popcount
parity).

### Comparators

LT, GT, EQ

There are only 3 comparators. Other typically found like LE, GE, and NE can be
created by simply negating one of the LGraph comparators. `GT = ~LE`, `LT = ~GE`, and `NE = ~EQ`.

`LT`/`GT` allow multiple drivers on both `a` and `b`; the result is the AND of
all the pairwise comparisons. `EQ` has a single multi-driver sink `a` and
checks that all the drivers are equal.

#### Forward Propagation

- `Y = a LT b`

- `Y = a0 LT b and a1 LT b`

- `Y = a0 LT b0 and a1 LT b0 and a0 LT b1 and a1 LT b1`

#### Other Considerations

Verilog treats all the inputs as unsigned if any of them is unsigned. LGraph
treats all the inputs as signed all the time. The unsigned inputs need a
`Get_mask(x,-1)` (to-positive) when translating:

| size | A | B | Operation |
|------|---|---|-----------|
| a==b | S | S | EQ(a,b) |
| a==b | S | U | EQ(a,b) |
| a==b | U | S | EQ(a,b) |
| a==b | U | U | EQ(a,b) |
| a< b | S | S | LT(a,b) |
| a< b | S | U | LT(a,get_mask(b,-1)) |
| a< b | U | S | LT(get_mask(a,-1),b) |
| a< b | U | U | LT(get_mask(a,-1),get_mask(b,-1)) |


### SHL

Shift Left performs the typical shift left when there is a single amount
(`a<<b`). The cell supports multiple drivers on the `b` (amount) sink; in this
case the results are OR-ed together, which is useful to build one hot encoding
masks (`a<<(1,2) == (a<<1)|(a<<2)`).

### SRA

Arithmetic (sign preserving) shift right: `Y = a >>> b`.

#### Verilog Considerations

Verilog has 2 types of shift `>>` and `>>>`. The first is unsigned right shift,
the 2nd is arithmetic right shift. LGraph only has arithmetic right shift. The
verilog translation should make the value unsigned
(`SRA(get_mask(a,-1),b)`) for a Verilog `>>`; for a `>>>` the input maps
directly.

### Mux

Multiplexer. Sink `s` is the selector; sinks `p1`...`pN` are the data inputs:
`s==0` selects `p1`, `s==1` selects `p2`, and so on. With more than two data
inputs the code generation emits a `case` statement over `s`.

### Hotmux

One-hot select multiplexer. Sink `s` is a one-hot encoded selector and
`p1`...`pN` are the data inputs; bit `i` of `s` selects `p(i+1)`. A
non-one-hot selector at runtime is an error. `Hotmux` avoids the
binary-encode/decode pair that a `Mux` would need when the surrounding logic
already produces one-hot signals.

A Pyrope `unique if` (and `match`, which is a unique-if chain by definition)
lowers to one `Hotmux` per merged variable: the selector packs one bit per
arm condition plus a top "none of the conditions" bit for the else /
fall-through slot, so it is one-hot by construction exactly when the
uniqueness assume holds. The code generation emits a `case` over the one-hot
constants (`1`, `2`, `4`, ...) with an `'hx` default modelling the
non-one-hot runtime error. `pass.cprop` folds a constant one-hot selector to
the selected arm (and collapses all-identical arms); `pass.bitwidth` gives
the selector the unsigned N-bit envelope and unions the data arms into the
output like `Mux`.

### LUT

Look-up table cell. The inputs connect to `p0`...`pN` and the table contents
live in the `livehd::attrs::lut` attribute.

### IO

Graph input or output node. Every graph has the `INPUT_NODE` and `OUTPUT_NODE`
singletons; the declared ports (name, bits, port id) live in the graph's
`hhds::GraphIO` tables and are accessed with `graph->get_io()`,
`graph->get_input_pin(name)`, and `graph->get_output_pin(name)`.

### Nconst

Constant node. Most constants are pins on the `CONST_NODE` singleton (small
integers `[-16,15]` are encoded in the port id; bigger values carry a
serialized `Dlop` payload in `livehd::attrs::pin_const_value`). A regular
`Nconst` node with a `livehd::attrs::const_value` attribute is the
node-shaped legacy form; both are valid constant sources.

### Flop

The single flop cell (it replaces the old SFlop/AFlop split — the `async` pin
selects the reset style):

| Sink | Meaning |
|------|---------|
| `async` | async (vs sync) reset select |
| `initial` | reset value |
| `clock_pin` | clock driver |
| `din` | data in (Q is driver pin 0) |
| `enable` | clock enable |
| `negreset` | active-low reset when set |
| `posclk` | posedge clock when set |
| `reset_pin` | reset driver |

The optional pins (`async`, `negreset`, `initial`, `enable`, ...) may simply
not be connected.

### Latch

| Sink | Meaning |
|------|---------|
| `din` | data in |
| `enable` | latch enable |
| `posclk` | polarity |

### Fflop (Fluid flop)

Flop with elastic/fluid handshaking:

| Sink | Meaning |
|------|---------|
| `valid` | valid in |
| `initial` | reset value |
| `clock_pin` | clock driver |
| `din` | data in |
| `stop` | stop (back-pressure) from the next cycle |
| `reset_pin` | reset driver |

### Memory

Memory is the basic block to represent SRAM-like structures and arrays. Any
large storage will benefit from using memory arrays instead of flops, which
are slower to simulate. These memories are highly configurable.

The sink pins (per `graph/cell.cpp`):

| Sink | Kind | Meaning |
|------|------|---------|
| `addr` | runtime, per port | address |
| `bits` | comptime, 1 | bits per entry |
| `clock_pin` | runtime, 1 or per port | clock |
| `din` | runtime, per port | write data |
| `enable` | runtime, per port | read/write enable |
| `fwd` | comptime, 1 | write forwarding (0/1) |
| `posclk` | comptime, 1 | clock polarity |
| `type` | comptime, 1 | 0: async, 1: sync, 2: array |
| `wensize` | comptime, 1 | number of write-enable bits |
| `size` | comptime, 1 | number of entries |
| `rdport` | comptime, per port | 1: read port, 0: write port |
| `init` | comptime, 1 | contents (entry 0 in the low `bits`, row-major); NOT restored by reset |

Multi-ported memories use port-id wrapping: the per-port pins repeat every 12
port ids (`pid % 12` selects the field, `pid / 12` the port). E.g., sink name
`"12addr"` is the `addr` of port 1. If a single driver is connected for a
shared field (like `clock_pin`), the same value is used across all the ports.

The read data for read port N comes out on driver pin `n_wr_ports + N`.

- `fwd` (forwarding) means writes forward their value to same-cycle reads —
  effectively zero cycles read latency when enabled. This is more than just a
  latency setting: with `fwd` enabled the write latency does not matter to
  observe the results, which requires costly forwarding logic.
- `type == 2` (array) generates an unclocked register array with forwarding
  semantics (writes visible to subsequent reads in the same cycle); `type` 0/1
  instantiate the `cgen_memory_*` wrapper modules. `type == 0` (async) reads
  are combinational on the CURRENT address.
- `init` is the per-cycle default for a `type == 2` array (a `mut`/`const`
  array's initializer / a ROM's contents) and the power-on contents otherwise;
  it is never restored by reset. Code generation currently rejects `init` on
  the clocked types 0/1 (no $readmemh-style seam into the wrappers yet).

The memory usually has power of two sizes. If the size is not a power of 2,
the address is rounded up. Writes to the invalid addresses will generated
random memory updates. Reads should read random data.

### Sub

Sub module instance. The sink and driver pins are resolved by name against the
sub-module's `GraphIO` declarations (`node.get_subnode_io()`), not the
`Ntype` tables. The module hierarchy is managed by the graph library
(`hhds::GraphLibrary`, the `lg:` directory of `lhd`).

### AttrSet

High-level attribute-set construct (`parent`, `field`, `value` sinks) kept
only for the bitwidth pass leftover-cleanup; it is dropped at code generation.
The old tuple-related cells (`TupAdd`, `TupGet`) and `AttrGet` no longer
exist — tuples are fully resolved at the LNAST level before reaching LGraph.

## Optimization

Not all the nodes have the same complexity overhead. When performing peephole
optimization is possible to trade one set of nodes for others. In general,
we have this set of overheads:

- 0 overhead: not, get_mask, set_mask, sext, and SHL/SRA with constant shift
  amounts. The rational is that those are just "wiring" cells to connect or
  extract wires across. The NOT gate is not really zero, but it could be easily
  mixed with sorrounding cells.

- 1 overhead: And, Or, Xor, LUT, Mux

- 3 overhead: LT, GT, EQ, Ror

- 4 overhead: Less than 4 bit output Sum, and SHL/SRA with non-compile time
  shift amount. This can be costly an require hardware like barrel shifters.

- 5 overhead: large Sum, SHL/SRA.

- 6 Overhead: Mult/Div

If a overhead level can be elininated having a small number of different cells
with a smaller overhead level,the translation makes sense. Notice the "small
number of cells", after all everything can be translated to nand gates. A 3x
factor is somewhat reasonable. This means that a 5-level overhead is fine to be
replaced for 3 4-level (or 3 3-level) but not for 4 4-level overhead. Zero
overhead cells are not included in the list of cells in the replacement.

This is a heuristic. Once works, it is a nice target to use AI to decide
when/if a transformation is worth.
