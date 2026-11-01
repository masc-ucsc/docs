# Installation

This is a high level description of how to build LiveHD.

## Requirements

LiveHD builds on Linux and macOS. The current macOS build targets macOS 26
or newer, as selected by the repository's `.bazelrc`; the checked-in CI workflow
also uses macOS 26.

The following programs are assumed to be present when building LiveHD:

- A C++23 capable compiler (GCC 16+ or Clang 20+ recommended)
- Bazel (use Bazelisk to select the version in `.bazelversion`)
- python3

Bazel fetches pinned libraries and build tools through Bzlmod (`MODULE.bazel`).
Use those declarations as the dependency reference; installing unrelated system
versions does not update the versions used by the build.

It is also assumed that bash is used to compile LiveHD.

If you're unsure if your copy of gcc or clang is new enough, you can check the version by typing

```sh
g++ --version
```

or

```sh
clang++ --version
```

## Steps

**Download LiveHD source**

```sh
git clone https://github.com/masc-ucsc/livehd
cd livehd
```

**Install Bazelisk**

Bazelisk is a wrapper around bazel that allows you to use a specific version.

If you do not have system permissions, you can install a local bazelisk

```sh
npm install  @bazel/bazelisk
alias bazel=$(pwd)/node_modules/\@bazel/bazelisk/bazelisk.js
```

You can also install it directly if you have administrative permissions:

macos:
```sh
brew install bazelisk
```

Linux:
```sh
npm install -g @bazel/bazelisk
```

```sh
go install github.com/bazelbuild/bazelisk@latest
export PATH=$PATH:$(go env GOPATH)/bin
```

Arch linux:
```sh
pacaur -S bazelisk  # or yay or paru installers
```

**Build LiveHD**

LiveHD has several build options, detailed below. All should result in a working executable, but may differ in speed or output.

The user-facing binary is the `lhd` command line driver, created in
`livehd/bazel-bin/lhd/lhd`.

```sh
bazel build        //lhd:lhd # fast build, no debug symbols, slow execution (default)
bazel build -c opt //lhd:lhd # fastest execution speed, no debug symbols, no assertions
bazel build -c dbg //lhd:lhd # moderate execution speed, debug symbols
```

To build every target in LiveHD (helpful for checking if changes cause
compilation failures):

```sh
bazel build //...
```

## Potential issues

LiveHD uses newer C++23 features. If your system GCC is older than GCC 16,
you may need to build with Clang 20 or newer instead:

```sh
CXX=clang++ CC=clang bazel build -c opt //...
```

If you have multiple GCC versions, you can specify GCC 16 explicitly:

```sh
CXX=g++-16 CC=gcc-16 bazel build //lhd:lhd -c opt # fast execution for benchmarking
CXX=g++-16 CC=gcc-16 bazel build //lhd:lhd -c dbg # debugging/development
```

If you want to run a specific Clang version:

```sh
CXX=clang++-20 CC=clang-20 bazel build //lhd:lhd -c dbg # debugging/development
```

Start with the first compiler or dependency error in the build log. Check the
compiler selection, `.bazelversion` and `.bazelrc` before clearing caches.
`bazel clean --expunge` is a last resort for stale build state; it forces an
expensive rebuild. Available memory limits useful build parallelism, especially
when compiling Slang, LLVM and the solver dependencies.

## Validation

```sh
bazel test -c opt //...
```

The ordinary suite is self-contained. Optional comparisons with external
simulators require those tools and an explicit `LHD_EXTERNAL_SIM=1`; see the
repository's `AGENTS.md` for the invocation and requirements.

## Next Steps

To start using LiveHD, check out [Usage](02-usage.md). If you're interested in working on LiveHD, refer to [Creating a pass](11-pass.md).
