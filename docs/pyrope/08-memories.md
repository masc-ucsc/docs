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
The memory has forwarding by default, which behaves like a 0 cycle
read/write. From a non-hardware programmer, the default memory looks like an array with
persistence across cycles.


Pyrope async memories behave like what a "traditional software programmer" will
expect in an array. This means that values are initialized and there is
forwarding enabled. This is not what a "traditional hardware programmer" will expect.
In languages like CHISEL there is no forwarding or initialization. In Pyrope is
possible to have different options of async memories, but those should use the
RTL interface.


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
mut index:u7 = nil
mut index2:u6 = nil

array[index] = something
some_result  = array[index2+3]
```

In the previous example, the compiler infers that the tuple at most has 127 entries.

There are several constructs to declare arrays or async memories:

```pyrope
reg mem1:[16]i8 = 3        // mem 16 entry init to 3 with type i8
reg mem2:[16]i8 = nil      // mem 16 entry init to 0 with type i8
mut mem3:[] = 0sb?         // array infer size and type, 0sb? initialized
mut mem4:[13] = 0          // array 13 entries size, initialized to zero
reg mem5:[4]i3 = (1,2,3,4) // mem 4 entries 3 bits each, initialized
```

Pyrope allows slicing of tuples and hence arrays.

```pyrope
x1 = array[first..<last]  // from first to last, last not included
x2 = array[first..=last]  // from first to last, last included
x3 = array[first..+size]  // from first to first+size, first+size. not included
```

Since tuples are multi-dimensional, arrays or async memories are multi-dimensional too.

```pyrope
mut a:[][] = 0
a[3][4] = 1

mut b:[4][8]u8 = 13

