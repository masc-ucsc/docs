# Pipelining


## Registers

Together with memories, flip-flop or latches are the basic construct used by
hardware to store information and to build pipeline stages. Pyrope goal is to
be a zero cost overhead, and as such it allows to handle flops directly.


To create an individual flop, a direct RTL instantiation of a `__flop` can be
used. Flops and latches have several pins `din`, `q`, `clock`, `enable` and
configuration options `posclk`, `initial`, and `async`. 


A more programmers friendly is to use to declare a register (flop) variabl. The
compiler does not provide guarantees that the register will not be split in
multiple registers.


In this example, `my_flop1_q and my_flop2_q` are equivalent.

```
my_flop1_q = __flop(din=my_din, reset=my_reset, clock=my_clock, enable=my_enable, posclk=true, initial=3, async=false)

reg my_flop2 = (reset=my_reset, clock=my_clock, posclk=true, initial=3, async=false)
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


If the register is accessed with `-1` cycle (`#something#[-1]`), the flop will
insert an additional pipeline to access 1 cycle before flop contents.


Latches are possible but with with the direct RTL instantiation. Latches have 
a `din` and `enable` pin like a flop, but just one option `posclk`.

```
my_latch_q = __latch(din=my_din, enable=my_enable, posclk=true)
```

## Pipelining

One of the fundamental differences between most programming languages and
hardware description languages is that pipelining is a fundamental feature that
must be used in hardware but not in software designs.

To illustrate the confusion/complication the following example illustrates a
multiplier that takes 3 cycles and an adder that takes 1 cycle to complete, and
the conceptual problems of integrating them:

```
let add1 = {|a,b| // 1 cycle add
  #reg = a+b
  ret #reg
}
let mul3 = {|a,b| // 3 cycle multiply
  #reg1 = $a * $b
  #reg2 = #reg1
  #reg3 = #reg2
  ret #reg3
}

pub let block = {|(in1,in2)->(out)|
  let x =# mul3(in1, in2)
  out   =# add1(x,in3)
}
```

The first observation is the new assignment `=#` instead of `=`. This is to explicitly indicate to Pyrope that the function called
(`mul3`, `add1`) can have pipeline outputs. This helps the tool but more importantly the programmer because it helps to check
assumptions about the function connections. The typical assignment `=` only connects combinational logic.

The previous code connects two inputs (in1/in2) to a multiplier, and then connects the result of the multiplier to an adder. The
`in1` inputs is also passed to the adder. This results in the following functionality:

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


The issue in most HDLs is that the connection is unaware of the pipelining, and it is left up to the programmer to understand and
check the potential pipeline stages inside `add1` and `mul3`. This lack of pipelining awareness in the language syntax is common
in most HDLs.

In Pyrope, the `=#` must be used when there is any path that starting from the inputs of the function passes through a pipeline
stage to generate the assignment. If all the paths have exactly 1 flop in between, it is a 1 stage pipeline, if some paths have 2
flops and others 3, it is a 2 or 3 pipeline stages. Sometimes, there are loops, and the tool has 1 to infinite pipeline stages.


The default pipeline assignment `=#` just checks that it is possible to have pipeline stages between the module/function inputs
and the assignment value. To restrict the check, it accepts a range. E.g: `=#[3]` means that there are exactly 3 flops or cycles
between inputs and the assignment. `=#[0..<4]` means that there are between 0 and 3 cycles, and open range could be used when
there are loops (E.g: `=#[2..]`).

```
let x = mul3(in1, in2)      // compile error: 'mul3' is pipelined
let x =# mul3(in1, in2)     // OK
%out  =# add1(x,in3)        // OK (in3 has 0 cycles, x has 3 cycles)
%out  =#[1] add1(x,in3)     // compile error: 'x' is pipelined with '3' cycles
%out  =#[3] add1(x,in3)     // compile error: 'in3' is pipelined with '1' cycle
%out  =#[1..<4] add1(x,in3) // OK
```

The previous code will check the assumptions in pipelining. It is likely that the designer wanted to implement a multiply-add.  As
such, the input to the adder should be from the same cycle as the multiplied started to operate. Otherwise, values across cycles
are mixed.

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
is error prone because it requires to know exactly the number of cycles for
`mul3`. This is were the `repipe` command becomes handy, it guarantees that all
the paths from the inputs to every tuple entry has exactly the same pipeline
depth. It does it by adding pipeline stages as needed. If it can not be done
automatically like when there are loops, an error is generated and an explicit
solution should be used.

=== "Explicitly added pipeline stages"

    ```
    x =# mul3(in1, in2)
    y = in1#[-3]
    %out =# add1(a=x,b=y)    // connect in1 from -3 cycles
    ```

=== "repipe statement"

    ```
    x =# mul3(in1, in2)
    repipe z = (in1, x)     // add flops to match x and in1
    %out =# add1(a=x,b=z)

    assert z == in1#[-3]
    ```

The |> keyword (`|>`) connects functions, but guarantees that all the outputs have the same delay from the inputs. Effectively,
it adds a `repipe` command.

=== "With |>"

    ```
    (a=mul3(in1, in2), b=in1) |> add |> %out   // pipelined add.b input



    (a=mul3(in1, in2)) |> add(b=in1)           // non-pipelined add.b input
    ```

=== "With repipe"

    ```
    let x =# mul3(in1, in2)
    repipe z = (in2, x)
    %out  =# add(a=x, b=z.in2)
    assert x == z.x

    let x =# mul3(in1, in2)
    %out  =# add(a=x, b=in1)                   // non-pipelined add.b input
    ```

=== "With explicit"

    ```
    let x =# mul3(in1, in2)                    // pipelined add.b input
    %out  =# add(a=x,b=in#[-3])

    let x =# mul3(in1, in2)
    %out  =# add(a=x, b=in1)                   // non-pipelined add.b input
    ```

The `repipe` command arguments can add pipeline stages, not remove pipeline
stages.


!!! Observation

    The explicit `v#[-cycles]` inserts flops and access the result `cycles` before. This same syntax
    can be used with assertions similar to the Verilog `$past(v, cycles)`.

## Future improvements

Pipelining is one of the concepts that add extra complexity to HDLs, and it is a research topic what is the best approach, as such this section
summarizes a couple of potential paths for future Pyrope development.


### Liam constructs

In most HDLs loops have to be compile time unrolled, in earlier version of
Pyrope[^liam] allowed for extra keywords to create an actor model and create
state machines were each loop iteration will be executed in a cycle.


```
while some_condition {

  step   // next cycle starts here
}
```

Fluid constructs:

* `variable?` check if `variable` valid bit is set
* `variable!` check if `variable` has a fluid backpressure
* `keep` do not consume variable on use
* `step` stop the cycle here, continue next cycle after the yield statement


[^liam]: Liam: An Actor Based Programming Model for HDLs, Haven Skinner, Rafael
T. Possignolo, and Jose Renau. 15th ACM-IEEE International Conference on Formal
Methods and Models for System Design (MEMOCODE), October 2017.
