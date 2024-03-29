# LGraph 

!!! Warning
    LiveHD is beta under active development and we keep improving the
    API. Semantic versioning is a 0.+, significant API changes are expect.



The LGraph is built directly through LNAST to LGraph translations. The LNAST
builds a gated-SSA which is translated to LGraph. Understanding the LGraph is
needed if you want to build a LiveHD pass.


LGraph is a graph or netlist where each vertex is called a node, and it has a
cell type and a set of input/output pins.


## API

A single LGraph represents a single netlist module. LGraph is composed of
nodes, node pins, edges, cell types, and tables of attributes. An LGraph node
is affiliated with a cell node type and each type defines different amounts of input
and output node pins. For example, a node can have 3 input ports and 2 output
pins. Each of the input/output pins can have many edges to other graph nodes.
Every node pin has an affiliated node pid. In the code, every node_pin has a
`Port_ID`.


A pair of driver pin and sink pin constitutes an edge.  The bitwidth of the
driver pin determines the edge bitwidth.


### Node, Node_pin, and Edge Construction

- create a node without associated type (edges can not be created until a type is associated)

```cpp
new_node = lg->create_node()
//note: type and/or bits still need to be assigned later
```

- create node with node type assigned

```cpp
new_node = lg->create_node(Node_type_Op)
//note: recommended way if you know the target node type
```

- create a constant node

```cpp
new_node = lg->create_node_const(value)
//note: recommended way to create a const node
```

- setup default driver pin for pin_0 of a node

```cpp
driver_pin = new_node.setup_driver_pin();
//note: every cell in LGraph has only one driver pin, pin0

```

- setup default sink pin for pin_0 of a node

```cpp
sink_pin = new_node.setup_sink_pin()
//note: when you know the node type only has one input pin
```

