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
| Temporal library: `past[n]`, `next[n]`, `rose`, `fell`, `stable`, `changed`, `eventually`, `always`, `.[rising]`/`.[falling]` | [Extended Verification](09-verification.md) | `2f-temporal` | |
| Testbench extras: `peek`/`poke`, `step`, `waitfor`, `force`/`release`, `sigref`, `spawn`/`join`/`cancel`, unbounded `tick { }` | [Extended Verification](09-verification.md) | `2f-testbench` | synchronous `test` + bounded `tick N` (DUT called in-loop) sim runs via `lhd sim` |
| `test` syntax: dotted names, runtime `(...)` params | [Testing](05b-statements.md#testing-test), [Extended Verification](09-verification.md) | `2f-test_syntax` | dotted names and the bounded `tick N` cycle loop run via `lhd sim`; replaces `test "string"`; near-term, independent of `2f-testbench` |
| Standard library (`import("prp")`) | [Standard Library](13-stdlib.md) | `2f-stdlib` | wish-list chapter |
| `macro=` memory-compiler binding | [Memories](08-memories.md) | `2f-macro` | |
| `covercase`, in-language `lec()` (and `requires`/`ensures` pre/post) | [Assertions](05-assert.md) | `2f-verif_extras` | `assert`/`cassert`/`cover` work |

Notes:

* Runtime `wrap`/`sat` lowering and enum-typed register resets are
  implemented (earlier limitations, since fixed).
* Glob import patterns were removed from the language: the import string is
  `"file"` or `"file.pub_name"` only (see
  [import](07-typesystem.md#import)).
* The comptime `[...]` test-parameter sweep (one test instance per swept value,
  the planned replacement for the `for { test ... }` fan-out idiom) is reserved
  but not yet specified.
