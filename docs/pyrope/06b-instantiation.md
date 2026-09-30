
# Instantiation

Instantiation is the process of translating from Pyrope to an equivalent set
of gates. The gates could be simplified or further optimized by later compiler
passes or optimization steps. This section provides an overview of how the
major Pyrope syntax constructs translate to gates.


## Basic gates

The `// RTL equivalent` code in this chapter uses the `__` basic gates, one per
LGraph cell. A basic gate is an ordinary call: every argument is named with
the cell's LGraph pin name, unless a call
[naming exception](06-functions.md#argument-naming) applies (a single-pin gate
may take its value unnamed); an ambiguous call is a compile error. The
``lec(gold=…, `impl`=…)`` checks compare the two versions. The pins used here:

* `__mux(s=cond, p1=f, p2=t)`: `t` when `s` is true, `f` otherwise.
* `__hotmux(p0=c0, p1=v0, p2=c1, p3=v1, ...)`: one (control, value) pair per
  arm, with an optional trailing default.
* ``__sum(`as`=(...), bs=(...))``: the `as` values added, the `bs` values subtracted.
* ``__and(`as`=(...))``, ``__or(`as`=(...))``, ``__xor(`as`=(...))``, ``__ror(`as`=x)``:
  bitwise over the `as` values (`__ror` reduces the bits of one value).
* `__not(a=x)`, `__shl(a=x, b=amt)`, `__get_mask(a=x, mask=m)`.
* `__flop(din=d, initial=v, clock_pin=clk, reset_pin=rst, ...)`.


## Conditionals

Conditional statements like `if/else` and `match` translate to multiplexers
(muxes).


A trivial `if/else` with all the options covered is a simple mux.

```pyrope
mut res:S4 = nil

if cond {
  res = a
} else {
  res = b
}

// RTL equivalent (mux of 4 bits in a,b,res2)
mut res2:S4 = __mux(s=cond, p1=b, p2=a)

lec(gold=res, `impl`=res2)
```

An expression `if/else` is also a mux.

```pyrope
mut res = if cond { a } else { b }

// RTL equivalent
mut res2 = __mux(s=cond, p1=b, p2=a)

lec(gold=res, `impl`=res2)
```

An explicit conditional assignment is also a mux.

```pyrope
mut res = a
if not cond {
  res = b
}

// RTL equivalent
mut res2 = __mux(s=cond, p1=b, p2=a)

lec(gold=res, `impl`=res2)
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
mut tmp = __mux(s=cond2, p1=a, p2=c)
mut res2 = __mux(s=cond1, p1=tmp, p2=b)

lec(gold=res, `impl`=res2)
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

// RTL equivalent — one (control, value) pair per arm, `a` as the trailing default
mut res2 = __hotmux(p0=cond1, p1=b, p2=cond2, p3=c, p4=a)
assume(!(cond1 and cond2)) // one hot check

lec(gold=res, `impl`=res2)
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
// one (control, value) pair per arm
mut res2 = __hotmux(p0=cond1, p1=b, p2=cond2, p3=c, p4=cond3, p5=d)
assume ( cond1 and !cond2 and !cond3)
    or (!cond1 and  cond2 and !cond3)
    or (!cond1 and !cond2 and  cond3)    // one hot check (no else allowed)

lec(gold=res, `impl`=res2)
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
    const lhs2   = __or(`as`=(v1, v2))
    const lhs2_v = __or(`as`=(__and(`as`=(v1.[valid], v1)), __and(`as`=(v2.[valid], v2))))

    lec(gold=lhs, `impl`=lhs2)
    lec(gold=lhs.[valid], `impl`=lhs2_v)
    ```

=== "Usual expression"

    ```pyrope
    mut lhs = v1 + v2

    // RTL equivalent
    const lhs2   = __sum(`as`=(v1, v2))
    const lhs2_v = __and(`as`=(v1.[valid], v2.[valid]))

    lec(gold=lhs, `impl`=lhs2)
    lec(gold=lhs.[valid], `impl`=lhs2_v)
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
    const tmp  = __mux(s=cond2, p1=v0, p2=v2)
    const lhs2 = __mux(s=cond1, p1=tmp, p2=v1)

    const tmp_v  = __mux(s=cond2, p1=v0.[valid], p2=v2.[valid])
    const lhs2_v = __mux(s=cond1, p1=tmp_v, p2=v1.[valid])

    lec(gold=lhs, `impl`=lhs2)
    lec(gold=lhs.[valid], `impl`=lhs2_v)
    ```

