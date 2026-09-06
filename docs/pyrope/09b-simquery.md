# Querying a simulation

`lhd sim --query` lets a tool — typically a coding agent — ask questions about a
simulation run without generating a VCD, parsing a waveform, or adding `puts`
statements to the testbench. One stateless invocation carries a versioned JSON
batch; the answers come back in the result envelope, in request order, each one
independently `ok` or carrying a structured error.

This is a *debugging* interface, not a language feature: nothing in this chapter
changes the design or the `test` block. It complements
[Extended Verification](09-verification.md), which is about what a testbench can
express; this is about inspecting what a testbench did.

## A worked example

```pyrope
mod fifo(push:bool, din:u8) -> (count:u4@[0], head:u8@[0]) {
  reg cnt:u4 = 0
  reg mem:[8]u8 = nil

  if push { mem[cnt] = din; wrap cnt += 1 }

  count = cnt
  head  = mem[0]
}

test fifo.fill {
  mut acc = fifo
  tick 6 {
    acc.push = clock < 4
    acc.din  = 0x10 + clock
    step
  }
  assert(acc.cnt == 4, "four pushes landed")
}
```

Ask what is observable:

```shell
lhd sim fifo.prp fifo.fill --workdir w --result-json out.json \
  --query '{"schema_version":1,"kind":"sim_query",
            "queries":[{"id":"all","op":"signals"}]}'
```

The answers land at `out.json`'s `query` member, alongside the existing `tests`
and `debug` members:

```json
{"name":"acc.cnt",   "kind":"flop",   "bits":4, "declared_bits":4, "signed":false}
{"name":"acc.push",  "kind":"input",  "bits":1, "declared_bits":1, "alias":"acc.__in.push"}
{"name":"acc.din",   "kind":"input",  "bits":8, "declared_bits":8}
{"name":"acc.count", "kind":"output", "bits":4, "declared_bits":4}
{"name":"acc.head",  "kind":"output", "bits":8, "declared_bits":8}
{"name":"acc.mem",   "kind":"memory", "bits":8, "declared_bits":8, "size":8}
```

Note `acc.cnt` is both stored and declared as 4 bits. Literal-width realization
means an unsigned value does not carry a hidden sign slot. Both fields remain in
the schema because imported or conservatively widened internal nets can still
differ from the source declaration. Everything else — `clock` and `reset`
inputs, the sub-instance tree — is enumerated the same way, with hierarchical
names rooted at the testbench instance variable.

## Reading values

```shell
--query '{"schema_version":1,"kind":"sim_query","queries":[
  {"id":"cnt","op":"value","signal":"acc.cnt","at":{"cycle":3}},
  {"id":"w2", "op":"value","signal":"acc.mem[2]","at":{"cycle":5}}]}'
```

```json
{"id":"cnt","ok":true,"at":{"cycle":3,"phase":"post"},"signal":"acc.cnt",
 "value":{"bits":4,"declared_bits":4,"signed":false,
          "hex":"4","dec":"4","known_mask":"f","sampled":"settled"}}
{"id":"w2","ok":true,"at":{"cycle":5,"phase":"post"},"signal":"acc.mem","index":2,
 "value":{"bits":8,"declared_bits":8,"signed":false,
          "hex":"12","dec":"18","known_mask":"ff"}}
```

Values are full-width hardware bit vectors, never host integers: `hex` is exactly
`ceil(bits/4)` digits, so a 97-bit signal round-trips without truncation. `dec` is
the same value rendered according to the published signedness at the declared
width, so a consumer never has to re-implement sign or zero extension.

`acc.mem[2]` is a single **memory word** read: memories are addressable by
explicit index. Selectors never enumerate memory contents, and there is no
whole-array dump — v1 reads one word at a time, on purpose.

## Outputs and state are one commit apart

This is the one semantic surprise, and it is deliberate:

```json
{"id":"cnt_at3","signal":"acc.cnt",  "value":{"hex":"04","dec":"4"}}
{"id":"out_at3","signal":"acc.count","value":{"hex":"3", "dec":"3"}}
```

At the same cycle the register `cnt` reads 4 while the output `count = cnt` reads
3. Both are correct:

* **State** (`flop`, `pipe`, `memrd`, `input`) is the **settled end-of-period**
  value — the point `--probe` has always sampled, and the value the next cycle
  starts from.
* **An output** is the value it **drove during** that period, computed from the
  state entering the cycle. That is exactly what the VCD shows at that period's
  timestamps.

So a register and the combinational output reading it are one clock edge apart by
construction. Reporting a post-commit output instead would mean re-evaluating the
whole design once per sampled cycle; serving it from what the cycle already
computed is free.

You never have to remember which is which: **every value says so**, carrying
`"sampled":"settled"` or `"sampled":"during_period"`.

There is only one sampling point, spelled `"phase":"post"`. Latch windows,
negedge commits and secondary-clock edges all happen *inside* one `step`, so
nothing observes them from outside; a `pre` phase is a planned extension.

## Transitions

`changes` returns the transitions of a signal over a closed interval; a change
reported at cycle *c* means the sample at *c* differs from the sample at *c-1*,
so *c* is the first observation of the new value — not a subcycle edge time.

```json
{"id":"rows","op":"changes","signal":"acc.cnt","from":{"cycle":0},"to":{"cycle":3}}
```

```json
{"id":"rows","ok":true,"signal":"acc.cnt","count":3,"complete":true,
 "changes":[{"cycle":1,"old":{"dec":"1"},"new":{"dec":"2"}},
            {"cycle":2,"old":{"dec":"2"},"new":{"dec":"3"}},
            {"cycle":3,"old":{"dec":"3"},"new":{"dec":"4"}}],
 "searched":{"from":0,"to":3}}
```

