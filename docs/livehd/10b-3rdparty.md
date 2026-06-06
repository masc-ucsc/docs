
# 3rd Party

This section is for more advanced users that want to build LiveHD with some external 3rd party tool.

When integrating LiveHD with a 3rd party tool (nextpnr in this example), you can either bring the 3rd
party tool to LiveHD and hence build it with bazel, or you can export the LiveHD code/libraries
and integrate with the 3rd party project. This document covers the later case.


## Requirements

Bazel pulls a specific set of library dependences through bzlmod
(`MODULE.bazel`); if you export, you must ensure that the 3rd party tool uses
the same library versions. The main sources of likely conflict are "boost"
and "abseil".

The pinned versions are listed directly in `MODULE.bazel` at the LiveHD root:

```
grep -E "abseil|boost" MODULE.bazel
# bazel_dep(name = "abseil-cpp", version = "20250814.2")
# bazel_dep(name = "boost.multiprecision", version = "1.90.0.bcr.1")
# bazel_dep(name = "boost.unordered", version = "1.90.0.bcr.1")
```

## nextpnr example

The general technique: build LiveHD, then reuse the bazel-generated link
parameters (`*.params`) of the `lhd` binary to link the LiveHD objects and
libraries into the 3rd party build.

nextpnr uses boost, so it must be compiled against the same boost version
that `MODULE.bazel` pins:

```
# nextpnr ice40 needs icestorm, so install it first
git clone https://github.com/cliffordwolf/icestorm.git
cd icestorm
make
sudo make install

# compile nextpnr itself
git clone https://github.com/YosysHQ/nextpnr.git
cd nextpnr
mkdir build
cd build
cmake -DARCH=ice40 ../
make -j $(ncpus)
```

The previous steps should compile before you attempt to integrate LiveHD to nextpnr.

Then, you need to clone and compile LiveHD. If you clone and compile parallel to nextpnr

```bash
git clone https://github.com/masc-ucsc/livehd.git
cd livehd
bazel build -c dbg //lhd:lhd  # You could use -c opt for faster/optimized compilation
cd ../nextpnr/build/
ln -s ../../livehd/
ln -s livehd/bazel-out
ln -s livehd/bazel-livehd
```

Then, copy the bazel link instructions of the `lhd` binary and adapt them for
the nextpnr build:

```
cp livehd/bazel-bin/lhd/lhd-2.params livehd.params
```

Edit `livehd.params`: remove the `-o .../lhd` output line and the `lhd`
`main` object (`bazel-out/.../lhd/_objs/lhd/lhd_main.pic.o`), and add your own
entry file (`extra.cpp` in this example) plus the `-I` include paths for the
LiveHD headers you use (`lnast/`, `graph/`, `core/`, and the
`bazel-livehd/external/...` directories for abseil/iassert). The exact list
in the params file changes with LiveHD versions — treat it as generated, not
as something to write by hand.

This example uses `extra.cpp` as a sample LiveHD call inside nextpnr, e.g.
loading a design library written by `lhd --emit-dir lg:lgdb/` and walking a
graph with the `livehd::graph_util` helpers.

Then you need to add the `@livehd.params` to the end of the `nextpnr-ice40` link step. A way to get the command line
is to use the `VERBOSE=1` option.

```
rm -f nextpnr-ice40
make VERBOSE=1 nextpnr-ice40
```

Cut and paste the link command and append `@livehd.params` to it.

You can check that the new binary includes LiveHD with something like:
```
nm nextpnr-ice40 | grep -i hhds
```
