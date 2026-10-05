# Pyrope Standard Library

Pyrope has two layers of library code: the built-in `std` namespace, which is
part of the language, and the `import("prp")` library, which is still a
wish-list.

## Built-in `std` namespace

`std` is a built-in namespace. Every file sees it without an `import`, and it
is not a file on the import path: `import("prp")` below is a different, much
larger library.

`std.clog2(x)` returns the number of bits needed to index `x` entries, with
Verilog `$clog2` semantics: the smallest `n` such that `(1 << n) >= x`. It is
comptime only; `x <= 0` or a runtime `x` is a compile error.

```pyrope
cassert(std.clog2(1)  == 0)
cassert(std.clog2(13) == 4)
cassert(std.clog2(16) == 4)
cassert(std.clog2(17) == 5)

mod pick<N=4>(v:Unsigned(bits=N), sel:Unsigned(bits=std.clog2(N))) -> (b:U1@[0]) {
  b = v#[sel]
}
```

`std.clog2(N)` is the width of an *index* into `N` entries; `N.[bits]` is the
width of the *value* `N` (with `comptime const N = 16`, `N.[bits] == 5` but
`std.clog2(N) == 4`). See [Bitwidth](07-typesystem.md#bitwidth).

### Memory image preload

`std.readmemh(file)` and `std.readmemb(file)` initialize a registered memory
once when a simulation starts:

```pyrope
mod program(addr:U8) -> (instruction:U32@[]) {
  reg code:[256]U32 = std.readmemh("program.hex")
  instruction = code[addr]
}
```

Declare a sized element type (`U32` above). The filename is one positional
comptime string; relative paths resolve against the source file containing the
call. A literal or a `comptime const` is accepted. The call supplies startup
contents, not a register reset value: reset does not reload the image. Normal
memory writes still work.

Files contain whitespace-separated hex or binary words, optional underscores,
`//` or `/* ... */` comments, and hexadecimal `@address` directives in either
format. Entry zero comes first. Words are truncated to the declared width;
short words are zero-extended. X/Z/? digits are unknown bits (the two-state
simulator resolves them using `sim.unknown_zero`). Unlisted entries retain the
startup fill, currently zero for memories. Missing files, malformed tokens,
unterminated comments, and out-of-range addresses fail simulation explicitly.

The generated simulator opens the file on each fresh simulation initialization,
even when compilation and generated C++ are reused. Changing just the image
therefore needs no HDL edit or recompile. Checkpoint restore overlays the freshly
initialized state; the image must still be available at startup. Exported IR
retains the resolved file dependency rather than embedding its contents.

For synthesis, these memories represent externally initialized storage, such as
memory loaded through a scan interface. The image does not become a hardware
ROM constant. LiveHD preserves the native memory boundary, including memories
with no functional RTL writer; exported Verilog gives that boundary a `blackbox`
attribute and a behavioral simulation model. A downstream implementation must
supply the memory macro/loading mechanism. This builtin does not generate a scan
chain. Native LiveHD formal reasoning uses stable symbolic contents until
ordinary writes; it does not specialize the proof to the image values.

For an independent Yosys check, `lgcheck` defines
`LIVEHD_FORMAL_MEMORY_MODEL` while reading the sources. This exposes the emitted
behavioral memory body through its default synthesis black-box boundary. The
same image files must be accessible to both sides. That check elaborates the
supplied image; it is not an image-independent proof of externally loaded
contents. Leave the macro undefined when preserving the synthesis boundary.

Whole-memory bulk update/reset is not supported with file preload.

The native Slang reader lowers unconditional `initial $readmemh(file, memory)`
and `$readmemb` calls to the same representation. It supports constant filenames
and local, zero-based, one-dimensional memories with integral elements. SV
filenames retain runtime working-directory semantics. Explicit address bounds,
conditional/timed calls, and mixed initial assignments are rejected. The Yosys
reader has not been updated to this external-initialization contract.

## The `import("prp")` library

!!! WARNING "TBD"
    The `import("prp")` standard library is not implemented yet; the rest of
    this chapter is the wish-list for it. See
    [Implementation status](15-tbd.md).

This is a list of functionality that `import("prp")` should produce.

### Basic operations

All the LNAST node have an associated function matching name to simplify the
creation of operations: `plus`, `minus`, `mult`, `div`, `mod`, `ror`...

```pyrope
const prp = import("prp")
cassert(prp.plus(first=1, second=2, third=3) == 6) // three named fields captured in a
```

Library code:
```pyrope
comb plus(...a:Signed) -> (r:Signed) {
  r = 0
  for e in a {
    r += e
  }
}
```

### Array/Tuple operators

#### Size of length

Sample use:
```pyrope
const x = (1,2,23)

cassert(prp.len(x) == 3)
```

Library code:
```pyrope
comb len(x) -> (r) { r = x.[size] }
```

#### map

Sample use:

```pyrope
const x = (1,2,3)
comb inc(a) -> (r) { r = a + 1 }

cassert(x.map(inc) == (2,3,4))
```

Library code:
```pyrope
comb map(self, f) -> (r:[]) {    // self: the tuple, so `x.map(inc)` is a UFCS call
  r = nil
  for e in self {
    r = (...r, f(e))
  }
}
```

#### filter

Sample use:

```pyrope
comb not_two(a) -> (r) { r = a != 2 }

cassert((1,2,3).filter(not_two) == (1,3))
```

Library code:

```pyrope
comb filter(self, f) -> (r:[]) {
  r = nil
  for e in self {
    if f(e) {
      r = (...r, e)
    }
  }
}
```

#### reduce

Sample use:

```pyrope
cassert((1,2,3).reduce(prp.plus) == 6)
```

Library code:

```pyrope
comb reduce(self, op) -> (res) {
  if self.[size] <= 1 {
    res = self
    return
  }

  res = self[0]
  for i in self[1..] {
    res = op(lhs=res, rhs=i)  // both arguments are captured, as in `prp.plus`
  }
}
```

### Strings

String helpers follow the C++23 `string_view` naming where possible:

```pyrope
const s = "hello"
cassert(s.len() == 5)
cassert(s.find("ll") == 2)
cassert(s.substr(pos=1, count=3) == "ell")
```

### File I/O

File access comes from a [`cpp`](07-typesystem.md#external-c-calls-via-cpp)
import; there is no special grammar. It is debug-only simulation functionality
(used inside `test` blocks), not synthesizable:

```pyrope
type Fs = ( read_file: comb(path:String) -> (data:String) )
const fs:Fs = cpp("file_io")

test vectors.load {
  const cfg = fs.read_file("config.txt")
  puts(cfg)
}
```

### Data structures

```pyrope
const q = prp.queue.make<T=Signed>(depth=16)
q.push(1)
assert(not q.empty())
const v = q.pop()
```

### Math and utilities

```pyrope
assert(prp.math.gcd(a=12, b=18) == 6)
const s = prp.str.join(parts=("a", "b"), sep=",")
```

#### TODO

 It would be nice to have the same methods (and names) as the c++20 `std::views`
 adaptors so that it is easier for developers to get familiar. E.g: filter,
 transform, drop, join, split, reverse, common, counted...

 https://en.cppreference.com/w/cpp/ranges

### Simulation arguments

Test signatures are the preferred interface for named simulation arguments:

```pyrope
test bench.run(cycles:U32=1000000) {
  // `cycles` uses the supplied value or this test's default.
}
```

Run with `lhd sim bench.prp bench.run +cycles=10000000`, or run the generated
executable with `./drv.bin --test bench.run +cycles=10000000`. Simulator controls
keep their `--` prefix. `--arg name=value` on `lhd sim` and `--name=value` on the
generated executable remain compatibility aliases; use `+name=value` in new code.

Explicit reads inside a test use the same supplied arguments:

```pyrope
const verbose = std.testplusarg("verbose")
const cycles = std.valueplusarg(name="cycles", default=1000000)
const firmware = std.valueplusarg(name="firmware", default="program.hex")
```

Names match exactly and are case sensitive. The first occurrence wins. A bare
`+verbose` is present; `+file=` supplies an empty string. Signature defaults and
accessor defaults are local: neither makes `std.testplusarg` return true.
`std.valueplusarg(name="cycles")` requires a numeric value; a missing value is an error.
Both arguments are named: `default` may also be a String, so an unnamed
`std.valueplusarg("cycles", default=1)` is ambiguous.
A string default selects string parsing. Numeric access currently uses signed
64-bit integers; sized numeric signature parameters additionally check their
range. `Bool` signature parameters accept bare flags or `true`, `false`, `1`,
and `0`. Strings can also be signature parameters with a string default.

Result rows record ordered supplied `arguments` and resolved `parameters`.
Argument changes participate in A/B workload identity; checkpoint replay rejects
changed arguments and checkpoints lacking argument metadata.

Pyrope accessors currently require a `test` block. General Pyrope module debug
execution remains pending; argument-dependent hardware is rejected.

Slang also supports `$test$plusargs` and `$value$plusargs` in untimed, simulation-only
`initial` blocks. These use SV prefix matching and the first matching supplied
argument. `$value$plusargs` returns success and updates its destination on a match;
a miss returns zero and leaves the destination unchanged. Supported conversions
are `%d`, `%b`, `%h`/`%x`, `%o`, and `%s`, with integral destinations up to 64 bits
or strings. The runtime is two-state.

The block can contain private variables, blocking assignments, basic arithmetic
and comparisons, conditionals, immediate assertions, and literal-format
`$display`/`$write`/`$fatal` calls. Debug variables must belong to one block and
cannot be ports or referenced by hardware, including through hierarchy. Put reads
inside the initial block, rather than module-scope declaration initializers.
Timed processes, real or wider destinations, user subroutine calls, and other
unsupported constructs produce diagnostics.

Initialization survives saved LNAST/LGraph and runs once per elaborated instance
at simulation startup. Emitted SV preserves it under `synthesis translate_off`.
Pyrope source emission of these SV blocks is explicitly rejected until module
debug emission exists; use `ln:` or `lg:` imports to preserve them.
