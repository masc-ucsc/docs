# C++ API

LiveHD is built on C++17, LGraph and LNAST are the two key data structures
inside LiveHD to support new hardware design.  Besides LNAST and LGraph, there
are other data structures like `mmap_lib::str`.

* [LGraph](05-lgraph.md) stands for Live Graph. It is graph or netlist data
  structure at the core of LiveHD.
* [LNAST](06-lnast.md) stands for Language Neutral AST. It is an Abstract
  Syntax Tree (AST) designed to be simple but to allow the translation from
  multiple languages like CHIRRTL, Verilog, and Pyrope.
* [mmap_lib::str](07-mmapstr.md) to provide persistent strings



While LNAST could be seen as a high level API with control flow information,
LGraph is a lower level graph API where many LNAST high level constructs are
simplified.

There is a division of functionality between LNAST and LGraph:

- LNAST: Language Neutral AST, the high level tree based representation/API
    + Bundles:
         - Flatten fields (only flat attributes passed to LGraph)
         - Find IOs (inputs and outputs). Populate the sub_node accordingly.
         - Detect as array if legal bundle index.
    + Constant propagation (comptime decision)
    + Linear time compiler passes (dead code elimination, constant folding) but not complex (GVN, SAT...)
    + Lgraph creation
         - Inline small LNASTs
         - Partition too large LGraphs
    + Type checking 
    + Unroll `for` and `while` loops 

- LGraph: Live Graph, the low level graph/netlist level based representation/API
    + Attributes
         - Bitwidth
         - Debug flag
    + Complex optimizations
         - cprop (Peephole, constant folding, ...)
         - lecopt, Logic Equivalence based optimizations
         - synthesis

