
# Creating a Pass

A pass transforms or analyzes one of LiveHD's intermediate representations.
This guide covers registration, configuration and focused validation.


LiveHD passes reside in three directories, by level and direction:

* `inou/`: translation from/to some external format (Pyrope, slang/Verilog,
  Yosys, Verilog code generation).
* `upass/`: LNAST-level (tree) passes — SSA, type system, constant
  propagation, and the terminal LNAST→LGraph lowering (`upass/tolg`).
* `pass/`: LGraph-level (graph) transformations — `pass/aegraph`, `pass/cprop`,
  `pass/bitwidth`, ... — plus the shared pass infrastructure in
  `pass/common`.

## How passes are registered and run

There is no interactive shell: passes register themselves statically through
`Pass_plugin` (see `pass/common/pass.hpp`), which adds an
[EPRP](https://github.com/masc-ucsc/livehd/tree/master/core) method with its
labels (arguments). The `lhd` driver initializes the registry at startup and
drives the registered methods programmatically — the pass chain is fixed
(constant propagation, then bitwidth inference; see [usage](02-usage.md)), and
`--set pass.flag=value` / `--config lhd.toml` provide the per-pass flags.

## Create a pass

Check an existing small pass (e.g. `pass/lnastfmt` or `pass/prp_writer`) for
the structure. The typical is to have these files:

* `pass/XXX/pass_XXX.[cpp|hpp]`: C++ and Header file to interface with the
  pass registry (the `Pass_plugin` + EPRP method setup)
* `pass/XXX/XXX.[cpp|hpp]`: C++ file to perform the pass over a LGraph or LNAST API
* `pass/XXX/BUILD`: the [Bazel](10-bazel.md) build configuration file
* A focused test and its Bazel target. Use `foo_test.cpp` only when a matching
  `foo.cpp` exists in the same or parent directory; otherwise use a descriptive
  name such as `foo_smoke.cpp`.


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

### Tracing and profiling

Use the current Perfetto instrumentation in `core/perf_tracing.hpp`; see
[tracing and profiling](10-bazel.md#tracing-and-profiling). The old `lgbench` /
`LGBENCH_PERF` instructions do not describe the current tree.

Developer-only environment controls use the `LHD_` prefix and are read through
`livehd::debug::env<"LHD_NAME">()` at setup, not repeatedly in hot loops.
User-facing behavior belongs in typed `--set` options. Follow the repository's
`AGENTS.md` for defaults, diagnostics and test rules.

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

### Reproducing CI failures

Use the compiler, platform and command from the failing job. The current
workflow is checked in at
[`.github/workflows/ubuntu.yml`](https://github.com/masc-ucsc/livehd/blob/master/.github/workflows/ubuntu.yml)
(the filename is historical; inspect its runner settings). Do not assume the
former Travis/Azure Docker images match today's build.

Run the failing target first, then the checks appropriate to the change.
Keep tests self-contained and preserve coverage when reducing their cost.
