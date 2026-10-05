# Memories

A significant effort of hardware design revolves around memories. Unlike Von
Neumann models, memories must be explicitly managed. Some list of concerns
when designing memories in ASIC/FPGAs:

* Reads and Writes may have different number of cycles to take effect
* Reset does not initialize memory contents
* There may not be data forwarding if a read and a write happen in the same cycle
* ASIC memories come from memory compilers that require custom setup pins and connections
* FPGA memories tend to have their own set of constraints too
* Logic around memories like BIST has to be added before fabrication

This constrains the language, it is difficult to have a typical vector/memory
provided by the language that handles all these cases. Instead, the complex
memories are managed by the Pyrope standard library.


The flow directly supports arrays/memories in two ways:

* Async memories or arrays
* RTL instantiation

## Async memories or arrays

Asynchronous memories, async memories for short, have the same Pyrope tuple
interface. The difference between tuples/arrays and async memories is that the
async memories preserve the array contents across cycles. In contrast, the array
contents are cleared at the end of each cycle.


In Pyrope, an async memory has one cycle to write a value and 0 cycles to read.
By default, same-cycle accesses resolve in **program order**
(`ordering="program"`, see [Same-cycle ordering](#same-cycle-ordering) below):
a read placed before a write sees the old contents, a read placed after it
sees the new value, and the last write to an address wins. From a non-hardware
programmer's point of view, the default memory looks exactly like an array
with persistence across cycles.


Pyrope async memories behave like what a "traditional software programmer"
will expect in an array. This means that values are initialized and same-cycle
accesses follow program order. This is not what a "traditional hardware
programmer" will expect. In languages like CHISEL there is no forwarding or
initialization. Pyrope has cheaper/looser options (`ordering="fwd"`,
`ordering="none"`) for those cases, and the RTL interface for full control.


The async memories behave like tuples/arrays but there is a small difference,
the persistence of state between clock cycles. To be persistent across clock
cycles, this is achieved with a `reg` declaration. When a variable is declared
with `mut` the contents are lost at the end of the cycle, when declared with
`reg` the contents are preserved across cycles.


In most cases, the arrays and async memories can be inferred automatically. The
maximum/minimum value on the index effectively sets the size and the default
initialization is zero.

```pyrope
reg mem:[] = 0
mem[3]   = something // async memory
mut array:[] = nil
array[3] = something // array no cross cycles persistence
```

```pyrope
mut index:U7 = nil
mut index2:U6 = nil

array[index] = something
some_result  = array[index2+3]
```

In the previous example, the compiler infers that the tuple at most has 127 entries.

There are several constructs to declare arrays or async memories:

```pyrope
reg mem1:[16]S8 = 3        // mem 16 entry init/reset to 3 with type S8
reg mem2:[16]S8 = nil      // mem 16 entry, NO reset (uninitialized, type S8)
mut mem3:[] = 0sb?         // array infer size and type, 0sb? initialized
mut mem4:[13] = 0          // array 13 entries size, initialized to zero
reg mem5:[4]U3 = (1,2,3,4) // mem 4 entries 3 bits each, initialized
```

A `for` loop whose body writes a memory or a `reg` array is always unrolled,
one write per iteration; it is never kept as a compact (rolled) loop.

An input parameter may leave its length open (`x:[]U8`). Each call infers
the length from its argument and checks every element against `U8`; see
[Lambda arguments](06-functions.md#argument-naming).

The entry type and size may be generic, and so may array ports. The index
width of an `N`-entry memory is `std.clog2(N)` (see
[Attributes](04b-attributes.md)):

```pyrope
mod ram<N=16, W=8>(addr:Unsigned(bits=std.clog2(N)), din:Unsigned(bits=W), we:Bool) -> (dout:Unsigned(bits=W)@[0]) {
  reg mem:[N]Unsigned(bits=W) = 0

  dout = mem[addr]            // read before the write: old contents
  if we { mem[addr] = din }
}
```

### Same-cycle ordering

`ordering` replaces the earlier `fwd=true|false` attribute (which survives
only as the low-level per-(read,write) matrix pair — `fwd` and `undef` — in
the [RTL interface](#rtl-instantiation)).

What does a read observe when the same address is also written in the same
cycle? The `ordering` attribute on the memory declaration picks one of four
semantics. The canonical sequence:

```pyrope
reg mem:[4]U2:[ordering="program"] = 0

d1 = mem[a1]     // read BEFORE the writes
mem[a2] = d2
mem[a3] = d3
d4 = mem[a4]     // read AFTER the writes
```

| same-cycle case | `"none"` | `"old"` | `"fwd"` | `"program"` (default) |
|---|---|---|---|---|
| `a4 == a3` (read after write) | undefined | old stored value | `d3` | `d3` |
| `a1 == a2` (read before write) | undefined | old stored value | `d2` | old stored value |
| `a2 == a3` (write-write) | undefined | `d3` commits (last write wins) | undefined | `d3` commits (last write wins) |

* **`"program"`** (default): reads and writes resolve in program order, the
  software reading of the source text. This is also what `mut` arrays (no
  cross-cycle persistence) always do.
* **`"fwd"`**: pure transparency — every read of an address written this
  cycle returns the new data, regardless of the read's textual position
  (hardware forwarding has no notion of statement order). With more than one
  same-cycle writer to one address the result is undefined.
* **`"old"`**: nothing forwards, and the read is still defined — every read
  of an address written this cycle returns the committed (pre-write)
  contents, whatever its textual position. This is what the Verilog reader
  emits, because a nonblocking write is invisible to a same-timestep read.
* **`"none"`**: no ordering hardware at all — the cheapest option. Any read
  of an address written this cycle is undefined.
* **undefined** means: in simulation, a random value (simulation does not
  model `?`), so latent collisions fail loudly; in formal, a `?` — either
  value is acceptable, so equivalence can still be PROVEN when the collision
  value genuinely does not matter (which is precisely the situation where
  program-order bypass hardware was never needed). *The undefined window is
  carried explicitly down to the netlist (the `undef` matrix below, `x` on
  the generated wrapper), so any bit-blasting consumer (`pass.abc`,
  `cgen_sim`) may refine it to a concrete value. A memory whose reads must
  see committed state is `ordering="old"`, not `"none"`.*

`ordering` governs what a same-cycle *user* read observes (and the write-write
column above). Two rules hold in every ordering:

* A **partial write** `mem[a]#[lo..=hi] = v` updates the entry as the earlier
  writes of the cycle left it, so several partial writes to one entry merge
  (a later one wins where they overlap). Its own read of the entry is not a
  user read. Spelling the same update by hand
  (`mut t = mem[a]; t#[..] = v; mem[a] = t`) *is* a user read and follows
  `ordering`. A `reg` array takes a partial write as a write-MASKED port: it enables
  only the lanes it writes (the memory's `wensize`, sized to the widest lane
  every constant range is made of; a runtime position such as `mem[a]#[k]`
  needs single-bit lanes), so it needs no read port of its own, and the
  lanes of one cycle's writes merge in program order.
* A **whole-array store** (`mem = 0`, `mem = other_bus`) is a write of every
  entry at its place in program order, so against a per-entry write of the
  same cycle it resolves like two per-entry writes (under `"program"` and
  `"old"`, the later one wins).

```pyrope
reg mem:[4]U16 = nil
if wr  { mem[a] = 0xffff }
if clr { mem = 0 }             // both enabled: mem[a] is 0 (the clear is later)
if we  { mem[a]#[0..<8] = x }  // lands on the cleared entry: 0x00xx
```

A user read of such a memory sees the whole-array store like any other write:
under `"program"` when the store precedes the read, under `"fwd"` always, and
never under `"old"` or `"none"`.

Ordering is resolved per read port, so one memory can mix positions: a read
placed before the writes and another placed after them coexist in the same
cell. The netlist carries this as a PAIR of matrix parameters with the same
layout — bit `read*n_writes + write` — on the generated `cgen_memory_*`
wrapper: `fwd` (the read sees the new data) and `undef` (the read sees `x`).
They are mutually exclusive per (read, write), and both bits clear means the
read sees the committed data, which is how `"old"` differs from `"none"`.

Pyrope allows slicing of tuples and hence arrays.

```pyrope
x1 = array[first..<last]  // from first to last, last not included
x2 = array[first..=last]  // from first to last, last included
x3 = array[first..+size]  // from first to first+size, first+size. not included
```

Since tuples are multi-dimensional, arrays or async memories are multi-dimensional too.
A multi-dimensional memory lowers to one flat memory with **row-major**
addressing (`b[i][j]` on a `[4][8]` array reads flat address `i*8 + j`), and
every access must supply one index per dimension.

```pyrope
mut a:[][] = 0
a[3][4] = 1

mut b:[4][8]U8 = 13

cassert(b[2][7] == 13)
assert(b[2][10]) // error: `b[2][10]` does not exist (out of bounds)
```

It is possible to initialize the async memory with an array. A `reg` array's
initializer means exactly what a scalar `reg`'s does: it is the **reset value**
of every entry, and it is the power-on contents too (the `initial` contents —
the wrapper's `INIT` parameter / a Verilog `initial` block). Like a scalar `reg`
with a reset value, an initialized `reg` array binds the module's
[implicit reset](04b-attributes.md#implicit-clock-and-reset) — its single
`Reset` input, whatever its name — or the signal named by
`reset_pin=my_rst` (no `ref`: a `_pin` is always a connection), or mints a
`reset:Reset` input when the module declares none (a non-`Reset` input already
named `reset` is then a compile error). An instantiating caller auto-wires its
own single `Reset` to that input; a caller with two or more `Reset` inputs must
bind it explicitly. With two or more `Reset` inputs in the module itself, name
the reset with `reset_pin=`. The memory is clocked the same way: by the
module's single `Clock` input (minted as `clock:Clock` when there is none)
unless `clock_pin=` names another. The binding is by type (`Clock`/`Reset`,
see [Type system](07-typesystem.md)), never by name.

The reset is **parallel**: while the reset is asserted every entry is restored to
its initializer in one cycle, exactly like a scalar `reg`, through the memory's
whole-array reset (`async=true` makes it asynchronous; the polarity is the
register's `negreset`, see [Attributes](04b-attributes.md)).
Reset has priority over program writes and over a whole-array
update, which are suppressed for as long as the reset is held, and a suppressed
write is not forwarded to a same-cycle read: a read during reset returns the
committed contents.

`initial=<contents>` (the packed contents, entry 0 in the low `bits`) is the
same pin: next to an initializer it must spell the same value, and it is a
compile error otherwise. Spell `= nil` (or `= 0sb?`) for an array with no reset
value at all: no reset is bound and the contents are undefined until written —
or given by `initial=` alone, which is then power-on contents only.

A file preload is a separate startup contract:
`reg code:[256]U32 = std.readmemh("program.hex")` loads the image once at
simulation initialization, and reset does not reload it. The filename must be a
nonempty comptime string; Pyrope-relative paths belong to the source file.
Ordinary writes remain available, while whole-memory bulk update/reset with a
file preload is not supported. Synthesis preserves externally loadable storage
instead of specializing it to the file's contents. See
[Memory image preload](13-stdlib.md#memory-image-preload) for binary files,
initialization and formal semantics, and Verilog import behavior.

Comptime conditions fold before the memory is built, so a conditional
initializer that picks `nil` is exactly `= nil`:
`reg m:[4]U8 = if RST { 0 } else { nil }` with a false `RST` (a `const`, or a
generic bound at the call site) binds no reset, while a true `RST` gives the
fully reset memory. A parameterized memory opts out of reset that way, with no
second declaration.

A key difference between arrays (no clock) and memories is that arrays
initialization value must be `comptime` while `memories` and `reg` can have a
sequence of statements to generate a reset value.

The init contents may be a tuple **literal**, a scalar broadcast, a
`comptime`-computed initializer variable (filled by a loop), or the
inferred-type form (`reg mem2 = reset_value` below — the array type and element
envelope are inferred from the initializer).

=== "Pyrope array syntax"
    ```pyrope
    mut mem1:[4][8]U5 = 0
    comptime mut reset_value:[3][8]U5 = nil // only used during reset
    for i in 0..<3 {
      for j in 0..<8 {
        reset_value[i][j] = j
      }
    }
    reg mem2 = reset_value   // infer async mem [3][8]U5
    ```

=== "Explicit initialization"
    ```pyrope
    mut mem = (
      (U5(0), U5(0), U5(0), U5(0), U5(0), U5(0), U5(0), U5(0)),
      (U5(0), U5(0), U5(0), U5(0), U5(0), U5(0), U5(0), U5(0)),
      (U5(0), U5(0), U5(0), U5(0), U5(0), U5(0), U5(0), U5(0)),
      (U5(0), U5(0), U5(0), U5(0), U5(0), U5(0), U5(0), U5(0))
    )
    reg mem2 = (
      (U5(0), U5(1), U5(2), U5(3), U5(4), U5(5), U5(6), U5(7)),
      (U5(0), U5(1), U5(2), U5(3), U5(4), U5(5), U5(6), U5(7)),
      (U5(0), U5(1), U5(2), U5(3), U5(4), U5(5), U5(6), U5(7))
    )
    ```

## Sync memories

Pyrope asynchronous memories provide the result of the read address and update
their contents on the same cycle. This means that traditional SRAM arrays can
not be directly used. Most SRAM arrays either flop the inputs or flop the
outputs (sense amplifiers). This document calls synchronous memories the
memories that either has a flop input or an output.

There are two ways in Pyrope to instantiate more traditional synchronous
memories. Either use async memories with flopped inputs/outputs or do a
direct RTL instantiation.


### Flop the inputs or outputs

When either the inputs or the output of the asynchronous memory access is
directly connected to a flop, the flow can recognize the memory as synchronous
memory. Multi-dimensional memories lower to one flat row-major memory and
partial updates become a write-masked port (see
[Async memories or arrays](#async-memories-or-arrays)), so neither needs the
RTL instantiation.


To illustrate the point of simple single dimensional synchronous memories, this
is a typical decode stage from an in-order CPU:

=== "Flop the inputs"
    ```pyrope
    reg rf:[32]S64 = 0sb?   // random initialized

    reg a:(addr1:U5, addr2:U5) = (addr1=0, addr2=0)

    data_rs1 = rf[a.addr1]
    data_rs2 = rf[a.addr2]

    a = (addr1=insn#[8..=11], addr2=insn#[0..=4])
    ```

=== "Flop the outputs"
    ```pyrope
    mut rf:[32]S64 = 0sb?

    reg a:(data1:S64, data2:S64) = nil

    data_rs1 = a.data1
    data_rs2 = a.data2

    a = (data1=rf[insn#[8..=11]], data2=rf[insn#[0..=4]])
    ```

### RTL instantiation

There are several constraints and additional options to synchronous memories
that the async memory interface can not provide, such as a negative edge
clock...


Pyrope allows for a direct call to LiveHD cells with the RTL instantiation, as
such that memories can be created directly.

```pyrope
// A 2rd+1wr memory (RF type)

mut res = __memory(
  addr      = (raddr0, raddr1, wraddr),
  bits      = 4,
  size      = 16,
  din       = (0, 0, din0),
  enable    = (1, 1, we0),
  fwd       = false,
  `type`      = 1,         // 0: async, 1: sync, 2: array
  wensize   = 1,         // we bit (no write mask)
  rdport    = (1, 1, 0), // 1: read port, 0: write port
)

q0 = res[0]
q1 = res[1]
```

The previous code directly instantiates a memory and passes the configuration.
Like every `__` cell call, it binds each argument by name, and the
configuration vocabulary is the per-port/config subset of the LiveHD
`Memory` cell sink pins, with backticks around reserved names such as
`` `type` ``
(`addr`/`bits`/`clock_pin`/`din`/`enable`/`fwd`/`undef`/`posclk`/`` `type` ``/
`wensize`/`size`/`rdport`/`initial`). The cell-level `fwd` pin is the
per-(read-port, write-port) forwarding matrix — bit `r*n_wr + w` — that the
surface `ordering` attribute lowers to, and `undef` is its twin for
`ordering="none"`: same layout, mutually exclusive per (r,w), with `fwd` set
meaning the read sees the NEW data, `undef` set meaning `x`, and both clear
meaning the COMMITTED data. There is no `latency` field — `type` selects async
(0, combinational read of the current address), sync (1, one-cycle read) or
array (2, unclocked); the optional `clock_pin` defaults to the module's
[implicit clock](04b-attributes.md#implicit-clock-and-reset) (its single
`Clock` input),
and `initial` provides comptime initial contents (a tuple literal or a packed
constant, entry 0 in the low `bits`). The call returns an unnamed tuple:
`res[N]` returns the data of the N-th read port (in
`rdport` order). From a timing point of view a memory is treated like a
register: reads return committed state at `@[0]`; for a sync memory the extra
cycle is the time the write takes to commit.

A memory can also be bound to a specific memory-compiler macro with the
`macro` attribute (TBD: not yet implemented); the toolchain maps the access
ports onto the macro:

```pyrope
reg ram:[1024]U32:[macro="sram_32kx32"] = 0
```


## Shared memories with `regref`

!!! WARNING "Not implemented"
    The *synthesizable* string-path `regref` described here — the one that
    resolves across the elaborated hierarchy and may match zero or many cells —
    is TBD. This section records its intended design. The `test`-block
    [`regref`](05b-statements.md#test-only-statements), which binds
    exactly one cell, is a different construct and is implemented; a testbench
    ref onto a memory word reads the **committed** contents, matching the
    remote-reader rule below. See [Implementation status](15-tbd.md).

ASIC memories want to be *physically* grouped — BIST and repair logic is too
expensive to replicate per memory, memory compiler instances carry setup
pins, and power domains or floorplan regions constrain placement. But the
*logical* owner of a memory usually sits deep in the module hierarchy, and
threading its ports through many levels of instantiation is boilerplate
that obscures the design.

Pyrope reconciles the two hierarchies with `regref` (see
[Visibility](04-variables.md#visibility-private-by-default-pub-to-export)
and [Register reference](07-typesystem.md#register-reference)): the
physical owner declares the memory, and the logical owner attaches to it by
hierarchy path or name from elsewhere in the instantiated design. The memory is
not imported and must not be declared `pub reg`.

```pyrope
// file: mem_pool.prp — physical owner: placement, BIST, repair
mod mem_pool(test_mode:Bool) -> () {
  reg buf0:[1024]U8 = nil
  reg buf1:[1024]U8 = nil

  if test_mode {
    // shared BIST/repair: march patterns over buf0/buf1 written once,
    // muxed here — the one place that legally owns all pooled memories
  }
}

// file: engine.prp — logical owner: the functional reads and writes
mod engine(addr:U10, din:U8, we:Bool) -> (dout:U8@[0]) {
  mut buf:[1024]U8 = regref("mem_pool/buf0") // type checked at elaboration

  dout = buf[addr]              // reads the committed 'q' state -> @[0]
  if we { buf[addr] = din }     // this is the single functional writer
}
```

The semantics follow from "an attached `regref` behaves like a local
`reg`":

* **Timing types are unchanged.** A memory is a state register for stage
  inference ([pipelining](06c-pipelining.md)) whether it is local or
  attached. Each attach site pins at its own stage; sites at different
  pipeline stages are legal, and the compiler can report the write-to-read
  visibility distance between them.
* **Sequential by construction.** Remote reads return `q`; remote writes
  drive `din`. Every cross-module connection crosses the flop boundary, so
  an attached memory can never create a combinational path between distant
  modules. For the same reason, **same-cycle visibility never crosses a
  `regref`**: in-cycle ordering (`ordering="program"` read-after-write, or
  `ordering="fwd"`) applies only to accesses local to the owning module;
  remote readers always see the last committed state.
* **One functional writer.** The single-writer-multiple-reader rule is
  checked globally at elaboration across local and attached accesses.
  BIST-style logic in the owner is the one sanctioned exception: an
  owner-local write guarded by a test mode, with the obligation (assert)
  that test and functional accesses are disjoint.
* **`ordering="none"` is value-level, not timing-level.** A read of an
  address with a write in flight returns undefined data — simulation
  randomizes the value so latent collisions fail loudly (formal treats it as
  `?`). Where collision freedom matters, assert it
  (`assert(!we or raddr != waddr)`).

In the generated netlist, every attach lowers to punched ports threaded
through the hierarchy: downstream tools (LEC, PD, DFT) see ordinary module
ports, never hierarchical references. A `regref` path is therefore part of the
elaborated hardware contract: renaming, removing, or moving the referenced
register can break downstream attach sites.


## Multidimensional arrays


Pyrope supports multi-dimensional arrays, it is possible to slice the array by
dimension. The entries are in a row-major order.


```pyrope
mut d2:[2][2] = ((1,2),(3,4))
cassert(d2[0][0] == 1 and d2[0][1] == 2 and d2[1][0] == 3 and d2[1][1] == 4)

cassert(d2[0] == (1,2) and d2[1] == (3,4))
```

The `for` iterator goes over each entry of the tuple/array. If a matrix, it
does in row-major order. This allows building a simple function to flatten
multi-dimensional arrays.

```pyrope
comb flatten(arr) -> (res) {
  res = ()
  for i in arr {
    res = (...res, i)
  }
}

cassert(flatten(d2) == (1,2,3,4))
cassert(flatten(arr=((((1),2),3),4)) == (1,2,3,4))
cassert(flatten((((1),2),3),4) == (1,2,3,4))  // one ordinary tuple parameter: outer parentheses may be omitted
```

## Array index

Array index by default are unsigned integers, but the index can be constrained
with tuples or by requiring an enumerate.


```pyrope
mut x1:[2]U3 = (0,1)
cassert(x1[0] == 0 and x1[1] == 1)

enum X = (
  t1 = 0, // sequential enum, not one hot enum (explicit assign)
  t2,
  t3
)

mut x2:[X]U3 = nil
x2[X.t1] = 0
x2[X.t2] = 1
x2[0]              // error: only enum index

mut x3:[-8..<7]U3 = nil  // accept signed values

mut x4:[100..<132]U3 = nil

cassert(x4[100] == 0)
assert(x4[3]) // error: out of bounds index
```

### Reset and initialization

Like the `const` and `mut` statements, `reg` statements require an initialization
value. While `const`/`mut` initialize every cycle, the `reg` initialization is the
value to set during reset.


Like in `const`/`mut` cases, the reset/initialization value can use the traditional
Verilog uninitialized (`0sb?`) contents. The Pyrope semantics for any bit with
`?` value is to respect arithmetic Verilog semantics at compile time, but to
randomly generate a zero/ones for each simulation. As a result assertions can
fail with unknowns.


```pyrope
reg r_ver = 0sb?

reg r = nil
mut v = nil

assert(v == 0 and r == 0)

assert(!(r_ver != 0)) // it will randomly fail
assert(!(r_ver == 0)) // it will randomly fail
assert(!(r_ver != 0sb?)) // it will randomly fail
assert(!(r_ver == 0sb?)) // it will randomly fail
```


An initialized array is restored in one cycle of reset (see
[Async memories or arrays](#async-memories-or-arrays)), but until then its
contents are unknown, which can lead to unexpected results around the reset
period. Memories and registers are randomly initialized before reset during
simulation. There is no guarantee of zero initialization before reset. The
reset is observed through the module's `Reset` input (see
[Implicit clock and reset](04b-attributes.md#implicit-clock-and-reset)), not
through a field of the memory.

```pyrope
mod m(rst:Reset) -> () {
  reg mem:[] = (0,1,2,3,4,5,6,7)

  assert_always(mem[7] == 7)     // may FAIL: checked before and during reset
  if not Bool(rst) {
    assert_always(mem[7] == 7)   // may FAIL: random contents before the first reset
  }
  assert(mem[7] == 7)            // OK, not checked during reset
}
```
