
# Instantiation

Instantiation is the process of translating from Pyrope to an equivalent set
of gates. The gates could be simplified or further optimized by later compiler
passes or optimization steps. This section provides an overview of how the
major Pyrope syntax constructs translate to gates.


## Conditionals

Conditional statements like `if/else` and `match` translate to multiplexers
(muxes).


A trivial `if/else` with all the options covered is a simple mux.

```pyrope
mut res:i4 = nil

if cond {
  res = a
} else {
  res = b
}

// RTL equivalent (mux of 4 bits in a,b,res2)
mut res2:i4 = __mux(cond, b, a)

lec(res, res2)
```

An expression `if/else` is also a mux.

```pyrope
mut res = if cond { a } else { b }

// RTL equivalent
mut res2 = __mux(cond, b, a)

lec(res, res2)
```

An explicit conditional assignment is also a mux.

```pyrope
mut res = a
if not cond {
  res = b
}

// RTL equivalent
mut res2 = __mux(cond, b, a)

lec(res, res2)
```

Chaining `if`/`elif` creates a chain of muxes. If not all the inputs are
covered, the value from before the `if` is used. If the variable did not exist,
a compile error is generated.

```pyrope
mut res = a
if cond1 {
  res = b
} elif cond2 {
  res = c
} else {
  assert(true) // no res
}

// RTL equivalent
mut tmp = __mux(cond2, a, c)
mut res2 = __mux(cond1, tmp, b)

lec(res, res2)
```

`unique if`/`elif` is similar but avoids mux nesting using a one-hot encoded
mux.

```pyrope
mut res = a
unique if cond1 {
  res = b
} elif cond2 {
  res = c
} // no res in else

// RTL equivalent — build the one-hot select bit-by-bit
mut sel:u3 = nil
sel#[0] = cond2
sel#[1] = cond1
sel#[2] = !cond1 and !cond2
mut res2 = __hotmux(sel, a, b, c)
assume(!(cond1 and cond2)) // one hot check

lec(res, res2)
```

The `match` is similar to the `unique if` but also checks that one of the
options is enabled, which allows further optimizations. From a Verilog designer
point of view, the `match` is a "full parallel" and the `unique if` is a
"parallel". Both are checked at verification and optimized at synthesis.

```pyrope
mut res = a
match x {
  == c1 { res = b }
  == c2 { res = c }
  == c3 { res = d }
  else  { }
}

// RTL equivalent
const cond1 = x == c1
const cond2 = x == c2
const cond3 = x == c3
// one hot encode (no cond3) — built bit-by-bit
mut sel:u3 = nil
sel#[0] = cond1
sel#[1] = cond2
sel#[2] = !cond1 and !cond2
mut res2 = __hotmux(sel, b, c, d)
assume ( cond1 and !cond2 and !cond3)
    or (!cond1 and  cond2 and !cond3)
    or (!cond1 and !cond2 and  cond3)    // one hot check (no else allowed)

lec(res, res2)
```

## Optional expression

Valid or optionals are computed for each assignment and passed to every lambda
call. Each variable has an associated valid bit, but it is removed if never
read, and it is always true unless the variables are assigned in conditionals
or short-circuit (`and`/`or`) expressions.


=== "Short-circuit expression"

    ```pyrope
    mut lhs = v1 or v2

    // RTL equivalent
    const lhs2  = __or(v1, v2)
    const lhs2_v = __or(__and(v1.[valid], v1), __and(v2.[valid], v2))

    lec(lhs , lhs2)
    lec(lhs.[valid], lhs2_v)
    ```

=== "Usual expression"

    ```pyrope
    mut lhs = v1 + v2

    // RTL equivalent
    const lhs2   = __sum(A=(v1, v2))
    const lhs2_v = __and(v1.[valid], v2.[valid])

    lec(lhs , lhs2)
    lec(lhs.[valid], lhs2_v)
    ```

=== "Conditionals"

    ```pyrope
    lhs = v0
    if cond1 {
      lhs = v1
    }elif cond2 {
      lhs = v2
    } // no else

    // RTL equivalent
    const tmp = __mux(cond2, v0, v2)
    const lhs2= __mux(cond1, tmp, v1)

    const tmp_v = __mux(cond2, v0.[valid], v2.[valid])
    const lhs2_v= __mux(cond1, tmp_v, v1.[valid])

    lec(lhs , lhs2)
    lec(lhs.[valid], lhs2_v)
    ```

=== "Lambda call (inlined)"

    ```pyrope
    comb f(a, b) -> (r) { r = if a == 0 { 3 } else { b } }

    mut lhs = c
    if cond {
       lhs = f(a,b)
    }

    // RTL equivalent
    const a_cond = __not(__ror(a))             // a == 0
    const tmp    = __mux(a_cond, b, 3)         // if a_cond { 3 }else{ b }
    mut lhs2   = c
    lhs2       = __mux(cond, lhs2, tmp)

    const tmp_v  = __mux(a_cond, a.[valid], __and(a.[valid], b.[valid])) // a.[valid] or (a==0 and b.[valid])

    const lhs2_v = __mux(cond, c.[valid], tmp_v)

    lec(lhs , lhs2)
    lec(lhs.[valid], lhs2_v)
    ```

