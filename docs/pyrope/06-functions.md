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
  `fluid`. The only state it can hold is debug state marked `::[debug]`,
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
  (`N >= 0`): `mod f(a:u8) -> (x:u8@[2], y:u8@[0])`. A cycle-0 output is a
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
  `mod`).

- `fluid` (TBD: not yet implemented) is a transactional block with valid/retry handshakes on its
  inputs and outputs. Fluid availability is dynamic: a transaction advances
  only when `.[fire]` is true (`.[valid] and !.[retry]`). A `fluid` call
  must be bound with a `fluid` declaration, and fluid calls are allowed only
  inside `mod` and `fluid` lambdas. See [Fluid Blocks](06d-fluid.md).

Generating an LGraph module (for Verilog or simulation) requires a concrete
fully typed interface and a fixed, fully named/ordered port list. A declaration
can provide that directly, or it can be **not fully typed** — an untyped
non-`self` input, a `(...args)` var-arg, or an unbound generic `<T>` — and defer
module generation until a call site binds the missing shape. `self`/`ref self`
methods derive `self`'s type from the enclosing tuple.

`pipe` and `mod` lambdas are module boundaries, and a concrete `pipe`/`mod`
call lowers to a module instance. A fully typed `pipe`/`mod` lowers to one
module directly. A not-fully-typed `pipe`/`mod` is a **deferred template**: it
produces no module at definition time and is **specialized per call site** into
a concrete module named by the actual types (`mod foo(a)` called with a `u8`
actual mints `foo__u8`; a `u16` actual mints `foo__u16`; identical signatures
share one module, each call still its own instance). Specialization keys on
each actual's **declared** type, so an **untyped actual** feeding such a
boundary is a compile error at the call site (annotate it, e.g. `x:u8`) — a
hardware port needs an explicit width.

