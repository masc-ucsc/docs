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


The explicit connection likely requires constructs like `.[defer]` to connect
the flop `q` pin.


=== "Structural flop style"
    ```
    var counter_next:u8:[wrap] = _

    let counter_q = __flop(din=counter_next.[defer] // defer to get last update
                       ,reset=my_rst, clock=my_clk
                       ,enable=my_enable            // enable control
                       ,posclk=true
                       ,initial=3                   // reset value
                       ,async=false)

    counter_next = counter_q + 1
    ```

=== "Pyrope style"
    ```
    reg counter:u8:[reset=my_rst, clock=my_clk, posclk=true, async=false]= 3
    assert counter == counter#[0]  // counter still has the q value

    if my_enable {
      counter::[wrap] = counter + 1
    }
    ```


Flops have `din` and a `q` pin. At the beginning of the cycle both `din` and
`q` have the same value, but as the `din` is updated with "next cycle" `q`
value their contents may be different. Different HDLs have different syntax to
distinguish between `din` and `q` pin. In Verilog, it is common to have a
coding style guideline that gives a different name to the din variables than to
the q variables (E.g: `counter_q` vs `counter_next`). The structural flop style
is a legal Pyrope code using these type of names.


In a more friendly Pyrope style, a register like `counter` starts with the `q`
pin each cycle. The last value written to `counter` connects to the `din`. It
is always possible to access the `q` pin/value directly with  pipeline
directives `something#[0]`.


If the register is accessed with the `-1` cycle (`#something#[-1]`), the flop will
insert an additional pipeline to access 1 cycle before flop contents.

It is also possible to use positive values (`variable#[3]`) which means the
value in the future 3 cycles, but this is only allowed in debug statements like
`assert` or `puts`.


Latches are possible but with the direct RTL instantiation. Latches have 
a `din` and `enable` pin like a flop, but just one option `posclk`.

```
var my_latch_q = __latch(din=my_din, enable=my_enable, posclk=true)
```

## Pipestage


Pyrope has a `pipestage` statement (`#>identifier[fsm_configuration]`) that
helps to create simple pipeline stages. The `identifier[fsm_configuration]` is
optional and the default meaning is a fully pipelined 1 pipeline stage depth.
It is the same as saying `_[lat=1]`. The identifier can be accessed as an
attribute to count the pipestage utilization.

The fsm configuration can have `lat` (number of pipeline stages or latency) or
`num` (number of units). The number of units is only needed when the code is
not fully pipelined in combination with loop constructs like `while`, `for`,
and `loop`.

The `num` sets the number of units. The hardware will not back pressure, but an
assertion will fail during simulation if the number of units is overflowed.
`num` only makes sense when the latency (`lat`) is more than 1.


```
// variables/register before

{
  // stage 0 scope
} #> {               // no identifier, 1 stage by default
  // stage 1 scope
} #>foo[2] {            // no identifier, 2 stages
  // stage 2-3 scope
} #>bar[1] {     // 'free_stage' identifier, 1 stages
  // stage 4 scope
} #> {
  // stage 5 scope
}

// variables/register after pipestage
```

The semantics of `pipestage` are as follows:

* Explicitly declared registers (`reg foo`) are not affected by `pipestage`

* Variables declared before are "pipelined" inside each of the `pipestage` scopes.

* Variables declared in a stage are pipelined to all the following stages
  unless the variable is private (`var priv_example::[private]=3`)

* The pipelined variables are not visible in the scope after the `pipestage`
  sequence.

* The original non-pipelined variable can be accessed with `v#[0]`.


To illustrate the semantics, imagine a module where the input `i` is a
monotonically increasing sequence (`0,1,2,3,4,5,6,7....`).


