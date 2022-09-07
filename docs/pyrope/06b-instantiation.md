
# Instantiation

Instantiation is the process of translating from Pyrope to a representative set
of gates. The gates could be simplified or further optimized by later compiler
passes or optimization steps.


## Conditionals

Conditional statements like `if/else` and `match` translate to multiplexers
(muxes).


A trivial `if`/`else` with all the options covered is a simple mux.

```
var res
if cond {
  res = a
}else{
  res = b
}

// RTL equivalent
var res2 = __mux(cond,b,a)

lec res, res2
```

Chaining `if`/`elif` creates a chain of muxes. If not all the inputs are
covered the value from before the `if` is used. If the variable did not exist,
a compile error is generated.

```
var res = a
if cond1 {
  res = b
}elif cond2 {
  res = c
}else{
  assert true // no res
}

// RTL equivalent
var tmp = __mux(cond2, a, c)
var res2= __mux(cond1, tmp, b)

lec res, res2
```

`unique if`/`elif` is similar but avoids mux nesting using a one-hot encoded
mux. 

```
var res = a
unique if cond1 {
  res = b
}elif cond2 {
  res = c
} // no res in else

// RTL equivalent
var sel = (!cond1 and !cond2, cond1, cond2)@[]  // one hot encode
var res2= __hotmux(sel, a, b, c)
assume !(cond1 and cond2)          // one hot check

lec res, res2
```

The `match` is similar to the `unique if` but also checks that one of the options is
enabled, which allows further optimizations.

```
var res = a
match x {
  == c1 { res = b }
  == c2 { res = c }
  == c3 { res = d }
}

// RTL equivalent
let cond1 = x == c1
let cond2 = x == c2
let cond3 = x == c3
var sel = (cond1, cond2, !cond1 and !cond2)@[]  // one hot encode (no cond3)
var res2= __hotmux(sel, b, c, d)
assume  ( cond1 and !cond2 and !cond3)
     or (!cond1 and  cond2 and !cond3)
     or (!cond1 and !cond2 and  cond3)    // one hot check (no else allowed)

lec res, res2
```

## Optional expression

Valid or options are computed for each assignment and passed to every lambda
call. Each variable has an associated valid bit, but it is removed if never
read, and it is always true unless the variables are assigned in conditionals
or not short-circuit (`and_then`/`or_else`) expressions.


=== "Short-circuit expression"

    ```
    var lhs = v1 or_else v2

    // RTL equivalent
    let lhs2  = __or(v1, v2)
    let lhs2_v = __or(__and(v1?, v1), __and(v2?, v2))

    lec lhs , lhs2
    lec lhs?, lhs2_v
    ```

=== "Usual expression"

    ```
    var lhs = v1 + v2

    // RTL equivalent
    let lhs2   = __sum(A=(v1, v2))
    let lhs2_v = __and(v1?, v2?)

    lec lhs , lhs2
    lec lhs?, lhs2_v
    ```

=== "Conditionals"

    ```
    lhs = v0
    if cond1 {
      lhs = v1
    }elif cond2 {
      lhs = v2
    } // no else

    // RTL equivalent
    let tmp = __mux(cond2, v0, v2)
    let lhs2= __mux(cond1, tmp, v1)

    let tmp_v = __mux(cond2, v0?, v2?)
    let lhs2_v= __mux(cond1, tmp_v, v1?)

    lec lhs , lhs2
    lec lhs?, lhs2_v
    ```


## Optional lambdas

