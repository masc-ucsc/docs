
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
covered the value from before the scope is used. If the variable did not exist,
a compile error is generated.

```
var res = a
if cond1 {
  res = b
}elif cond2 {
  res = c
}else{
  // no res
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
match {
  cond1 { res = b }
  cond2 { res = c }
  cond3 { res = d }
}

// RTL equivalent
var sel = (cond1, cond2, !cond1 and !cond2)@[]  // one hot encode (no cond3)
var res2= __hotmux(sel, b, c, d)
assume  ( cond1 and !cond2 and !cond3)
     or (!cond1 and  cond2 and !cond3)
     or (!cond1 and !cond2 and  cond3)    // one hot check (no else allowed)

lec res, res2
```

## Optionals

Valid or options are computed for each assignment and passed to every lambda
call. Each variable has an associated valid bit, but it is removed if never
read, and it is always true unless the variables are assigned in conditionals
or not short-circuit (`and_then`/`or_else`) expressions.


=== "Short-circuit expression"

    ```
    var lhs = v1 or_then v2

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

## Lambdas

HDLs use typical software constructs that look like function calls to represent
instances in design. As [previously
explained](00-hwdesign.md#instantiation-vs-execution), hardware languages are
about instantiation, and software languages are about instruction execution. A
lambda called unconditionally is likely to result in `module` unless the
compiler decides to be small and it is inlined.


Conditional called `lambdas` have extra logic to compute the associated
`optionals`. `lambdas` also pass the input optionals as part of their inputs,
and the outputs are generated accordingly.

```
let fun = {|(a,b)->(c,d)| 
   c = a+b
   if c==0 { 
    d = a-b 
  }
}

if cond {
  c,d = fun(a,b)
}

// RTL equivalent
let tmp_a = a
let tmp_b = b
tmp_a? = __and(a?, cond)   // adjust the call arg valids
tmp_b? = __and(b?, cond)

tmp_c, tmp_d = fun(tmp_a,tmp_b)

let c2 = __mux(cond, c, tmp_c)
let d2 = __mux(cond, d, tmp_d)

let c2_v = __mux(cond, c?, tmp_c?)
let d2_v = __mux(cond, d?, tmp_d?)

lec c, c2
lec d, d2

lec c?, c2_v
lec d?, d2_v
```


The previous code WILL call `fun` every cycle, but in some cycles the inputs
will be invalid. This is one of the main Pyrope differences with other HDLs. In
languages like Verilog, modules can not be conditionally called. Pyrope allows
it by toggling the inputs valids. The module can decide how to handle it. 


The main concern happens on how to deal with `puts` or assertions. The problem of
`conditionals` is somewhat similar to the `reset`. The lambda or expressions
can be called during reset or when the inputs are not valid, this can lead to faulty
assertions or maybe unwanted debug messages.


To help, Pyrope has a `disable` variable for each lambda. The disable allows to
disable `asserts` and `puts` for the remaining of the lambda or until it is
uncleared. The semantics is like if the `disable` tuple was a global variable.
Lambda definitions will capture the disable by value, and they can be locally
modified like any captured mutable variable. 


=== "Explicitly handled"

    ```
    let div = {|a,b|

      assert b!=0 or b?  // OK if invalid too
      out = a / b
    }
    let fun = {|a,b|
      out = a + b
      if out? {          // we may want to print only when valid
        puts "{} + {} is {}", a, b, out
      }
    }
    ```

=== "Disable"

    ```
    let div = {|a,b|
      disable.assert not b?
      assert b!=0 
      out = a / b
    }

    let fun2 = {|a,b|
      out = a + b

      disable.puts = not out?
      puts "{} + {} is {}", a, b, out
    }
    ```


## Expressions

Pyrope expressions are guaranteed to have the same result independent of the
order of evaluation. Only `and_then`, `or_else` or complex constructs like
`if/else`, `match`, `for` have evaluation order.


## Setup vs Reset vs Execution

In a normal programming language, the Von Neumann PC specifies clear semantics
on when the code is executed. The language could also have a macro or template
system executed at compile-time, the rest of the code is called explicitly when
the function is called. As mentioned, a key difference is that HDLs are all about
instantiation, not instruction execution. The instantiated functionality in HDLs
tend to have 3 code sections:


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
synthesizable. Pyrope does not have such simulation-only code.


Pyrope aims to have the setup, reset, and execution specified.

### Setup code

Compiling a Pyrope program requires specifying a "top file" file and a
"top variable" in the top file. The top file is executed only once. The top
file may "import" other files. Each of the imports is executed only once too.
The imported files are executed before the current file is executed. This is
applied recursively but no loops are supported in import dependence chains.

The "setup" code is the statements executed once for each imported file. Those
statements can not be "imported" by other files. Only the resulting `pub`
variables can be imported.


During setup, each file can have a list of `pub` variables. Those are variables
that can be used by importing modules.  The "top variable" is selected for simulation/synthesis.


It is important to point that `comptime` may be used during setup but also in
non-setup code. `comptime` just means that the associated variables are known
at compile time. This is quite useful during reset and execution too.


### Reset


The most common reset logic is associated with registers and memories. The
assignment to `reg` variable declaration is the reset code. It will be called
for as many cycles are the reset is held active.  The `reg` assignment can be
a constant or a call to `conf` that can provide a runtime file with the values
to start the simulation/synthesis.


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

  ,always_reset = {|(self)->(self)|
     reg reset_iter:u10 = (reset="") // no reset flop

     self[reset_iter].state = I

     reset_iter = u10(reset_iter + 1)
  }
)
```


### Execution

HDLs specify a tree-like structure of modules. Usually, there is a top module
that instantiates several sub-modules. Pyrope Setup phase is to create such
hierarchical structures.


The hierarchy is achieved with modules calling other modules. The top file can
have one or more modules.

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
    pub let inner = {|(z,y)->(a,h)|
      a =   y & z
      h = !(y & z)
    }

    pub let top2 = {|(a,b)->(c,d)|
      let x= inner(y=a,z=b)
      c = x.a
      d = x.h
    }
    ```

=== "Pyrope alternative"

    ```
    type inner_t = (
      ,pub set = {|(z,y)->(self)|
        self.z = z
        self.y = y
      }
      ,always_after = {||
        self.a =   self.y & self.z
        self.h = !(self.y & self.z)
      }
    )

    pub let top2 = {|(a,b)->(c,d)|
      let foo:inner_t = (y=a,z=b)
      c = foo.a
      d = foo.h
    }
    ```


The top-level module `top2` must be a module, but as the alternative Pyrope
syntax shows, the inner modules may be in tuples or direct module calls. The
are advantages to each approach but the code quality should be the same.

