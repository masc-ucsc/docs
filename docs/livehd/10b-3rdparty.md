
# 3rd Party

This section is for more advanced users that want to build LiveHD with some external 3rd party tool.

When integrating LiveHD with a 3rd party tool (nextpnr in this example), you can either bring the 3rd
party tool to LiveHD and hence build it with bazel, or you can export the LiveHD code/libraries
and integrate with the 3rd party project. This document covers the later case.


## Requirements

Bazel pulls a specific set of library dependences, if you export, you must ensure that the 3rd party tool
uses the same library version. The 3 main source of likely conflict is "boost", "abseil", and "fmt".
The "fmt" library is unlikely to be a conflict because LiveHD uses it as "header" only to avoid conflicts
with other tools like slang.


To check the boost and abseil version, the easiest way:
```
bazel build -c dbg //main:all
# boost version 1.71 in this case
grep -i "define BOOST_VERSION " bazel-*/external/boost//boost/version.hpp
#define BOOST_VERSION 107100

# abseil version 20210324
grep "define ABSL_OPTION_INLINE_NAMESPACE_NAME" bazel-*/external/com_google_absl/absl/base/options.h
#define ABSL_OPTION_INLINE_NAMESPACE_NAME lts_20210324
```

## nextpnr example


nextpnr uses boost, in the previous example, you need to compile it with boost 1.71, with the usual requirements:

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
bazel build -c dbg //main:all  # You could use -c opt for faster/optimized compilation
cd ../nextpnr/build/
ln -s ../../livehd/
ln -s livehd/bazel-out
ln -s livehd/bazel-livehd
```

Then, we need to copy the bazel gcc build instructions and combine with the nextpnr build

Copy this to a file called `pp`:
```patch
--- livehd.params	2021-09-25 17:47:36.656724997 -0700
+++ livehd.params	2021-09-25 17:40:24.365650808 -0700
@@ -1,16 +1,17 @@
--o
-bazel-out/k8-dbg/bin/main/lgshell
+-std=c++17
+-Wno-unknown-pragmas
+-I livehd/eprp -I livehd/elab -I bazel-livehd/external/com_google_absl -I bazel-livehd/external/fmt/include/ -I bazel-livehd/external/iassert/src -I livehd/mmap_lib/include -I livehd/core -I livehd/task -I livehd/lemu -I ./bazel-livehd/external/rapidjson -I livehd/pass/common -I ./bazel-livehd/external/replxx/include
+./extra.cpp
 -pie
 -fuse-ld=gold
 -Wl,-no-as-needed
 -Wl,-z,relro,-z,now
 -B/usr/bin
 -pass-exit-codes
 -lstdc++
 -lm
-bazel-out/k8-dbg/bin/main/_objs/lgshell/main.pic.o
 -Wl,--start-lib
 bazel-out/k8-dbg/bin/main/_objs/main/inou_lef_api.pic.o
 bazel-out/k8-dbg/bin/main/_objs/main/main_api.pic.o
 bazel-out/k8-dbg/bin/main/_objs/main/meta_api.pic.o
 bazel-out/k8-dbg/bin/main/_objs/main/top_api.pic.o
```

The patch adds a new c++ file to compile (`extra.cpp`). It will be nicer if the file is in the nextpnr directory structure, but this is as an example of how to integrate. `extra.cpp` has a call to LiveHD to open a database as example.

```
cp livehd/bazel-bin/main/lgshell-2.params livehd.params
patch <pp
```

This example uses `extra.cpp` as a sample LiveHD call inside nextpnr. The `extra.cpp` contents:

```c++
#include "lgraph.hpp"

