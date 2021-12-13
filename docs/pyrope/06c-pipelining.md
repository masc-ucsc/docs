# Pipelining


## Registers

Together with memories, flip-flops or latches are the basic constructs used by
hardware to store information and to build pipeline stages. Pyrope's goal is to
be a zero-cost overhead, and as such it allows to handle flops directly.


To create an individual flop, a direct RTL instantiation of a `__flop` can be
used. Flops and latches have several pins `din`, `q`, `clock`, `enable` and
configuration options `posclk`, `initial`, and `async`. 


A more programmer-friendly is to use to declare a register. The compiler does
not provide guarantees that the register will not be split into multiple
registers.


In this example, `my_flop1_q and my_flop2_q` are equivalent.

```
my_flop1_q = __flop(din=my_din, reset=my_rst, clock=my_clk
                   ,enable=my_enable, posclk=true, initial=3, async=false)

reg my_flop2 = (reset=my_rst, clock=my_clk, posclk=true, initial=3, async=false)
let my_flop2_q = my_flop2

if my_enable {
  my_flop2 = my_din
}
```

Flops have `din` and a `q` pin. At the beginning of the cycle both `din` and
`q` have the same value, but as the `din` is updated with "next cycle" `q`
value their contents may be different. Different HDLs have different syntax to
distinguish between `din` and `q` pin. In Verilog is common to have a coding
style guideline that gives a different name to the din variables than to the q
variables (E.g: `something_q` vs `something_next`).

In Pyrope the `something` points to the `din` pin. This is the value to
update.  To have the `q` pin contents there are two ways. Read it before being
updated, or use the pipeline directive `something#[0]`.


If the register is accessed with the `-1` cycle (`#something#[-1]`), the flop will
insert an additional pipeline to access 1 cycle before flop contents.


Latches are possible but with the direct RTL instantiation. Latches have 
a `din` and `enable` pin like a flop, but just one option `posclk`.

```
my_latch_q = __latch(din=my_din, enable=my_enable, posclk=true)
```

## Pipestage

One of the fundamental differences between most programming languages and
hardware description languages is that pipelining is a fundamental feature that
must be used in hardware but not in software designs.


Pyrope has a `pipestage` statement that helps to create simple pipeline stages.
The syntax for pipestage:

```
// variables/register before

{
  // stage 0 scope
} #> {
  // stage 1 scope
} ... {
  // stage n scope
}

// variables/register after pipestage
```

The semantics of `pipestage` are as follows:

* Explicitly declared registers are not affected by `pipestage`

* Variables declared before are "pipelined" inside each of the `pipestage` scopes.

* Variables declared in the stage `i` are pipelined to all the stages after `i`
  when they are locally declared `pub`.

* The pipelined variables are not visible in the scope after the `pipestage`
  sequence.

* The original non-pipelined variable can be accessed with `v#[0]`.


To illustrate the semantics, imagine a module where the input `i` is a
monotonically increasing sequence (`0,1,2,3,4,5,6,7....`).


```
assert i==0 or (i#[-1] + 1 == i)

let i_let = i

var i_var0 = i
var i_var1
i_var1 = i

reg i_reg0 = i   // initialization only
reg i_reg1
i_reg1 = i       // every cycle


{
  assert i == i#[0]       // i#[0] is unflop input (or first defined) value
  assert i == i_let
  assert i == i_var0
  assert i == i_var1

  assert 0 == i_reg0
  assert i == i_reg1

  let local_var = 3

  pub let pub_var = 100 + i

} #> {
  assert local_var!=0       // compile error, local_var is not in scope
  assert pub_var == 100 + i // pipelined pub_var

  // both inputs and variables flop, so asserts hold
  assert i == i_let
  assert i == i_var0
  assert i == i_var1

  assert 0 == i_reg0        // i_reg0 never changes, so 0 is fine
  assert i#[-1] == i_reg1   // last i-reg, not current

  assert i == 0 or (i == i#[0]+1)  // i#[0] is the unflop original
}

assert pub_var != 0 // compile error, pub_var is not in scope
```


## Retiming

The registers manually inserted with the `reg` directive are preserved
and annotated so that synthesis retiming can not change them.


A register can be marked with the `retime` flag, in which case the synthesis
tools are allowed to perform the following optimizations:

* Retime or move logic across which effectively changes the meaning of the register.

* Duplication is allowed when frequency improvements grant it.

* Elimination. If there are no reads or no writes, the register can be remove
  and replaced with a constant (no writes) or just removed (no reads).

* Copy propagation is allowed across registers. This is not possible without
  retime because the scan chain could reconfigure the flop.


The registers automatically inserted with the `pipestage` command are marked
with `retime` true. Additionally, retime can be set in any register:

```
reg my_reg:(retime=true,clock=my_clk)
```


## Multiply-Add example