cassert(b[2][7] == 13)
assert(b[2][10]) // error: '10' is out of bound access for 'b[2]'
```

It is possible to initialize the async memory with an array. The initialization
of async memories happens whenever `reset` is set on the system. A key difference
between arrays (no clock) and memories is that arrays initialization value must
be `comptime` while `memories` and `reg` can have a sequence of statements to
generate a reset value.

=== "Pyrope array syntax"
    ```pyrope
    mut mem1:[4][8]u5 = 0
    comptime mut reset_value:[3][8]u5 = nil // only used during reset
    for i in 0..<3 {
      for j in 0..<8 {
        reset_value[i][j] = j
      }
    }
    reg mem2 = reset_value   // infer async mem u5[3][8]
    ```

=== "Explicit initialization"
    ```pyrope
    mut mem = (
      (u5(0), u5(0), u5(0), u5(0), u5(0), u5(0), u5(0), u5(0)),
      (u5(0), u5(0), u5(0), u5(0), u5(0), u5(0), u5(0), u5(0)),
      (u5(0), u5(0), u5(0), u5(0), u5(0), u5(0), u5(0), u5(0)),
      (u5(0), u5(0), u5(0), u5(0), u5(0), u5(0), u5(0), u5(0))
    )
    reg mem2 = (
      (u5(0), u5(1), u5(2), u5(3), u5(4), u5(5), u5(6), u5(7)),
      (u5(0), u5(1), u5(2), u5(3), u5(4), u5(5), u5(6), u5(7)),
      (u5(0), u5(1), u5(2), u5(3), u5(4), u5(5), u5(6), u5(7))
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
directly connected to a flop, the flow can recognize the memory as asynchronous memory. A further constrain is that only single dimension memories.
Multi-dimensional memories or memories with partial updates need to use the
RTL instantiation.


To illustrate the point of simple single dimensional synchronous memories, this
is a typical decode stage from an in-order CPU:

=== "Flop the inputs"
    ```pyrope
    reg rf:[32]i64 = 0sb?   // random initialized

    reg a:(addr1:u5, addr2:u5) = (0,0)

    data_rs1 = rf[a.addr1]
    data_rs2 = rf[a.addr2]

    a = (insn[8..=11], insn[0..=4])
    ```

=== "Flop the outputs"
    ```pyrope
    mut rf:[32]i64 = 0sb?

    reg a:(data1:i64, data2:i64) = nil

    data_rs1 = a.data1
    data_rs2 = a.data2

    a = (rf[insn[8..=11]], rf[insn[0..=4]])
    ```

### RTL instantiation

There are several constraints and additional options to synchronous memories
that the async memory interface can not provide: multi-dimension, partial updates,
negative edge clock...


Pyrope allows for a direct call to LiveHD cells with the RTL instantiation, as
such that memories can be created directly.

```pyrope
// A 2rd+1wr memory (RF type)

mem.addr    = (raddr0, raddr1, wraddr)
mem.bits    = 4
mem.size    = 16
mem.clock   = my_clock
mem.din     = (0, 0, din0)
mem.enable  = (1, 1, we0)

mem.fwd     = false
mem.latency = (1, 1, 1)
mem.wensize = 1 // we bit (no write mask)
mem.rdport  = (-1,1,0) // 0 WR, !=0 -> RD

stage[1..<inf] res = __memory(mem)

q0 = res[0]
q1 = res[1]

```

The previous code directly instantiates a memory and passes the configuration.


Multi cycle memories are pipelined elements, and using them requires the `stage[1..<inf]`
declaration modifier and the same rules as pipeline flops apply (See [pipelining](06c-pipelining.md)).


## Shared memories with `pub reg` and `regref`

ASIC memories want to be *physically* grouped — BIST and repair logic is too
expensive to replicate per memory, memory compiler instances carry setup
pins, and power domains or floorplan regions constrain placement. But the
*logical* owner of a memory usually sits deep in the module hierarchy, and
threading its ports through many levels of instantiation is boilerplate
that obscures the design.

Pyrope reconciles the two hierarchies with `pub reg` and `regref` (see
[Visibility](04-variables.md#visibility-private-by-default-pub-to-export)
and [Register reference](07-typesystem.md#register-reference)): the
physical owner declares the memory `pub`, and the logical owner attaches to
it from anywhere in the instantiation hierarchy.

```pyrope
// file: mem_pool.prp — physical owner: placement, BIST, repair
mod mem_pool(test_mode:bool) {
  pub reg buf0:[1024]u8 = nil   // synthesizable regref may attach
  pub reg buf1:[1024]u8 = nil

  if test_mode {
    // shared BIST/repair: march patterns over buf0/buf1 written once,
    // muxed here — the one place that legally owns all pooled memories
  }
}

// file: engine.prp — logical owner: the functional reads and writes
mod engine(addr:u10, din:u8, we:bool) -> (dout:u8@[0]) {
  mut buf:[1024]u8 = regref("mem_pool/buf0") // type checked at elaboration

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
  modules. For the same reason, **forwarding never crosses a `regref`**:
  in-cycle forwarding (`fwd=true`) applies only to accesses local to the
  owning module; remote readers always see the last committed state.
* **One functional writer.** The single-writer-multiple-reader rule is
  checked globally at elaboration across local and attached accesses.
  BIST-style logic in the owner is the one sanctioned exception: an
  owner-local write guarded by a test mode, with the obligation (assert)
  that test and functional accesses are disjoint.
* **`fwd=false` is value-level, not timing-level.** A read of an address
  with a write in flight returns undefined data — simulation randomizes the
  value so latent collisions fail loudly. Where collision freedom matters,
  assert it (`assert(!we or raddr != waddr)`).

In the generated netlist, every attach lowers to punched ports threaded
through the hierarchy: downstream tools (LEC, PD, DFT) see ordinary module
ports, never hierarchical references. The `pub` surface of a module is
enumerable, like its ports — renaming or removing a `pub reg` is an
interface change.


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
comb flatten(...arr) -> (res) {
  res = ()
  for i in arr {
    res ++= i
  }
}

cassert(flatten(d2) == (1,2,3,4))
cassert(flatten((((1),2),3),4) == (1,2,3,4))
```

## Array index

Array index by default are unsigned integers, but the index can be constrained
with tuples or by requiring an enumerate.


```pyrope
mut x1:[2]u3 = (0,1)
cassert(x1[0] == 0 and x1[1] == 1)

enum X = (
  t1 = 0, // sequential enum, not one hot enum (explicit assign)
  t2,
  t3
)

mut x2:[X]u3 = nil
x2[X.t1] = 0
x2[X.t2] = 1
x2[0]              // error: only enum index

mut x3:[-8..<7]u3 = nil  // accept signed values

mut x4:[100..<132]u3 = nil

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


The reset for arrays may take several cycles to take effect, this can lead to
unexpected results during the reset period. Memories and registers are randomly
initialized before reset during simulation. There is no guarantee of zero
initialization before reset.

```pyrope
mut arr:[] = (0,1,2,3,4,5,6,7)

always_assert(arr[0] == 0 and arr[7] == 7) // may FAIL during reset

reg mem:[] = (0,1,2,3,4,5,6,7)

always_assert(mem[7] == 7) // may FAIL during reset
always_assert(mem[7] == 7) unless mem.reset // OK
assert(mem[7] == 7) // OK, not checked during reset
```