void some_func() {
  Lgraph *lg = Lgraph::open("lgdb","top");

  lg->dump();
}
```

Then you need to add the `@livehd.params` to the end of the `nextpnr-ice40` link step. A way to get the command line
is to use the `VERBOSE=1` option.

```
rm -f nextpnr-ice40
make VERBOSE=1 nextpnr-ice40
```

Cut and paste the command, it will end with something like `thon3.9.so @livehd.params` to be something like:
```
/usr/bin/c++ -Wall -Wextra -Wno-unused-parameter -Wno-missing-field-initializers -Wno-array-bounds -fPIC -O3 -g -pipe -flto -fno-fat-lto-objects CMakeFiles/nextpnr-ice40.dir/common/archcheck.cc.o CMakeFiles/nextpnr-ice40.dir/common/basectx.cc.o CMakeFiles/nextpnr-ice40.dir/common/bits.cc.o CMakeFiles/nextpnr-ice40.dir/common/command.cc.o CMakeFiles/nextpnr-ice40.dir/common/context.cc.o CMakeFiles/nextpnr-ice40.dir/common/design_utils.cc.o CMakeFiles/nextpnr-ice40.dir/common/embed.cc.o CMakeFiles/nextpnr-ice40.dir/common/handle_error.cc.o CMakeFiles/nextpnr-ice40.dir/common/idstring.cc.o CMakeFiles/nextpnr-ice40.dir/common/idstringlist.cc.o CMakeFiles/nextpnr-ice40.dir/common/log.cc.o CMakeFiles/nextpnr-ice40.dir/common/nextpnr.cc.o CMakeFiles/nextpnr-ice40.dir/common/nextpnr_assertions.cc.o CMakeFiles/nextpnr-ice40.dir/common/nextpnr_namespaces.cc.o CMakeFiles/nextpnr-ice40.dir/common/nextpnr_types.cc.o CMakeFiles/nextpnr-ice40.dir/common/place_common.cc.o CMakeFiles/nextpnr-ice40.dir/common/placer1.cc.o CMakeFiles/nextpnr-ice40.dir/common/placer_heap.cc.o CMakeFiles/nextpnr-ice40.dir/common/property.cc.o CMakeFiles/nextpnr-ice40.dir/common/pybindings.cc.o CMakeFiles/nextpnr-ice40.dir/common/report.cc.o CMakeFiles/nextpnr-ice40.dir/common/router1.cc.o CMakeFiles/nextpnr-ice40.dir/common/router2.cc.o CMakeFiles/nextpnr-ice40.dir/common/sdf.cc.o CMakeFiles/nextpnr-ice40.dir/common/str_ring_buffer.cc.o CMakeFiles/nextpnr-ice40.dir/common/svg.cc.o CMakeFiles/nextpnr-ice40.dir/common/timing.cc.o CMakeFiles/nextpnr-ice40.dir/common/timing_opt.cc.o CMakeFiles/nextpnr-ice40.dir/3rdparty/json11/json11.cpp.o CMakeFiles/nextpnr-ice40.dir/json/jsonwrite.cc.o CMakeFiles/nextpnr-ice40.dir/frontend/json_frontend.cc.o CMakeFiles/nextpnr-ice40.dir/ice40/arch.cc.o CMakeFiles/nextpnr-ice40.dir/ice40/arch_place.cc.o CMakeFiles/nextpnr-ice40.dir/ice40/arch_pybindings.cc.o CMakeFiles/nextpnr-ice40.dir/ice40/bitstream.cc.o CMakeFiles/nextpnr-ice40.dir/ice40/cells.cc.o CMakeFiles/nextpnr-ice40.dir/ice40/chains.cc.o CMakeFiles/nextpnr-ice40.dir/ice40/delay.cc.o CMakeFiles/nextpnr-ice40.dir/ice40/gfx.cc.o CMakeFiles/nextpnr-ice40.dir/ice40/main.cc.o CMakeFiles/nextpnr-ice40.dir/ice40/pack.cc.o CMakeFiles/nextpnr-ice40.dir/ice40/pcf.cc.o CMakeFiles/chipdb-ice40.dir/ice40/chipdb/chipdb-384.cc.o CMakeFiles/chipdb-ice40.dir/ice40/chipdb/chipdb-1k.cc.o CMakeFiles/chipdb-ice40.dir/ice40/chipdb/chipdb-5k.cc.o CMakeFiles/chipdb-ice40.dir/ice40/chipdb/chipdb-u4k.cc.o CMakeFiles/chipdb-ice40.dir/ice40/chipdb/chipdb-8k.cc.o -o nextpnr-ice40  -ltbb /usr/lib/x86_64-linux-gnu/libboost_filesystem.so /usr/lib/x86_64-linux-gnu/libboost_program_options.so /usr/lib/x86_64-linux-gnu/libboost_iostreams.so /usr/lib/x86_64-linux-gnu/libboost_system.so /usr/lib/x86_64-linux-gnu/libboost_thread.so -lpthread /usr/lib/x86_64-linux-gnu/libboost_regex.so /usr/lib/x86_64-linux-gnu/libboost_chrono.so /usr/lib/x86_64-linux-gnu/libboost_date_time.so /usr/lib/x86_64-linux-gnu/libboost_atomic.so -lpthread /usr/lib/x86_64-linux-gnu/libpython3.9.so @livehd.params
```

You can check that the new binary includes liveHD with something like:
```
nm nextpnr-ice40 | grep -i Lgraph
```

