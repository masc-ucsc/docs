# Lambdas


A `lambda` consists of a sequence of statements that can be bound to a variable.
The variable can be copied and called as needed. Unlike most languages, Pyrope
only supports anonymous lambdas. The reason is that without it lambdas would be
assigned to a namespace. Supporting namespaces would avoid aliases across
libraries, but Pyrope allows different versions of the same library at
different parts of the project. This will effectively create a namespace alias.
The solution is to not have namespaces but relies upon variable scope to decide
which lambda to call.


!!! Observation

    Allowing multiple version of the same library/code is supported by Pyrope.
    It looks like a strange feature from a software point of view, but it is
    common in hardware to have different blocks designed/verified at different
    times. The team may not want to open and modernize a block. In hardware, it
    is also common to have different blocks to be compiled with different
    compiler versions. These are features that Pyrope enables.


Pyrope divides lambdas into four categories: `comb`, `pipe`, `mod`, and
`fluid`.

- `comb` is pure combinational logic. The outputs are purely a function of
  the inputs — no registers, no state, no cycle-level side effects. A
  `comb` may not declare a `reg` and may not call a `pipe`, `mod`, or
  `fluid`, and it may not declare a `Clock` or `Reset` input (compile
  error). The only state it can hold is debug state marked `::[debug]`,
  which is forbidden from influencing non-debug outputs (the compiler
  enforces this). Any external call inside a `comb` can only affect debug
  statements (e.g., `puts`), not synthesizable code. `comb` can use `ref`
  arguments to modify tuples; `ref` is equivalent to having the argument
  as both input and output, which is still purely combinational. `comb`
  resembles `pure functions` in normal programming languages.

- `pipe` is a fixed-latency pipeline: every output lands exactly `N` cycles
  after the inputs it derives from (`out[t] = f(in[t-N], state)`), and there
  is never a combinational path from an input to an output. The latency is
  written as an argument to the keyword: `pipe[3] foo(...)` is fixed
  3-cycle, `pipe[1..=3] foo(...)` lets the caller pick within a range, and
  bare `pipe foo(...)` leaves the latency fully flexible for the caller to
  specify via `stage[N]` at the call site. The reference behavior is a
  `comb` with N flops appended at the outputs, but flop placement is free
  (retiming, SRAM macros with registered inputs, ...) as long as the
  contract holds. `pipe` can use `reg` for feedback state (accumulators,
  counters); a pure feedforward `reg` is an explicit pipeline stage and
  counts toward `N`. See [Pipelining](06c-pipelining.md) for the
  accept/reject rules (stage inference).