=== "Lambda call (inlined)"

    ```pyrope
    comb f(a, b) -> (r) { r = if a == 0 { 3 } else { b } }

    mut lhs = c
    if cond {
       lhs = f(a, b)                           // a and b match the parameter names
    }

    // RTL equivalent
    const a_cond = __not(a=__ror(`as`=a))              // a == 0
    const tmp    = __mux(s=a_cond, p1=b, p2=3)       // if a_cond { 3 } else { b }
    mut lhs2   = c
    lhs2       = __mux(s=cond, p1=lhs2, p2=tmp)

    // a == 0 returns 3 (needs only a); otherwise b (needs a and b)
    const tmp_v  = __mux(s=a_cond, p1=__and(`as`=(a.[valid], b.[valid])), p2=a.[valid])

    const lhs2_v = __mux(s=cond, p1=c.[valid], p2=tmp_v)

    lec(gold=lhs, `impl`=lhs2)
    lec(gold=lhs.[valid], `impl`=lhs2_v)
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
    mod sum(a:U32, b:U32) -> (x:U32@[0]) { wrap x = a + b }

    mod sub(a:U32, b:U32) -> (x:U32@[0]) {
      const tmp = sum(a, b)      // instance tmp,sum

      x = sum(a=tmp, b=3)          // instance x,sum
    }

    mod top(a:U32, b:U32, c:Bool) -> (x:U32@[0]) {

     x = sub(a, b).x
     if c {
       const tmp = 3
       wrap x += sub(a=b, b=tmp).x
     }
    }
    ```

=== "Instance"
    ```pyrope
    mod sum(a:U32, b:U32) -> (x:U32@[0]) { wrap x = a + b }

    mod sub(a:U32, b:U32) -> (x:U32@[0]) {
      const tmp = sum(a, b)      // instance tmp

      x = sum(a=tmp, b=3)          // instance x
    }

    mod top(a:U32, b:U32, c:Bool) -> (x:U32@[0]) {

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
     x_0 = sub(a=sub_arg_0, b=sub_arg_1).x // instance x_0 (SSA)
    }
    ```

### name: explicit instance name

The default instance name is the assigned variable, which a generator or a
Verilog translation often cannot choose. An attribute block between the callee
and the argument list pins it:

```pyrope
mod counter(en:Bool) -> (v:U8@[0]) {
  reg c:U8 = 0
  if en { wrap c = c + 1 }
  v = c
}

pub mod top(en:Bool) -> (r:U8@[0]) {
  mut inst = counter::[name=u_cnt](en=en)  // instance u_cnt, not inst
  r = inst.v
}
```

* `name` is the only attribute allowed at a call site. Any other key
  (`f::[color=2](…)`) or a bare flag (`f::[donttouch](…)`) is a compile error.
