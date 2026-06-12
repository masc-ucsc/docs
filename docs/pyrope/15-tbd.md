# Implementation status (TBD)

Most of Pyrope is implemented in [LiveHD](https://github.com/masc-ucsc/livehd)
and exercised by its test suite. This page lists the documented features that
are **not implemented yet**; each is also marked "TBD" where it is described.
A feature on this list may parse (`lhd elaborate` is permissive) but does not
lower to working hardware.

| Feature | Documented in | Notes |
|---------|---------------|-------|
| `fluid` lambdas, valid/retry/fire elastic handshakes | [Fluid Blocks](06d-fluid.md) | syntax parses; no lowering |
| `.[defer]` end-of-cycle reads | [Statements](05b-statements.md#cycle-access-and-defer), [Attributes](04b-attributes.md) | attribute name recognized only |
| Temporal library: `past[n]`, `next[n]`, `rose`, `fell`, `stable`, `changed`, `eventually`, `always`, `.[rising]`/`.[falling]` | [Extended Verification](09-verification.md) | |
| Testbench extras: `peek`/`poke`, `waitfor`, `force`/`release`, `sigref`, `spawn`/`join`/`cancel` | [Extended Verification](09-verification.md) | plain `test`/`step` blocks work |
| Overload-gathering call dispatch (`const add = [add1, add2]; add(x)`) | [Lambdas](06-functions.md) | `init` overload sets already resolve |
| Generic `<T>` per-call-site specialization | [Lambdas](06-functions.md) | untyped-parameter templates work; explicit `<T>` body substitution pending |
| Standard library (`import("prp")`) | [Standard Library](13-stdlib.md) | wish-list chapter |
| Multi-dimensional memories, memory initialization contents | [Memories](08-memories.md) | |
| `macro=` memory-compiler binding | [Memories](08-memories.md) | |
| `lg` attribute (explicit lgraph/module name) | [Attributes](04b-attributes.md#lg-explicit-lgraph-name) | |
| `.[bw_max]`/`.[bw_min]` debug attribute reads | [Attributes](04b-attributes.md), [Type system](07-typesystem.md) | the pass tracks the values internally; the read is not wired |
| `covercase`, in-language `lec()` (and `requires`/`ensures` pre/post) | [Assertions](05-assert.md) | `assert`/`cassert`/`cover` work |

Notes:

* Runtime `wrap`/`sat` lowering and enum-typed register resets are
  implemented (earlier limitations, since fixed).
* Glob import patterns were removed from the language: the import string is
  `"file"` or `"file.pub_name"` only (see
  [import](07-typesystem.md#import)).
