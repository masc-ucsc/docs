# Implementation status (TBD)

Most of Pyrope is implemented in [LiveHD](https://github.com/masc-ucsc/livehd)
and exercised by its test suite. This page lists the documented features that
are **not implemented yet**; each is also marked "TBD" where it is described.
A feature on this list may parse (`lhd elaborate` is permissive) but does not
lower to working hardware.

Each feature has a matching task page (with a failing example) in the LiveHD
repo under `todo/pyrope/`.

| Feature | Documented in | Task | Notes |
|---------|---------------|------|-------|
| `fluid` lambdas, valid/retry/fire elastic handshakes | [Fluid Blocks](06d-fluid.md) | `2f-fluid` | syntax parses; no lowering |
| `.[defer]` end-of-cycle reads | [Statements](05b-statements.md#cycle-access-and-defer), [Attributes](04b-attributes.md) | `2f-defer` | attribute name recognized only |
| Temporal library: `past[n]`, `next[n]`, `rose`, `fell`, `stable`, `changed`, `eventually`, `always`, `.[rising]`/`.[falling]` | [Extended Verification](09-verification.md) | `2f-temporal` | |
| Testbench extras: `peek`/`poke`, `waitfor`, `force`/`release`, `sigref`, `spawn`/`join`/`cancel` | [Extended Verification](09-verification.md) | `2f-testbench` | plain `test`/`step` blocks work |
| Standard library (`import("prp")`) | [Standard Library](13-stdlib.md) | `2f-stdlib` | wish-list chapter |
| `comptime`-computed / inferred-type memory init (`reg mem2 = reset_value`) | [Memories](08-memories.md) | `2f-mem_comptime_init` | multi-dim memories + literal/scalar init contents are implemented |
| `macro=` memory-compiler binding | [Memories](08-memories.md) | `2f-macro` | |
| `lg` attribute (explicit lgraph/module name) | [Attributes](04b-attributes.md#lg-explicit-lgraph-name) | `2f-lg` | |
| `...` splice surface: mid-literal insertion (`(1, ...mid, 6)`) and call-argument spread (`foo(a=1, ...rest)`) | [Tuples](03-bundle.md#tuple-mutability), [Variables](04-variables.md#tupleset-operators), [Struct types](07b-structtype.md) | `2f-splice` | the merge form `(...a, ...b)` and var-arg gather `(...args)` work |
| `covercase`, in-language `lec()` (and `requires`/`ensures` pre/post) | [Assertions](05-assert.md) | `2f-verif_extras` | `assert`/`cassert`/`cover` work |

Notes:

* Runtime `wrap`/`sat` lowering and enum-typed register resets are
  implemented (earlier limitations, since fixed).
* Glob import patterns were removed from the language: the import string is
  `"file"` or `"file.pub_name"` only (see
  [import](07-typesystem.md#import)).
