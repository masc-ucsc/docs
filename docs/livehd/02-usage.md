# Usage
This is a high level description of how to use LiveHD.

## Sample usage
Below are some sample usages of the LiveHD shell (lgshell). A bash prompt is
indicated by `$`, an lgshell prompt is indicated by `livehd>`, and a Yosys
prompt is indicated by a `yosys>`. Lgshell supports color output and
autocompletion using the tab key.

### General concepts

Currently, LiveHD can interface Verilog, FIRRTL, and Pyrope HDLs through
different front-end commands. After the parsing step, the HDL source can
be be transformed into LiveHD's internal intermediate representations, LNAST and
LGraph, and perform mid-end optimizations based on the two IRs, and generates
the optimized (or synthesized) Verilog code at the back-end. 


### Starting and exiting the shell
```
$ ./bazel-bin/main/lgshell
livehd> help
  ...
livehd> help pass.sample
livehd> exit
```


### Verilog Compilation

The following uses Verilog as the example to demonstrate the compilations
commands.  It imports a Verilog file with a specified the database path,
translates to the LNAST IR, lowers the LNAST IR to LGraph IR, executes some
compiler optimizations, and generates the optimized Verilog code to the `tmp`
directory. By default, a database called `lgdb` will be set in the `livehd`
directory to store the internal representations, but users can optionally
specify a prefered path. 

```
livehd> inou.liveparse path:/your/path/lgdb_foo files:/your/path/bar.v |> inou.verilog |> pass.lnast_tolg |> pass.cprop |> pass.bitwidth |> inou.cgen.verilog odir:tmp
```

A command `lgraph.match` can also be used to specify a (sub)hierarchy to operate
over, which can then be moved from pass to pass using the pipe (`|>`) operator.

When Verilog file(s) are compiled through a series of commands in lgshell, if a
problem occurs while compiling Verilog files (due to a syntax error, use of
un-synthesizable Verilog, or something else), the corresponding error will be
printed. Once a hierarchy has been created, other lgshell commands can read,
modify, or export this hierarchy freely.


### Pyrope Compilation

The Pyrope compilation flow is similar to the Verilog commands except the
front-end Pyrope parser pass `inou.pyrope`

```
livehd> inou.pyrope path:/your/path/lgdb_foo files:/your/path/bar.prp |> pass.lnast_tolg |> pass.cprop |> pass.bitwidth |> inou.cgen.verilog odir:tmp
```

Additionally, users can compile a Pyrope code with a mid-end command of
`pass.compiler` which integrates standard compilation passes in LiveHD such as (1)
`pass.lnast_tolg` for IR lowering, (2) `pass.cprop` for legacy compiler
optimizations such as copy and constant propagation, peep-hole optimization, deadcode elimination, and high-level data-structure resolving (3) `pass.bitwidth` for circuit bitwidth optimization.

```
livehd> inou.pyrope path:/your/path/lgdb_foo files:/your/path/bar.prp |> pass.compiler |> inou.cgen.verilog odir:tmp
```

### FIRRTL Compilation
LiveHD compiles FIRRTL code with the protocal buffer format. Users can reference
[this doc](https://github.com/masc-ucsc/livehd/blob/master/docs/FIRRTL.md)
to generate the protocol buffers file from Chisel/FIRRTL compiler.

The LiveHD FIRRTL compiler uses a integrated mid-end commands as explained in
the previous Pyrope example to compiles the FIRRTL HDL. Set `gviz` option to
true to automatically generate the visiual Graphviz for individual steps. Set
`hier` option to true for hierarchical Chisel design in most cases. Specify the
top module name with the `top` option.

```
livehd> inou.firrtl.tolnast path:/your/path/lgdb_foo files:/your/path/bar.pb |> pass.compiler gviz:false top:top_module_name hier:true |> inou.cgen.verilog odir:tmp
```


### Textual LNAST IR Dump
To display the content of the LNAST IR after parse (Pyrope as the example)

`inou.pyrope files:foo.prp |> lnast.dump`

### Textual LGraph IR Dump
To display the content of the LGraph IR (Pyrope as the example)

`inou.pyrope files:foo.prp |> pass.lnast_tolg |> lgraph.dump`

### Graphviz LGraph IR Dump

To display the content of the LGraph IR (Pyrope after the `cprop` pass as the example)
`inou.pyrope files:foo.prp |> pass.lnast_tolg |> pass.cprop |> inou.graphviz.from`

- Print information about an existing LGraph:
  ```
  $ ./bazel-bin/main/lgshell
  livehd> inou.liveparse files:./inou/yosys/tests/trivial.v |> inou.verilog
  livehd> lgraph.match |> lgraph.stats
  livehd> lgraph.match |> lgraph.dump
  ```
  `lgraph.match` picks up any LGraphs matching the regex passed (or everything if no regex is provided) and treats every single one as the top of the hierarchy, whereas `lgraph.open name:<root module>` will just open the root module as the top of the hierarchy.


### Running a custom pass
```
$ ./bazel-bin/main/lgshell
livehd> inou.pyrope files:./inou/pyrope/tests/if1.prp
livehd> lgraph.match |> <pass name>
```


### Low level directed build

- To compile an individual pass:
  ```
  $ bazel build -c dbg //pass/sample:pass_sample
  $ bazel build -c dbg //inou/yosys:all
  ```
- To build a direct Yosys executable that has LiveHD embedded:
  ```
  $ bazel build -c dbg //inou/yosys:all
  $./bazel-bin/inou/yosys/yosys2
  ```