A `comb` may stay not fully typed, in which case it is always **inlined** and no
separate LGraph is generated. If a `comb` is fully typed, the compiler may
inline it or keep it as its own module instance. Var-args gather into the param
and `args[i]`/`args.NAME` resolve at the call site; for a generated module, the
specialized call must provide the final fixed port order and names. A template
that is exported (`pub`) or selected as a synthesis top but never specialized in
its own unit simply yields no module — it is not an error.

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
    pipe[3] multiply(a:u16, b:u16) -> (result:u32) { // fixed 3-cycle latency
      result = a * b
    }

    pipe[1..=3] add_pipe(a:u32, b:u32) -> (result:u32) { // caller picks 1-3 cycles
      wrap result = a + b
    }

    pipe flexible_mul(a:u16, b:u16) -> (result:u32) { // bare: caller picks via stage[N]
      result = a * b
    }
    ```

=== "Module with pipeline orchestration (mod)"
    ```pyrope
    pipe mul(a:u16, b:u16) -> (c:u32) { c = a * b }
    pipe add(a:u32, b:u32) -> (c:u32) { wrap c = a + b }

    mod multiply_add(in1:u16, in2:u16) -> (out:u32@[4]) {
      stage[3] tmp     = mul(a=in1, b=in2)     // mul picks 3 stages
      stage[3] in1_d   = in1                   // delay in1 by 3
      stage[1] out@[4] = add(a=tmp@[3], b=in1_d@[3]) // adder takes 1 stage; out@[4] typechecks
    }

    mod accum(in1:u16, in2:u16) -> (out:u32@[3]) {
      reg total:u32 = 0                  // mod can use reg (state, home stage 3)
      stage[3] tmp = mul(a=in1, b=in2)
      wrap total = total + tmp@[3]       // state q + stage-3 value: coherent
      out = total                        // q read; out lands at cycle 3
    }
    ```

=== "Module with registered outputs (mod)"
    ```pyrope
    mod counter(enable:bool) -> (reg count:u8@[0]) {
      if enable { wrap count += 1 }      // conditional write -> state reg, home 0
    }

    mod add_reg(a:u8, b:u8) -> (reg result:u9@[1]) {
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
type a_lambda_type = comb()->(v)
cassert(a_lambda equals a_lambda_type)
cassert(a_lambda() == 4)
```

The lambda definition has the following fields:

```txt
[GENERIC] [COMPTIME] [INPUT] [-> OUTPUT] |
```

+ `GENERIC` is an optional comma separated list of names between `<` and `>` to
  use as generic types in the lambda. The call site binds them explicitly
  (`f<signed,string>(…)`, one type per name in declaration order) or by
  inference from the actuals' declared types (see "Overloading/generics"
  below).

+ `COMPTIME` has the optional list of explicit comptime parameters for the
  lambda. Each entry is a typed declaration (e.g., `n:signed`) or a typed
  declaration with a default (e.g., `n:signed=1`). Defaults may refer to visible
  comptime bindings from the enclosing scope. Callers can override any
  comptime parameter at the call site using the same `[...]` slot
  (`foo[N](args)`).

+ Lambdas do not have an explicit capture list. Visible comptime bindings from
  enclosing scopes, including imports and `comptime const` declarations, are
  available lexically inside the lambda body and signature. The compiler records
  those references as explicit comptime dependencies of the lambda; no capture
  syntax is written by the programmer. Runtime `const`, `mut`, and `reg`
  declarations from enclosing lambda scopes are not visible inside a nested
  lambda unless passed as normal inputs or stored in an explicit tuple/object
  that the lambda receives.

+ `INPUT` has a list of inputs allowed with optional types. `()` indicates no
  inputs. `(...args)` allow to accept a variable number of arguments. A
  `...args` var-arg is the trailing parameter; it gathers every actual not
  consumed by a fixed leading parameter into one tuple — positional leftovers
  become positional entries (read as `args[i]`), named leftovers become named
  fields (read as `args.NAME`). Var-args are supported on a `comb` (which can
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
comb add1(...x) -> (r) { r = x[0] + x[1] + x[2] }   // var-args, single output
comb add2(a, b, c) -> (r) { r = a + b + c }         // constrain inputs to a,b,c
comb add3(a, b, c) -> (r:u32) { r = a + b + c }     // constrain result to u32
comb add4(a:u32, b:s3, c) -> (r) { r = a + b + c }  // constrain some input types
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
const s = add(a=1, b=2, c=3)   // a 3-arg call → the first 3-arg-compatible add

const x = 2
comb addx1(a) -> (r) { r = x + a }    // error: x is runtime, not visible in lambda

/// Visible comptime bindings are available lexically:
comptime const Scale = 2
comb addx2(a) -> (r) { r = Scale + a }       // OK: Scale is comptime

/// Imports are comptime aliases:
const lib = import("lib.math")
comb is_add(op:lib.OpType) -> (r) { r = op == lib.AddOp }

mut y = (
  mut val:u32 = 1,
  comb inc1(ref self) { self.val = u32(self.val + 1) } // no outputs; mutates via ref
)

comb my_log::[debug](...inp) -> () { // no outputs; side-effecting print
  print("logging:")
  for i in inp {
    print(" {}", i)
  }
  puts()
}

comb f<X>(a:X, b:X) -> (r) { r = a + b }    // enforces a and b with same type
cassert(f(a=u22(33), b=u22(100)) == 133)    // X = u22 (inferred; args named per
                                            // the argument-naming rules below)
cassert(f<u8>(a=1, b=2) == 3)               // X = u8 (explicit call-site binding)

my_log(a, false, x + 1)
```

A generic binds **per call site** — a pure type-macro expansion, with the
normal typing rules applying after substitution (no implicit coercion). The
call may bind explicitly with `f<type, …>(…)` (one type per generic name, in
declaration order, all-or-nothing), or leave the binding to inference: each
generic unifies over the **declared** types of the actuals at its `:T`
positions (a `u8` actual and a `u16` actual for one `T` is a compile error —
`fcall-generic-mismatch`), while bare literals contribute only their kind, so
`f(a=1, b=2)` infers `X = signed`. On a `pipe`/`mod` boundary each distinct
binding mints its own module, exactly like the untyped-parameter deferred
templates above (`madd<T>` called with `u8` actuals mints `madd__u8_u8`).

## Argument naming

Every input argument must be named at the call site (`fcall(a=2, b=3)`),
whether the call is direct or UFCS. There are a few narrow exceptions that
let an argument be passed unnamed:

* The lambda has exactly one argument (and `self` does not count, see
  below). With nothing to disambiguate, position is unambiguous.

* The calling expression is a variable whose name matches a parameter name
  (`fcall(a)` matches a parameter named `a`).

* The argument types make the mapping unambiguous with no implicit
  conversion required. This applies when each unnamed call-site value
  matches exactly one parameter by type; if two parameters have the same
  type, or an untyped parameter could accept the value, the call must name
  the argument.

* `self` is always bound positionally — by the value before the dot in a
  UFCS call, or by the first positional actual in a direct call — and is
  never named at the call site.

Structured tuple parameters can be supplied either as one tuple value or as
expanded dotted fields. The expanded form is legal but usually noisier; it is
useful when mapping to generated LGraph/Verilog ports, because those interfaces
are flattened into separate signals. This uses the same path expansion as
[tuple literals](03-bundle.md#dotted-field-expansion).

```pyrope
comb pick(ar:(x:u3, y:s4), cond:bool) -> (res:s5) {
  res = if cond { ar.x + 1 } else { ar.y - 1 }
}

const a = pick(ar=(x=1, y=10), cond=true)  // compact tuple argument
const b = pick(ar.x=1, ar.y=10, cond=true) // expanded fields, same binding
```

### Binding return values

Outputs are always named, and **binding the result of a call mirrors the
argument-naming rules above** — the same name-match / non-ambiguous / type
exceptions, just in the other direction. There is no positional return list and
no binding by order.

* **One output.** The output name is dropped and the result binds directly to
  the destination. If that single output is a tuple, the destination *is* that
  tuple:

  ```pyrope
  comb pair(a:signed, b:signed) -> (p:(first:signed, second:signed)) { p = (first=a, second=b) }

  const inner = pair(a=100, b=50)   // single output `p` maps to `inner`
  cassert(inner.first == 100)       // `inner` IS the tuple (no `inner.p` level)
  ```

* **Several outputs.** Destructure into names that **match the output names**
  (the same exceptions apply: a lone output is unambiguous, a matching variable
  name binds, or a unique type decides). Binding several outputs to one
  variable is a compile error, and there is **no mapping by position**:

  ```pyrope
  comb two(a:signed, b:signed) -> (p1:signed, p2:signed) { p1 = a; p2 = b }

  const (p1, p2) = two(a=100, b=50)        // OK: names match the outputs
  cassert(p1==100 and p2==50)

  const inner   = two(a=100, b=50)         // ERROR: two outputs, one variable
  const (x, y)  = two(a=100, b=50)         // ERROR: x/y do not match p1/p2 (no by-order)
  const (x=two.p1, y=two.p2) = two(a=100, b=50)  // OK: explicit remap `var = callee.output`
  ```

There are several rules on how to handle arguments.

* **Every lambda call requires parentheses.** `foo()`, `foo(a=1,b=2)`, and
  `x.bar(y=y)` are the only forms. There is no "drop parens after newline"
  or "drop parens after a pipeline operator" sugar. This keeps every call
  site unambiguously identifiable.

* **Calls use Uniform Function Call Syntax (UFCS).** `x.f(args)` is
  rewritten to `f(x, args)` with `x` bound positionally to `self`. The
  UFCS form is valid ONLY when the lambda declares `self`: calling a
  self-less lambda as `x.f(args)` is a compile error (use the direct
  form).

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
const t2 = 8.div(2)                  // error: `2` is not named
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

The UFCS allows `lambdas` to call any tuple, but if the called tuple has a
lambda defined with the same name a compile error is generated. Like with
variables, Pyrope does not allow `lambda` call shadowing. Polymorphism is
allowed but only explicit one as explained later.

```pyrope
mut tup = (
  comb f1(self) -> (r) { r = 1 }
)

comb f1(self) -> (r) { r = 2 } // error: f1 shadows tup.f1
comb f1() -> (r) { r = 3 }     // OK, no self

assert(f1() != 0)        // error: missing argument
assert(f1(tup) != 0)     // error: free `f1` takes no arguments
assert(4.f1() != 0)      // error: f1 can be called for tup, so shadowed
assert(tup.f1() != 0)    // error: f1 is shadowing

comb xx(self:tup) -> (r) { r = self.f1() } // OK, explicit input restricts scope for f1
cassert((tup).xx() == 1)                   // xx declares self → UFCS OK (xx(tup) works too)

const t4:tup = 4
cassert(t4.f1() == 1)     // typed as tup → tup.f1 is called
cassert((4).f1() == 3)    // UFCS call, scalar bound to self
cassert(tup.f1() == 1)
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
  mut val:u8 = 0sb?,
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
  mut field:u32,
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
comb ret1() -> (a:signed) {
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

const (x1, x2) = ret3()
cassert(x1 == 3 and x2 == 4)
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
  mut found_once:bool = false,
  comb init(ref self, start:bool) {   // constructor
    self.found_once = start
  },
  mod call(ref self, a:u8) -> (result:u9@[0]) { // receiver is locally expanded
    self.found_once or= (a == 0)
    result = a + 1
  }
)

mut p1:Counter = false   // init(ref p1, false)
mut p2 = p1              // plain structural copy

test "testing p1" {
  assert(p1.found_once == false)
  assert(p2.found_once == false)

  cassert(p1.call(3) == 4)   // typed argument: `a:u8` is unambiguous
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
  mut x:u10,
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

Since UFCS does not allow shadowing, a wrapper must be built or a compile error is generated.

```pyrope
mut counter = (
  ,mut val:s32 = 0
  ,comb inc(ref self, v) { self.val += v }
)

cassert(counter.val == 0)
counter.inc(v=3)
cassert(counter.val == 3)

comb inc(ref self, v) { self.val *= v } // NOT INC but multiply
counter.inc(v=2)           // error: multiple inc options

mut n = (mut val:s32 = 4)
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
const t1 = (mut a:u32)

mut x:t1 = (a=3)

comb t1_do_double(ref self) { self.a *= 2 }
t1.double = t1_do_double

mut y:t1 = (a=3)
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
    comb foo(self:signed) { puts("comb.foo") }
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
