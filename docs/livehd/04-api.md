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


- LNAST: Anything that is comptime, or should become comptime after enough inlining
    + for and while loops 
    + type declaration 
    + bundle fields
    + Find the "super set" of IOs (inputs and outputs). Populate the sub_node accordingly.
    + No hierarchy concept. It has a "flatten" and a callee/caller concept.
    + LNAST virtually flattens if for/while/type/bundles can not  be decided locally at LNAST time.
    + Inline small LNASTs (no LG for trivial LNAST unless a "directive" is set)

- LGraph: Hierarchy, bitwidth, attributes, punch
    + Handling attributes
    + Bitwidth
    + cross hierarchy optimization without flattening
    + synthesis
    + Finishes bundles (attributes)

- Both LNAST and LGraph can:
    + Copy/constant optimizations
    + Must understand bundles