* The value is a bare identifier or a comptime string. Like
  [`lg`](04b-attributes.md#lg-explicit-lgraph-name) it may be any string
  accepted as a name, even one that is not a legal Pyrope identifier
  (`name="u.add[0]"`).
* It renames the instance, not the variable and not the module: the outputs are
  still read through the assigned variable (`inst.v`), the generated module
  name is `lg`'s business, and the instance hierarchy uses the new name — a
  `formal` or `test` block reaches the register as `top.u_cnt.c`, and
  `top.inst.c` no longer resolves.
* On a `comb` call that the compiler inlines there is no instance to name; the
  attribute is accepted and changes nothing in the generated hardware.

A call site is a different position from a declaration. `mut
inst::[name=u_cnt] = counter(…)` sets an attribute on the *variable* `inst`
(and reads `u_cnt` as an ordinary expression), so it does **not** name the
instance — the attribute block must sit before the `(`.

### Clock, reset, and output timing of an instance

Clocks and resets bind by type, not by name: an input declared
[`Clock` or `Reset`](07-typesystem.md) is the clock or reset, whatever its
name. An instance's clock and reset follow the
[implicit clock and reset](04b-attributes.md#implicit-clock-and-reset) rules:

* An unbound `Clock` or `Reset` input of a `mod`/`pipe` child is wired to
  the caller's single `Clock` or `Reset` input. The same happens for the
  `clock:Clock`/`reset:Reset` input minted in a child that has registers and
  no `Clock`/`Reset` input (a non-`Clock` input already named `clock`, or a
  non-`Reset` one named `reset`, is a compile error). When the caller has no
  `Clock` (`Reset`) input, one is minted in the caller too.
* A caller with two or more `Clock` inputs has no implicit clock. It names
  the clock on every register (`clock_pin=clk_b`), and binds every child
  `Clock` input explicitly (`counter(clk=clk_b, …)`); an unbound one is a
  compile error. The same holds for two or more `Reset` inputs, `reset_pin`,
  and child `Reset` inputs.
* A `Clock` input can never be bound to a constant (`counter(clk=true, …)`
  is a compile error). A `Reset` input is Bool-like: it takes any `Bool`
  expression, and the constant `false` means "no reset".
* A `comb` cannot declare a `Clock` or `Reset` input (compile error), so
  nothing is wired into it. An input a `comb` never reads may be omitted, and
  omitting one it reads is a missing-argument error. A read counts once the
  body is folded at compile time: an input read only under a condition that
  folds to `false` is not read.

A caller sees each child output at that output's own declared landing cycle
`@[N]`. See [Cycle rules for `mod` outputs](06-functions.md#cycle-rules-for-mod-outputs).

```pyrope
mod counter(clk:Clock, rst:Reset, en:Bool) -> (v:U8@[0]) {
  reg c:U8 = 0                        // clocked by 'clk', reset by 'rst'
  if en { wrap c = c + 1 }
  v = c
}

pub mod top(ck:Clock, rs:Reset, en:Bool) -> (r:U8@[0], s:U8@[0]) {
  const a = counter(en=en)            // OK: 'clk' and 'rst' wired to top's 'ck' and 'rs'
  const b = counter(clk=true, en=en)  // error: a Clock bound to a constant
  r = a.v
  s = b.v
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
    mod case_1_counter(runtime:U8) -> (res:U16@[0]) {

      mut r = (
        reg total:U16 = 0,          // r is reg, everything is reg
        comb increase(ref self, a) -> (r) {
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
    mod case_1_counter(runtime:U8) -> (res:U16@[0]) {

      mut r = (
        reg total:U16 = 0,
        comb increase(ref self, a) -> (r) {
          puts("hello")

          r = self.total
          wrap self.total = r + a
        }
      )

      if runtime == 2 {
        puts("hello")

        const old = r.total
        wrap r.total = old + 3
        res = old
      }elif runtime == 4 {
        puts("hello")

        const old = r.total
        wrap r.total = old + 9
        res = old
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
types, and constants can be imported. Registers are not imported; referencing
an instantiated register across scopes is planned through the synthesizable
string-path `regref` (TBD, see [Implementation status](15-tbd.md)); the
single-cell `test`-block
[`regref`](05b-statements.md#test-only-statements) is a separate,
implemented construct.


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
reg r:U16 = 3 // reset sets r to 3
r = 2             // non-reset assignment

reg array:[4]U16 = (1, 2, 3, 4)  // reset values

reg r2:U128 = conf.get("my_data.for.r2")

reg array:[] = conf.get("some.conf.hex.dump") // dynamic size from config
```


The assignment during declaration to a register is always the reset value. A
constant or tuple initializer on a register array is restored to every entry in
**one** cycle of `reset`, exactly like a scalar `reg`; only a reset *lambda*
(below) runs once per reset cycle. If the assignment is a method (a lambda
referenced by name, **not** called — i.e., no parentheses), the method is
invoked every cycle during reset.

```pyrope
mod array_reset(ref self) {
  reg reset_iter:U10 = nil // no reset flop (a `nil` initializer binds no reset)

  self[reset_iter].state = I

  wrap reset_iter = reset_iter + 1
}

reg array:[1024]Tag:[clock_pin=my_clock] = array_reset  // no () — pass the method
```


Since the reset can be high many cycles, it may be practical/necessary to have
a reset inside the reset lambda. To guarantee determinism, any register
inside the reset lambda can be either asynchronous reset or a register
without reset signal.


```pyrope
mod my_flop_reset(ref self) {
  reg reset_counter:U3:[async=true] = 0 // asynchronous reset

  self[reset_counter] = reset_counter
  wrap reset_counter += 1
}

reg my_flop:[8]U32 = my_flop_reset
```

A related functionality and constrains happen when a tuple have some register
fields and some non-register fields. The same reset lambda is called every
cycle Similarly a tuple can have a reset when assigned to a register.


=== "Mixed tuple reset with constants"

    ```pyrope
    const Mix_tup = (
      reg flag:Bool = false,
      mut state:U2 = nil
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
      reg flag:Bool = false,
      mut state:U2 = nil,
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
reg my_async_other_reg:U8:[
  async = true,
  clock_pin = clk2,        // a connection to clk2, not a read of its value
  reset_pin = reset33      // a connection to reset33, not a read of its value
] = 33 // initialized to 33 at reset


if my_async_other_reg == 33 {
  my_async_other_reg = 4
}

assert(my_async_other_reg in (4, 33))
```

### retime

!!! WARNING "TBD"
    The `retime` attribute is not yet implemented in LiveHD (it parses, but
    nothing lowers it — the compiler reports `reg-attr-not-lowered`). See
    [Implementation status](15-tbd.md).

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
      assign h = ~(y & z);

    endmodule

    module top2(input a, input b, output c, output d);

    inner foo(.y(a),.z(b),.a(c),.h(d));

    endmodule
    ```

=== "Pyrope equivalent"


    ```pyrope
    comb inner(z, y) -> (a, h) {
      a = y & z
      h = ~(y & z)
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
        self.h = ~(y & z)
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
        self.h = ~(y & z)
      }
    )

    const Top2_t = (
      mut foo:Inner_t = nil,
      comb init(ref self, a, b) {
        const r = self.foo(y=a, z=b)  // `(self.c, self.d) = ...` is an error
        self.c = r.a
        self.d = r.h
      }
    )

    const top:Top2_t = (a, b)
    ```


The top-level `top2` can be any lambda kind (here a `comb`), but as the
alternative Pyrope syntax shows, the inner modules may be in tuples or direct
module calls. The are advantages to each approach but the code quality should
be the same.


## Registers

!!! WARNING "TBD"
    The `// RTL equivalent` half of the block below is illustrative
    pseudo-code: `__flop(...)` is not currently implemented — `lhd compile`
    rejects it with `call to undefined function '__flop'`. See
    [Implementation status](15-tbd.md).

```pyrope
reg a:U4 = 3
sat a = a + 1

reg b = 4
if cond {
  reg c = nil           // weird as reg, but legal syntax
  c = b + 1
  b = 5
}

// RTL equivalent
wire a_next = nil                                  // final in-cycle value of 'a'
// a_next = ...                                       // (driver elaborated from the writes to 'a')
a_qpin = __flop(reset_pin=reset, clock_pin=clock, initial=3, din=a_next)
tmp    = __sum(`as`=(a_qpin, 1))
a      = __mux(s=tmp#[4], p1=tmp#[0..=3], p2=0xF)   // saturate, not wrap

wire b_next = nil
// b_next = ...
b_qpin = __flop(reset_pin=reset, clock_pin=clock, initial=4, din=b_next)
b      = __mux(s=cond, p1=b_qpin, p2=5)

wire c_cond_next = nil
// c_cond_next = ...
c_cond_qpin = __flop(reset_pin=reset, clock_pin=clock, initial=0, din=c_cond_next)
c_cond      = __sum(`as`=(b, 1))
```
