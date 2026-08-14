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
| `fluid` lambdas, valid/retry/fire elastic handshakes | [Fluid Blocks](06d-fluid.md) | `2f-fluid` | syntax parses; no lowering |
| Temporal library: `past(x, n)`, `rose`, `fell`, `stable`, `changed`, `eventually(x, w)`, `always(x, w)` | [Extended Verification](09-verification.md) | `2f-temporal` | positional args only — there is no `f[N](x)` bracket form. The *pipelining* `past[N](x)` DOES work (design body only) and is a different operator. No edge attributes: `.[rising]`/`.[falling]`/`.[changed]`/`.[stable]` are not recognized. `lhd formal verify` must reject these calls with an explicit "not implemented" diagnostic |
| Testbench extras: multi-match string-path refs, `force`/`release`, `cpp(...)` external models, unbounded `tick { }` | [Extended Verification](09-verification.md) | `2f-testbench` | the instance/`step` model runs via `lhd sim`, with bare dotted DUT access and both the dotted and single-cell string forms of `sigref`/`regref`, plus `if`/`continue` waiting and `if`-block monitors. `peek`/`poke` are **removed** — a ref bound outside the loop replaces them; `waitfor`/`spawn`/`join`/`cancel` are dropped (replaced by that idiom) |
| `regref` — the SYNTHESIZABLE cross-scope register/memory attach by string path (zero-or-many matches) | [Type system](07-typesystem.md#register-reference), [Memories](08-memories.md#shared-memories-with-regref) | `2f-testbench` | still TBD. The `test`-block `sigref`/`regref` (single cell, dotted or string, writable for `regref`) is a separate construct and is IMPLEMENTED |
| Statements rejected inside a `test` block: `for` loops, `.[rand]`/`.[crand]`, `past[N]`, positional instantiation-by-call | [Testing](05b-statements.md#testing-test) | `2f-test_syntax` | dotted names, runtime `(...)` params, `tick`/`step`/`break`/`continue`, bare dotted DUT access, and `sigref`/`regref` all work |
| Standard library (`import("prp")`) | [Standard Library](13-stdlib.md) | `2f-stdlib` | wish-list chapter |
| `macro=` memory-compiler binding | [Memories](08-memories.md) | `2f-macro` | |
| `cover`, `covercase`, in-language `lec()`/`lec_valid()` | [Assertions](05-assert.md) | `2f-verif_extras` | `assert`/`cassert`/`assume`/`assert_always` work; `cover` does NOT exist in any context |
| `.[rand]` / `.[crand]` random generation | [Random](05-assert.md#random) | `2f-verif_extras` | rejected in `test` blocks and design bodies; survives only where it constant-folds |
| `assert.[failed]` (read/clear the accumulated failure flag in a `test`) | [Test](05-assert.md#test) | `2f-verif_extras` | |
| `always_assert` / `always_cassert` / `always_assume` / `always_cover` / `always_covercase`; valid-based (`.[valid]`) gating of checks | [Reset and verification](05-assert.md) | `2f-verif_extras` | the implemented spelling is `assert_always`; no valid-based gating exists |
| Generics: body references of a generic name (`T(a)`, `mut tmp:T`, `a + N`, `F(v=a)`), constant/lambda-valued generics, defaults `<T, N=4>`, named `<T=…>` bindings | [Functions](06-functions.md) | `3g` | signature `:T` binding works: explicit `f<u8>(…)`, inference, `mod`/`pipe` specialization |
| Input default values (`comb f(in1:u4, in2=3)`, tuple-scope `b:signed=a+5`) | [Functions](06-functions.md), [Variables](04-variables.md) | `3g` | omitting a defaulted input errors `fcall-missing-arg` today |

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
* The comptime `[...]` test-parameter sweep (one test instance per swept value,
  the planned replacement for the `for { test ... }` fan-out idiom) is reserved
  but not yet specified.