Add `"count_only":true` when only the number matters — useful when a window holds
more transitions than you want to transport. Every result carries `count`
regardless, so a row list capped by `max_results` still tells you how many events
there were:

```json
{"id":"edges","ok":true,"signal":"acc.cnt","changes":[],"count":3,
 "complete":true,"truncated":false,"searched":{"from":0,"to":5}}
```

`next_change` is the same machinery bounded to the first transition after a
point, and its anchor is strictly exclusive.

## Searching

`find` scans an interval for the first cycle satisfying a predicate, and can
report other signals at the moment it hits — answering "what was X when Y first
became Z" in a single run:

```json
{"id":"hit","op":"find","from":{"cycle":0},"to":{"cycle":5},
 "expr":{"sig":"acc.cnt","cmp":"==","value":"3"},
 "sample":["acc.din","acc.head"]}
```

```json
{"id":"hit","ok":true,"found":true,"at":{"cycle":2,"phase":"post"},
 "sample":[{"signal":"acc.din", "value":{"hex":"12","dec":"18"}},
           {"signal":"acc.head","value":{"hex":"10","dec":"16"}}],
 "complete":true,"searched":{"from":0,"to":5}}
```

The predicate is a JSON tree, not a string, so there is no expression parser to
disagree with: `all`/`any`/`not` nodes over leaves that are either a comparison
(`==`, `!=`, `<`, `<=`, `>`, `>=`) against a literal or another signal, or an
edge test (`rising`, `falling`, `changed`). Literals are decimal or hex
*strings*, parsed at arbitrary precision — a 64-bit host integer never appears
anywhere on this path.

## Selections

`values`, `snapshot` and `diff` work over a set of signals chosen by `scope`,
`glob`, `regex` or `kind` — placed directly on the query object:

```json
{"id":"state","op":"values","kind":"flop","at":{"cycle":5}}
{"id":"delta","op":"diff","scope":"acc","from":{"cycle":2},"to":{"cycle":4}}
```

`diff` lists only what actually changed:

```json
{"id":"delta","ok":true,
 "from":{"cycle":2,"phase":"post"},"to":{"cycle":4,"phase":"post"},
 "diff":[{"signal":"acc.cnt",  "from_value":{"dec":"3"},"to_value":{"dec":"4"}},
         {"signal":"acc.count","from_value":{"dec":"2"},"to_value":{"dec":"4"}}],
 "complete":true,"truncated":false}
```

Expansion order is the catalog order, so results are reproducible across runs.

## Asking about a failure

The common case is not "what is signal X at cycle 4200" — it is "the test just
failed, show me what was going on". A timestamp can therefore be **relative to
the failing assert** instead of absolute:

```shell
--query '{"schema_version":1,"kind":"sim_query","queries":[
  {"id":"at_fail","op":"snapshot","scope":"a","at":{"event":"fail"}},
  {"id":"before", "op":"value","signal":"a.c","at":{"event":"fail","offset":-1}}]}'
```

The same run that reports the failure answers both, so there is no round trip to
learn the cycle first:

```json
"run":{"fail_cycle":5, ...}
{"id":"at_fail","ok":true,"at":{"cycle":5,"phase":"post"},"values":[...]}
{"id":"before", "ok":true,"at":{"cycle":4,"phase":"post"},"signal":"a.c",
 "value":{"dec":"5","sampled":"settled"}}
```

The invocation still exits with the assert code — the verdict is unchanged by
asking about it. If the test *passed*, an anchored query says so rather than
inventing a cycle:

```json
{"id":"n","ok":false,
 "error":{"class":"invalid_range",
          "message":"this query is relative to the first failing assert, but the test did not fail"}}
```

## Errors

A bad signal name fails that one query, not the batch, and suggests neighbours:

```json
{"id":"oops","ok":false,
 "error":{"class":"unknown_signal","message":"no signal matches acc.nosuch",
          "suggestions":["acc.count","acc.push","acc.clock","acc.reset","acc.cnt"]}}
```

The split is deliberate. A malformed *request* — unknown `schema_version`, an
unknown op, an unknown field, a bad time range — is a usage error and exits 2,
because it means the caller is confused about the protocol. A well-formed request
that asks about something absent exits 0 with `ok:false` in band, because the
answer *is* "that does not exist". Unknown fields are rejected rather than
ignored, so a typo can never silently change what you asked.

If the replayed test fails an assert, the run still exits with the assert code
and the query answers are still emitted — the whole point is to inspect a run
that went wrong.

## What v1 does not do

Named plainly, because each fails loudly rather than returning something
misleading:

* **No `known_mask` information.** The field is always all-ones. The compiled
  simulator is two-state: `x`/`?` bits are resolved to concrete pseudo-random
  values when a literal is parsed. The honest disclosure is `run.seed` and
  `run.rng_draws`, which the response always carries.
* **No checkpoint acceleration.** A batch always replays from cycle 0 and reports
  `checkpoint_used: null` and `cycles_replayed`, so the cost is visible.
  `--query` does not combine with `--restart-at` or the `--vcd-*` window flags.
* **One test per invocation**, and only the first `tick` loop's timeline.
  A `cycle` is that loop's iteration index; a body that advances several periods
  per iteration exposes one settled sample per iteration, not per period.
* `changes`/`next_change` take a single signal; `find` has no bit-slice leaf;
  signed ordered comparisons are refused rather than guessed.

## Relationship to the older flags

`--list-signals`, `--probe` and `--break-when` still work exactly as before and
still report through the envelope's `debug` member. They remain the low-ceremony
spelling for a quick look. The differences that matter: they truncate values to
64 bits, they cannot see outputs or memories, and `--break-when` reports a
missing signal as simply "never true". The query API exists because none of those
are acceptable when a tool, rather than a person, is reading the answer.
