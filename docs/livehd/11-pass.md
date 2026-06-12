
# Creating a Pass

This document provides some minimal suggestion on how to build a new LiveHD pass.


LiveHD passes reside in three directories, by level and direction:

* `inou/`: translation from/to some external format (Pyrope, slang/Verilog,
  Yosys, Verilog code generation).
* `upass/`: LNAST-level (tree) passes — SSA, type system, constant
  propagation, and the terminal LNAST→LGraph lowering (`upass/tolg`).
* `pass/`: LGraph-level (graph) transformations — `pass/cprop`,
  `pass/bitwidth`, ... — plus the shared pass infrastructure in
  `pass/common`.

## How passes are registered and run

There is no interactive shell: passes register themselves statically through
`Pass_plugin` (see `pass/common/pass.hpp`), which adds an
[EPRP](https://github.com/masc-ucsc/livehd/tree/main/core) method with its
labels (arguments). The `lhd` driver initializes the registry at startup and
drives the registered methods programmatically — a [recipe](02-usage.md)
(`O0`/`O1`/`O2`) names the ordered pass chain, and `--set pass.flag=value` /
`--config lhd.toml` provide the per-pass flags.

## Create a pass

Check an existing small pass (e.g. `pass/lnastfmt` or `pass/prp_writer`) for
the structure. The typical is to have these files:

* `pass/XXX/pass_XXX.[cpp|hpp]`: C++ and Header file to interface with the
  pass registry (the `Pass_plugin` + EPRP method setup)
* `pass/XXX/XXX.[cpp|hpp]`: C++ file to perform the pass over a LGraph or LNAST API
* `pass/XXX/BUILD`: the [Bazel](10-bazel.md) build configuration file
* `pass/XXX/tests/XXX_test.cpp`: A google test checking the pass


Finally, add the new pass to the `lhd` binary dependencies in `lhd/BUILD`
(`lhd_lib` deps) so the registry links it in.


## Pass Parameters and Common variables

One of the main goals is to have a uniform set of passes. Passes should use
these common EPRP label names when possible:

```bash
    name:foo        lgraph name
    path:lgdb       lgraph database path (lgdb)
    files:foo,var   comma separated list of files used for INPUT
    odir:.          output directory to generate files like verilog/pyrope...
```

The `Pass` base class provides `get_files`/`get_path`/`get_odir` accessors
and `Pass::info` (debug-build progress logging). Errors and warnings go
through `livehd::diag` — `diag::err(pass, code, category)…​.fatal()` /
`diag::warn(…)….emit()` — so every record carries a stable code, a pinned
category, and (when available) a resolved source span. `.fatal()` throws an
exception that the `lhd` driver catches and classifies (the `error.class` of
the [result JSON](02-usage.md)). See the "Error handling" section of
[13-style](13-style.md).

## Some hints/comments useful for developers

### Using clang when building

The regression system builds for both gcc and clang. To force a clang build, set the following environment variables before building:

```sh
CXX=clang++ CC=clang bazel build -c dbg //...
```

### Perf in lgbench

Use lgbench to gather statistics in your code block. It also allows to run perf record
for the code section (from lgbench construction to destruction). To enable perf record
set LGBENCH_PERF environment variable

```sh
export LGBENCH_PERF=1
```

### GDB/LLDB usage

For most tests, you can debug with

```sh
gdb --args ./bazel-bin/lhd/lhd compile foo.prp --emit verilog:foo.v
```

or

```sh
lldb -- ./bazel-bin/lhd/lhd compile foo.prp --emit verilog:foo.v
```

Note that breakpoint locations may not resolve until lhd is started and the relevant LiveHD libraries are loaded.

### Address Sanitizer

LiveHD has the option to run it with address sanitizer to detect memory leaks.

```sh
bazel build -c dbg --config asan //...
```

### Thread Sanitizer

To debug with concurrent data race.

```sh
bazel build -c dbg --config tsan //...
```

(`--config ubsan` for undefined behavior is also available.)

### Debugging a broken Docker image

The travis/azure regressions run several docker images. To debug the issue, run the same as the failing
docker image. c++ OPT with archlinux-masc image

1. Create some directory to share data in/out the docker run (to avoid
   mistakes/issues, I would not share home directory unless you have done it
   several times before)

```sh
mkdir $HOME/docker
```

2. Run the docker image (in some masc docker images you can change the user to not being root)

```sh
docker run --rm --cap-add SYS_ADMIN -it  -e LOCAL_USER_ID=$(id -u $USER) -v ${HOME}/docker:/home/user mascucsc/archlinux-masc

# Once inside docker image. Create local "user" at /home/user with your userid
/usr/local/bin/entrypoint.sh
```

3. If the docker image did not have the livehd repo, clone it

```sh
git clone https://github.com/masc-ucsc/livehd.git
```

4. Build with the failing options and debug

```sh
CXX=g++ CC=gcc bazel build -c opt //...
```

A docker distro that specially fails (address randomizing and muslc vs libc) is alpine. The command line to debug it:

```sh
docker run --rm --cap-add SYS_ADMIN -it -e LOCAL_USER_ID=$(id -u $USER) -v $HOME:/home/user -v/local/scrap:/local/scrap mascucsc/alpine-masc
```
