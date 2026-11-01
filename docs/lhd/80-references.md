# References and algorithmic context

These references support the method's background and terminology. The current
LiveHD behavior is established by the reviewed implementation, not inferred
from historical papers. No benchmark result from these papers is claimed for
the present flow.

## LiveHD {#livehd}

S.-H. Wang, R. T. Possignolo, H. B. Skinner and J. Renau.
**LiveHD: A Productive Live Hardware Development Flow.** IEEE Micro, 40(4), 2020.
[Author manuscript](https://masc.cse.ucsc.edu/docs/ieeemicro20.pdf).

Context: shared graph representation and interactive hardware development.

## LiveSynth {#livesynth}

R. T. Possignolo and J. Renau.
**LiveSynth: Towards an Interactive Synthesis Flow.** DAC, 2017.
[Author manuscript](https://masc.soe.ucsc.edu/docs/dac17.pdf),
[DOI](https://doi.org/10.1145/3061639.3062275).

Context: synthesis decomposition and reuse across small edits.

## SMatch {#smatch}

R. T. Possignolo and J. Renau.
**SMatch: Structural Matching for Fast Resynthesis in FPGAs.** DAC, 2019.
[Author manuscript](https://masc.soe.ucsc.edu/docs/dac19.pdf),
[DOI](https://doi.org/10.1145/3316781.3317912).

Context: structural correspondence as a basis for incremental implementation;
the paper's FPGA flow is not the current ASIC flow specification.

## Acyclic e-graphs {#aegraphs}

C. Fallin. **ægraphs: Acyclic E-graphs for Efficient Optimization in a
Production Compiler.** Invited talk, EGRAPHS workshop, 2023.
[Talk and slides](https://pldi23.sigplan.org/details/egraphs-2023-papers/2/-graphs-Acyclic-E-graphs-for-Efficient-Optimization-in-a-Production-Compiler).
See also the [Cranelift aegraph design documentation](https://docs.rs/cranelift-egraph/0.91.1/cranelift_egraph/index.html).

Context: eager rewriting, acyclic alternatives and inexpensive extraction.
LiveHD supplies its own hardware semantics, rule guards and cost models.

## ABC {#abc}

R. Brayton and A. Mishchenko.
**ABC: An Academic Industrial-Strength Verification Tool.** CAV, 2010.
[DOI](https://doi.org/10.1007/978-3-642-14295-6_5),
[ABC project and algorithm references](https://people.eecs.berkeley.edu/~alanmi/abc/).

Context: AIG-based synthesis and verification infrastructure. The actual
LiveHD recipe and physical boundary handling are integration decisions.

## DAG-aware AIG rewriting {#aig-rewriting}

A. Mishchenko, S. Chatterjee and R. Brayton.
**DAG-aware AIG Rewriting: A Fresh Look at Combinational Logic Synthesis.**
DAC, 2006. [Paper](https://doi.org/10.1145/1146909.1147048).

Context: rewriting with awareness of shared Boolean structure, used within
the broader ABC optimization framework.

## DREAMPlace {#dreamplace}

Y. Lin, S. Dhar, W. Li, H. Ren, B. Khailany and D. Z. Pan.
**DREAMPlace: Deep Learning Toolkit-Enabled GPU Acceleration for Modern VLSI
Placement.** DAC, 2019.
[Author publication page and paper](https://research.nvidia.com/publication/2019-06_dreamplace-deep-learning-toolkit-enabled-gpu-acceleration-modern-vlsi-placement).

Context: analytical wirelength/density optimization and placement kernels.
The native integration, stage policies and timing feedback described here must
be checked against LiveHD, rather than assumed from the original runtime.

## OpenTimer {#opentimer}

T.-W. Huang and M. D. F. Wong.
**OpenTimer: A High-Performance Timing Analysis Tool.** ICCAD, 2015.
[Conference publication record](https://ieee-ceda.org/media/opentimer-high-performance-timing-analysis-tool),
[DOI](https://doi.org/10.1109/ICCAD.2015.7372666).

Context: timing propagation and incremental analysis. The models and
constraints supplied by LiveHD determine the scope of an individual result.

## cvc5 {#cvc5}

H. Barbosa et al. **cvc5: A Versatile and Industrial-Strength SMT Solver.**
TACAS, 2022.
[Author publication record and paper](https://theory.stanford.edu/~barrett/pubs/BBB%2B22-abstract.html).

Context: SMT solver infrastructure for encoded hardware obligations. See the
[LiveHD formal reference](../livehd/07-formal.md) for proof semantics.
