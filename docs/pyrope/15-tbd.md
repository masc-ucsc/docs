# Implementation status (TBD)

Most of Pyrope is implemented in [LiveHD](https://github.com/masc-ucsc/livehd)
and exercised by its test suite. This page lists the documented features that
are **not implemented yet**; each is also marked "TBD" where it is described.
A feature on this list may parse (`lhd elaborate` is permissive) but does not
lower to working hardware.

Each feature has a matching task page (with a failing example) in the LiveHD
repo under `todo/`.

| Feature | Documented in | Task | Notes |
|---------|---------------|------|-------|
| `fluid` lambdas, valid/retry/fire elastic handshakes | [Fluid Blocks](06d-fluid.md) | `3f-fluid` | syntax parses; no lowering |
| Temporal library: `past(x, n)`, `rose`, `fell`, `stable`, `changed`, `eventually(x, w)`, `always(x, w)` | [Extended Verification](09-verification.md) | `3f-temporal` | positional args only — there is no `f[N](x)` bracket form. The *pipelining* `past[N](x)` DOES work (design body only) and is a different operator. No edge attributes: `.[rising]`/`.[falling]`/`.[changed]`/`.[stable]` are not recognized. `lhd formal verify` must reject these calls with an explicit "not implemented" diagnostic |
| Testbench extras: multi-match string-path refs, `force`/`release`, `cpp(...)` external models, unbounded `tick { }`, writing a register BELOW the top instance | [Extended Verification](09-verification.md) | `3f-temporal` | the instance/`step` model runs via `lhd sim`: bare dotted DUT access READS any cell at any depth, and `regref` (dotted or single-cell string) DRIVES one at the top level. `peek`/`poke` and `sigref` are **removed** — a bare dotted read is exactly what `sigref` was; `waitfor`/`spawn`/`join`/`cancel` are dropped |
| `regref` — the SYNTHESIZABLE cross-scope register/memory attach by string path (zero-or-many matches) | [Type system](07-typesystem.md#register-reference), [Memories](08-memories.md#shared-memories-with-regref) | `3f-temporal` | still TBD. The `test`-block `regref` (single cell, dotted or string, writable) is a separate construct and is IMPLEMENTED |
| Statements rejected inside a `test` block: `.[rand]`/`.[crand]`, `past[N]`, positional instantiation-by-call | [Testing](05b-statements.md#testing-test) | `3f-temporal` | dotted names, runtime `(...)` params, `tick`/`step`/`break`/`continue`, bare dotted DUT access, `for` loops and `regref` all work. `sigref` was REMOVED 2026-09-06 -- a bare dotted read is exactly it |
| Standard library (`import("prp")`) | [Standard Library](13-stdlib.md) | `3f-bitpack` | wish-list chapter |
| `macro=` memory-compiler binding | [Memories](08-memories.md) | `3f-macro` | |
| `cover`, `covercase`, in-language `lec()`/`lec_valid()` | [Assertions](05-assert.md) | `3f-temporal` | `assert`/`cassert`/`assume`/`assert_always` work; `cover` does NOT exist in any context |
| `.[rand]` / `.[crand]` random generation | [Random](05-assert.md#random) | `3f-temporal` | rejected in `test` blocks and design bodies; survives only where it constant-folds |
| `assert.[failed]` (read/clear the accumulated failure flag in a `test`) | [Test](05-assert.md#test) | `3f-temporal` | |
| `always_assert` / `always_cassert` / `always_assume` / `always_cover` / `always_covercase`; valid-based (`.[valid]`) gating of checks | [Reset and verification](05-assert.md) | `3f-temporal` | the implemented spelling is `assert_always`; no valid-based gating exists |
| A `ref self` method used in a right-hand-side EXPRESSION (`mut a_2 = a_1.f1(x=4)`, output named `self`) | [Functions](06-functions.md), [Struct types](07b-structtype.md), [Type system](07-typesystem.md) | `3g` | the STATEMENT form and UFCS both work; only the expression form errors `a method with a 'ref' parameter … cannot be used in a right-hand-side expression`. Workaround: copy first, then mutate |
| A VECTOR io port — an unnamed/positional tuple or an array as a module port | [Functions](06-functions.md) | `3g` | no lowering in either direction; the NAMED tuple port works (`tests/sim/tuple_io_ports.prp`). Tracker: `inou/prp/tests/fixme/vector_io_ports.prp` |
| Bit packing with `#[..]`: comptime unpack into an array, the exact-width check on unpack, `...` splice of a declared `[N]T` when BUILDING a tuple, reductions/`#sext` over an array variable | [Internals](10-internals.md), [Deprecated](21-deprecated.md) | `3f-bitpack` | Implemented: packing a tuple LITERAL (`(a, b)#[..]`, `(...stages, inp)#[..]`) at comptime and at runtime, entry 0 at bit 0; packing a tuple/array VARIABLE (`x#[..]`); the declared-width guard, so an untyped or literal entry is rejected; the exact-width destination check (`z:u16 = (b, a)#[..]` on 12 bits errors, and an undeclared destination errors); the named-field rule, with the real diagnostic on a multi-field bundle and the one-field case still legal; reductions and sub-ranges over a packed tuple literal (`(a, b)#+[..]`); unpacking into a declared array at RUNTIME (`const x:[2]u4 = b#[..]` emits `b[3:0]`, `b[7:4]`). `concat` is REMOVED and diagnoses its own replacement (`concat-removed`), which is the error to read first, because the argument order reverses. Still missing: comptime unpack does not split — `const x:[2]u4 = b8#[..]` folds BOTH entries to the whole word, a silent wrong value; the exact-width check on unpack, so `b:u9` into `[2]u4` silently drops bit 8; `...` expands an unnamed tuple and an untyped array literal but not a declared `const x:[2]u4 = (3,1)` when building a tuple (as a PACKING entry it does expand); reductions and `#sext` reject an array VARIABLE operand (a tuple literal is fine); an array ELEMENT read is not a packing entry (`(x, arr[2], arr[1])#[..]` reports `concat lane … has no declared bit width` — bind each to a typed name first); `#[..]` on a string does not constant-fold |

Notes:

* `requires`/`ensures` were **removed** from the language. They parse today
  only to emit a "no obligation generated" warning; write an `assume` for a
  precondition and an `assert` for a postcondition.
* A design-body `assert` is checked by `pass.formal` and emitted into the
  Verilog netlist, but is **not executed by `lhd sim`** — the simulation
  runtime fallback is pending. Only assertions written inside a `test` block
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
  ('h','i')`, `..."h"`, `string#[..]`, `signed('cad')`, `"ab"#+[..]` — strings
  are opaque, `string(int)` stays); `pub wire`; `format(...)`; a type produced
  by a call (`:Param_type(string)`) and the computed width `u(W)` — both use
  generics instead; the recursive-enum ADT (`add:(Expr,Expr)` + `match does`) —
  nested enums work and stay; and the tuple-LHS subset test for `in`.
* Tuples are **compile-time only**, now and ever.
* An integer is not a condition: write `if i != 0`, not `if i`.
* The comptime `[...]` test-parameter sweep (one test instance per swept value,
  the planned replacement for the `for { test ... }` fan-out idiom) is reserved
  but not yet specified.
