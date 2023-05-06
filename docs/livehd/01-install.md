# Installation

This is a high level description of how to build LiveHD.

## Requirements

Although LiveHD should run on most common Linux distributions, it is heavily tested on both Arch and Kali (Debian based).

The following programs are assumed to be present when building LiveHD:

- GCC 10+ or Clang 10+ (C++17 support is required)
- Bazel
- python3

It is also assumed that bash is used to compile LiveHD.

gcc and clang offers better warnings and execution speed dependent of the benchmark.

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

**Install Bazel**isk

Bazelisk is a wrapper around bazel that allows you to use a specific version.

If you do not have system permissions, you can install a local bazelisk

```sh
npm install  @bazel/bazelisk
alias bazel=$(pwd)/node_modules/\@bazel/bazelisk/bazelisk.js
```

You can also install it directly if you have administrative permissions:

macos:
```sh
brew install bazelisk.
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

LiveHD has several build options, detailed below. All three should result in a working executable, but may differ in speed or output.

A binary will be created in `livehd/bazel-bin/main/lgshell`.

```sh
bazel build       //main:all # fast build, no debug symbols, slow execution (default)
bazel build -copt //main:all # fastest execution speed, no debug symbols, no assertions
bazel build -cdbg //main:all # moderate execution speed, debug symbols
```

## Potential issues

If you have multiple gcc versions, you may need to specify the latest. E.g:

```sh
CXX=g++-8 CC=gcc-8 bazel build //main:all -c opt # fast execution for benchmarking
CXX=g++-8 CC=gcc-8 bazel build //main:all -c dbg # debugging/development
```

If you want to run clang specific version:

```sh
CXX=clang++-10 CC=clang-10 bazel build //main:all -c dbg # debugging/development
```

Make sure that the openJDK installed is compatible with bazel and has the certificates to use tools. E.g in debian:

```sh
dpkg-reconfigure openjdk-11-jdk
/var/lib/dpkg/ca-certificates-java.postinst configure
```

If you fail to build for the first time, you may need to clear the cache under your home directory before rebuilding:

```sh
rm -rf ~/.cache/bazel
```

Make sure to have enough memory (4+GB at least)

## Next Steps

To start using LiveHD, check out [Usage](02-usage.md). If you're interested in working on LiveHD, refer to [Creating a pass](11-pass.md).

