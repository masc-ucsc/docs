# Memories

A significant effort of hardware design revolves around memories. Unlike Von
Neumann models, the memories must be explicitly managed. Some list of concerns
when designing memories in ASIC/FPGAs:

* Reads and Writes may have different number of cycles to take effect
* Reset does not initialize memory contents
* There may not be forwarding if a read and a write happen in the same cycle
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
async memories preserve the array contents across cycles while the array
contents are cleared at the end of each cycle.


In Pyrope, an async memory has 1 cycle to write a value and 0 cycles to read.
The memory has forwarding by default which makes it behave like a 0 cycle
read/write. From a traditional programmer, this memory looks like an array
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
with `var` the contents are lost at the end of the cycle, when declared with
`reg` the contents are preserved across cycles.


In most cases, the arrays and async memories can be inferred automatically. The
maximum/minimum value on the index effectively sets the size and the default
initialization is zero.

```
reg mem:[]
mem[3]   = something // async memory
var array:[]
array[3] = something // array no cross cycles persistence
```

```
var index:u7
var index2:u6

array[index] = something
some_result  = array[index2+3]
```

In the previous example, the compiler infers that the bundle at most has 127 entries.

There are several constructs to declare arrays or async memories:

```
reg mem1:i8[16] = 3       // mem 16bit memory initialized to 3 with type i8
reg mem2:i8[16]           // mem 16bit memory initialized to 0 with type i8
var mem3:[] = 0sb?        // array infer size and type, 0sb? initialized
var mem4:[13]             // array 13 entries size, initialized to zero
```

Pyrope allows slicing of bundles and hence arrays.

```
x1 = array[first..<last]  // from first to last, last not included
x2 = array[first..=last]  // from first to last, last included
x3 = array[first..+size]  // from first to first+size, first+size. not included
```

Since bundles are multi-dimensional, arrays or async memories are multi-dimensional too.

```
a[3][4] = 1

var b:u8[4][8] = 13

assert b[2][7] == 13
assert b[2][10]      // compile error, '10' is out of bound access for 'b[2]'
```

It is possible to initialize the async memory with an array. The initialization
of async memories happens whenever `reset` is set on the system. Notice that
the memories reset value must be a `comptime` or a compilation error will be
triggered.

=== "Pyrope array syntax"
    ```
    var mem1:u5[4][8] = 0
    comptime var reset_value:u5[3][8]  // only used during reset
    for i in 0..<3 {
      for j in 0..<8 {
        reset_value[i][j] = j
      }
    }
    reg mem2 = reset_value   // infer async mem u5[3][8]
    ```

=== "Explicit initialization"
    ```
    var mem:( 
      ,(u5(0), u5(0), u5(0), u5(0), u5(0), u5(0), u5(0), u5(0))
      ,(u5(0), u5(0), u5(0), u5(0), u5(0), u5(0), u5(0), u5(0))
      ,(u5(0), u5(0), u5(0), u5(0), u5(0), u5(0), u5(0), u5(0))
      ,(u5(0), u5(0), u5(0), u5(0), u5(0), u5(0), u5(0), u5(0))
    )
    reg mem2:( 
      ,(u5(0), u5(1), u5(2), u5(3), u5(4), u5(5), u5(6), u5(7))
      ,(u5(0), u5(1), u5(2), u5(3), u5(4), u5(5), u5(6), u5(7))
      ,(u5(0), u5(1), u5(2), u5(3), u5(4), u5(5), u5(6), u5(7))
    )
    ```

## Sync Memories

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
    ```
    reg rf:i64[32]

    reg a:(addr1:u5, addr2:u5)

    data_rs1 = rf[a.addr1]
    data_rs2 = rf[a.addr2]

    a = (insn[8..=11], insn[0..=4])
    ```

=== "Flop the outputs"
    ```
    reg rf:i64[32]

    reg a:(data1:i64, data2:i64)

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

```
// A 2rd+1wr memory (RF type)

mem.addr    = ($raddr0, $raddr1, $wraddr)
mem.bits    = 4
mem.size    = 16
mem.clock   = $my_clock
mem.din     = (0, 0, $din0)
mem.enable  = (1, 1, $we0)

mem.fwd     = false
mem.latency = (1, 1, 1)
mem.wensize = 1 // we bit (no write mask)
mem.rdport  = (-1,1,0) // 0 WR, !=0 -> RD

res =# __memory(mem)

%q0 = res.0
%q1 = res.1

```

The previous code directly instantiates a memory and passes the configuration. The
memory attributes:

* `addr`: Address ports for the memory. In the example port 0 is `$raddr0`, and port 2 is `$wraddr`
* `bits`: The number of bits for each memory entry
* `size`: The number of entries. Total size in bits is $size x bits$.
* `clock`: Optional clock pin, `clock` by default. A bundle is possible to specify the clock for each address port.
* `din`: Data in port. The read ports must be hardwired to a constant like `0`.
* `enable`: Enable bundle for each memory port
* `fwd`: Forwarding guaranteed (true/false). If fwd is false, there is no guarantee, it can have fwd or not.
* `latency`: Number of cycles (`0` or `1`) when the read is performed
* `wensize`: Write enable size allows to have a write mask. The default value
  is 1, a wensize of 2 means that there are 2 bits in the `enable` for each
  port. a wensize 2 with 2 ports has a total of 2+2+2 enable bits. Bit 0 of the
  enable controls the lower bits of the memory entry selected.
* `rdport`: Indicates which of the ports are read and which are written ports.
* `posclk`: Positive edge clock memory. The default is `true` but it can be set to `false`.


Multi cycle memories are pipelined elements, and using them requires the `=#` assignment
and the same rules as pipeline flops apply (See [pipelining](06b-pipelining.md)).


## Multidimensional arrays


Pyrope supports multi-dimensional arrays, it is possible to slice the array by
dimension. The entries are in a row-major order.


```
var d2:[2][2] = ((1,2),(3,4))
assert d2[0][0] == 1 and d2[0][1] == 2 and d2[1][0] == 3 and d2[1][1] == 4

assert d2[0] == (1,2) and d2[1] == (2,3)
```

The `for` iterator goes over each entry of the bundle/array. If a matrix, it
does in row-major order. This allows building a simple function to flatten
multi-dimensional arrays.

```
let flatten = {|arr|
  var res
  for i in arr {
    res ++= i
  }
  ret res
}

assert flatten(d2) == (1,2,3,4)
assert flatten((((1),2),3),4) == (1,2,3,4)
```