```
assert i==0 or (i#[-1] + 1 == i)

let i_let = i

var i_var0 = i
var i_var1 = i

reg i_reg0 = i        // initialization only
reg i_reg1:i_reg0 = _

i_reg1 = i                // every cycle

{
  assert i == i#[0]       // i#[0] is unflop input (or first defined) value
  assert i == i_let
  assert i == i_var0
  assert i == i_var1

  assert 0 == i_reg0
  assert i == i_reg1

  let _local_var = 3

  let pub_var = 100 + i

} #> {
  assert _local_var!=0      // compile error, _local_var is not in scope
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


The pipestage accept the `clock` and `posclk` attributes from register to allow
the selection of different clock signal. Notice that it does not allow `reset`
or `latch` or `async` because it does not require reset logic.


Pipelining is one of the challenges of designing hardware. Even a simple pipestage
code can result in incorrect hardware. The reason is that if two pipestage blocks
generate an output simultaneously, there is no way to generate both outputs. The
result is a compile or simulation error.

```
let bad_code = proc(my_clk, inp)->(o1,o2) {

  {
    o1 = 1
    o2 = inp + 1  // o2? iff bad_code called this cycle and inp? is valid
  } #>my_pipe[lat=1,clock=my_clk] {
    o1 = 2        // compile error, o1 driven simultaneous from multiple stages
    o2 = inp + 2  // may be OK if inp is not valid every cycle
  }

}
```

## Pipestage with loops


The pipestage directive (`#>identifier[cycles]{  }`) automatically creates a fully
pipeline design with `cycles` pipeline depth. `cycles` must be bigger or equal
than 1 and known at compile time. When `cycles` is not specified a `1` value is
assumed.

Pipestage can be applied to `while` and `loop` statements, not to `for`
statements because `for` must be fully unrolled at compile time.

When applied to loops, the loop becames a state machine with `cycles` the
maximum number of simultaneous loop iterations. It effectively means that
number of units or state machines that can perform the loop simultaneously.
The identifier becomes a procedure attribute.


=== "Fully Pipelined"
    ```
    let mul3=proc(a,b)->res {
      let tmp = a*b
      #>full_case[lat=3,num=3] { // Same as full_case[lat=3]
        res = tmp
      }
    }
    ```
=== "State-machine"
    ```
    let mul_slow=proc(a,b)->res {

      let result  = 0
      let rest    = a

      while rest >= b #>_[lat=1,num=4] {  // lat=1 is latency per iteration
        rest = rest - b
        result += 1
      }

      res = result
    }
    ```
=== "Slow 1 Stage"
    ```
    let mul1=proc(a,b)->(reg res) {
      res = a*b
    }
    ```
=== "Slow 1 Stage (alt syntax)"
    ```
    let mul1=proc(a,b)->(res) {
      #>full_case_again[lat=1] { 
        res = a*b
      }
    }
    ```
=== "Pure Combinatinal"
    ```
    let mul0=proc(a,b)->(res) {
      res = a*b
    }
    ```

To understand the fully pipelined behavior, the following shows the pipestage
against the more direct implementation with registers.

```
if cond {
  var p1 = inp1
  var out = _

  {
    var _l1 = inp1 + 1

    var p2 = inp1 + 2
  } #> {
    out = p1 + p2
  }

  res = out
}

// Non pipestage equivalent
if cond {
  var p1 = inp1
  var out = _

  {
    reg p1r = _
    reg p2r = _

    var l1::[private] = inp1 + 1  // private
    var p2 = inp1 + 2             // public

    out = p1r + p2r               // registered values

    p1r = p1
    p2r = p2
  }

  res = out
}
```


## Retiming

The registers manually inserted with the `reg` directive are preserved
and annotated so that synthesis retiming can not change them. This means
that by default register can not be duplicated or logic can move around.


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
reg my_reg::[retime=true,clock=my_clk] = 0
```


## Multiply-Add example

To illustrate the confusion/complication the following example illustrates a
multiplier that takes 3 cycles and an adder that takes 1 cycle to complete, and
the conceptual problems of integrating them:


=== "Pipestage"
    ```
    let block = proc(in1,in2)->(out) {
      {
        let tmp = in1 * in2
      } #>some_id[lat=3] {
        out = tmp + in1#[0]
      }
    }
    ```

=== "Explicit Stages"
    ```
    add1 = proc(a,b) {     // 1 cycle add
      reg r  = _
      let rr = r           // get flop value
      r = a+b
      ret rr
    }
    let mul3 = proc(a,b) { // 3 cycle multiply
      reg reg1 = _
      reg reg2 = _
      reg reg3 = _
      reg3 = reg2
      reg2 = reg1
      reg1 = a * b
      ret reg3
    }

    let block = proc(in1,in2)->(out) {
      let x =#[..] mul3(in1, in2)
      out   =#[..] add1(x,in3)
    }
    ```

In general, `#` is used when dealing with registers. The previous example use
`procedures` (`proc ... {...}`) instead of `functions` (`fun ... {...}`) because functions
only have combinational logic. When the procedures are called, the assigned
variable needs the `=#[..]`. This is to explicitly indicate to Pyrope that the
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

