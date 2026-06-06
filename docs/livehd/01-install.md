# Installation

This is a high level description of how to build LiveHD.

## Requirements

Although LiveHD should run on most common Linux distributions, it is heavily tested on both Arch and Kali (Debian based). It also builds on macOS (13.3+).

The following programs are assumed to be present when building LiveHD:

- A C++23 capable compiler (recent GCC or Clang)
- Bazel (use bazelisk, see below)
- python3

Most library dependences (abseil, boost, flex/bison, googletest, mimalloc,
rapidjson, ...) are fetched and built by Bazel itself through bzlmod
(`MODULE.bazel`), so they do not need to be installed on the system.

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

If you have multiple gcc versions, you may need to specify the latest. E.g:

```sh
CXX=g++-13 CC=gcc-13 bazel build //lhd:lhd -c opt # fast execution for benchmarking
CXX=g++-13 CC=gcc-13 bazel build //lhd:lhd -c dbg # debugging/development
```

If you want to run a specific clang version:

```sh
CXX=clang++-18 CC=clang-18 bazel build //lhd:lhd -c dbg # debugging/development
```

If you fail to build for the first time, you may need to clear the cache under your home directory before rebuilding:

```sh
rm -rf ~/.cache/bazel
```

Make sure to have enough memory (4+GB at least)

## Next Steps

To start using LiveHD, check out [Usage](02-usage.md). If you're interested in working on LiveHD, refer to [Creating a pass](11-pass.md).
