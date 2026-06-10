
# Bazel build

Bazel is a build system open sourced by google. The main difference
with traditional Makefiles is that it checks to make sure that dependences are not
lost and the builds are reproducible and hermetic. This document explains how
to use Bazel in the LiveHD project. External dependences are managed with
bzlmod (`MODULE.bazel`).

Build targets are referred to using the syntax `//<relative path to BUILD file>:<executable>`, where
`//` is the path of the root livehd directory.

To build the `lhd` driver and supporting libraries, the target would be `//lhd:lhd`.
To build every target in LiveHD (helpful for checking if changes cause compilation failures), the target would be `//...`.  For more details on target syntax, see [this](https://docs.bazel.build/versions/master/guide.html#target-patterns) page.


## Release vs fastbuild (default) vs debug

For debugging/development use `-c dbg`, for benchmarking and testing `-c opt`.

 - Fast build: no optimization, minimal debugging information (no local variable information), assertions turned on (default)
```    
$ bazel build <target>
```

 - Debug build: some optimization, full debugging information, assertions turned on
```
$ bazel build -c dbg <target>
```

or use address sanitizer to detect memory leaks
```
$ bazel build -c dbg --config asan //...
```

or use thread sanitizer to detect data races
```
$ bazel build -c dbg --config tsan //...
```

or use undefined behavior sanitizer
```
$ bazel build -c dbg --config ubsan //...
```

 - Release build: most optimization, no debug symbols, assertions turned off
```
$ bazel build -c opt <target>
```

 - Benchmarking build: aggressive optimization for the current architecture (binary may not be portable!)
```
$ bazel build --config=bench <target>
```

## See the commands executed

The bazel '-s' option prints the command executed. The sandbox may still be deleted.

```
$ bazel build -s //lhd:lhd
```

## Keep all the files in bazel run for debugging

Bazel runs process in a sandbox what it is deleted after each run. To preserve it for debugging a failing test.

```
bazel test --sandbox_debug -c dbg //YOUR_TEST_HERE
```

Check the failing log, it will show you the sandbox location. You can change directory to it, and debug as usual.

## To run FIXME tests

Many times, we have new tests that make the regression fail. We use "fixme" if
the test is a new one and LGraph is still not patched. We want the test in the system,
but we do not want to make fail the regressions.

Those tests are marked with tags "fixme" in the BUILD. E.g:

    sh_test(
        name = "my_test.sh",
        tags = ["fixme"],  # This is a fixme test. It fails, but we should fix it
        srcs = ["tests/pyrope_test.sh"],

To run all the fixme tests
```
$ bazel test --test_tag_filters "fixme" <target>
```
To list all the fixme tests (the goal is to have zero)
```
$ bazel query 'attr(tags, fixme, tests(<target>))'
```

## List bazel targets starting from top directory
```
$ bazel query <target>
```
## List bazel targets starting from any directory
```
$ bazel query <target>
```
## List files needed for a given target
```
$ bazel query "deps(<target>)"
```
## List all the passes that use core (those should be listed at lhd/BUILD deps)
```
$ bazel query "rdeps(//pass/..., //core:all)" | grep pass_
```

## Clear out cache (not needed in most cases)

This command is useful for benchmarking build time, and when system parameters change (the compiler gets upgraded, for example)
```
$ bazel clean --expunge
```

## To run LONG tests

In addition to the short tests, there are sets of long tests that are run frequently
but not before every push to main line. The reason is that those are multi-hour
tests.
```
$ bazel test --test_tag_filters "long1" <target>
```
There are up to 8 long tests categories (long1, long2, long3...). Each of those
tests groups should last less than 4 hours when running in a dual core machine
(travis or azure).

To list the tests under each tag. E.g., to list all the tests with long1 tag.
```
$ bazel query 'attr(tags, long1, tests(<target>))'
```
## Debugging with bazel

First run the tests to see the failing one. Then run with debug options
the failing test. E.g:
```
$ bazel test -c dbg //lnast:all
```
To run with gdb
```
$ bazel build -c dbg //lnast:lnast_test
$ gdb bazel-bin/lnast/lnast_test
(gdb) b Lnast::dump
(gdb) r
```
(lldb is also supported.)

## To create a fully static binary

In the cc_binary of the relevant BUILD file, add `linkopts = ['-static']`

Notice that lhd still needs the directory inside
`bazel-bin/lhd/lhd.runfiles` when using the Yosys-based Verilog readers (the
`//inou/yosys:scripts` data dependency).

## Tracing and profiling

LiveHD is instrumented with [Perfetto](https://perfetto.dev) track events.

Build with profiling on:

```sh
bazel build --define=profiling=1 -c opt //...
```

Run the operations you want to trace; a `livehd.trace` file is written to the
current working directory. Open [ui.perfetto.dev](https://ui.perfetto.dev) and
drag the trace file in to view it.

### Adding trace events

Include `perf_tracing.hpp`, then:

```cpp
#include "perf_tracing.hpp"

{ TRACE_EVENT(category, event); ... }          // RAII (function/scope timing)

TRACE_EVENT_BEGIN(category, event); ...        // events that don't nest by scope
TRACE_EVENT_END(category);
```

For a runtime-computed event name:

```cpp
TRACE_EVENT(category, nullptr, [&name](perfetto::EventContext ctx) {
  ctx.event()->set_name(name);
});
```

New categories are declared in `core/perf_tracing.hpp` via
`PERFETTO_DEFINE_CATEGORIES`:

```cpp
perfetto::Category(category).SetDescription(description)
```

### System-wide mode

Follow Perfetto's
[Linux tracing quickstart](https://perfetto.dev/docs/quickstart/linux-tracing#building-from-source),
add `data_sources {config {name: "track_event"}}` to
`test/configs/scheduling.cfg`, and run
`tools/tmux -c test/configs/scheduling.cfg -C out/linux -n` (the tmux window
prints the command that launches the tracing session). The trace file `trace`
lands in a temporary directory.
