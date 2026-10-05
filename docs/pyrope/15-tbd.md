# Implementation status (TBD)

Most of Pyrope is implemented in [LiveHD](https://github.com/masc-ucsc/livehd)
and exercised by its test suite. This page lists the documented features that
are **not implemented yet**; each is also marked "TBD" where it is described.
A feature on this list may parse (`lhd elaborate` is permissive) but does not
lower to working hardware.

The Task column names an existing task page in the LiveHD repo under `todo/`
where one is available; a dash means no separate task page exists.

| Feature | Documented in | Task | Notes |
|---------|---------------|------|-------|
| `fluid` lambdas, valid/retry/fire elastic handshakes | [Fluid Blocks](06d-fluid.md) | `3f-fluid` | syntax parses; no lowering |
| Temporal library: `past(x, n)`, `rose`, `fell`, `stable`, `changed`, `eventually(x, w)`, `always(x, w)` | [Extended Verification](09-verification.md) | `3f-temporal` | cycle arguments are ordinary named arguments (`past(x, n=3)`, `rose(x=sig, w=1..=10)`) — there is no `f[N](x)` bracket form. The *pipelining* `past[N](x)` DOES work (design body only) and is a different operator. No edge attributes: `.[rising]`/`.[falling]`/`.[changed]`/`.[stable]` are not recognized. `lhd formal verify` must reject these calls with an explicit "not implemented" diagnostic |
| Testbench extras: multi-match string-path refs, `force`/`release`, `cpp(...)` external models, unbounded `tick { }` | [Extended Verification](09-verification.md) | `3f-temporal` | the instance/`step` model runs via `lhd sim`: bare dotted DUT access READS any cell at any depth, and `regref` (dotted or single-cell string) DRIVES a register at any depth. `peek`/`poke` and `sigref` are **removed** — a bare dotted read is exactly what `sigref` was; `waitfor`/`spawn`/`join`/`cancel` are dropped |
| `regref` — the SYNTHESIZABLE cross-scope register/memory attach by string path (zero-or-many matches) | [Type system](07-typesystem.md#register-reference), [Memories](08-memories.md#shared-memories-with-regref) | `3f-temporal` | still TBD. The `test`-block `regref` (single cell, dotted or string, writable) is a separate construct and is IMPLEMENTED |
| Statements rejected inside a `test` block: `for`/`while`/`loop` statements, `.[rand]`/`.[crand]`, `past[N]`, positional instantiation-by-call; a `test` nested in a top-scope comptime `for` (the test fan-out idiom) | [Testing](05b-statements.md#testing-test) | `3f-temporal` | dotted names, runtime `(...)` params, `tick`/`step`/`break`/`continue`, bare dotted DUT access and `regref` all work; write a cycle loop as `tick N { … }`. `lhd sim` reports `unsupported statement in test: for_statement` (or `while_statement`) for a loop in a test body, and `no test blocks found` when every `test` sits inside a top-scope `for` (checked 2026-09-27). `sigref` was REMOVED 2026-09-06 -- a bare dotted read is exactly it |
| Standard library (`import("prp")`) | [Standard Library](13-stdlib.md) | — | wish-list chapter. The built-in `std` namespace (`std.clog2`, no `import`) is part of the language and not on this list |
| `macro=` memory-compiler binding | [Memories](08-memories.md) | `3f-macro` | |
| `cover`, `covercase`, in-language `lec()`/`lec_valid()` | [Assertions](05-assert.md) | `3f-temporal` | `assert`/`cassert`/`assume`/`assert_always` work; `cover` does NOT exist in any context |
| `.[rand]` / `.[crand]` random generation | [Random](05-assert.md#random) | `3f-temporal` | rejected in `test` blocks and design bodies; survives only where it constant-folds |
| `assert.[failed]` (read/clear the accumulated failure flag in a `test`) | [Test](05-assert.md#test) | `3f-temporal` | |
| `always_assert` / `always_cassert` / `always_assume` / `always_cover` / `always_covercase`; valid-based (`.[valid]`) gating of checks | [Reset and verification](05-assert.md) | `3f-temporal` | the implemented spelling is `assert_always`; no valid-based gating exists |
| A `ref self` method used in a right-hand-side EXPRESSION (`mut a_2 = a_1.f1(x=4)`, output named `self`) | [Functions](06-functions.md), [Struct types](07b-structtype.md), [Type system](07-typesystem.md) | — | the STATEMENT form and UFCS both work; only the expression form errors `a method with a 'ref' parameter … cannot be used in a right-hand-side expression`. Workaround: copy first, then mutate |
| An unnamed/positional tuple as a module port (`v:(U4, U8)`) | [Functions](06-functions.md) | — | no lowering yet. The NAMED tuple port works (`tests/sim/tuple_io_ports.prp`), and so do array input and output ports (`v:[2]U8`). Tracker: `inou/prp/tests/fixme/vector_io_ports.prp` |
| Landing cycle of a plain `reg` declared in a `mod` *body* that drives an `@[N]` output | [Functions](06-functions.md#cycle-rules-for-mod-outputs), [Pipelining](06c-pipelining.md) | — | settled (ruling 83, 2026-09-30) for a body `reg` written every cycle from its inputs whose q drives an `@[N]` output directly or through a bit slice (`q = r`, `q = r#[0..<4]`): it lands one cycle after its inputs, with the implicit clock or an explicit `clock_pin`/`reset_pin`, written whole or through bit slices. **Not settled:** any other read of it is cycle-0 state today (`q = ~r`, `q = r ^ 1`, or a `wire` alias of `r` needs `q@[0]`), so two outputs of the same flop can declare different cycles (a `valid@[1]` next to a `data@[0]`); making those `@[1]` too turns a Mealy read of the register next to a same-cycle input (`e = d and !prev; prev = d`) into a cycle-mix error. A conditionally written or feedback body `reg` is state at its home stage today (`if en { r = d }; q = r` needs `q@[0]`), while the same register on a gated clock (`clock_pin=Clock(clock_pin=clk, enable=en)`; its data has no hold path) needs `q@[1]`. A cycle-stable form is `reg` in the output list (`-> (reg q:T@[N])`) or `stage[N]`. `::[timecheck=false]` turns off all timing checks of that lambda and makes every plain `reg` cycle-0 state (see [timecheck](04b-attributes.md#timecheck-timing-check-escape-hatch)); it is an escape hatch, not idiomatic code |
| A `does` check on a generic inside a lambda body (`cassert(T does Addable)`, the documented way to constrain a generic) | [Functions](06-functions.md), [Struct types](07b-structtype.md) | — | today `does` on a generic `T` does not fold inside the body: `lhd compile` reports `node type 'does' has no hardware lowering` (or `cassert condition did not fold to a compile-time value`) (checked 2026-09-27) |
| The `pipe[N]` state-output idiom (`pipe[1] counter(enable:Bool) -> (reg count:U8 = 0)`) | [Pipelining](06c-pipelining.md#accepted-examples) | — | rejected today: `state register 'count' … homes at stage 0 but its declared landing cycle 1 requires home 1` (checked 2026-09-27). Use the `mod` form, `mod counter(enable:Bool) -> (reg count:U8@[0] = 0)` |
| Bit packing with `#[..]`: comptime unpack into an array, the exact-width check on unpack, `...` splice of a declared `[N]T` when BUILDING a tuple | [Internals](10-internals.md), [Deprecated](21-deprecated.md) | `3f-bitpack` | Implemented: packing a tuple LITERAL (`(a, b)#[..]`, `(...stages, inp)#[..]`) at comptime and at runtime, entry 0 at bit 0; packing a tuple/array VARIABLE (`x#[..]`); the declared-width guard, so an untyped or literal entry is rejected; the exact-width destination check (`z:U16 = (b, a)#[..]` on 12 bits errors, and an undeclared destination errors); the named-field rule, with the real diagnostic on a multi-field bundle and the one-field case still legal; reductions, sign extension, and sub-ranges over a packed tuple literal or an array/tuple variable; unpacking into a declared array at RUNTIME (`const x:[2]U4 = b#[..]` emits `b[3:0]`, `b[7:4]`). `concat` is REMOVED and diagnoses its own replacement (`concat-removed`), which is the error to read first, because the argument order reverses. Still missing: comptime unpack does not split — `const x:[2]U4 = b8#[..]` folds BOTH entries to the whole word, a silent wrong value; the exact-width check on unpack, so `b:U9` into `[2]U4` silently drops bit 8; `...` expands an unnamed tuple and an untyped array literal but not a declared `const x:[2]U4 = (3,1)` when building a tuple (as a PACKING entry it does expand); an array ELEMENT read is not a packing entry (`(x, arr[2], arr[1])#[..]` reports `concat lane … has no declared bit width` — bind each to a typed name first) |

Notes:

* `requires`/`ensures` were **removed** from the language. They parse today
  only to emit a "no obligation generated" warning; write an `assume` for a
  precondition and an `assert` for a postcondition.
* A design-body `assert` is checked by `pass.formal` and emitted into the
  Verilog netlist, but is **not executed by `lhd sim`** — the simulation
  runtime fallback is **TBD**. Only assertions written inside a `test` block
  are checked at simulation time.
* A verification statement does not inherit an enclosing `if` guard:
  `if c { assert(x) }` is lowered as an unconditional `assert(x)`. Use
  `assert(c implies x)`.
* A refutable `assume` over free inputs is a hard build error at the **top**
  module and a deferred runtime check in an **instantiated** one.
* Runtime `wrap`/`sat` lowering and enum-typed register resets are
  implemented (earlier limitations, since fixed).
* Glob import patterns were removed from the language: the import string is
  `"file"` or `"file.pub_name"` only (see
  [import](07-typesystem.md#import)).
* **Removed 2026-09-06** (docs↔LiveHD consistency audit): `sigref` (a bare
  dotted `dut.x` read is exactly it — `regref` stays as the way to DRIVE a
  cell); the operator-overload hooks `eq`/`lt`/`to_string`/`to_bool` (no
  dispatch ever existed — `==` is structural, comparisons are integer-only, and
  `to_string`/`to_bool` are ordinary explicit methods; `init` constructor
  overload lists **work** and stay); strings as char tuples (`"hi" ==
  ('h','i')`, `..."h"`, `str#[..]`, `Signed('cad')`, `"ab"#+[..]` — strings
  are opaque, `String(value)` on an integer stays); `pub wire`;
  `format(...)`; a type produced by a call (`:Param_type(String)`) and the
  computed width `u(W)` — both use generics instead (a generic width is
  spelled `Unsigned(bits=W)`); the recursive-enum ADT (`add:(Expr,Expr)` +
  `match does`) — nested enums work and stay; and the tuple-LHS subset test
  for `in`.
* **Removed**: the `int` type and `int(...)` cast (use `Signed`/`Unsigned`,
  `S<N>`/`U<N>`). The register attribute `sync=` is
  deprecated: `async=` is the canonical spelling (`sync=false` means
  `async=true`), and `sync=` still compiles with a deprecation warning.
* **Breaking changes 2026-09-29** (the complete list; code written against the
  earlier rules may need these edits):
    * **Types.** The built-in types are capitalized — `U<N>`, `S<N>`,
      `Unsigned`, `Signed`, `Bool`, `String` — and `Clock`/`Reset` are new (see
      [Type system](07-typesystem.md)). `I<N>`/`iN` is removed (write
      `S<N>`). Casts use the type names (`U8(x)`, `Bool(x)`, `String(x)`). A
      type word may head a suffix chain (`U8.[max]`, `U8(x)#[0]`); `U8.x` is an
      error. User-defined types and variables accept either case; the style
      guide recommends starting type names with uppercase and variable names
      with lowercase.
    * **Old lowercase spellings.** `u8`, `s20`, `i32` (any `u`/`s`/`i` followed
      by digits), `bool`, `boolean`, `unsigned`, `signed` and `string` have no
      alias as types, but they are ordinary identifiers (`s1`, `i0`, `u4` are
      legal variable, field, parameter or lambda names, no backticks). Used as
      a type or cast (`x:u8`, `u8(x)`) without a user declaration they are an
      error whose diagnostic names the new spelling (`u8` was renamed `U8`).
    * **Reserved type words.** `U`/`S` followed by any digit string (`U0`,
      `U1333`), `Unsigned`, `Signed`, `Bool`, `String`, `Clock` and `Reset` can
      not be declared as names, including after `.` (fields, attributes).
    * **Identifiers** (see [Basics](02-basics.md#identifiers)). A backticked
      name equals the plain name only for non-reserved words: `` `else` `` is
      not `else`, and a backticked reserved word (`` `U4` ``, `` `_` ``) is an
      ordinary name (a backticked `` `u8` `` is just `u8`). `$` is not an identifier
      character (write `` `foo$bar` ``). Only letters, digits and `_` form a
      name; emoji and other non-ASCII symbols are errors. A bare `_` is
      reserved and is an error.
    * **Comments and continuation.** Block comments nest
      (`/* a /* b */ c */` is one comment), and nothing inside a comment affects
      parsing. A line that starts with a binary operator, `:`, `#[`/`#`, or
      `case` continues the previous statement. A line that starts with `@` is an
      error. `: :[attr]` is an error (`::` is one token).
    * **Strings** (see [Strings](02-basics.md#strings)). Literal braces are
      only `{{` and `}}`. An empty hole `{}` is always an error, including in
      `puts` (write `puts("a={x} b={y}")`, not `puts("a={} b={}", x, y)`); a
      lone `}` is an error; `"{:b}"` (a format spec with no expression) and a
      backslash inside a format spec are errors. The escapes are exactly
      `\n \t \r \\ \" \' \0 \xNN \u{1-6 hex digits}` and `` \` ``;
      `\uNNNN` without braces, `\{`, `\}` and every other `\c` are errors.
      The same escapes apply inside backticked identifiers. A comment opener
      inside a string is text, while comments inside a `{...}` hole are
      comments.
    * **Enums.** The declaration needs `=` (`enum E = (a, b)`,
      `enum E:U8 = (a, b)`); `enum E:U8 (a, b)` and the expression form
      `enum(...)` (`const Color = enum(...)`) are errors.
    * **Tuples** (see [Tuples](03-bundle.md)). A tuple is all-named or
      all-unnamed; mixing named and unnamed entries is an error. An unnamed
      tuple is accessed only by position (`t[0]`), a named tuple only by name
      (`t.a`, never `t[0]`). A splice concatenates two unnamed tuples or merges
      two named ones (an overlapping name is an error unless one side is `nil`
      or both are equal; an unknown `0sb?` does not yield); mixing a named and
      an unnamed splice is an error. A named tuple's field order has no
      meaning: `for` and `keys()` visit its fields in field-name order.
    * **Assignment targets and destructuring.** Targets are names, fields,
      selectors, bit-selects, and a destructuring of names as a statement
      (`(a, b) = f()`, `(x=f.b, y=f.c) = f(a=3)`,
      `const (p1, p2) = two(...)`). Errors: `f(x) = 3`, `a + b = 3`,
      `(1) = 2`, `(a, f(x)) = g()`, complex entries such as
      `(a.b, c[1]) = f()` or `(self.c, self.d) = ...`, targets rooted at a call
      or expression (`f(x).a = 3`, `(a+b).c = 3`), and an assignment or
      destructuring inside an expression or an init clause
      (`const q = (f(x)=1)`, `if (a, b) = f(); a {}`). A destructuring slot
      never carries a type (`const (a:U32, b) = ...` is an error). A named
      right-hand side binds each bare slot by name, so a slot that matches no
      field is an error; an unnamed one binds by position.
    * **Argument naming** (see
      [Argument naming](06-functions.md#argument-naming)). A call never binds by
      position except for a single non-`self` parameter, a bare variable whose
      name matches a parameter, an argument whose type is unique among all the
      parameters, and `self`. The same rules bind a typed tuple construction
      (`mut x:T = (...)`) and the `__` basic gates, whose arguments are the
      LGraph pin names (`__mux(s=c, p1=b, p2=a)`, ``__or(`as`=(a, b))``); the gate
      names are the cell names too (`__gt`, no `__ge`; `a % b` has no `__mod`
      gate). `puts`/`print` name the message (`msg=`) once `priority` or
      `file` is passed. A var-arg
      `...x` is one parameter holding an unnamed tuple and is always passed by
      name (`add1(x=(1, 2, 3))`, `log(a=a, inp=(false, x))`; `add1(1, 2, 3)` and
      `log(a, false, x)` are errors). Generic calls on
      dotted callees are legal (`prp.queue.make<T=Signed>(depth=16)`).
      Specialized module names use the canonical type spelling (`foo__U8`).
    * **Clock and reset** (see
      [Implicit clock and reset](04b-attributes.md#implicit-clock-and-reset)).
      Registers bind by type to the module's single `Clock`/`Reset` input,
      whatever its name; the name-based binding of `clk`/`clock`/`rst`/`reset`
      is removed. Two or more `Clock` (or `Reset`) inputs require
      `clock_pin=x` (`reset_pin=x`), written without `ref`. A module with
      registers and no `Clock` (`Reset`) input gets a minted `clock:Clock`
      (`reset:Reset`), and a non-`Clock` (non-`Reset`) input with that name is
      an error. Reset polarity comes only from `negreset=true`; a `_n` suffix
      means nothing. A Clock's numeric view (its simulation cycle count) is
      legal only in debug contexts (`test`, `puts`, `assert`/`cassert`); in
      synthesizable logic a Clock only drives clock pins, a `Clock_cell` or
      another `Clock` port, so `U1(clk)` is an error. A Clock is never bound to
      a constant and is modified only through a `Clock_cell`; there are no
      derived clocks or clock muxes for now (use enables). A `Reset` is Bool-like: a Bool expression binds to it
      without a cast, and `false` means no reset. `Clock` and `Reset` are
      distinct types. An instance auto-wires an unbound child `Clock`/`Reset`
      input to the caller's single one; a caller with two or more must bind
      each explicitly. A `comb` can not have `Clock`/`Reset` inputs.
    * **Tests** (see [Running cycles](05b-statements.md#running-cycles-tick)).
      Each `tick` block mints a `clock:Clock` whose count is the tick's 0-based
      cycle index, advanced by `step`. A harness passes a real Clock, never a
      constant such as `clk=1`.
    * **Memories** (see [Memories](08-memories.md)). The default `ordering` of
      a `reg` array is `"program"`. `std.clog2(x)` is a comptime built-in.
    * **Other parser rules.** `wrap` needs an initializer (`wrap const y:U8`
      is an error); a bare typed statement such as `value:U8` is an error;
      `stage[1] out@[4]` with no initializer is legal; a field of a tuple type
      in type position (`reg f:(a:Bool).flags`) is an error; a lambda as a
      binary or bit-select operand inside a tuple is an error. `tick` and
      `step` are reserved words, so `const tick = 1` is an error. Fields and
      methods require backticks too; `async`/`await` are not reserved.
* Tuples are **compile-time only**, now and ever.
* An integer is not a condition: write `if i != 0`, not `if i`.
* The comptime `[...]` test-parameter sweep (one test instance per swept value,
  the planned replacement for the `for { test ... }` fan-out idiom) is reserved
  but not yet specified.
