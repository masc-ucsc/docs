# Fluid Blocks

## Motivation

`comb`, `pipe`, and `mod` describe static dataflow and static cycle
relationships. A `pipe` result is available at a known latency, and `@[N]`
checks that a value is aligned to a known cycle.

A **fluid** block is different. It describes a transactional stream where
each input and output has a valid/retry handshake. The latency of a
transaction may stretch because an internal unit is busy or because a
downstream consumer applies backpressure.

A typical example is a floating-point unit in a CPU. The CPU presents an
operation when it can issue one. The FPU may retry the request when a long
operation such as square root is already running. Later, when a result is
ready, the CPU or scoreboard may retry the response if writeback is blocked.

This is not a `pipe@[1..]` case. `@[N]` is a static cycle-alignment type
check; fluid availability is dynamic and protocol-driven.

## Fluid Lambdas (`fluid`)

A `fluid` lambda is a block whose inputs and outputs are transactional by
default:

```pyrope
type FpuReq = (
  state: u10,
  round: u2,
  op:    u7,
  src1:  u64,
  src2:  u64,
)

type FpuResp = (
  state:  u10,
  result: u64,
  icc:    u3,
)

fluid fpu(req:FpuReq) -> (resp:FpuResp) {
  // req and resp have payload fields plus .[valid], .[retry], and .[fire]
}
```

For each fluid port `x`, the compiler provides:

* `x.[valid]` - producer to consumer; the payload is meaningful this cycle.
* `x.[retry]` - consumer to producer; true means "do not consume/advance".
* `x.[fire]` - shorthand for `x.[valid] and !x.[retry]`.

The payload is still the declared type. For tuple payloads, fields are
accessed normally:

```pyrope
if req.[fire] {
  const op = req.op
}
```

The two handshake directions are written differently:

* **`valid` is inferred.** Assigning a fluid value sets its `.[valid]` to
  the path condition of the assignment — the same inference Pyrope already
  performs for ordinary optional values. `if c { out = f(x) }` produces a
  token exactly when `c` holds. An explicit `out.[valid] = ...` assignment
  overrides the inference (allowed, never required), and an output that is
  never assigned is never valid. An unconditional assignment means a token
  every cycle.
* **`retry` is explicit.** "I can not accept this token" is a policy
  decision (busy, hazard, arbitration loss), not a fact the compiler can
  derive. The consumer must drive `.[retry]`, or explicitly tie it false.

For a fluid input, the caller assigns the payload (its `.[valid]` is
inferred from the assignment) and the callee drives `.[retry]`. For a fluid
output, the callee assigns the payload and the caller drives `.[retry]`.

## Calling Fluid Blocks

A `fluid` call must be bound with a `fluid` declaration:

```pyrope
mod cpu(/*...*/) -> (/*...*/) {
  fluid mut fpu_req:FpuReq

  if issue_fpu {
    fpu_req = (state=rd_state, round=round, op=op, src1=rs1, src2=rs2)
  }                                  // fpu_req.[valid] inferred = issue_fpu

  fluid fpu_resp = fpu(fpu_req)

  // The CPU must account for request retry or the operation could be lost.
  stall = fpu_req.[retry] or other_stall

  fpu_resp.[retry] = writeback_blocked

  if fpu_resp.[fire] {
    regfile[fpu_resp.state] = fpu_resp.result
  }
}
```

The following is rejected:

```pyrope
const fpu_resp = fpu(fpu_req)  // ERROR: fluid call result must be fluid
```

`fluid` calls are allowed only inside `mod` and `fluid` lambdas:

* `comb` may not instantiate `fluid`.
* `pipe` may not instantiate `fluid`.
* `mod` may instantiate `fluid`.
* `fluid` may instantiate `fluid`.

The `fluid`-inside-`fluid` rule is needed for hierarchy. A large unit such as
an FPU can contain internal retry stages, arbiters, result queues, and other
fluid sub-blocks while exposing one fluid request/response interface.

## The Fluid Contract

A fluid port makes protocol promises, not cycle promises:

