
# Introduction

LiveHD is an infrastructure designed for Live Hardware Development. By live, we
mean that small changes in the design should have the synthesis and simulation
results in a few seconds.

As the goal of "seconds," we do not need to perform too fine grain incremental
work. Notice that this is a different goal from having an typical incremental
synthesis, where many edges are added and removed in the order of thousands of
nodes/edges.

## Goal

LiveHD: a fast and friendly hardware development flow that you can trust

* To be "Fast", LiveHD aims to be parallel, scalable, and incremental/live flow.
* To be "friendly", LiveHD aims to build new models to have good error reporting.
* To "trust", LiveHD has CI and many random tests with logic equivalence tests (LEC).



## LiveHD Framework

LiveHD is optimized for synthesis and simulation. The main components of LiveHD
includes LGraph, LNAST, integrated 3rd-party tools, code generation, and "live"
techniques. The core of LiveHD is a graph structure called LGraph (Live Graph).
LGraph is built for fast synthesis and simulation, and interfaces other tools
like Yosys, ABC, OpenTimer, and Mockturtle. LNAST stands for language neutral
AST, which is a high-level IR on both front/back-end of LGraph. LNAST helps to
bridge different HDLs and HLS into LiveHD and is useful for HDLs/C++ code
generation.

![LiveHD overall flow](../../assets/images/livehd.svg)