To illustrate the confusion/complication the following example illustrates a
multiplier that takes 3 cycles and an adder that takes 1 cycle to complete, and
the conceptual problems of integrating them:


=== "Pipestage"
    ```
    pub let block = #{|(in1,in2)->(out)|
      {
        pub let tmp = in1 * in2
      } #> {
        // extra cycle for multiply
      } #> {
        // extra cycle for multiply
      } #> {
        out = tmp + in1#[0]
      }
    }
    ```

=== "Explicit Stages"

    ```
    let add1 = #{|a,b| // 1 cycle add
      #reg = a+b
      ret #reg
    }
    let mul3 = #{|a,b| // 3 cycle multiply
      #reg1 = $a * $b
      #reg2 = #reg1
      #reg3 = #reg2
      ret #reg3
    }

    pub let block = #{|(in1,in2)->(out)|
      let x =# mul3(in1, in2)
      out   =# add1(x,in3)
    }
    ```

In general, `#` is used when dealing with registers. The previous example use
`procedures` (`#{||...}`) instead of `functions` (`{||...}`) because functions
only have combinational logic. When the procedures are called, the assigned
variable needs the `=#`. This is to explicitly indicate to Pyrope that the
function called (`mul3`, `add1`) can have pipeline outputs. This helps the tool
but more importantly the programmer because it helps to check assumptions about
the function connections. The typical assignment `=` only connects
combinational logic.


The previous code connects two inputs (`in1`/`in2`) to a multiplier, and then
connects the result of the multiplier to an adder. The inputs are also
passed to the adder. This results in the following functionality:

``` mermaid
graph LR
    in1[in1] --a--> m0(mul3 cycle 0)
    in2[in2] --b--> m0

    m0 --> m1(mul3 cycle 1)
    m1 --> m2(mul3 cycle 2)

    in1--a--> a0[add1 cycle 1]
    m2 --b--> a0
    a0 --> out[out]
```


The issue in most HDLs is that the connection is unaware of the pipelining, and
it is left up to the programmer to understand and check the potential pipeline
stages inside `add1` and `mul3`. This lack of pipelining awareness in the
language syntax is common in most HDLs.

In Pyrope, the `=#` must be used when there is any path that starts from the
inputs of the function passes through a pipeline stage to generate the
assignment. If all the paths have exactly 1 flop in between, it is a 1 stage
pipeline, if some paths have 2 flops and others 3, it is a 2 or 3 pipeline
stages. Sometimes, there are loops, and the tool has 1 to infinite pipeline
stages.


The default pipeline assignment `=#` just checks that it is possible to have
pipeline stages between the module/function inputs and the assignment value. To
restrict the check, it accepts a range. E.g: `=#[3]` means that there are
exactly 3 flops or cycles between inputs and the assignment. `=#[0..<4]` means
that there are between 0 and 3 cycles, and open range could be used when there
are loops (E.g: `=#[2..]`).

```
let x = mul3(in1, in2)      // compile error: 'mul3' is pipelined
let x =# mul3(in1, in2)     // OK
%out  =# add1(x,in3)        // OK (in3 has 0 cycles, x has 3 cycles)
%out  =#[1] add1(x,in3)     // compile error: 'x' is pipelined with '3' cycles
%out  =#[3] add1(x,in3)     // compile error: 'in3' is pipelined with '1' cycle
%out  =#[1..<4] add1(x,in3) // OK
```



The designer likely wanted to implement a multiply-add. As such,
the input to the adder should be from the same cycle as the multiplied started
to operate. Otherwise, values across cycles are mixed.

``` mermaid
graph LR
  in1[in1] --a--> m0(mul3 cycle 0)
  in2[in2] --b--> m0

  m0 --> m1(mul3 cycle 1)
  m1 --> m2(mul3 cycle 2)

  in1  --> in1_0(flop cycle 0)
  in1_0--> in1_1(flop cycle 1)
  in1_1--> in1_2(flop cycle 2)
  in1_2--a--> a0[add1 cycle 0]
  m2 --b--> a0
  a0 --> out[out]
```

It is possible to balance the pipeline stages explicitly, the issue is that it
is error-prone because it requires knowing exactly the number of cycles for
`mul3`. 

=== "Pipestage"
    ```
    {
      pub tmp = in1 * in2
    } #> {
      // extra cycle for multiply
    } #> {
      // extra cycle for multiply
    } #> {
      out = tmp + in1
    }
    ```

=== "Explicitly added pipeline stages"

    ```
    x =# mul3(in1, in2)
    y = in1#[-3]
    %out =# add1(a=x,b=y)    // connect in1 from -3 cycles
    ```

!!! Observation

    The explicit `v#[-cycles]` inserts registers and access the result `cycles`
    before. This same syntax can be used with assertions similar to the Verilog
    `$past(v, cycles)`.