* A transaction is consumed only when `input.[fire]` is true.
* A transaction is produced or released only when `output.[fire]` is true.
* Payload remains stable while `valid and retry` is true.
* An input retry must be asserted when the block cannot accept the current
  transaction.
* An output valid must remain asserted while a produced transaction is being
  retried.
* A block that accepts a request whose result is not immediately consumed
  must buffer enough state to preserve the transaction.

For example:

```pyrope
fluid fpu(req:FpuReq) -> (resp:FpuResp) {
  reg busy = false
  reg pending:FpuResp = nil
  reg pending_valid = false

  req.[retry] = busy or pending_valid

  if req.[fire] {
    busy = true
    start_operation(req)
  }

  if operation_done {
    pending = operation_result
    pending_valid = true
    busy = false
  }

  if pending_valid {
    resp = pending           // resp.[valid] inferred = pending_valid
  }

  if resp.[fire] {
    pending_valid = false
  }
}
```

## Holding a Transaction

Fluid control often needs to hold a transaction at the current block. A CPU
decode stage, for example, may see an instruction but hold it until a RAW
hazard clears. Holding is expressed by driving `.[retry]`:

```pyrope
fluid decode(tok:FetchTok) -> (out:DecodeTok) {
  tok.[retry] = tok.[valid] and raw_hazard(tok.inst)

  if tok.[fire] {
    out = decode_inst(tok)   // out.[valid] inferred from the path condition
  }
}
```

The idiom has two levels, matching the protocol checks:

* The retry decision **reads** the payload — legal under `.[valid]`, even
  though the token may not fire this cycle.
* The **consumption** — deriving `out` from `tok` — is guarded by
  `.[fire]`.

A retried transaction costs no local storage: the producer must keep the
payload stable while `valid and retry` holds, so the data simply stays
available at the input. To use a transaction's data **beyond** the cycle
where it fires, capture what is needed into a `reg` at fire time. These are
the only two ways to extend a transaction's lifetime: retry it (the
producer holds it) or consume it and store locally.

## Pass-Through Transactions

Pipeline-style CPU stages often carry the same token through several blocks,
adding or changing a few fields along the way. Prefer a tuple payload and
return an updated token:

```pyrope
type FetchTok = (pc:u64, inst:u32)
type DecodeTok = (...FetchTok, src1:u64, src2:u64)

fluid decode(tok:FetchTok) -> (out:DecodeTok) {
  tok.[retry] = tok.[valid] and hazard(tok.inst)

  if tok.[fire] {
    out = (
      ...tok,
      src1 = read_src1(tok.inst),
      src2 = read_src2(tok.inst),
    )
  }
}
```

This replaces older `input output` stage ports with explicit transaction
payloads. The handshake remains attached to the whole transaction, not to
each individual field.

## Protocol Type Checks

The compiler should check fluid protocol use in addition to ordinary type
compatibility:

* A fluid call argument must be a fluid value.
* A fluid call result must be bound with `fluid`.
* A fluid producer assigns the payload; `.[valid]` is the inferred path
  condition of the assignment (an explicit `.[valid]` assignment
  overrides). An output that is never assigned is never valid.
* A fluid consumer must drive `.[retry]`, or explicitly tie it to false.
* A payload **read** must be guarded by `.[valid]` (or a proof that valid
  holds). Reading while retrying is legal and normal — hazard checks and
  arbitration need it.
* A **consuming effect** — updating a `reg` from a transaction, or deriving
  an output transaction from it — must be guarded by `.[fire]`.
* **Data lifetime**: a payload is only meaningful in cycles where
  `.[valid]` holds. To use it longer, either assert `.[retry]` (the
  producer holds the payload stable under `valid and retry`) or let it
  fire and capture the needed fields into a `reg`. Reading the payload in
  a later cycle without one of the two is a compile error.
* An input's `.[retry]` must not combinationally depend on that same
  input's `.[fire]` (checked as a handshake combinational loop).
* A request-side `.[retry]` must be used to stall, hold, or otherwise
  preserve the request. Ignoring retry is a compile error unless explicitly
  waived.