- `mod` has no constraints on registers or output structure. It can be
  combinational, Mealy, Moore, or a pipeline orchestrator. Unlike `pipe`,
  where every output lands at the same declared latency, **each `mod`
  output declares its own landing cycle at the interface** with `@[N]`
  (`N >= 0`): `mod f(a:U8) -> (x:U8@[2], y:U8@[0])`. A cycle-0 output is a
  combinational feedthrough — legal in `mod`, forbidden in `pipe`. A
  registered output is declared `reg name:T@[H]`: the register's q value
  is the output (no appended flop), and `H` declares the cycle it lands
  at — the home stage for a state register, `σ(din)+1` for a feedforward
  stage register. The empty form `@[]` is an explicit opt-out: the output
  still carries a timing slot, but with min and/or max set to `nil`
  (unconstrained) — this is also how foreign Verilog modules, which carry
  no markings, ingest. A `mod` output with no `@[...]` declaration at all
  is a compile error. When a `mod` calls `pipe` lambdas and needs to align
  their outputs with other signals, it uses the `stage[N]` declaration
  modifier and the `@[N]` cycle type check (these constructs used to
  belong to the separate `flow` category, which has been merged into
  `mod`). See [Cycle rules for `mod` outputs](#cycle-rules-for-mod-outputs).

- `fluid` (TBD: not yet implemented) is a transactional block with valid/retry handshakes on its
  inputs and outputs. Fluid availability is dynamic: a transaction advances
  only when `.[fire]` is true (`.[valid] and !.[retry]`). A `fluid` call
  must be bound with a `fluid` declaration, and fluid calls are allowed only
  inside `mod` and `fluid` lambdas. See [Fluid Blocks](06d-fluid.md).

Generating an LGraph module (for Verilog or simulation) requires a concrete
fully typed interface and a fixed, fully named/ordered port list. A declaration
can provide that directly, or it can be **not fully typed** — an untyped
non-`self` input, a `(...args)` var-arg, or a generic `<T>` — and defer
module generation until a call site binds the missing shape. `self`/`ref self`
methods derive `self`'s type from the enclosing tuple.

`pipe` and `mod` lambdas are module boundaries, and a concrete `pipe`/`mod`
call lowers to a module instance. A fully typed `pipe`/`mod` lowers to one
module directly. A not-fully-typed `pipe`/`mod` is a **deferred template**: it
produces no module at definition time and is **specialized per call site** into
a concrete module named by the actual types (`mod foo(a)` called with a `U8`
actual mints `foo__U8`; a `U16` actual mints `foo__U16`; identical signatures
share one module, each call still its own instance). Specialization keys on
each actual's **declared** type, so an **untyped actual** feeding such a
boundary is a compile error at the call site (annotate it, e.g. `x:U8`) — a
hardware port needs an explicit width.

A `comb` that is not fully typed (an untyped input, an open array length, a
var-arg, or generics) is
a **template**: it is always **inlined** at each call and no separate LGraph is
generated. A fully typed `comb` is a normal unit: it has its own LGraph module
and can be the compile top; at a call site the compiler may still inline its
body or keep an instance of that module. An input default does not make a
`comb` a template: in the fully typed `comb f(a:U8, b:U8=3)`, `b` is a real
port of `f`'s module, and the default applies only at a call site that omits
`b`. A var-arg's tuple (and each `args[i]` read) resolves at the call site;
for a generated module, the specialized call must provide the final
fixed port order and names. A template that is exported (`pub`) but never
specialized in its own unit simply yields no module — it is not an error, and
neither is an untyped or var-arg template selected as the synthesis top. A
generic lambda selected as the top is the one exception: it is specialized with
its declared generic defaults and keeps its own name (see the generic entry
point below); a generic with no default is then a compile error
(`top-generic-default`).

Methods are `comb`/`pipe`/`mod`/`fluid` lambdas that have `self` as the first
argument, which allows operating on tuples.

=== "Combinational (comb)"
    ```pyrope
    comb add(a, b) -> (result) {  // Same as const add = comb(a, b) -> (result)
      result = a + b
    }
    ```

=== "Pipeline (pipe)"
    ```pyrope
    pipe[3] multiply(a:U16, b:U16) -> (result:U32) { // fixed 3-cycle latency
      result = a * b
    }

    pipe[1..=3] add_pipe(a:U32, b:U32) -> (result:U32) { // caller picks 1-3 cycles
      wrap result = a + b
    }

    pipe flexible_mul(a:U16, b:U16) -> (result:U32) { // bare: caller picks via stage[N]
      result = a * b
    }
    ```

=== "Module with pipeline orchestration (mod)"
    ```pyrope
    pipe mul(a:U16, b:U16) -> (c:U32) { c = a * b }
    pipe add(a:U32, b:U32) -> (c:U32) { wrap c = a + b }

    mod multiply_add(in1:U16, in2:U16) -> (out:U32@[4]) {
      stage[3] tmp     = mul(a=in1, b=in2)     // mul picks 3 stages
      stage[3] in1_d   = in1                   // delay in1 by 3
      stage[1] out@[4] = add(a=tmp@[3], b=in1_d@[3]) // adder takes 1 stage; out@[4] typechecks
    }

    mod accum(in1:U16, in2:U16) -> (out:U32@[3]) {
      reg total:U32 = 0                  // mod can use reg (state, home stage 3)
                                         // body-reg landing rule not settled, see Implementation status
      stage[3] tmp = mul(a=in1, b=in2)
      wrap total = total + tmp@[3]       // state q + stage-3 value: coherent
      out = total                        // q read; out lands at cycle 3
    }
    ```

=== "Module with registered outputs (mod)"
    ```pyrope
    mod counter(enable:Bool) -> (reg count:U8@[0] = 0) {  // '= 0': reset value
      if enable { wrap count += 1 }      // conditional write -> state reg, home 0
    }

    mod add_reg(a:U8, b:U8) -> (reg result:U9@[1]) {
      result = a + b                     // unconditional write -> stage reg; q at 1
    }
    ```

=== "Fluid block"
    ```pyrope
    fluid fpu(req:FpuReq) -> (resp:FpuResp) {
      req.[retry] = busy

      if req.[fire] {
        start_operation(req)
      }

      resp.[valid] = result_pending
      if resp.[fire] {
        result_pending = false
      }
    }
    ```

## Cycle rules for `mod` outputs

The `@[N]` on each `mod` output is a timing contract that the compiler
checks on both sides of the boundary:

* **Inputs are cycle 0.** An input is driven at each call, so `reg` on an
  input is a compile error.
* **Each output lands at its declared cycle.** The value assigned to an
  output must land at the `N` its `@[N]` declares; a mismatch is a compile
  error. A value computed combinationally from the inputs lands at cycle 0;
  `stage[N]` and `pipe` calls move a value to a later cycle.
* **`reg` in the output list** (`-> (reg q:T@[N])`) declares a persistent
  register whose q is the output (no flop is appended after it). `= v` after
  the cycle (`-> (reg q:T@[N] = 0)`) is its reset value; without it the
  register has no reset. A
  conditional or feedback write makes it a state register that lands at its
  home stage (`counter` above: `@[0]`). An unconditional write of a fresh
  value makes it a stage register whose q lands one cycle after its input
  (`add_reg` above: `@[1]`).
* **A caller sees each child output at that output's own declared cycle.**
  Given `mod f(a:U8) -> (x:U8@[2], y:U8@[0])` and `const c = f(a=v)`, `c.y`
  is a cycle-0 value in the caller and `c.x` a cycle-2 value; combining
  `c.x` with a cycle-0 value needs an explicit alignment (`stage[2]`), exactly
  like the output of a `pipe[2]` call.
* **`@[]` opts out.** The output keeps its timing slot, but it is
  unconstrained (min and/or max `nil`).

A register declared in the *body* (a plain `reg`, not in the output list)
written every cycle from its inputs and read directly by an output lands one
cycle after them (`reg r = 0; r = d; q = r` needs `q@[1]`), whatever its clock
or reset pin and whether it is written or read whole or through bit slices.
The other body-register cases are not settled yet (see
[Implementation status](15-tbd.md)); when the cycle of a registered output
matters, declare the register in the output list or use `stage[N]`.

`::[timecheck=false]` (old spelling `hdl`) on a lambda
(`mod legacy::[timecheck=false](…)`) turns off **all** the timing checks
inside it: the landing-cycle checks, the cycle-mix checks (including through
the children's declared latencies), and the same-cycle `wire`-ring
(combinational loop) check. In such a lambda a plain `reg` is cycle-0 state
and an undriven `wire` reads `x`. The Verilog importer and the Pyrope writer
set it on the code they generate; in hand-written code it is an escape hatch
only (see [timecheck](04b-attributes.md#timecheck-timing-check-escape-hatch)).

## Declaration

There are two interchangeable forms for declaring a lambda. The **kind-first
declaration form** is preferred — it matches the rest of Pyrope's grammar,
where every declaration starts with a kind keyword (`const`/`mut`/`reg` for
data, `comb`/`pipe`/`mod`/`fluid` for lambdas):

```pyrope
comb get_five() -> (v) { v = 5 }              // kind-first form
```

Both forms are legal at top level, inside tuple literals, and inside code
blocks. The kind-first form is shorter, reads like a method declaration in
most languages, and lets an agent scan for all lambda declarations with a
single pattern. Lambdas are always immutable.

Only anonymous lambdas are supported — there is no global scope for
functions, procedures, or modules. The only way for a file to access a
lambda is to have access to a local binding with a definition or to
`import` a `pub` lambda from another file.

```pyrope
const a_3 = { 3 }             // just scope, not a lambda. Scope is evaluated now
comb a_lambda() -> (v) { v = 4 }   // kind-first form

pub comb get_five() -> (v) { v = 5 }   // pub: can be imported by other files

const x = a_3()             // error: explicit call not possible in scope
const x = a_lambda()        // OK, explicit call needed when no arguments

cassert(a_3 == 3)
type a_lambda_t = comb()->(v)
cassert(a_lambda equals a_lambda_t)
cassert(a_lambda() == 4)
```

The lambda definition has the following fields:

```txt
[GENERIC] [INPUT] [-> OUTPUT] |
```

+ `GENERIC` is an optional comma separated list of names between `<` and `>`.
  Each name binds to any **compile-time entity** — a type (`U8`, a `type`
  alias, a struct type), a comptime constant, or a lambda — and is visible
  throughout the signature and body. Unlike an input, a generic can
  constrain the types of other inputs and of outputs
  (`comb f<T>(a:T) -> (r:T)`). A name may declare a default (`<T, N=4>`); a
  defaulted generic may be omitted at the call site. A default, like a
  call-site binding, names a type, lambda or comptime const DECLARED EARLIER
  in the file (`comb f<T=Pixel>` before `type Pixel = U8` is a compile
  error: declare before use). The call site binds
  generics explicitly (`f<T=U8, N=3>(…)`) under the same naming rules as
  arguments (see "Argument naming" below: named unless the binding is
  unambiguous), or leaves a type-valued generic to inference from the
  actuals' declared types (see the binding rules after the example block).
  There is no separate comptime-parameter list — a comptime constant the
  caller picks is just a constant-valued generic. A width that depends on a
  generic is spelled `Unsigned(bits=N)` / `Signed(bits=N)` (see
  [Generic widths](#generic-widths)).

+ Lambdas do not have an explicit capture list. Name lookup is lexical, and
  an enclosing binding is always visible, but a nested lambda may READ only
  the ones that are **compile-time constants**. The rule is the same at file
  scope and inside a `comb`, `mod` or `pipe`, and it is fold-based: a
  `comptime const`, a plain `const` whose value folds to a constant
  (`const x = 2`, `const w = N * 4` with `N` comptime or a generic,
  `mut m = 3; const s = m + 1` in a `mod` body, a const accumulated by a
  loop over constants, an attribute read such as `const W = a.[bits]` of an
  input `a:U8`), the generics of an enclosing lambda, the index of an
  enclosing `for` (and its element when the iterable is comptime), imports,
  types, and lambdas. The compiler records those references as explicit
  comptime dependencies of the lambda (it recomputes each such const inside
  the lambda); no capture syntax is written by the programmer. Reading an
  enclosing **runtime** value — a `const` whose value depends on an input, a
  `reg`, a `wire` or a `mod` instance (`const s = a + 1` with `a` an input,
  or `const s = m` after `addby(ref m, by=a)`: a write through `ref` counts
  like an assignment), a `mut` read directly, or the element of a `for` over runtime values
  (`for x in (a, b)`) — from a nested lambda is a compile error at the read:
  pass the value as an input (a tuple input can bundle several). Reading a
  name with no accessible declaration is always a compile error at the read,
  never `nil` or a hidden input.

+ A lambda's inputs, outputs and generics may not reuse the name of a
  visible enclosing const, type or lambda (`const W = 4` then
  `mod m(W:U8)`): that is shadowing, a compile error like any other. A
  reserved type word (`U8`, `Bool`, `Clock`, ...) cannot name one either;
  the backticked spelling (`` `U8` ``) is an ordinary name (see
  [Identifiers](02-basics.md#identifiers)).

+ `INPUT` has a list of inputs allowed with optional types. An input may
  declare a **default value** (`comb f(a:U8, b:U8=3) -> …`), on a `comb` or
  a `mod`: a call that omits that input takes the default, and a call that
  provides it always uses the provided value (`f(a=1)` binds `b=3`,
  `f(a=1, b=9)` binds `b=9`). A default never makes a lambda a template:
  in a fully typed `comb` or `mod`, the defaulted input is a real port of its
  module and the default is applied at each call site that omits it. The
  default expression evaluates in
  the parameter tuple's scope. A `comb` default may reference earlier
  parameters (`comb example(a:Signed, b:Signed=a+5)`, see the tuple-scope
  example in [Variables](04-variables.md)), visible comptime bindings, and
  generic names (`b:U8=N`). A `mod`/`pipe` default is what the CALLER drives
  the omitted port with, so it must fold to a compile-time constant. Any
  expression that folds is legal: a literal, a generic (`c:U8=N`,
  `c:U8=N*2`, folded per specialization), a `comptime const`, an attribute
  read (`w:U8=W.[bits]`, also of an earlier input: `b:U8=a.[bits]`), an enum
  entry (`c:Color=Color.Green`), a `comb`
  call with constant arguments (`b:U8=g(a=3)`), an `if` expression over
  constants, or arithmetic and `std.clog2` over them. A `mod` default that
  reads another input's value (`mod m(a:U8, b:U8=a+1)`), or that does not
  fold (a `mod` instance), is a compile error (`default-not-comptime`): pass
  `b` at the call, or compute it inside the body. A default must fit the
  input's type, like an argument. An argument must fit
  its parameter's declared type (see [Argument types](#argument-types)).
  `()` indicates no
  inputs. A trailing `...args` captures the arguments left over after binding
  the fixed parameters. In a named call, each leftover argument becomes a
  field of the capture tuple: `f(a=1, b=2)` with `comb f(...args)` makes
  `args.a == 1` and `args.b == 2`. The capture may be empty. It does not
  make fixed parameters optional: `comb gg(c:U32, ...rest)` still requires
  `c`, so `gg(a=2, b=2)` is an invalid call.
  The capture's name is local to the function, not a parameter to bind
  directly: `f(args=(1, 2))` captures a field named `args`, accessed inside
  the function as `args.args`. Positional leftovers are not captured:
  `f(1, 2, 3)` is an error when `f` declares `...args`.
  Var-args are supported on a `comb` (which can
  inline without generating a module). A `pipe`/`mod`/`fluid` hardware boundary
  can be written with varargs as a deferred template, but each generated module
  instance needs a concrete call that resolves them into a fixed port list.

+ `OUTPUT` has a list of outputs allowed with optional types. `-> ()`
  indicates no outputs. The `-> (...)` clause is **mandatory**; omitting it
  is a compile error. The only exemption is a `self` method (first input
  parameter named `self`, with or without `ref`): it acts through the
  receiver — setters, constructors, or debug-only prints/asserts — and may
  omit the clause. Outputs are **always declared by
  name** — there are no anonymous/positional return lists. The body assigns
  to those names. An output may have the same Pyrope name as an input:
  `comb f(x) -> (x) { x = x + 1 }` is legal. In the lambda body, reads before
  the output assignment use the input value and the assignment binds the output
  field. This is a source-level name match, not a bidirectional hardware port:
  LNAST can represent the shared source name, but LGraph/Verilog generation
  emits distinct input and output signal names.

Dispatch between alternative lambdas is always explicit at the call site
using `if`/`elif` chains. Pyrope does not have a `where` clause on lambda
declarations (an earlier design did); this keeps the call flow visible and
locally readable.

```pyrope
comb add1(...x) -> (r) { r = x.a + x.b + x.c }       // named capture, single output
comb add2(a, b, c) -> (r) { r = a + b + c }         // constrain inputs to a,b,c
comb add3(a, b, c) -> (r:U32) { r = a + b + c }     // constrain result to U32
comb add4(a:U32, b:S3, c) -> (r) { r = a + b + c }  // constrain some input types
comb add5(a, b:a, c:a) -> (r) { r = a + b + c }     // constrain inputs to same type
comb add6<T>(a:T, b:T, c:T) -> (r) { r = a + b + c} // generic, single output

// To overload, declare each lambda separately and gather them:
const add = [add1, add2, add3, add4, add5, add6]
// A call through the set dispatches to the FIRST gathered lambda whose
// signature can accept the call (tuple order is the tie-break — no ambiguity
// error). "Can accept" uses the SAME argument rules as a direct call (so
// same-kind positional args must still be named); if no candidate matches it
// is a compile error. Dispatch is resolved at compile time, so the selected
// lambda's body is what lowers — there is no runtime mux of the alternatives.
const s = add(a=1, b=2, c=3)   // selects add1: its capture accepts these names

const x = 2                           // a compile-time value: comptime, visible below
comb addx1(a) -> (r) { r = x + a }    // OK: reads the constant `x`
comb addx3(a, k) -> (r) { r = k + a } // runtime values are passed as inputs, addx3(a=1, k=x)

mod top(b:U8) -> (o:U9@[0]) {
  mut m = 3
  const s = m + 1                     // folds to 4: a compile-time constant
  comb adds(a) -> (r) { r = s + a }   // OK: reads the constant `s`
  const t = b + 1                     // computed from the input `b`: a runtime value
  comb addt(a) -> (r) { r = t + a }   // error: `t` is runtime, not readable in a nested lambda
  o = addx3(a=b, k=t)                 // OK: pass it as an input
}

/// Visible comptime bindings are available lexically:
comptime const Scale = 2
comb addx2(a) -> (r) { r = Scale + a }       // OK: Scale is comptime

/// Imports are comptime aliases:
const lib = import("lib.math")
comb is_add(op:lib.OpType) -> (r) { r = op == lib.AddOp }

mut y = (
  mut val:U32 = 1,
  comb inc1(ref self) { wrap self.val += 1 } // no outputs; mutates via ref (U32 wraps)
)

comb my_log::[debug](...inp) -> () { // no outputs; side-effecting print
  print("logging:")
  for i in inp {
    print(" {i}")
  }
  puts()
}

comb f<X>(a:X, b:X) -> (r) { r = a + b }    // enforces a and b with same type
cassert(f(a=U22(33), b=U22(100)) == 133)    // X = U22 (inferred; args named per
                                            // the argument-naming rules below)
cassert(f<U8>(a=1, b=2) == 3)               // X = U8 (explicit call-site binding)

comb addk<T, K=1>(a:T) -> (r) { r = a + K } // K: constant generic with default
cassert(addk<U8>(a=3) == 4)                 // K defaults to 1 (single unnamed
                                            // binding is unambiguous → T)
cassert(addk<T=U8, K=10>(a=3) == 13)        // named bindings, same rules as args

comb inc(v:U8) -> (o:U9) { o = v + 1 }
comb apply<F>(a:U8) -> (r) { r = F(v=a) }   // F: lambda-valued generic
cassert(apply<inc>(a=3) == 4)

comb addd(a:U8, b:U8=3) -> (r:U9) { r = a + b } // input default; not a template: `b` is a port
cassert(addd(a=1) == 4)                         // b omitted: takes the default 3
cassert(addd(a=1, b=9) == 10)                   // a provided b overrides the default

my_log(value=a, flag=false, next=x + 1) // OK: three fields captured in inp
my_log(a, false, x + 1)            // error: the arguments must be named

comb tag_log::[debug](a, ...inp) -> () {
  print("{a}:")
  for i in inp {
    print(" {i}")
  }
  puts()
}
tag_log(a=a, flag=false, next=x + 1) // a binds the fixed parameter; inp captures flag and next
tag_log(a, false, x + 1)           // error: a binds the fixed parameter; positional leftovers cannot be captured
```

A generic binds **per call site** — a pure comptime-macro expansion, with the
normal typing rules applying after substitution (no implicit coercion). A
generic name may bind any compile-time entity: a type, a comptime constant,
or a lambda. After substitution, whatever is legal for the bound entity is
legal for the generic, and nothing more — `T(a)` is a cast when `T` binds a
type and a call when it binds a lambda; `a + N` needs `N` to bind a constant;
attribute queries on a generic are exactly as legal as on the substituted
entity.

Explicit call-site bindings follow the **same naming rules as arguments**
("Argument naming" below): each binding is named (`f<T=U8, N=8>(…)`) unless
it is unambiguous — a single generic name, bindings whose kinds (type vs
constant vs lambda) match only one assignment, or a bound identifier whose
name matches the generic's name. The callee may be a dotted path
(`prp.queue.make<T=Signed>(depth=16)`). A generic the call leaves unbound
takes its declared default (`<T, N=4>`) if it has one; otherwise, a generic that
appears in `:T` type positions of the parameters is inferred: it unifies
over the **declared** types of the actuals at its `:T` positions (a `U8`
actual and a `U16` actual for one `T` is a compile error —
`fcall-generic-mismatch`), while bare literals contribute only their kind, so
`f(a=1, b=2)` infers `X = Signed`. A constant- or lambda-valued generic is
never inferred — it must be bound explicitly or defaulted. On a `pipe`/`mod`
boundary each distinct binding mints its own module, exactly like the
untyped-parameter deferred templates above (`madd<T>` called with `U8`
actuals mints `madd__U8_U8`).
A declared default may be a type (`<T=U8>`), a comptime constant (`<N=3>`,
`<MODE="add">`, `<F=false>`), or a visible comptime name (`<N=SIZE>`).
Inside `<…>`, at the declaration and at the call site alike, a binding may be
a type, a literal, a name, or a **postfix** value written bare — a dotted
field or an attribute read: `f<N=x.[bits]>(…)`, `<N=cfg.width>`. Any other
expression is parenthesized — an **operator** expression (a negative constant
is one) or a call: `<N=(W*2)>`, `<N=(-3)>`, `<N=(std.clog2(D))>`. The bare
`<N=W*2>` and `<N=-3>` are syntax errors, and a bare call
(`<N=std.clog2(D)>`) is read as a type, which is an error. A generic
lambda may also be the design entry point (the compile top): it elaborates
with its declared defaults and keeps its own name, so `mod m<N=3>(…)`
selected as the top is the same hardware as a parameter-free `mod m` with
`N` written `3`. A generic with no default cannot be a top
(`top-generic-default`) — either give it a default, or select a concrete
caller as the top.

There is no constraint clause on the declaration (no `where`, no
`<T does …>`). To constrain what a caller may bind, assert it in the body:
`cassert(T does Addable)` fails at instantiation with the normal
comptime-assert diagnostics. (TBD: `does` on a generic does not fold inside a
lambda body yet, see [Implementation status](15-tbd.md).)

### Generic widths

A width that depends on a generic (or on any comptime value) is spelled
`Unsigned(bits=N)` / `Signed(bits=N)`; `U<N>`/`S<N>` (`U8`, `S20`) take only
a literal width, and there is no `U<W>` sugar. The form is valid wherever a
type is: ports, locals, tuple field types, array elements (`[N]Unsigned(bits=W)`), type
aliases (`type Row = Unsigned(bits=W)`), and generic arguments
(`<T=Unsigned(bits=W)>`).

```pyrope
mod pass_t<T>(a:T) -> (y:T@[0]) { y = a }

mod pick_row<N=4, W=8>(v:[N]Unsigned(bits=W), req:(sel:Unsigned(bits=std.clog2(N)), en:Bool))
  -> (y:Unsigned(bits=W)@[0]) {
  type Row = Unsigned(bits=W)                  // type alias
  const r:Row = if req.en { v[req.sel] } else { 0 }
  const p = pass_t<T=Unsigned(bits=W)>(a=r)    // generic argument
  y = p.y
}

pub mod pick4(v:[4]U8, sel:U2, en:Bool) -> (y:U8@[0]) {
  const i = pick_row<N=4, W=8>(v=v, req=(sel=sel, en=en))  // req.sel is 2 bits
  y = i.y
}

mod bad<W=8>(a:U<W>) -> (y:U<W>@[0]) { y = a }  // error: write Unsigned(bits=W)
```

An input such as `x:[]U8` is partially typed: each call determines its
length, while every element must fit `U8`. Different calls to the same lambda
may have different lengths. This is an ordinary tuple/array parameter, so
it supports the single-parameter tuple shorthand described below. The length
is known at compile time for each call; a generated module has a concrete
array port for that call's length.

```pyrope
comb sum_bytes(x:[]U8) -> (total) {
  total = 0
  for a in x { total += a }
}
cassert(sum_bytes(1,2) == 3)
cassert(sum_bytes(x=(1,2,3)) == 6)
// sum_bytes(1,256)             // error: 256 does not fit U8
// sum_bytes(1,true)            // error: Bool is not an integer element
```

## Argument naming

Every input argument must be named at the call site (`fcall(a=2, b=3)`),
whether the call is direct or UFCS. There are a few narrow exceptions that
let an argument be passed unnamed:

* The lambda has exactly one ordinary parameter (and `self` does not
  count, see below). With nothing to disambiguate, its name may be omitted.
  If the argument is an unnamed tuple, the extra parentheses may also be
  omitted: `f(x=(1,2,3))`, `f((1,2,3))`, and `f(1,2,3)` are equivalent
  for `comb f(x)`. The parameter may be untyped or have a compatible tuple
  or array type. This rule does not apply to a `...rest` capture.

* The calling expression is a variable whose name matches a parameter name
  (`fcall(a)` matches a parameter named `a`).

* The argument types make the mapping unambiguous with no implicit
  conversion required. This applies when each unnamed call-site value
  matches exactly one of all the parameters by type; if two parameters have
  the same type, or an untyped parameter could accept the value, the call
  must name the argument.

* `self` is always bound positionally — by the value before the dot in a
  UFCS call, or by the first positional actual in a direct call — and is
  never named at the call site.

The argument list is a named tuple (see
[all-named or all-unnamed](03-bundle.md)): after the exceptions above, every
actual must end up bound to a parameter name. An unnamed actual that no
exception covers, or a mix the exceptions cannot resolve, is a compile error.
A trailing `...args` additionally captures named arguments that do not bind
to a fixed parameter (see `INPUT` above); they need not match declared
parameter names. Required fixed parameters must still be supplied.
The same rules bind the values of a typed tuple construction
(`mut x:T = (…)`, see [Typing](07-typesystem.md)) and the pins of the `__`
basic gates (`__mux(s=c, p1=b, p2=a)`, see
[Instantiation](06b-instantiation.md#basic-gates)).

```pyrope
comb sum(x) -> (total) {
  total = 0
  for a in x { total += a }
}
cassert(sum(x=(1,2,3)) == 6)
cassert(sum((1,2,3)) == 6)
cassert(sum(1,2,3) == 6)

comb capture(...rest) -> (r) { r = rest.a + rest.b }
cassert(capture(a=1, b=2) == 3)
// capture(1,2)                  // error: positional leftovers are not captured
```

Structured tuple parameters can be supplied either as one tuple value or as
expanded dotted fields. The expanded form is legal but usually noisier; it is
useful when mapping to generated LGraph/Verilog ports, because those interfaces
are flattened into separate signals. This uses the same path expansion as
[tuple literals](03-bundle.md#dotted-field-expansion).

```pyrope
comb pick(ar:(x:U3, y:S4), cond:Bool) -> (res:S5) {
  res = if cond { ar.x + 1 } else { ar.y - 1 }
}

const a = pick(ar=(x=1, y=5), cond=true)  // compact tuple argument
const b = pick(ar.x=1, ar.y=5, cond=true) // expanded fields, same binding
```

### Argument types

Binding an argument to a parameter follows the same overflow rule as an
assignment (see [wrap and sat](04b-attributes.md#wrap-and-sat-modifier)): an
argument whose range may not fit the parameter's declared range is a compile
error, for every lambda kind, generic or not. A literal or other comptime value
is checked by value, and a runtime value by its computed range (a `U16` input
port may hold any value in `0..=65535`). An argument cannot carry
`wrap`/`sat`, so the caller narrows explicitly: slice the value, or narrow it
into a local first. (A parameter with no declared type takes the argument's
type, so nothing can overflow it.)
The kind must match too: a `Bool` parameter binds a `Bool`, and an integer
parameter binds an integer (see [Boolean ports](#boolean-ports)).

```pyrope
comb low(a:U4) -> (r:U4) { r = a }
comb low_g<N=4>(a:Unsigned(bits=N)) -> (r:Unsigned(bits=N)) { r = a }

const x:U16 = 0x1234
const r1 = low(a=x)             // error: 0x1234 overflows `a:U4`
const r2 = low(a=x#[0..<4])     // OK: explicit slice
const r3 = low(a=20)            // error: 20 overflows `a:U4`
const r4 = low_g<N=4>(a=x)      // error: same rule on a generic width
wrap const nib:U4 = x           // OK: narrowed on its own line...
const r5 = low(a=nib)           // ...then bound
```

### Binding return values

Outputs are always named, and **binding the result of a call mirrors the
argument-naming rules above**, in the other direction: binding is by name.
There is no positional return list and no binding by order.

* **One output.** The output name is dropped and the result binds directly to
  the destination. If that single output is a tuple, the destination *is* that
  tuple:

  ```pyrope
  comb pair(a:Signed, b:Signed) -> (p:(first:Signed, second:Signed)) { p = (first=a, second=b) }

  const inner = pair(a=100, b=50)   // single output `p` maps to `inner`
  cassert(inner.first == 100)       // `inner` IS the tuple (no `inner.p` level)
  ```

* **Several outputs.** Binding to one variable produces a tuple whose fields
  have the output names. Alternatively, destructure into names that **match the
  output names**, or rename a slot explicitly (`x=two.p1`). A slot that matches
  no output is a compile error, and destructuring slots never carry a type.
  There is **no mapping by position**:

  ```pyrope
  comb two(a:Signed, b:Signed) -> (p1:Signed, p2:Signed) { p1 = a; p2 = b }

  const (p1, p2) = two(a=100, b=50)        // OK: names match the outputs
  cassert(p1==100 and p2==50)

  const inner   = two(a=100, b=50)         // named tuple: inner.p1=100, inner.p2=50
  const (x, y)  = two(a=100, b=50)         // ERROR: x/y do not match p1/p2 (no by-order)
  const (x=two.p1, y=two.p2) = two(a=100, b=50)  // OK: explicit remap `var = callee.output`
  ```

There are several rules on how to handle arguments.

* **Every lambda call requires parentheses.** `foo()`, `foo(a=1,b=2)`, and
  `x.bar(y=y)` are the only forms. There is no "drop parens after newline"
  or "drop parens after a pipeline operator" sugar. This keeps every call
  site unambiguously identifiable.

* **UFCS requires `self`.** An external function `f` can be called as
  `x.f(args)` only when it declares `self`; this binds `x` positionally
  to `self`, like `f(x, args)`. A callable tuple field `x.f` is resolved
  independently and need not declare `self`. If both a callable field and
  an external function declaring `self` match, the dotted call is ambiguous
  and is a compile error.

* **If a lambda declares `self`, BOTH call forms are valid:** the UFCS
  form `value.method(args)` and the direct form `method(value, args)`
  — the receiver is simply the first positional actual. `self` binds
  only positionally; the named spelling `method(self=...)` is rejected.

### Uniform Function Call Syntax (UFCS)

Pyrope's UFCS resembles Nim or D, but the naming rules above apply at the
call site. Every argument inside the parentheses must follow the naming
rules — UFCS is not a shortcut for skipping argument names.

```pyrope
comb div(self, b) -> (r) { r = self / b }     // method: declares self
comb div2(a, b)   -> (r) { r = a / b }        // free function: no self
comb noarg()      -> (r) { r = 33 }           // explicit no args

cassert(33 == noarg())               // () always required, even for no-arg calls

const b1 = (8).div(b=2)              // OK: 8 → self, b named (4)
const b2 = div(8, b=2)               // OK: direct form, 8 → self (4)
const d1 = div2(a=8, b=2)            // OK: direct call, all named (4)

const c1 = (const a=8, const b=2).div2() // error: div2 has no self → no UFCS
const t1 = (8).div2(b=2)             // error: div2 has no self → no UFCS
const t2 = (8).div(2)                // OK: `b` is the single non-self parameter (4)
const t3 = div(self=8, b=2)          // error: `self` cannot be named

assert(noarg)                        // error: `noarg()` needed for calls
```

When the lambda declares `self`, the leading dotted value may be any value
(scalar, array, or tuple) — it is bound positionally to `self`. The
remaining arguments still follow the naming rules.

```pyrope
comb some_op(self, d=3) -> (r) { /* ... */ }

(8).some_op(d=3)        // scalar bound to self
[8, 2, a].some_op(d=3)  // array bound to self
(8, 2).some_op(d=2)     // unnamed tuple bound to self
some_op(8, d=3)         // direct form: 8 bound to self

some_op(self=8, d=3)    // error: `self` cannot be passed by name
```

Tuple fields and external names are separate. Declaring a field with the same
name as an external variable or function does not alias or shadow that name.
A callable field without `self` receives only the explicitly supplied arguments;
a field method declaring `self` receives its tuple as `self`.

For a dotted call, an external function without `self` is not a UFCS candidate
and does not compete with a callable field. When both a callable field and an
external function declaring `self` are available, neither takes precedence:
the call is an error, even if the field refers to that same external function.
Rename one of the candidates or use an explicit direct call to disambiguate.
These rules apply with or without explicit generic arguments.

```pyrope
comb addk1<K>(a) -> (r) { r = a + K }
comb addk2<K>(self, a) -> (r) { r = a + K }
mut foo = 3

const ns1 = (const addk1 = addk1)
cassert(foo.addk2<K=3>(a=1) == 4) // external function: foo binds self
cassert(ns1.addk1<K=3>(a=1) == 4) // tuple field: no self needed
cassert(ns1.addk2<K=3>(a=1) == 4) // no such field: external UFCS, ns1 binds self
// foo.addk1<K=3>(a=1)           // error: external addk1 has no self

const ns2 = (const addk2 = addk1) // declaration is legal
// ns2.addk2<K=3>(a=1)          // error: callable field and external UFCS both match
cassert(addk2<K=3>(ns2, a=1) == 4) // explicit direct call to external addk2

const values = (mut foo = 4)
cassert(foo != values.foo)       // independent variable and tuple field
```

The keyword `self` is used to indicate that the function is accessing a tuple.
`self` is required to be the first argument. If the method modifies the tuple
contents, a `ref self` must be passed as input. Since `ref` is equivalent to
having the argument as both input and output, `comb` can use `ref` and still
be purely combinational. `ref self` is a special receiver form: `foo.f1(...)`
expands locally against `foo`, so the receiver is not a Verilog module port.
For non-`self` parameters, `ref` is legal only on `comb`; a `mod` or `pipe`
boundary is a real hardware boundary and cannot expose ordinary pass-by-ref
ports.

A typed `self` (`self:T` / `ref self:T`) constrains the receiver
STRUCTURALLY: the call is valid when `receiver does T` — per-field name
presence, matching scalar kinds, and integer ranges within the declared
bounds; extra receiver fields are fine (see
[Structural typing](07b-structtype.md)). Only NAMED self types are
supported; an inline tuple type on
`self` is a compile error. The `does`-check applies to `self` only — the
other arguments keep the normal argument rules above.

`ref self` additionally requires a `mut` value receiver: calling a
ref-self method on a `const` or on a `type` binding is a compile error
(same as passing a const to any `ref` parameter). A non-ref `self` method IS
callable on a `type` binding — it reads the field defaults.


```pyrope
mut tup2 = (
  mut val:U8 = 0sb?,
  comb upd(ref self) { sat self.val += 1 },
  comb calc(self) -> (r) { r = self.val }
)
```

A lambda call always uses parentheses (`foo()` or `foo(a=1, b=2)`). There is no
exception: reading a variable or field never invokes a method implicitly.

The `init` method is an implicit construction hook, so it must be `comb`. If
an operation needs registers, pipeline latency, or cycle-level side effects,
use an explicit `mod` or `pipe` method call instead.

```pyrope
no_arg_fun()     // parentheses always required
arg_fun(a=1, b=2) // parenthesis required; multi-argument calls name arguments

mut constructed:(
  mut field:U32 = nil,
  comb init(ref self, v) { self.field = v + 1 }
) = 0            // construction calls init(ref constructed, 0)

cassert(constructed.field == 1)
constructed.field = 7     // plain write, no hook
cassert(constructed.field == 7)
```

## Pass by reference

Pyrope is an HDL, and as such, there are not memory allocation issues. This
means that all the arguments are pass by value and the language has value
semantics. In other words, there is not need to worry about ownership or
move/forward semantics like in C++/Rust. All the arguments are always by value.
Nevertheless, sometimes is useful to pass a reference to an array/register so
that it can be updated/accessed on different lambdas.


Pyrope arguments are by value, unless the `ref` keyword is used. Pass by
reference is needed to avoid the copy by value of the function call. Unlike
non-hardware languages, there is no performance overhead in passing by value.
The reason for passing as reference is to allow the lambda to operate over the
passed argument. If modified, it behaves like if it were an implicit output.
This is quite useful for large objects like memories to avoid the copy.


The pass by reference behaves like if the calling lambda were inlined in the
caller lambda while still respecting the lambda scope. The `ref` keyword must
be explicit in the lambda input definition but also in the lambda call. The
lambda outputs can not have a `ref` modifier.


No logical or arithmetic operation can be done with a `ref`. As a result, it is
only useful for lambda input arguments.


```pyrope
comb inc1(ref a) -> () { a += 1 }

const x = 3
inc1(ref x)       // error: `x` is immutable but modified inside inc1

mut y = 3
inc1(ref y)
cassert(y == 4)

comb banner() -> () { puts("hello") }
type T_noarg = comb() -> ()
comb execute_method(fn:T_noarg) -> () {  // explicit type for fn (declared ahead)
  fn() // prints hello when banner passed as argument
}

execute_method(banner)     // OK
```

In Pyrope, every method call uses parentheses, including no-argument calls.
A bare lambda name is a value reference used for higher-order functions, not
a call. This keeps no-argument calls visually distinct from passing the lambda
itself.

## Output tuple

Everything in Pyrope is a tuple, including the result of a lambda call. There
are three rules that work together:

1. **Outputs are always declared by name in `-> ( ... )`.** There is no
   anonymous/positional output list. A lambda with no outputs writes `-> ()`;
   omitting the clause is a compile error, except in a `self` method (first
   input parameter named `self`, with or without `ref`), which acts through
   the receiver and may omit it.

2. **The body assigns to the declared output names.** A bare expression at
   the end of a lambda body does not assign an output and has no special
   return meaning. Binding the call result of a `-> ()` lambda
   (`const a = top()`) is a compile error — there is no value to bind.

3. **`return` is a terminator only.** The keyword ends the current lambda
   and never carries a value (`return X` is a syntax error). Whatever has
   been assigned to the declared output names so far is what the caller
   sees. Use `if cond { return }` for conditional early exits.

Callers always see a named tuple. They can read fields by name
(`r.a`, `r.b`) or destructure on the LHS. Destructuring follows the
[named-tuple destructuring](03-bundle.md#named-tuple-destructuring) rules:
bare LHS names bind by output field name, not by position. Use that section
for rename and nested-field examples.

Each field also keeps the type declared for that output. A `mod` call is no
exception: it lowers to an instance, but the handle exposes the declared port
types, not just their bit widths. Given
`mod leaf(a:U4) -> (flag:Bool@[0], val:U8@[0])` and `const child = leaf(a=a)`,
`child.flag` is a `Bool` and `child.val` is a `U8`. A `Bool` output never
mixes with integers implicitly: `if child.flag` is fine, but arithmetic needs
`U1(child.flag)` (true == 1). See [Boolean ports](#boolean-ports).


```pyrope
comb parts(x) -> (next, doubled) {
  next = x + 1
  doubled = x + x
}

const r = parts(x=3)
cassert(r.next == 4 and r.doubled == 6)

const (doubled, next) = parts(x=3) // OK: output names bind regardless of order
```

A single-field output tuple auto-unwraps when used in scalar context.

```pyrope
comb ret1() -> (a:Signed) {
  a = 1
}

comb ret3() -> (a, b) {
  a = 3
  b = 4
}

comb early(x) -> (r) {
  r = 0
  if x == 0 { return }     // bail out; r already assigned
  r = 100 / x
}

comb next_value(x) -> (x) {
  x = x + 1                // same source name; generated input/output nets differ
}

const a1 = ret1()
cassert(a1.a == 1 and a1 == 1) // single-field tuple auto-unwraps

const a3 = ret3()
cassert(a3.a == 3 and a3.b == 4)

const (x1=ret3.a, x2=ret3.b) = ret3()   // rename: `const (x1, x2) = ret3()` is an error
cassert(x1 == 3 and x2 == 4)
```

### Boolean ports

`Bool` is legal on every port, including the top-level IOs of the design: it
is a 1-bit port where `true == 1`. Booleans never mix with integers
implicitly, and a port boundary or an instance output is no exception:

* A `Bool` parameter binds a `Bool` value. Pass an integer bit as
  `Bool(v#[0])` (or `v#[0] == 1`). A `U1` or a wider integer bound to a
  `Bool` port is a compile error.
* An integer parameter binds an integer. Pass a `Bool` as `U1(flag)`.
* A `Bool` output stays a `Bool` in the caller. Use it as a number with
  `U1(child.flag)`.

Declare a port `U1` only where the value is used arithmetically. The
`Bool`-to-bit conversion is `U1(b)`; `Signed(true) == -1` is a sign
reinterpretation, not the idiom.

```pyrope
mod leaf(go:Bool, n:U4) -> (rdy:Bool@[0], cnt:U4@[0]) {
  rdy = go and n != 0
  cnt = if go { n } else { 0 }
}

pub mod top(v:U8, en:Bool) -> (sum:U8@[0], busy:Bool@[0]) { // Bool IOs: 1-bit ports
  const c1 = leaf(go=en, n=v#[4..<8])               // OK: Bool into a Bool port
  const c2 = leaf(go=Bool(v#[0]), n=v#[4..<8])      // OK: explicit bit -> Bool
  const c3 = leaf(go=v#[0], n=v#[4..<8])            // error: write Bool(v#[0])
  const c4 = leaf(go=v#[0..<4], n=v#[4..<8])        // error: an integer into a Bool port
  const sm = c2.cnt + c1.rdy                        // error: Bool output in arithmetic
  sum  = c2.cnt + U1(c1.rdy)                        // OK
  busy = c1.rdy or c2.rdy                           // OK: stays Bool
}
```

### Lambda body

Every lambda body uses the explicit form: name your output(s) in `-> (...)`,
assign to them by name in the body, and terminate normally or with a bare
`return`. There is **no placeholder lambda sugar** — `_`, `_0`, `_1`, etc.
are not positional-argument shorthands. Higher-order calls take a fully
explicit lambda:

```pyrope
comb add(a, b) -> (r) { r = a + b }
comb inc(a)    -> (r) { r = a + 1 }

mymap.each(inc)   // OK: `each` has one non-self argument
```

## Init (constructor)


Object-like behavior is modeled as a tuple with fields and methods. Methods can
mutate the tuple through `ref self`, which expands locally at a UFCS call such
as `foo.f1(...)`. The only implicit hook is `init`, the constructor: it runs
once when a variable of the type is constructed, and it must be `comb`. After
construction, reads and writes are always structural; stateful or pipelined
behavior is exposed as an explicit `mod` or `pipe` method. Ordinary non-`self`
`ref` parameters remain `comb`-only.

```pyrope
const Counter = (
  mut found_once:Bool = false,
  comb init(ref self, start:Bool) {   // constructor
    self.found_once = start
  },
  mod call(ref self, a:U8) -> (result:U9@[0]) { // receiver is locally expanded
    self.found_once or= (a == 0)
    result = a + 1
  }
)

mut p1:Counter = false   // init(ref p1, false)
mut p2 = p1              // plain structural copy

test counter.p1 {
  assert(p1.found_once == false)
  assert(p2.found_once == false)

  cassert(p1.call(3) == 4)   // typed argument: `a:U8` is unambiguous
  assert(p1.found_once == false)

  cassert(p1.call(0) == 1)
  assert(p1.found_once == true)

  cassert(p1.call(50) == 51)
  assert(p1.found_once == true)
  assert(p2.found_once == false)
}
```

## Methods

Pyrope arguments are by value, unless the `ref` keyword is used. `ref` is
needed when a method intends to update the tuple contents. In this case, `ref
self` argument behaves like a pass by reference in non-hardware languages. This
means that the tuple fields are updated as the method executes, it does not
wait until the method finishes execution. A method without the `ref` keyword is
a pass by value call. Since all the inputs are immutable by default (`const`),
any `self` updates should generate a compile error. Ordinary non-`self` `ref`
parameters are legal only on `comb`; `ref self` is the method receiver
exception and expands locally at the call site.

```pyrope
const Nested_call = (
  mut x = 1,
  comb outter(ref self) { self.x = 100; self.inner(); self.x = 5 },
  comb inner(self)      { assert(self.x == 100) },
  comb faulty(self)     { self.x = 55 }, // error: immutable self
  comb okcall(ref self) { self.x = 55 }
)
```

`self` can also be returned but this behaves like a normal copy by value
variable return.

```pyrope
mut a_1 = (
  mut x:U10 = 0,
  comb f1(ref self, x) -> (self) { // output named `self` mirrors the ref input
    self.x = x                     // mutates the ref; output `self` reflects the new value
  }
)

a_1.f1(x=3)
mut a_2 = a_1.f1(x=4)  // a_2 is updated, not a_1
cassert(a_1.x == 3 and a_2.x == 4)

// Same behavior as in a function with UFCS
comb set_x(ref self, x) -> (self) { self.x = x }

a_1.set_x(x=10)
mut a_3 = a_1.set_x(x=20)
cassert(a_1.x == 10 and a_3.x == 20)
```

A callable field and an external `self` function may share a name, but calling
that name through the tuple is ambiguous. Use a different external name or an
explicit direct call:

```pyrope
mut counter = (
  ,mut val:S32 = 0
  ,comb inc(ref self, v) { wrap self.val += v }
)

cassert(counter.val == 0)

comb inc(ref self, v) { wrap self.val *= v } // external function multiplies
// counter.inc(v=2)        // error: callable field and external UFCS both match

mut n = (mut val:S32 = 4)
n.inc(v=2)                 // unambiguous: only the global inc matches
cassert(n.val == 8)

counter.val = 5
const mul = inc
counter.mul(v=2)           // call the new mul method with UFCS
cassert(counter.val == 10)

mul(counter, v=2)          // OK: direct form, counter bound to self (val == 20)
```


It is possible to add new methods after the type declaration. In some
languages, this is called extension functions.

```pyrope
const T1 = (mut a:U32 = 0)

mut x:T1 = (a=3)

comb t1_do_double(ref self) { wrap self.a *= 2 }
T1.double = t1_do_double

mut y:T1 = (a=3)
x.double()           // error: double method does not exist
y.double()           // OK
assert(y.a == 6)
```

### Constraining arguments

Arguments can constrain the inputs and input types. Unconstrained input types
allow for more freedom and a potentially variable number of arguments generics, but
it can be error-prone.

=== "unconstrained declaration"
    ```pyrope
    comb foo(self) { puts("comb.foo") }
    const a = (
      ,comb foo() -> (r) {
         comb bar() -> () { puts("bar") }
         puts("mem.foo")
         r = (const bar=bar)
      }
    )
    const b = 3
    const c = "string"

    b.foo()       // prints "comb.foo"
    y = a.foo()   // prints "mem.foo"
    y.bar()       // prints "bar"

    a.foo().bar() // prints "mem.foo" and then "bar"

    c.foo()       // prints "comb.foo"
    ```

=== "constrained declaration"

    ```pyrope
    comb foo(self:Signed) { puts("comb.foo") }
    const a = (
      ,comb foo() -> (r) {
         comb bar() -> () { puts("bar") }
         puts("mem.foo")
         r = (const bar=bar)
      }
    )
    const b = 3
    const c = "string"

    b.foo()       // prints "comb.foo"
    const y = a.foo()   // prints "mem.foo"
    y.bar()       // prints "bar"

    a.foo().bar() // prints "mem.foo" and then "bar"

    c.foo()       // error: undefined 'foo' field/call
    ```
