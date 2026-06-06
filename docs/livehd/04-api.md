# C++ API

LiveHD is built on C++23. LGraph and LNAST are the two key data structures
inside LiveHD to support new hardware design, and both are stored in HHDS
(Hierarchical Hardware Data Structures):
* [LGraph](05-lgraph.md) stands for Live Graph. It is the graph or netlist
  data structure at the core of LiveHD (an `hhds::Graph` per module, plus
  LiveHD cell types and attributes layered on top).
* [LNAST](06-lnast.md) stands for Language Neutral AST. It is an Abstract
  Syntax Tree (an `hhds::Tree` per unit) designed to be simple but to allow
  the translation from multiple languages like Pyrope and SystemVerilog.



While LNAST could be seen as a high level API with control flow information,
LGraph is a lower level graph API where many LNAST high level constructs are
simplified.

There is a division of functionality between LNAST and LGraph. The LNAST-level
passes live in `upass/`, the LGraph-level passes in `pass/`:

- LNAST: Language Neutral AST, the high level tree based representation/API
    + Tuples/bundles:
         - Flatten fields (only flat attributes passed to LGraph)
         - Find IOs (inputs and outputs). Populate the `io_meta()` side-channel accordingly.
         - Detect as array if legal bundle index.
    + SSA construction
    + Constant propagation (comptime decision)
    + Linear time compiler passes (dead code elimination, constant folding) but not complex (GVN, SAT...)
    + Type checking and bitwidth range inference (`bw_meta()`)
    + Unroll `for` and `while` loops
    + LGraph creation (`upass/tolg`)

- LGraph: Live Graph, the low level graph/netlist level based representation/API
    + Attributes
         - Bitwidth
         - Debug flag
    + Complex optimizations
         - cprop (Peephole, constant folding, ...)
         - bitwidth inference
         - synthesis (through Yosys integration)