HDLs use typical software constructs that look like function calls to represent
instances in design. As [previously
explained](00-hwdesign.md#instantiation-vs-execution), hardware languages are
about instantiation, and software languages are about instruction execution. A
lambda called unconditionally is likely to result in `module` unless the
compiler decides to be small and it is inlined.



In Pyrope, the semantics are that when a lambda is conditionally called, it
should behave like if the lambda were inlined in the conditional place. Since
functions have no side effects, it is also equivalent to call the lambda before
the conditional path, and assign the return value inside the conditional path
only. Special care must be handled for the `puts` which is allowed in
functions. The `puts` should not be called if the function is conditionally
called.


=== "Conditional proc call"

    ```
    pub case_1_counter = proc(runtime)->(res) {

      reg r:(
        ,reg total
        ,increase = fun(a) {
          puts "hello"

          let res = self.total
          self.total = u16(res+a)

          ret res
        }
      )

      if runtime == 2 {
        res = r.increase(3)
      }elif runtime == 4 {
        res = r.increase(9)
      }
    }
    ```

=== "Pyrope inline equivalent"

    ```
    pub case_1_counter = proc(runtime)->(res) {

      reg r:(
        ,reg total
        ,increase = fun(a) {
          puts "hello"

          let res = self.total
          self.total = u16(res+a)

          ret res
        }
      )

      if runtime == 2 {
        puts "hello"

        let res = r.total
        r.total = u16(res+3)
        res = res
      }elif runtime == 4 {
        puts "hello"

        let res = r.total
        r.total = u16(res+9)
        res = res
      }
    }
    ```

The result of conditionally calling procedures is that most of the code may be
inlined. This can change the expected equivalent Verilog generated modules.


Calling a procedure with the inputs set invalid has a different behavior. For
once C++ calls will still happen, and updates to registers with not valid data
is allowed to reset the valid bit.


## Expressions

Pyrope expressions are guaranteed to have the same result independent of the
order of evaluation. Only `and_then`, `or_else` or complex constructs like
`if/else`, `match`, `for` have evaluation order.


## Setup vs Reset vs Execution

In a normal programming language, the Von Neumann PC specifies clear semantics
on when the code is executed. The language could also have a macro or template
system executed at compile-time, the rest of the code is called explicitly when
the function is called. As mentioned, a key difference is that HDLs focus on
instantiation of gates/logic/registers, not instruction execution. HDLs tend to
have 3 code sections:


* Setup: This is code executed to set up the hierarchies, parameters, read
  configuration setups... It is usually executed at compile time. In Verilog,
  these are the preprocessor directives and the generate statements.  In
  CHISEL, the scala is the setup code.

* Reset: Hardware starts in an undefined/inconsistent state. Usually, a reset
  signal is enabled several cycles and the associated reset logic configures
  the system to a given state.

* Execution: This is the code executed every cycle after reset. The reset
  logic activation can happen at any time, and parts of the machine may be in
  reset mode while others are not.


In addition, some languages like Verilog have "initialization" code that is
executed before reset. This is usually done for debugging, and it is not
synthesizable. Although not always synthesizable, we consider this setup code.


Pyrope aims to have the setup, reset, and execution specified.

### Setup code

Compiling a Pyrope program requires specifying a "top file" file and a
"top variable" in the top file. The top file is executed only once. The top
file may "import" other files. Each of the imports is executed only once too.
The imported files are executed before the current file is executed. This is
applied recursively but no loops are supported in import dependence chains.

The "setup" code is the statements executed once for each imported file. Those
statements can not be "imported" by other files. Only the resulting public
variables can be imported.


During setup, each file can have a list of public variables. Those are
variables that can be used by importing modules.  The "top variable" is
selected for simulation/synthesis.


It is important to point that `comptime` may be used during setup but also in
non-setup code. `comptime` just means that the associated variables are known
at compile time. This is quite useful during reset and execution too or just to
guaranteed that a computation is solved at compile time.


### Reset


The reset logic is associated with registers and memories. The assignment to
register declaration is the reset code. It will be called for as many cycles
are the reset is held active.  The `reg` assignment can be a constant or a call
to `conf` that can provide a runtime file with the values to start the
simulation/synthesis.


```
reg r:u16 = 3 // reset sets r to 3
r = 2         // non-reset assignment

reg array:u16[] = (1,2,3,4)  // reset values

reg r2:u128 = conf.get("my_data.for.r2")

reg array:[] = conf.get("some.conf.hex.dump")
```

When a state machine is needed to execute for several cycles a tuple with an
`always_reset` must be created and assigned to the register[s] that use it.

```
reg array:tag[1024] = (
  ,clock=my_clock

  ,always_reset = fun(ref self) {
     reg reset_iter:u10 = (reset="") // no reset flop

     self[reset_iter].state = I

     reset_iter = u10(reset_iter + 1)
  }
)
```

All registers and memories can have a `always_reset` overload  method. If a tuple is
called as a register state, the reset field is also called.

To guarantee determinism, the following reset call constrains are applied:

* Synchronous reset statements can not read the contents of other registers
  with synchronous resets. Synchronous reset method can read asynchronous reset
  methods.

* Asynchronous resets can not read other reset values.

* Reset method (`always_reset`) can read other resets if the reset signal is
  different.


```
reg my_flop:u32[8] ++ (
  ,always_reset = proc(ref self) {
    reg reset_counter:u3 ++ (async=true) // async is only posedge reset

    self[reset_counter] = reset_counter
    wrap reset_counter += 1
  }
)
```

Similarly a tuple can have a reset when assigned to a register:

```
type My_update = (
  ,counter:u32
  ,state:u2
  ,always_reset = proc(self) {
    self.state = 2
    self.counter = 33
  }
)

reg my_flop2:My_update 
```


### Execution

HDLs specify a tree-like structure of modules. The top module could instantiate
several sub-modules. Pyrope Setup phase is to create such hierarchical
structures. The call order follows a program order from the top point every
cycle, even when reset is set.


The following Verilog hierarchy can be encoded with the equivalent Pyrope:

=== "Verilog"

    ```verilog
    module inner(input z, input y, output a, output h);
      assign a =   y & z;
      assign h = !(y & z);

    endmodule

    module top2(input a, input b, output c, output d);

    inner foo(.y(a),.z(b),.a(c),.h(d));

    endmodule
    ```

=== "Pyrope equivalent"


    ```
    pub let inner = fun(z,y)->(a,h) {
      a =   y & z
      h = !(y & z)
    }

    pub let top2 = fun(a,b)->(c,d) {
      let x= inner(y=a,z=b)
      c = x.a
      d = x.h
    }
    ```

=== "Pyrope alternative"

    ```
    type inner_t = (
      ,pub set = fun(ref self, z,y) {
        self.a =   y & z
        self.h = !(y & z)
      }
    )

    pub let top2 = fun(a,b)->(c,d) {
      let foo:inner_t = (y=a,z=b)
      c = foo.a
      d = foo.h
    }
    ```


The top-level module `top2` must be a module, but as the alternative Pyrope
syntax shows, the inner modules may be in tuples or direct module calls. The
are advantages to each approach but the code quality should be the same.

## Pipestages


The pipestage directive (`#>`) automatically creates pipeline resources.


```
if cond {
  var p1 = inp1
  var out

  {
    var l1 = inp1 + 1

    pub var p2 = inp1 + 2
  } #> {
    out = p1 + p2
  }

  res = out
}

// Non pipestage equivalent
if cond {
  var p1 = inp1
  var out

  {
    reg p1r
    reg p2r

    var l1 = inp1 + 1
    pub var p2 = inp1 + 2 // now pub has no special meaning

    out = p1r + p2r       // registered values

    p1r = p1
    p2r = p2
  }

  res = out
}
```

## Registers


```
reg a = 3
a = u16(a+1)

reg b = 4
if cond {
  reg c
  c = b + 1
  b = 5
}

// RTL equivalent
a_qpin = __flop(reset=reset, clk=clk, reset_value=3, din=a.__last_value)
a      = __sum(A=(a_qpin, 1))

b_qpin = __flop(reset=reset, clk=clk, reset_value=4, din=b.__last_value)
b      = __mux(cond, b_qpin, 5)

c_cond_qpin = __flop(reset=reset, clk=clk, din=c_cond.__last_value)
c_cond      = __sum(A=(b, 1))
```