## Lambda calls

A `pipe` or `mod` call always lowers to a module instance; a `comb` call is
inlined by default, but a fully-typed `comb` may also be kept as its own
instance (the compiler decides). When the instance is located in a conditional
path, the instance is moved to the main scope toggling the inputs valid
attribute `.[valid] = false`. The instance has the assigned variable name. If
the instance is a `mut`, the variable name can be the SSA name.

=== "Lambda call"
    ```pyrope
    mod sum(a:u32, b:u32) -> (x:u32@[0]) { wrap x = a + b }

    mod sub(a:u32, b:u32) -> (x:u32@[0]) {
      const tmp = sum(a, b)      // instance tmp,sum

      x = sum(tmp, 3)          // instance x,sum
    }

    mod top(a:u32, b:u32, c:bool) -> (x:u32@[0]) {

     x = sub(a, b).x
     if c {
       const tmp = 3
       wrap x += sub(b, tmp).x
     }
    }
    ```

=== "Instance"
    ```pyrope
    mod sum(a:u32, b:u32) -> (x:u32@[0]) { wrap x = a + b }

    mod sub(a:u32, b:u32) -> (x:u32@[0]) {
      const tmp = sum(a, b)      // instance tmp

      x = sum(tmp, 3)          // instance x
    }

    mod top(a:u32, b:u32, c:bool) -> (x:u32@[0]) {

     x = sub(a, b).x          // instance x

     const x_0 = nil
     const sub_arg_0 = nil
     const sub_arg_1 = nil
     if c {
       const tmp = 3
       sub_arg_0 = b
       sub_arg_1 = tmp
       wrap x += x_0           // x_0 is a wire driven below; readable before its driver
     }
     x_0 = sub(sub_arg_0, sub_arg_1).x   // instance x_0 (SSA)
    }
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
functions. The `puts` is not called if the function is conditionally called and
the condition is false.


=== "Conditional mod call"

    ```pyrope
    mod case_1_counter(runtime:u8) -> (res:u16@[0]) {

      const r = (
        reg total:u16 = 0,          // r is reg, everything is reg
        comb increase(a) -> (r) {
          puts("hello")

          r = self.total
          wrap self.total = r + a
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

    ```pyrope
    mod case_1_counter(runtime:u8) -> (res:u16@[0]) {

      const r = (
        reg total:u16 = 0,
        comb increase(a) -> (r) {
          puts("hello")

          r = self.total
          wrap self.total = r + a
        }
      )

      if runtime == 2 {
        puts("hello")

        const res = r.total
        wrap r.total = res + 3
        res = res
      }elif runtime == 4 {
        puts("hello")

        const res = r.total
        wrap r.total = res + 9
        res = res
      }
    }
    ```

The result of conditionally calling lambdas is that most of the code may be
inlined. This can change the expected equivalent Verilog generated modules.


Calling a lambda with the inputs set invalid has a different behavior. For
once C++ calls will still happen, and updates to registers with not valid data
is allowed to reset the valid bit.


## Expressions

Pyrope expressions are guaranteed to have the same result independent of the
order of evaluation. Only `and`, `or` (short-circuit) or complex constructs
like `if/else`, `match`, `for` have evaluation order.


## Setup vs reset vs execution

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
statements can not be "imported" by other files. Only resulting `pub` lambdas,
types, and constants can be imported. Registers are not imported; use `regref`
to reference instantiated registers across scopes.


During setup, each file can have a list of `pub` declarations. Those are
declarations that can be used by importing modules (declarations without `pub`
are private to the file). The "top variable" is selected for
simulation/synthesis.


It is important to point that `comptime` may be used during setup but also in
non-setup code. `comptime` just means that the associated variables are known
at compile time. This is quite useful during reset and execution too or just to
guaranteed that a computation is solved at compile time.


### Reset code


The reset logic is associated with registers and memories. The assignment to
register declaration is the reset code. It will be called for as many cycles
are the reset is held active.  The `reg` assignment can be a constant or a call
to `conf` that can provide a runtime file with the values to start the
simulation/synthesis.


```pyrope
reg r:u16 = 3 // reset sets r to 3
r = 2             // non-reset assignment

reg array:[4]u16 = (1, 2, 3, 4)  // reset values

reg r2:u128 = conf.get("my_data.for.r2")

reg array:[] = conf.get("some.conf.hex.dump") // dynamic size from config
```


The assignment during declaration to a register is always the reset value. If
the assignment is a method (a lambda referenced by name, **not** called —
i.e., no parentheses), the method is invoked every cycle during reset.

```pyrope
mod array_reset(ref self) {
  reg reset_iter:u10:[reset_pin=false] = 0sb? // no reset flop

  self[reset_iter].state = I

  wrap reset_iter = reset_iter + 1
}

reg array:[1024]tag:[clock_pin=ref my_clock] = array_reset  // no () — pass the method
```


Since the reset can be high many cycles, it may be practical/necessary to have
a reset inside the reset lambda. To guarantee determinism, any register
inside the reset lambda can be either asynchronous reset or a register
without reset signal.


```pyrope
mod my_flop_reset(ref self) {
  reg reset_counter:u3:[sync=false] = 0sb? // asynchronous reset is posedge only

  self[reset_counter] = reset_counter
  wrap reset_counter += 1
}

reg my_flop:[8]u32 = my_flop_reset
```

A related functionality and constrains happen when a tuple have some register
fields and some non-register fields. The same reset lambda is called every
cycle Similarly a tuple can have a reset when assigned to a register.


=== "Mixed tuple reset with constants"

    ```pyrope
    const Mix_tup = (
      reg flag:bool = false,
      mut state:u2 = nil
    )

    mut x:Mix_tup = (false, 1)  // false used at reset, 1 used every cycle

    assert(x.flag implies x.state == 2)

    x.state = 0
    if x.flag {
      x.state = 2
    }
    x.flag = true
    ```

=== "Mixed tuple reset with method"

    ```pyrope
    const Mix_tup = (
      reg flag:bool = false,
      mut state:u2 = nil,
      comb init(ref self) {
        mod flag_reset(ref self) { self = false }
        self.flag  = flag_reset          // reset code (pass by name, no ())
        self.state = 2                   // every cycle code
      }
    )

    mut x:Mix_tup = nil                  // init runs at construction

    assert(x.flag implies x.state == 2)

    x.state = 0
    if x.flag {
      x.state = 2
    }
    ```

A sample of asynchronous reset with different reset and clock signal

```pyrope
reg my_asyn_other_reg:u8:[
  sync = false,
  clock_pin = ref clk2,    // ref to connect, not read clk2 value
  reset_pin = ref reset33  // ref to connect, not read current reset33 value
] = 33 // initialized to 33 at reset


if my_async_other_reg == 33 {
  my_async_other_reg = 4
}

assert(my_async_other_reg in (4, 33))
```

### retime

Values stored in registers (flop or latches) and memories (synchronous or
asynchronous) can not be used in compiler optimization passes. The reason is that
a scan chain is allowed to replace the values.


The `retime` attribute indicates that the register/memory can be replicated and
used for optimization. Copy values can propagate through `retime`
register/memories.


A register or memory without explicit `:[retime]` attribute can only be optimized away
if there is no read AND no write to the register. Even just having writes the
register is preserved because it can be used to read values with the
scan-chain.


### Execution code

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


    ```pyrope
    comb inner(z, y) -> (a, h) {
      a = y & z
      h = !(y & z)
    }

    comb top2(a, b) -> (c, d) {
      const x = inner(y=a, z=b)
      c = x.a
      d = x.h
    }
    ```

=== "Pyrope alternative I"

    ```pyrope
    const Inner_t = (
      comb init(ref self, z, y) {
        self.a = y & z
        self.h = !(y & z)
      }
    )

    const Top2_t = (
      comb init(ref self, a, b) {
        const foo:Inner_t = (y=a, z=b)

        self.c = foo.a
        self.d = foo.h
      }
    )

    const top:Top2_t = (a, b)
    ```

=== "Pyrope alternative II"

    ```pyrope
    const Inner_t = (
      comb init(ref self, z, y) {
        self.a = y & z
        self.h = !(y & z)
      }
    )

    const Top2_t = (
      mut foo:Inner_t = nil,
      comb init(ref self, a, b) {
        (self.c, self.d) = self.foo(y=a, z=b)
      }
    )

    const top:Top2_t = (a, b)
    ```


The top-level `top2` can be any lambda kind (here a `comb`), but as the
alternative Pyrope syntax shows, the inner modules may be in tuples or direct
module calls. The are advantages to each approach but the code quality should
be the same.


## Registers

```pyrope
reg a:u4 = 3
sat a = a + 1

reg b = 4
if cond {
  reg c = nil           // weird as reg, but legal syntax
  c = b + 1
  b = 5
}

// RTL equivalent
wire a_next = nil                                  // final in-cycle value of 'a'
a_next = ...                                       // (driver elaborated from the writes to 'a')
a_qpin = __flop(reset_pin=ref reset, clock_pin=ref clk, initial=3, din=a_next)
tmp    = __sum(A=(a_qpin, 1))
a      = __mux(tmp[4], tmp#[0..=3], 0xF)    // saturate, not wrap

wire b_next = nil
b_next = ...
b_qpin = __flop(reset_pin=ref reset, clock_pin=ref clk, initial=4, din=b_next)
b      = __mux(cond, b_qpin, 5)

wire c_cond_next = nil
c_cond_next = ...
c_cond_qpin = __flop(reset_pin=ref reset, clock_pin=ref clk, initial=0, din=c_cond_next)
c_cond      = __sum(A=(b, 1))
```