* Payload written under `valid and retry` must be stable across cycles.

The retry-use rule is intentionally strict. If a CPU issues an FPU operation
and ignores `fpu_req.[retry]`, the operation can be silently dropped. The
language should reject that pattern.

When several internal producers can finish at once, the fluid block owns the
arbitration and retries the producers that lose:

```pyrope
fluid result_queue(add:AddResp, mul:MulResp, sqrt:SqrtResp, div:DivResp)
  -> (resp:FpuResp) {

  // fixed priority: add > mul > sqrt > div; losers are retried
  add.[retry]  = resp.[retry]
  mul.[retry]  = resp.[retry] or add.[valid]
  sqrt.[retry] = resp.[retry] or add.[valid] or mul.[valid]
  div.[retry]  = resp.[retry] or add.[valid] or mul.[valid] or sqrt.[valid]

  if add.[fire]    { resp = add_to_resp(add) }
  elif mul.[fire]  { resp = mul_to_resp(mul) }
  elif sqrt.[fire] { resp = sqrt_to_resp(sqrt) }
  elif div.[fire]  { resp = div_to_resp(div) }
  // resp.[valid] inferred: the or of the four fire conditions
}
```

The example gives add highest priority, then multiply, square root, and
divide. A real implementation may use a different policy, but the policy
belongs inside the fluid block that merges the streams.

## Relation to Optional Valid

Fluid validity is not a new mechanism. Pyrope already infers `.[valid]` for
ordinary values as the path condition of their assignment. That one
inferred bit serves three roles:

* **Read safety** — consuming a value whose valid is false is an error.
  This is the existing optional-valid rule.
* **Power** — a flop holding a value with inferred valid `C` does not need
  to be clocked when `!C`. Because invalid data is unreadable, payload
  flops are don't-care on invalid cycles, which licenses automatic clock
  gating — including the compiler-inserted `pipe` stage flops, which
  inherit the valid of the value they transport and gate themselves as
  bubbles travel (see [Pipelining](06c-pipelining.md)). Simulation
  randomizes invalid payloads so code that peeks at gated-off data fails
  loudly instead of working in simulation and breaking on the netlist.
* **Protocol** — under `fluid`, the same bit becomes the producer half of
  the handshake, with `.[retry]` and `.[fire]` added on top.

`valid` is inferred from where you assign; `retry` is explicit because it
is a decision, not a fact. Do not use a fluid value as if it were an
ordinary optional value unless the handshake has fired.

## Relation to `pipe`, `stage[N]`, and `@[N]`

`pipe`, `stage[N]`, and `@[N]` remain the right tools for static latency:

```pyrope
stage[3] tmp = mul(a=a, b=b)
stage[1] out@[4] = add(a=tmp@[3], b=c@[3])
```

Fluid is for dynamic availability:

```pyrope
fluid resp = fpu(req)
if resp.[fire] {
  writeback(resp)
}
```

`resp@[N]` is rejected for fluid values. Even if a fluid block has a bounded
internal latency, downstream retry can delay the visible transaction.

If latency bounds are useful for verification or scheduling, express them as
fluid attributes:

```pyrope
fluid[lat=1..=70, ordered=true] fpu(req:FpuReq) -> (resp:FpuResp) {
  // ...
}
```

These attributes constrain protocol behavior, but they do not make the
result cycle-addressable with `@[N]`.

## Lowering

A fluid port lowers to payload plus handshake signals. For a request/response
FPU:

```text
req payload        -> state, round, op, src1, src2
req.[valid]        -> start
req.[retry]        <- out_retry

resp payload       <- fpu_result, fpu_state, fpu_icc
resp.[valid]       <- fpu_ready
resp.[retry]       -> in_retry
```

For a simple retry stage:

```text
input payload      -> din
input.[valid]      -> dinValid
input.[retry]      <- dinRetry

output payload     <- q
output.[valid]     <- qValid
output.[retry]     -> qRetry
```

`.[fire]` does not need to lower to a stored signal unless it is referenced;
it is the combinational expression `valid and !retry`.