In Pyrope, the `=#[..]` must be used when there is any path that starts from the
inputs of the function passes through a pipeline stage to generate the
assignment. If all the paths have exactly 1 flop in between, it is a 1 stage
pipeline, if some paths have 2 flops and others 3, it is a 2 or 3 pipeline
stages. Sometimes, there are loops, and the tool has 1 to infinite pipeline
stages.


The default pipeline assignment `=#[..]` just checks that it is possible to have
pipeline stages between the module/function inputs and the assignment value. To
restrict the check, it accepts a range. E.g: `=#[3]` means that there are
exactly 3 flops or cycles between inputs and the assignment. `=#[0..<4]` means
that there are between 0 and 3 cycles, and open range could be used when there
are loops (E.g: `=#[2..]`).

```
let x = mul3(in1, in2)      // compile error: 'mul3' is pipelined
let x =#[..] mul3(in1, in2) // OK
out  =#[..] add1(x,in3)     // OK (in3 has 0 cycles, x has 3 cycles)
out  =#[1] add1(x,in3)      // compile error: 'x' is pipelined with '3' cycles
out  =#[3] add1(x,in3)      // compile error: 'in3' is pipelined with '1' cycle
out  =#[1..<4] add1(x,in3)  // OK
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
      let tmp = in1 * in2
    } #>fully_pipe[lat=3] {
      out = tmp + in1
    }
    ```

=== "Explicitly added pipeline stages"

    ```
    x =#[..] mul3(in1, in2)
    y = in1#[-3]
    out =#[..] add1(a=x,b=y)    // connect in1 from -3 cycles
    ```

!!! Observation

    The explicit `v#[-cycles]` inserts registers and access the result `cycles`
    before. This same syntax can be used with assertions similar to the Verilog
    `$past(v, cycles)`.


## ALU example


Pipestages allow to build fully pipelined structures but also non-pipelined
state machines when applied to loops. This creates potential contention that the
designer must decide how to manage. This contention can be propagated outside
the procedure with attributes.


The ALU example illustrates the contention by creating an ALU with 3 different
pipelines (add,mul,div) that have different latencies and contention.


```
let quick_log2 = fun(a) {

  cassert a>=1

  var i = 1
  var v = 0
  while i < a.[bits] {
    v |= i
    i *= 2
  }

  ret v
}

let div=proc(a,b,id)->(res,id) {
  loop #>free_div_units[4] {
    ret (a >> quick_log2(b), id) when b@+[..] == 1
    #>my_fsm[lat=5,num=1] {
      res = (a/b, id)
    }
  }
}

let mul=proc(a,b,id)->(res, id) {
  #>pending_counter[lat=3,num=2] {
    res = a*b
    id  = id
  }
}

let add=proc(a,b,id)->(res,id) {
  #>add_counter[lat=1] {         // Fully pipeline, num not specified
    res = a+b
    id  = id
  }
}

let alu = proc(a,b,op, id)->(res,id) {

  self.[total_free_units] = 1 
     + mul.[pending_counter] 
     + div.[free_div_units]
     + add.[add_counter]

  self.[div_units] = div.[free_div_units]

  match op {
    == OP.div {
      assert div.[free_div_units]>0
      res,id = div(a,b,id)
    }
    == OP.mul { res,id = mul(a,b,id) }
    == OP.add { res,id = add(a,b,id) }
  }
}

test "alu too many div" {

 cassert alu.[total_free_units] == (1+3+4)

 let r1 = alu(13,3, OP.div, 1)
 assert alu.div_units==3
 let r2 = alu(13,3, OP.div, 2)
 assert alu.div_units==2
 let r3 = alu(13,3, OP.div, 3)
 assert alu.div_units==1
 let r4 = alu(13,3, OP.div, 4)
 assert alu.div_units==0

 assert !r1? and !r2? and !r3? and !r4? // still invalid

 let r5 = alu(13,4, OP.mul,5)
 cassert mul.[pending_counter] == 2
}
```
