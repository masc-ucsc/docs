# Memories

A significant effort of hardware design revolves around memories. Unlike Von Neumann models, the memories
must be explicitly managed. Some list of concerns when designing memories in ASIC/FPGAs:

* Reads and Writes may have different number of cycles to take effect
* Reset does not initialize memory contents
* There may not be forwarding if a read and a write happens in the same cycle
* ASIC memories come from memory compilers that require custom setup pins and connections
* FPGA memories tend to have their own set of constrains too
* Logic around memories like BIST has to be added before fabrication

This constrains the language, it is difficult to have a typical vector/memory provided by the language
that handles all these cases. Instead the complex memories are managed by the Pyrope standard library.


The flow directly supports arrays/memories in two ways:

* Async memories or arrays
* RTL instantiation

## Async memories or arrays

In Pyrope, an async memory has 1 cycle to write a value and 0 cycles to read.
The memory has forwarding by default which makes it behave like a 0 cycle
read/write. From a traditional programmer, this memory looks like an array.


Pyrope async memories behave like a non-hardware programmer will expect in an
array.  This means that values are initialized and there is forwarding enabled.
It is possible to have different options of async memories, but those should
use the RTL interface.


The bundles allow ordered unnamed accessed, this is in-fact an async memory or
an array. The async memories behave like arrays but there is a small
difference, the persistence of state between clock cycles. To be persistent
across clock cycles, the same flop modifier is applied (`#`).

In most cases, the arrays and async memories can be inferred automatically. The
maximum/minimum value on the index effectively sets the size, and the default
initialization is zero.

```
#mem[3]  = something // async memory
array[3] = something // array no cross cycles persistence
```

```
var index:u7
var index2:u6

array[index] = something
some_result  = array[index2+3]
```

The previous example, the compiler infers that the bundle at most has 127 entries.

Looking at multiple programming languages, the 3 most common keywords to query
for the size of an array are `count`, `length`, `len`, or `size`. Pyrope being
a stone similar to a Ruby, uses the same `size` keyword as Ruby, but it has the
double underscore for the attribute (`__size`).

```
#mem1 = (__size=16,__init=0:i16) // 16bit memory initialized to 0 with type i16
#mem2 = (__init=nil)             // infer size, initialized to nil
#mem3 = (__init=0sb?)            // infer size, 0sb? initialized
#mem4 = (__size=13)              // 13 entries size, initialized to zero
```



Pyrope allows slicing of bundles and hence arrays.

```
x1 = name[first..<last]  // from first to last, last not included
x2 = name[first..=last]  // from first to last, last included
x3 = name[first..+size]  // from first to first+size, first+size. not included
```

Since bundles are multi-dimensional, arrays or async memories are multi-dimensional too.

```
a[3][4] = 1

b = (
  ,__size=4
  ,__init=:(
    ,__size=8
    ,__init=13:u8
  )
)
assert b[2][7] == 13
assert b[2][10]      // compile error, '10' is out of bound access for 'b[2]'
```

Since the previous syntax is a bit low level, a syntax sugar equivalent
functionality is provided by the Pyrope for simple regular arrays. In this
example, `#mem1`, `#mem2`, and `#mem3` are identical.

```
var #mem1:[4][8] = 0:u5
var #mem2:(_size=4, __init=(__size=8,__init=0:u5)
var #mem3:( 
  ,(0:u5, 0:u5, 0:u5, 0:u5, 0:u5, 0:u5, 0:u5, 0:u5)
  ,(0:u5, 0:u5, 0:u5, 0:u5, 0:u5, 0:u5, 0:u5, 0:u5)
  ,(0:u5, 0:u5, 0:u5, 0:u5, 0:u5, 0:u5, 0:u5, 0:u5)
  ,(0:u5, 0:u5, 0:u5, 0:u5, 0:u5, 0:u5, 0:u5, 0:u5)
)
            
```

## RTL instantiation

Multi cycle memories can not use the array syntax. Pyrope allows for a direct
call to LiveHD cells with the RTL instantiation, as such the memories can be
created directly.

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

res = __memory(mem)

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
* `latency`: Number of cycles (`0` or `1`) when the result has effect
* `wensize`: Write enable size allows to have a write mask. The default value
  is 1, a wensize of 2 means that there are 2 bits in the `enable` for each
  port. a wensize 2 with 2 ports has a total of 2+2+2 enable bits. Bit 0 of the
  enable controls the lower bits of the memory entry selected.
* `rdport`: Indicates which of the ports are read and which are write ports.
* `posclk`: Positive edge clock memory. The default is `true` but it can be set to `false`.


Multi cycle memories are pipelined elements, and such using them requires to use the `=#` assignment
and the same rules as pipeline flops apply (See [pipelining](06b-pipelining.md)).


