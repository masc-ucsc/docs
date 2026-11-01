# LiveHD and Pyrope

LiveHD provides compilation, simulation, synthesis and formal verification for
**Pyrope and Verilog/SystemVerilog**. Start with the guide for practical use,
or the algorithm reference for the methodology behind the flow.

| Reference | What you will find |
| --- | --- |
| [LiveHD guide](livehd/00-intro.md) | Installation, the `lhd` driver, intermediate representations and developer workflows |
| [Pyrope language](pyrope/01-introduction.md) | Language concepts, syntax and hardware semantics |
| [LiveHD algorithms](lhd/index.md) | A draft methodology reference for experts and agents: default synthesis, optional physical design, reuse and verification |
| [Hardware design](pyrope/00-hwdesign.md) | An introduction for software designers |

Direct Chisel/FIRRTL input is no longer supported. Chisel-generated
Verilog/SystemVerilog can enter through the RTL readers; see
[supported inputs](livehd/00-intro.md#supported-inputs).