- setup sink pin for pin_x of a node, for more information, please refer to the
  Cell type section. For quick reference of the sink pin names of each cell
  type, please see
  [cell.cpp](https://github.com/masc-ucsc/livehd/blob/master/lgraph/cell.cpp)
```cpp
sink_pin = new_node.setup_sink_pin("some_name")
```

- add an edge between driver_pin and sink_pin

```cpp
driver_pin.connect(sink_pin);
```

- get the driver node of an edge

```cpp
driver_node = edge.driver.get_node()

```

- use node as the index/key for a container

```cpp
absl::flat_hash_map<Node::Compact, int> my_map;
my_map[node1.get_compact()] = 77;
my_map[node2.get_compact()] = 42;
...
```

- use node_pin as the index/key for a container

```cpp
absl::flat_hash_map<Node_pin::Compact, int> my_map;
my_map[node_pin1.get_compact()] = 14;
my_map[node_pin2.get_compact()] = 58;
...
```

- get the node_pin back from a Node_pin::Compact

```cpp
Node_pin dpin(lg, some_dpin.get_compact())
```

- get the node back from a Node::Compact

```cpp
Node node(lg, some_node.get_compact())
```

- create a LGraph input(output) with the name

```cpp
new_node_pin = lg->add_graph_input(std::string_view)
```

- debug information of a node

```cpp
node.debug_name()
```

- debug information of a node_pin

```cpp
node_pin.debug_name()
```

- iterate output edges and get node/pin information from it

```cpp
for (auto &out : node.out_edges()) {
  auto  dpin       = out.driver;
  auto  dpin_pid   = dpin.get_pid();
  auto  dnode_name = dpin.get_node().debug_name();
  auto  snode_name = out.sink.get_node().debug_name();
  auto  spin_pid   = out.sink.get_pid();
  auto  dpin_name  = dpin.has_name() ? dpin.get_name() : "";
  auto  dbits      = dpin.get_bits();

  fmt::print(" {}->{}[label=\"{}b :{} :{} :{}\"];\n"
      , dnode_name, snode_name, dbits, dpin_pid, spin_pid, dpin_name);
}
```

### Non-Hierarchical Traversal Iterators

LGraph allows forward and backward traversals in the nodes (bidirectional
graph). The reason is that some algorithms need a forward and some a backward
traversal, being bidirectional would help. Whenever possible, the fast iterator
should be used.

```cpp
for (const auto &node:lg->fast())     {...} // unordered but very fast traversal

for (const auto &node:lg->forward())  {...} // propagates forward from each input/constant

for (const auto &node:lg->backward()) {...} // propagates backward from each output
```

The LGraph iterator such as `for(auto node: g->forward())` do not visit graph
input and outputs.

```
// simple way using lambda
lg->each_graph_input([&](const Node_pin &pin){

  //your operation with graph_input node_pin;

});
```

### Hierarchical Traversal Iterators

LGraph supports hierarchical traversal. Each sub-module of a hierarchical
design will be transformed into a new LGraph and represented as a sub-graph node
in the parent module. If the hierarchical traversal is used, every time the
iterator encounters a sub-graph node, it will load the sub-graph persistent
tables to the memory and traverse the subgraph recursively, ignoring the
sub-graph input/outputs. This cross-module traversal treats the hierarchical
netlist just like a flattened design. In this way, all integrated third-party
tools could automatically achieve global design optimization or analysis by
leveraging the LGraph hierarchical traversal feature.

```cpp
for (const auto &node:lg->forward(true)) {...}
```

### Edge Iterators

To iterate over the input edges of node, simply call:

```cpp
for (const auto &inp_edge : node.inp_edges()) {...}
```

And for output edges:

```cpp
for (const auto &out_edge : node.out_edges()) {...}
```

## Attribute Design

Design attribute stands for the characteristic given to a LGraph node or node
pin. For instance, the characteristic of a node name and node physical
placement. Despite a single LGraph stands for a particular module, it could be
instantiated multiple times. In this case, same module could have different
attribute at different hierarchy of the netlist. A good design of attribute
structure should be able to represent both non-hierarchical and hierarchical
characteristic.

### Non-Hierarchical Attribute

Non-hierarchical LGraph attributes include pin name, node name and line of
source code. Such properties should be the same across different LGraph
instantia- tions. Two instantiations of the same LGraph module will have the
exact same user-defined node name on every node. For example, instantiations of
a subgraph-2 in both top and subgraph-1 would maintain the same non-hierarchical
attribute table.

```cpp
node.set_name(std::string_view name);
```

### Hierarchical attribute

LGraph also support hierarchical attribute. It is achieved by using a tree data
structure to record the design hierarchy. In LGraph, every graph has a unique
id (lg_id), every instantiation of a graph would form some nodes in the tree and
every tree node is indexed by a unique hierarchical id (hid). We are able to
identify a unique instantiation of a graph and generate its own hierarchical
attribute table. An example of hierarchical attribute is wire-delay.

```cpp
node_pin.set_delay(float delay);
```

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


Maybe even more important is that all the LGraph cell types generate the same
result if the input is sign-extended. This has implications, for example a
typical HDL IR type like "concat" does not exist because the result is
dependent on the inputs size. This has the advantage of simplifying the
decisions of when to drop bits in a value. It also makes it easier to guarantee
no loss of precision. Any drop of precision requires explicit handling with
operations like and-gate with masks or Shifts. 


The document also explains corner cases in relationship to Verilog and how to
convert to/from Verilog semantics. These are corner cases to deal with sign and
precision. Each HDL may have different semantics, the Verilog is to showcase
the specifics because it is a popular HDL.


All the cell types are in `core/cell.hpp` and `core/cell.cpp`. The type
enumerate is called `Ntype`. In general the nodes have a single output with the
exception of complex nodes like subgraphs or memories. The inputs is a string in
lower case or upper case. Upper case ('A') means that many edges (or output
drivers) can connect to the same node input or sink pin, lower case ('a') means
that only a driver can connect to the input or sink pin.


Each cell type can be called directly with Pyrope using a low level RTL syntax.
This is useful for debugging not for general use as it can result in less
efficient LNAST code.

An example of a multi-driver sink pin is the `Sum` cell which can do `Y=3+20+a0+a3`
where `A_{0} = 3`, `A_{1} = 20`, `A_{2} = a0`, and `A_{3} = a3`. Another way to
represent in valid Pyrope RTL syntax is:

```
Y = __sum(A=(3,20,a0,a3))
```

An example if single driver sink pin is the `SRA` cell which can do `Y=20>>3`.
It is lower case because only one driver pin can connect to 'a' and 'b'. Another way
to represent a valid Pyrope RTL syntax is:

```
Y = __sra(a=20,b=3)
```

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
2-complement additions and substractions with unlimited precision.

``` mermaid
graph LR
    cell  --Y--> c(fa:fa-spinner)
    a(fa:fa-spinner) --A--> cell[Sum]:::cell
    b(fa:fa-spinner) --B--> cell
    classDef cell stroke-width:3px
```

If the inputs do not have the same size, they are sign extended to all have the
same length.

**Forward Propagation**

- Value:
```
%Y = A.reduce('+') - B.reduce('+')
```
- Max/min:
```
%max = 0
%min = 0
for a in A {
  %max += A.max
  %min += A.min
}
for b in B {
  %max -= b.min
  %min -= b.max
}
```

**Backward Propagation**

Backward propagation is possible when all the inputs but ONE are known. The
algorithm can check and look for the inputs that have more precision than
needed and reduce the max/min backwards.

For example, if and all the inputs but one A are known (max/min has the max/min
computed for all the inputs but the unknown one)

```
A_{unknown}.max = Y.max - max 
A_{unknown}.min = Y.min - min 
```

If the unknow is in port `B`:

```
B_{unknown}.max = min - T.min
B_{unknown}.min = max - Y.max
```

**Verilog Considerations**

In Verilog, the addition is unsigned if any of the inputs is unsigned. If any
input is unsigned. all the inputs will be "unsigned extended" to match the
largest value. This is different from Sum_Op semantics were each input is
signed or unsigned extended independent of the other inputs. To match the
semantics, when mixing signed and unsigned, all the potentially negative inputs
must be converted to unsign with the Ntype_op::Tposs.

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

Multiply operator. There is no cell type that combines multiplication and
division because unlike in `Sum`. The reason is that with integers the order of multiplication/division changes
the result even with unlimited precision integers (`a*(b/c) != (a*b)/c`).

``` mermaid
graph LR
    cell  --Y--> c(fa:fa-spinner)
    a(fa:fa-spinner) --A--> cell[Mult]:::cell
    classDef cell stroke-width:3px
```

**Forward Propagation**

- Value:
```
Y = A.reduce('*')
```
- Max/min:
```
var tmax = 1
vat tmin = 1
var sign  = 0
for i in A {
  tmax *= maxabs(A.max, A.min)
  tmin *= minabs(A.max, A.min)
  known = false                when min<0 and max>0
  sign += 1                    when max<0
}
if know { // sign is know
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
output and the other inputs. Like in the `sum` case, if all the inputs but one
and the output is known, it is possible to backward propagate to further
constraint the unknown input.

```
A_{unknown}.max = Y.max / A.min
A_{unknown}.min = Y.min / A.max
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
the multiplication, but a key difference is that only one driver is allowed for
each input ('a' vs 'A').

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

There is no mod cell (Ntype_op::Mod) in LGraph. The reason is that a modulo
different from a power of 2 is very rare in hardware. If the language supports
modulo operations, they must be translated to division/multiplication.

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
    a(fa:fa-spinner) --a--> cell[Div]:::cell
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

*Verilog Considerations**

Same semantics as verilog

**Peephole Optimizations**

No optimizations by itself, it has a single input. Other operations like Sum_Op can optimize when combined with Not_Op.

### And

`And` is a typical AND gate with multiple inputs. All the inputs connect to pin
'A' because input order does not matter. The result is always a signed number.

```{.graph .center caption="Ntype_op::And LGraph Node."}
digraph And {
    rankdir=LR;
    size="1,0.5"

    node [shape = circle]; And;
    node [shape = point ]; q0
    node [shape = point ]; q

    q0 -> And [ label ="A" ];
    And  -> q [ label = "Y" ];
}
```

#### Forward Propagation

- $Y = \forall_{i=0}^{\infty} Y \& A_{i}$
- $m = \forall_{i=0}^{\infty} min(m,A_{i}.bits)$
- $Y.max = (1\ll m)-1$
- $Y.min = -Y.max-1$

#### Backward Propagation

The And cell has a significant backpropagation impact. Even if some inputs had
more bits, after the And cell the upper bits are dropped. This allows the back
propagation to indicate that those bits are useless.

- $a.max = Y.max $
- $a.min = -Y.max-1 $

#### Other Considerations

#### Peephole Optimizations


### Comparators

LT, GT, EQ

There are only 3 comparators. Other typically found like LE, GE, and NE can be
created by simply negating one of the LGraph comparators. `GT = ~LE`, `LT = ~GE`, and `NE = ~EQ`.

#### Forward Propagation

- `Y = A LT B`

- `Y = A0 LT B and A1 LT B`

- `Y = A0 LT B0 and A1 LT B0 and A0 LT B1 and A1 LT B1`

#### Backward Propagation

#### Peephole Optimizations

#### Other Considerations

Verilog treats all the inputs as unsigned if any of them is unsigned. LGraph treats all the inputs as signed all the time.

| size | A | B | Operation |
|------|---|---|-----------|
| a==b | S | S | EQ(a,b) |
| a==b | S | U | EQ(a,b) |
| a==b | U | S | EQ(a,b) |
| a==b | U | U | EQ(a,b) |
| a< b | S | S | LT(a,b) |
| a< b | S | U | LT(a,Tposs(b)) |
| a< b | U | S | LT(Tposs(a),b) |
| a< b | U | U | LT(Tposs(a),Tposs(b)) |


### SHL_op

Shift Left performs the typical shift left when there is a single amount
(`a<<amt`). The allow supports multiple left shift amounts. In this case the
shift left is used to build one hot encoding mask. (`1<<(1,2) == (1<<1)|(1<<2)`)

The result for when there are not amounts (`a<<()`) is `-1`. Notice that this
is not ZERO but -1. The -1 means that all the bits are set. The reason is that
when there are no offsets in the onehot encoding, the default functionality is
to select all the bit masks, and hence -1.

### SRA_op

Logical or sign extension shift right.

#### Verilog Considerations

Verilog has 2 types of shift `>>` and `>>>`. The first is unsigned right shift,
the 2nd is arithmetic right shift. LGraph only has arithmetic right shift
(ShiftRigt_op). The verilog translation should make the value unsigned
(`ShiftRigt(Join(0,a),b)`) before calling the shift operation. Conversely, for
a `>>>` if the input is Verilog unsigned (`ShiftRigt(a,b)`)

### Mux_op

#### Forward Propagation

- $Y = P_{(1+P_{0}}$
- $Y.max = (1\ll m)-1$
- $Y.max = \forall_{i=0}^{\infty} P_{i}.max$
- $Y.max = \forall_{i=0}^{\infty} P_{i}.min$

#### Backward Propagation

#### Peephole Optimizations

#### Other Considerations

### LUT_op

### And_op

reduce AND `a =u= -1` // unsigned equal

### Or_op

reduce OR `a != 0`

### Xor_op

reduce xor is a chain of XORs.

### Const_op

### SFlop_op

### AFlop_op

### FFlop_op

### Latch_op

### Get_mask_op

Inputs - a, mask
Get_mask (a, mask)
Functionality - Output contains only those bits a[i], for which mask[i] = 1, other bits a[i] for which mask[i] = 0, are dropped.
a & mask are interpreted as signed numbers and sign extended to the size of the other, if required.
eg - Get_mask (0sb11000011, 0sb10101010) = 0sb1001 
     Get_mask (0sb11110000, 0sb00001111) = 0sb0000
     Get_mask (0sb0011, 0sb10) = 0sb001
     Get_mask (0sb10, 0sb1010) = 0sb11

### Set_mask_op

Inputs - a, value, mask
Set_mask(a, mask, value)
Functionality - Replaces all bits a[i] for which mask[i] = 1, with value[i] 
Retains all bits a[i] for which mask[i] = 0.
// Check - if a, value are signed, actually none of them should be extended and their signs should not matter, but a might need to retain it's sign
eg - Set_mask (0b101 01 010, 0sb000 11 000, 0b001 10 011) = 0sb 101 10 010

### Sext_op  (Sign extend)

Inputs - a, b
Sext (a, b)
Selects only bits a[b:0] dropping all remaining MSBs.
The selected a[b:0] is interpretded as a signed value, a's sign does not matter,b conyains the MSB index and hence is always unsigned/ positive
eg Sext (0b10101010, 4) = 0sb01010 = 0xA = +10
Sext (0b10101010, 5) = 0sb101010 = 0x2A = -22



### Memory_op

Memory is the basic block to represent SRAM-like structures. Any large storage will benefit from using memory arrays instead of flops, which are slower to simulate. These memories are highly configurable.

```{.graph .center caption="Memory LGraph Node."}
digraph Memory {
    rankdir=LR;
    size="2,1"

    node [shape = circle]; Memory;
    node [shape = point ]; q0
    node [shape = point ]; q1
    node [shape = point ]; q2
    node [shape = point ]; q3
    node [shape = point ]; q4
    node [shape = point ]; q5
    node [shape = point ]; q6
    node [shape = point ]; q7
    node [shape = point ]; q8
    node [shape = point ]; q9
    node [shape = point ]; q10
    node [shape = point ]; q

    q0 -> Memory [ label ="a (addr)" ];
    q1 -> Memory [ label ="b (bits)" ];
    q2 -> Memory [ label ="c (clock)" ];
    q3 -> Memory [ label ="d (data in)" ];
    q4 -> Memory [ label ="e (enable)" ];
    q5 -> Memory [ label ="f (fwd)" ];
    q6 -> Memory [ label ="l (latency)" ];
    q7 -> Memory [ label ="m (wmask)" ];
    q8 -> Memory [ label ="p (posedge)" ];
    q9 -> Memory [ label ="s (size)" ];
    q10 -> Memory [ label ="w (wmode)" ];
    Memory  -> q [ label ="Q (data out)" ];
}
```

- `s` (`size`) is for the array size in number of entries
- `b` (`bits`) is the number of bits per entry
- `f` (`fwd`) points to a 0/1 constant driver pin to indicate if writes forward value (`0b0` for write-only ports). Effectively, it means zero cycles read latency when enabled. `fwd` is more than just setting `latency=0`. Even with latency zero, the write delay affects until the result is visible. With `fwd` enabled, the write latency does not matter to observe the results. This requires a costly forwarding logic.
- `c`,`d`,`e`,`q`... are the memory configuration, data, address ports

Ports (`a`,`c`...`p`,`w`) are arrays/vectors to support multiported memories. If a single instance
exists in a port, the same is used across all the ports. E.g: if clock (`c`) is populated:

```
mem1.c = clk1 // clk for all the memory ports

mem2.c[0] = clk1 // clock for memory port 0
mem2.c[1] = clk2 // clock for memory port 1
mem2.c[2] = clk2 // clock for memory port 2
```

Each memory port (rd, wr, or rd/wr) has the following ports:

- `a` (`addr`) points to the driver pin for the address. The address bits should match the array size (`ceil(log2(s))`)
- `c` (`clock`) points to the clock driver pin
- `d` (`data_in`) points to the write data driver pin (read result is in `q` port).
- `e` (`enable`) points to the driver pin for read/write enable.
- `l` (`latency`) points to an integer constant driver pin (2 bits always). For writes `latency from 1 to 3`, for reads `latency from 0 to 3`
- `w` (`wmask`) Points to the write mask (1 == write, 0==no write). The mask bust be a big as the number of bits per entry (`b`). The `wmask` pin can be disconnected which means no write mask (a write will write all the bits).
- `p` (`posedge`) points to a 1/0 constant driver pin
- `m` (`mode`) points to the driver pin or switching between read (0) and write mode (1) (single bit)
- `Q` (`data_out`) is a driver pin with the data read from the memory

All the entries but the `wmask` must be populated. If the `wmask` is not set, a
full write size is expected. Read-only ports do not have `data` and `wmask`
fields if the write use the low ports (0,1...). By placing the read-only ports
to the high numbers, we can avoid populating the wmask (`m`) and data out (`q`)
ports. If the read ports use low port numbers those fields must be populated to
allow the correct matching between write port (`a[n]`) and write result
(`q[n]`).

All the ports must be populated with the correct size. This is important
because some modules access the field by bit position.
If it is not used, it will point to a zero constant with the correct number of bits.
The exception to this is `wmask` which, if `b` indicates 8 bits per entry,
will be equivalent to `0xFF`. Setting wmask to `0b1` will mean a 1 bit zero,
and the memory will be incorrectly operated.

The memory usually has power of two sizes. If the size is not a power of 2, the
address is rounded up. Writes to the invalid addresses will generated random
memory updates. Reads should read random data.

#### Forward Propagation

#### Backward Propagation

#### Other Considerations

#### Peephole Optimizations

### SubGraph_op

And_Op: bitwise AND with 2 outputs single bit reduction (RED) or bitwise
Y = VAL&..&VAL ; RED= &Y

#### Forward Propagation

- $Y = \left\{\begin{matrix} VAL>>OFF & SZ==0 \\ (VAL>>OFF) \& (1<<SZ)-1) & otherwise \end{matrix}\right.$
- $Y.max = \left\{\begin{matrix} VAL.max>>OFF & SZ==0 \\ (VAL.max>>OFF) \& (1<<SZ)-1) & otherwise \end{matrix}\right.$
- $Y.min = 0$
- $Y.sign = 0$

#### Backward Propagation

The sign can not be backward propagated because Pick_Op removes the sign no matter the input sign.


#### To be continued ...

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
