# C++ API

LiveHD uses C++23 and two complementary intermediate representations, both
stored in HHDS. Choose the representation that retains the information your
transformation needs.

| Representation | Role | Storage | LiveHD interface |
| --- | --- | --- | --- |
| [LNAST](06-lnast.md) | Source-level structure, elaboration and type information | `hhds::Tree` and `hhds::Forest` | `lnast/`, `upass/` |
| [LGraph](05-lgraph.md) | Hardware connectivity, state and hierarchical netlists | `hhds::Graph` and `hhds::GraphLibrary` | `graph/`, `pass/` |

## LNAST: elaboration and lowering

LNAST carries control flow, names, bundles and source types. Its passes resolve
these constructs, evaluate compile-time expressions, construct SSA and infer
ranges. The terminal `upass/tolg` lowering builds LGraph. Lowering need not
preserve a one-to-one correspondence between tree nodes and graph cells.

Use per-node HHDS attributes for persistent payloads; keep temporary pass
state in local side maps. The current node catalog is
[`lnast/lnast_nodes.def`](https://github.com/masc-ucsc/livehd/blob/master/lnast/lnast_nodes.def).

## LGraph: hardware transformations

LiveHD layers cell semantics, pin attributes and traversal helpers over HHDS.
`graph/cell.hpp` defines the cell catalog, `graph/attrs.hpp` carries attributes,
and `graph/node_util.hpp` provides helpers in `livehd::graph_util`.

Graph consumers include constant propagation (aegraph by default), bitwidth
inference, simulation, formal checking and synthesis. The shared synthesis
pipeline is in `pass/synth`; ABC integration is isolated in `pass/abc`, while
native synthesis lives in `pass/usyn`. Yosys is an optional frontend and an
independent checking tool, not the implementation of the shared synthesis
pipeline.

See [memory and concurrency](03-memory.md) for ownership and
[creating a pass](11-pass.md) for registration and build integration. Component
READMEs in the source repository provide implementation details; the
[algorithm reference](../lhd/index.md) describes the flow at a higher level.
