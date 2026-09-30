# Attributes

Attributes is the mechanism that the programmer specifies some special
checks/functionality that the compiler should perform. Attributes are
associated to variables either by setting them at declaration or by reading
their value at use sites. Some example of attribute use is to mark statements
compile time constant, read the number of bits in an assertion, give placement
hints, or even interact with the synthesis flow to read timing delays.


A key difference between attributes and tuple fields is that attributes are
compile-time metadata interpreted by the compiler flow. `valid` and `retry`
are the only runtime exceptions: they temporarily use attribute syntax
because a better syntax for the fluid handshake signals has not been settled.
[Fluid support](06d-fluid.md) is not fully implemented.
Fluid also defines `x.[fire]` as shorthand for
`x.[valid] and !x.[retry]`; it is derived from those two signals.

Internally, types are also propagated as attributes, but basic types can only be
an integer (`Unsigned`/`Signed`), `Bool`, `String`, `Clock`, or `Reset` (see
[Type system](07-typesystem.md)).


Pyrope does not specify all the attributes, the compiler flow specifies them.
There are some built-in required attributes like checking the number of bits.
For example, a synthesis flow may define placement/timing/power attributes
(`reg r::[left_of=other, max_delay=2, low_power=true, donttouch=true] = 0`);
these are tool-defined, not part of the language.

Reading compile-time metadata attributes should not affect a logical equivalence check. Setting
attributes can have a side-effect because it can change bits used for an
integer or change pins like reset/clock in registers. Additionally,
attributes can affect assertions, so they can stop/abort the compilation.


There are two operations that can be done with attributes: **set** and
**read**. The two operations have distinct syntax so the reader (and the
parser) can never confuse them.

* **Set** (`var::[attr]`): only allowed at *declaration* sites — `mut`,
  `reg`, `const`, `comb`, `pipe`, `mod` — and on tuple fields at the point
  they are introduced. The set binds the attribute to all uses of the
  variable. If no value is given, the attribute is set to `true`. E.g:
  `reg counter::[clock_pin=clk1] = 0`, `const c::[debug] = 3`.
  Integer range/width attributes such as `max`, `min`, `bits`,
  and `sign` are read-only metadata. Constrain them indirectly
  through the declared type, e.g. `mut foo:Signed(max=300, min=0) = 4` or
  `mut bar:U14 = 0`, never with `foo:Signed:[max=300]`.

* **Read** (`var.[attr]`): allowed everywhere a normal expression is
  allowed. Returns the attribute's current value (any type — usually
  integer, `Bool`, or `String`). If the attribute was not set, the read
  returns `nil`. E.g: `tmp.[bits] < 30`, `assert.[failed]`,
  `x.[size]`, `i.[max]`. `bits` of an untyped comptime integer is derived
  from its value (`comptime const N = 13` gives `N.[bits] == 4`); an untyped
  runtime value reads `nil` (see
  [Integer Bitwidth](#integer-bitwidth-attribute-list)).

The two exceptions, `valid` and `retry`, represent *runtime* handshake signals
rather than compile-time metadata. Their `.[...]` syntax can also appear on
the LHS to drive the underlying wire (`self.[valid] = v != 33` or
`req.[retry] = busy`); the fluid machinery remains TBD.
All other attributes (`max`, `bits`,
`comptime`, `debug`, `key`, …) are read-only at use sites. Integer range
metadata (`max`/`min`/`bits`/`sign`) comes from the declared type (except
`bits` of an untyped comptime integer, which comes from its value); the
others are bound with `::[…]` at the declaration.

Compile-time metadata reads happen at elaboration time. The fluid handshake
signals and their derived `fire` expression are runtime values.
To turn a read into a check, wrap it in `cassert` (or `assert`):

```pyrope
cassert(y.[`comptime`]) // 'y' must be comptime
cassert(y.[bar] == 3) // 'y.[bar]' must equal 3
cassert(tmp.[bits] < 30)
```

To check whether an attribute is set at all (without caring about its
value), compare against `nil`. Inside `.[...]` reads, comparisons against
`nil` are exempt from "the attribute must be defined" — they return `true`
or `false` rather than erroring at compile time:

```pyrope
cassert(foo.[attr1] != nil) // attr1 was set on 'foo'
cassert(xx.[attr2] == nil) // attr2 was never set on 'xx'
cassert(foo.[attr1] == 2) // value check (errors at compile time if unset)
```

Since conditional code can depend on an attribute, which results in executing a
different code sequence that can lead to the change of the attribute. This can
create a iterative process. It is up to the compiler to handle this, but the
most logical is to trigger a compile error if there is no fast convergence.


```pyrope
// comptime as prefix modifier
comptime const foo:U32 = xx     // enforce that foo is comptime constant
yyy = xx                        // yyy does not check comptime
cassert(yyy.[`comptime`]) // now, checks that 'yyy' is comptime

// reading attributes
mut tmp:U8 = 0
if bar == 3 {
  tmp = bar
  cassert(bar.[`comptime`])
}

cassert(tmp.[bits] == 8 and not tmp.[`comptime`])  // typed: bits from U8
```

Pyrope allows to assign the attribute to a variable or a function call. Not to
statements because it is confusing if applied to the condition or all the
sub-statements.

```pyrope
comptime mut z = xx            // z is a comptime variable

if cond.[`comptime`] {           // cond is checked to be compile time constant
  comptime const x = a + 1     // x is comptime
}else{
  comptime const x = b         // x is comptime
}


if cond.[`comptime`] {           // checks if cond is comptime
  const v = cond
  if cond {
    puts("cond is compile time and true")
  }
}
```


The programmer could create custom attributes but then a LiveHD compiler pass
to deal with the new attribute is needed to handle based on their specific
semantic. To understand the potential Pyrope syntax, this is a hypothetical
`poison` attribute that marks a tuple field.

```pyrope
const bad = (const a=3, const b::[poison=true]=4)

const b = bad.b

cassert(b.[poison] and b==4)
```


Attributes control fields like the default reset and clock signal. This allows
to change the control inside procedures. A `*_pin` attribute (`clock_pin`,
`reset_pin`, ...) is always a connection: it connects the pin to the named
wire, not to the wire's current value, so it takes the signal directly and is
written without `ref` (`clock_pin=ref clk` is a compile error). A `Reset` is
Bool-like, so `reset_pin=false` means no reset. A `Clock` is never bound to a
constant, so `clock_pin` always names a `Clock` signal.

```pyrope
reg counter:U32 = 0

reg counter2::[clock_pin=clk1]=0
reg counter3::[reset_pin=rst2]=0
reg counter5:U32:[reset_pin=false]=nil // OK, no reset
reg counter6::[clock_pin=true]=0       // error: a Clock is never a constant
reg counter7::[clock_pin=ref clk1]=0   // error: a pin takes the signal, no `ref`
```

In the long term, the goal is to have any synthesis directive that can affect
the correctness of the result to be part of the design specification so that it
can be checked during simulation/verification.


There are 3 main classes of a attributes that all the Pyrope compilers should
always implement: Bitwidth, comptime, debug.

## Variable attribute list

In the future, the compiler may implement some of the following attributes, as
such. The attributes are by category.

Attributes are always compile time, but have the property of being sticky
(propagate across assignments and expression usage) or just being used for
checks/instantiation/hints on the assigned variable. From the following lists,
only `_debug` is a sticky, but all the "user custom" attributes can be sticky
or not. All the user attributes starting with `_` (like `_foo`) are sticky.
Otherwise, they are not sticky.

### Synthesis attribute list

There are a list of reserved attribute names for synthesis. These are hints and
can be ignored if not supported by the tool:

* `critical`: synthesis time criticality
* `delay`: synthesis optimization target delay hint
* `donttouch` or `keep`: do not touch/optimize away
* `inp_delay`, `out_delay`: synthesis optimizations hints
* `left_of`, `right_of`, `top_of`, `bottom_of`, `align_with`: placement hints
* `max_delay`, `min_delay`: synthesis optimizations checked at simulation
* `max_load`, `max_fanout`, `max_cap`: synthesis optimization hints

A clock or reset wire is not marked with an attribute: it is declared with the
`Clock` or `Reset` type (see [Implicit clock and reset](#implicit-clock-and-reset)).

#### Block-scoped synthesis attributes (implemented)

A statement block can carry its own synthesis attributes: the block becomes
its own synthesis **partition region**, optionally with a per-region ABC flow:

```
{::[abc='strash; &get -n; &dch -f; &nf {D}; &put', color=2]
  mut t = b & c
  if s { t = a | b }
  y = t ^ c
}
```

* `color=<positive integer | "label">` picks the region id. Two blocks with the
  same integer (or the same label anywhere in the file) form one region group;
  with no `color` a fresh id is auto-allocated.
* `abc='…'` is the region's verbatim ABC flow override (same vocabulary as
  `--set pass.abc.flow`). **Single-quote it** — a double-quoted string would
  interpolate `{D}` (unless written `{{D}}`, see
  [Strings](02-basics.md#strings)).
* The annotation is semantics-free: the annotated source is LEC-provably
  identical to the stripped source. Unknown attribute names or malformed
  values are hard compile errors (a mistyped hint never silently no-ops).
* Every hardware node generated by the block's statements gets the region's
  node color; `lhd pass abc` maps each color region as a separate module and
  `lhd pass color <alg>` preserves source-seeded regions (algorithm ids
  allocate above them). See the LiveHD `08-synth.md` chapter for the
  frequency-optimization loop these attributes serve.

A worked customization sample. The ALU below spends most of its delay in the
compare cone; the block isolates it and gives only that region a deeper,
delay-targeted ABC flow, while the label groups two lexically separate blocks
into one region:

```pyrope
mod mini_alu(op:U2, a:U16, b:U16) -> (res:U16@[0], cmp:Bool@[0]) {
  // default region (color 0): mapped with the global flow
  mut r:U16 = 0
  match op {
    == 0 { wrap r = a + b }
    == 1 { r = a ^ b }
    == 2 { r = a & b }
    == 3 { r = a | b }
  }
  res = r

  // its own region, deeper optimization + a binding delay target of 4
  {::[abc='strash; &get -n; &fraig -x; &put; &get -n; &dc4; &dch -f; &nf -D 4; &put', color="cmp"]
    cmp = a < b
  }

  // same label => SAME region as the block above (one mapping unit)
  {::[color="cmp"]
    if a == b {
      cmp = false
    }
  }
}
```

Observing the effect: `lhd pass abc --top mini_alu.mini_alu lg:G --emit-dir
lg:NET --workdir W` logs `region 'mini_alu.mini_alu__c1': color 1 options
override applied (coloring_info)` and `W/qor.json` reports the `__c1` region's
gates/area/delay separately from the color-0 rest. The same knobs can be set
without touching the source via
`--set pass.abc.region_opts='{"1":{"flow":"…","adder":"cla"}}'` (the CLI wins
over the source attribute). The attribute changes no semantics — `lhd lec`
proves the annotated and stripped sources identical.

### Debug attribute list

There are a list of reserved attribute names for debug:

* `debug` and `_debug`: variable use for debug only, not synthesis allowed
* `key`: variable/entry key name
* `rand` and `crand`: simulation and compile time random number generation

### Type attribute list

Visibility is not an attribute: declarations are private by default, and the
`pub` declaration modifier exports them (see
[Visibility](04-variables.md#visibility-private-by-default-pub-to-export)).

* `` `comptime` ``: indicates that the variable should be compile time or a compile error is generated
* `` `const` ``: indicates that only one assignment to the variable can be done per cycle
* `` `mut` ``: multiple assignments to the variable can be done
* `` `type` ``: Either an integer (`Unsigned`/`Signed`) or `String` or `Bool` or `Clock` or `Reset` or `range` or complex tuple.
* `size`: Number of unnamed entries in tuple or array (0 if no unnamed entries)
* `fields`: string list (tuple) with tuple named fields

### Integer Bitwidth attribute list

To set constraints on integer, the compiler has a set of bitwidth related
attributes. Only `max` and `min` exist internally as attributes to control bit
size; `bits` and `sign` are "syntax sugar" translated from `max`/`min`. There
are no `ubits`/`sbits` attributes: use `bits`, and check the sign with
`min >= 0`.

* `max`: the declared maximum value allowed
* `min`: the declared minimum value allowed
* `bits`: read-only; the number of bits needed to represent the declared
  `max`/`min` range (`var.[bits]` in assertions). A typed value reports its
  declared type. An **untyped comptime** integer has no declared range, so
  its `bits` is derived from its value: the minimal width that holds it
  (`13` -> 4, `0` -> 1, a negative value -> its signed width, `-4` -> 3).
  An untyped runtime value reads `nil`.
* `sign`: read-only; 1 when the declared range includes negative values
  (`min < 0`), 0 otherwise, and `nil` when the type pins no min

To size a select or a counter from a comptime count, use the built-in
`std.clog2(x)` (Verilog `$clog2`: `std.clog2(13) == 4`, `std.clog2(16) == 4`,
`std.clog2(17) == 5`, `std.clog2(1) == 0`). It is comptime only; `x <= 0` or a
runtime `x` is a compile error. `std` is a built-in namespace, available
without `import` (see [Standard library](13-stdlib.md)). Note the difference
with `.[bits]`: `N.[bits]` is the width of the value `N`, `std.clog2(N)` the
width of an index into `N` entries (with `comptime const N = 16`,
`N.[bits] == 5` but `std.clog2(N) == 4`).

Separately from the declared range, the bitwidth pass computes the *actual*
range of each variable at each point: `mut x:U8 = 30` has `max == 255` and
`min == 0`, but the actual range is just `30`. The actual range is usually
narrower than the declared one; if it ever exceeds it, that is a compile
error (use `wrap`/`sat` on the assignment to fix it). The actual range is
readable as `bw_max`/`bw_min`, but **only inside debug statements**
(`cassert`/`assert`) — each elaboration may compute a different (legal)
range, so non-debug code must not make decisions based on it (see
[Type system](07-typesystem.md)).

Overflow handling (`wrap`/`sat`) is **not** an attribute. It is a
statement-level prefix on the assignment — see the
[wrap/sat modifier](#wrap-and-sat-modifier) section below.

### Registers and pipestage attribute list

Registers have the following attributes:

* `valid`, `stop`: for elastic pipelines. `stop` is the canonical spelling —
  it is the name in the attribute vocabulary and the `Fflop` cell pin
  (`stop from next cycle`). `fire` is not an attribute: it is sugar for
  `valid and !stop`. (TBD: nothing lowers either name yet.)
* `async`: false by default, `async=true` selects an asynchronous reset
  (sensitive to the edge that asserts it: posedge, or negedge when
  `negreset`). This is the canonical spelling: the Verilog importer's
  inverse `sync=` (`sync=false` means `async=true`) is still accepted, with a
  deprecation warning
* `initial`: reset value, loaded while the reset is asserted
* `clock_pin`: the clock signal (`clock_pin=clk2`): a `Clock` input, a gated
  clock (`Clock(clock_pin=clk, enable=en)`) or a child's `Clock` output, never
  a constant, a `Reset` or data, and written without `ref`; defaults to the
  module's [implicit clock](#implicit-clock-and-reset)
* `reset_pin`: the reset signal (`reset_pin=rst2`, a `Reset` or a `Bool`
  expression); defaults to the module's
  [implicit reset](#implicit-clock-and-reset). `reset_pin=false` means no
  reset (the register must then be initialized with `nil`)
* `negreset`: active-low reset. `false` by default: a reset is active-high
  unless the register sets `negreset=true`. The reset's name carries no
  polarity (`rst_n` is active-high without `negreset=true`)
* `posclk`: true by default, selects a posedge or negnedge flop. On a latch
  the same pin is the enable *polarity*, not a clock edge, and `posclk=false`
  is refused there (see `enable_high`)
* `enable_high`: alias of `posclk`, accepted on any register. On a flop it is
  the clock edge, exactly like `posclk`; on a latch it is the enable polarity.
  `enable_high=false` (an active-low enable) on a latch is refused, because the
  latch lowering derives the hold from the same condition and a bare polarity
  flip would make it write itself instead of capturing the data — write the
  inverted condition instead, `if !g { ... }`
* `latch`: declares a level-sensitive latch instead of a flop
  (`reg l:U8:[latch=true] = 0`). The grammar has no `latch` declaration keyword, so
  the marker is consumed at the declaration and is not readable back as
  `.[latch]`
* `enable`: extra write enable. The register updates only on a cycle where the
  condition holds (on a `latch=true` register: it is transparent only then);
  reset keeps priority over it. It is ANDed with the conditions of the `if`s
  that guard the writes, so `reg q::[enable=(wen!=0)] = 0; q = d` and
  `reg q = 0; if wen!=0 { q = d }` describe the same flop. It names a signal, so
  it needs a value: the flag-only `:[enable]` is an error, and so is
  `enable=false` (a register that can never update)
* `retime`: allow to retime across the register (TBD: not yet implemented —
  the name is accepted but no pass consumes it, so a register carrying it
  warns `reg-attr-not-lowered` and is retimed no differently)

Pipestage accept the same register attributes but also two more:

* `lat`: latency for the pipestage
* `num`: maximum number of units allowed

A register with a non-nil initializer needs a reset input. Whether that
reset is synchronous or asynchronous is **target-dependent**, so it is an
elaboration flag rather than a per-register default: `compile.upass.reset_style`
(`sync` | `async`, default `sync` — FPGA-typical) selects how every
implicit-reset flop wires its reset. A per-register `async` attribute (above)
overrides the flag for that register. `reg foo = nil` declares a register with
**no** reset.

#### Implicit clock and reset

Clocks and resets bind by **type**, not by name. An input declared with the
`Clock` type is a clock and one declared with `Reset` is a reset, whatever
their names (both types are defined in
[Type system](07-typesystem.md#clock-and-reset)). `Clock` and `Reset` are
distinct types (`Clock does Bool` is false). A register without
`clock_pin`/`reset_pin` uses the module's implicit clock and reset:

* Implicit clock: the module's single `Clock` input, whatever its name.
* Implicit reset: the module's single `Reset` input, whatever its name. It is
  active-high unless the register sets `negreset=true`; a name ending in `_n`
  has no meaning.
* Two or more `Clock` inputs leave no implicit clock: every register must name
  its clock with `clock_pin=x`, and one that relies on the implicit clock
  is a compile error. Two or more `Reset` inputs likewise require
  `reset_pin=x`.
* A module with registers and no `Clock` (or `Reset`) input gets one minted:
  `` `clock`:Clock`` (or `` `reset`:Reset``). A module also mints one when an instance
  in it needs its clock (or reset) auto-wired, see below. If a non-`Clock`
  input is already named `clock` (a non-`Reset` input named `reset`), minting
  is a compile error.

There is no name-based binding: an input named `clk`, `clock`, `rst` or
`reset` that is not typed `Clock`/`Reset` (a `Bool`, a `U1`) is plain data.

A `Clock` is not data ([Clock and Reset](07-typesystem.md#clock-and-reset)):
it only drives clock pins, a `Clock_cell` (clock gating), or another `Clock`
port, `U1(clk)` is a compile error, and its simulation cycle count
(`` `clock` < 1000``) is readable only in debug contexts (`test` blocks, `puts`,
`assert`/`cassert`). There are no derived clocks and no clock muxes; use
enables. The one derived `Clock` is a gated one: `Clock(clock_pin=clk,
enable=en)` (named arguments) is a `Clock_cell`, an ICG that latches `en`
while `clk` is low, and its result is a `Clock` usable as a `clock_pin` or a
`Clock` port. The one-argument `Clock(x)` is not a cast.

```pyrope
mod gated(clk:Clock, en:Bool, d:U8) -> (q:U8@[1]) {
  const gclk = Clock(clock_pin=clk, enable=en) // clk gated by en (a Clock_cell)
  reg r::[clock_pin=gclk] = 0                  // loads only on cycles where en is high
  r = d
  q = r
}
```

A `Reset` is Bool-like. It can be computed (`rst or soft_rst`, a
synchronizer), the constant `false` means no reset, and a `Bool` expression
binds to a `Reset` input or to `reset_pin` without a cast.

At a call site, an unbound `Clock` (or `Reset`) input of a `mod`/`pipe` child
(its declared one, or the one minted for it) is auto-wired to the caller's
single `Clock` (or `Reset`), which is minted in the caller if it has none. A
caller with two or more `Clock` (or `Reset`) inputs must bind every child
`Clock` (or `Reset`) input explicitly; leaving one unbound is a compile error.

A `comb` holds no state and can not declare a `Clock` or `Reset` input (a
compile error), so nothing is auto-wired into it. A comb input that the body
never reads may be omitted at a call (nothing is wired), while omitting one
the comb reads is the ordinary missing-argument error.

Binding a constant to a `Clock` is always a compile error: `clock_pin=k` with
a constant `k`, or a call that binds a constant to a `Clock` input, whether
or not a register reads that clock. A register whose clock a constant holds
off through a `Clock_cell` never ticks and is also a compile error. A `Bool`
input is data whatever its name, so binding a constant to it is legal. The
same rule applies to Verilog read by LiveHD: a register or a memory port
whose clock is a constant (`always @(posedge clk)` in a module instantiated
with `.clk(1'b0)`) or is left unconnected (`.clk()`, or the port omitted) is a
compile error naming the register, or the memory. The name means nothing
there either: an unconnected input that clocks no register or memory is plain
data.

```pyrope
mod cnt8(core_clk:Clock, rst_n:Reset, en:Bool) -> (q:U8@[0]) {
  reg cnt:U8:[negreset=true] = 0 // clocked by 'core_clk', reset while 'rst_n' is low
  if en { wrap cnt = cnt + 1 }
  q = cnt
}

mod two_clk(clk_a:Clock, clk_b:Clock, rst:Reset, a:U8, b:U8) -> (qa:U8@[0], qb:U8@[0]) {
  reg ra:U8:[clock_pin=clk_a] = 0   // two Clock inputs: name the clock
  reg rb:U8:[clock_pin=clk_b] = 0   // both reset by the single Reset 'rst'
  reg rc:U8 = 0                     // error: two Clock inputs, no implicit clock
  if a != 0 { ra = a }
  if b != 0 { rb = b }
  qa = ra
  qb = rb
}

comb parity(clk:Bool, a:U8) -> (p:U8) {
  p = a ^ U1(clk)                  // 'clk' is Bool data: the name makes no clock
}

comb gate(c:Clock, a:U8) -> (p:U8) { p = a }  // error: a comb has no Clock input

mod bad_mint(`clock`:U1, d:U8) -> (q:U8@[0]) {
  reg r:U8 = 0      // error: minting 'clock:Clock' clashes with the U1 input 'clock'
  r = d
  q = r
}

mod top(clk:Clock, rst:Reset, soft_rst:Bool, en:Bool) -> (q:U8@[0], q2:U8@[0], p:U8@[0]) {
  const c = cnt8(en=en)                          // OK, 'core_clk'/'rst_n' wired to 'clk'/'rst'
  const d = cnt8(rst_n=rst or soft_rst, en=en)   // OK, a computed reset; 'core_clk' auto-wired
  const e = cnt8(core_clk=true, en=en)           // error: a Clock is never bound to a constant
  const f = U1(clk)                              // error: a Clock is not data
  p  = parity(clk=true, a=c.q)                   // OK, a constant into a data input
  q  = c.q
  q2 = d.q
}
```

### Memories attribute list

Memories are arrays with persistence like registers. As such, some of the attributes
are similar to registers, but unlike registers they can have multiple clocks.

* `addr`: Tuple of address ports for the memory.
* `bits`: The number of bits for each memory entry
* `size`: The number of entries. Total size in bits is $size x bits$.
* `clock_pin`: Optional clock pin (`clock_pin=clk2`), the module's
  [implicit clock](#implicit-clock-and-reset) by default. Like a register's,
  it names a `Clock` (never a constant, a `Reset` or data). A tuple is possible
  to specify the clock for each address port.
* `din`: Tuple for memory data in port. The read ports must be hardwired to `0`.
* `enable`: Tuple for each memory port. Write or read enable (read ports can have enable too).
* `ordering`: Same-cycle read/write ordering. `"program"` (default): accesses
  resolve in program order — a read before a write sees the old value, a read
  after it the new value, the last write to an address wins. `"fwd"`:
  position-blind forwarding — every read of an address written this cycle
  returns the new data; multi-writer collisions are undefined. `"old"`: every
  same-cycle read of an address written this cycle returns the OLD value,
  whatever the program order. `"none"`: no
  guarantee — a same-cycle read of a written address is undefined (random in
  simulation, `?` in formal). See
  [Same-cycle ordering](08-memories.md#same-cycle-ordering). Replaces the
  deprecated `fwd=true|false` attribute. At the cell level it lowers to the
  `fwd` per-(read-port, write-port) bit matrix (bit `r*n_wr + w` forwards
  write port `w` to read port `r`), which the RTL `__memory` vocabulary still
  exposes verbatim as the low-level escape hatch.
* `` `type` ``: Memory type: `0` async (combinational read of the current address), `1` sync (one-cycle read), `2` array (unclocked)
* `wensize`: Write enable size allows to have a write mask. The default value
  is 1, a wensize of 2 means that there are 2 bits in the `enable` for each
  port. a wensize 2 with 2 ports has a total of 2+2+2 enable bits. Bit 0 of the
  enable controls the lower bits of the memory entry selected.
* `rdport`: Indicates which of the ports are read and which are written ports.
* `posclk`: Positive edge clock memory for all the memory clocks. The default is `true` but it can be set to `false`.
* `initial`: comptime initial contents (a tuple literal or a packed constant,
  entry 0 in the low `bits`). A `reg` array's initializer (`= 0`, `= (1,2,3)`)
  is its reset value AND lands on this same pin, so `initial=` next to an
  initializer must spell the same packed value (a compile error otherwise);
  next to `= nil` it is power-on-only contents and no reset is wired
  (see [Memories](08-memories.md))
* `reset_pin`, `negreset`, `async`: as on a register — the reset that restores
  the initializer to every entry in one cycle

### Lambda attribute list

Lambda attributes allow [Introspection](07-typesystem.md#introspection) which requires some attributes.

* `inp`: returns the input port-name tuple from the lambda
* `out`: returns the output port-name tuple from the lambda
* `lg`: pins the name of the generated lgraph (and hence the netlist/Verilog
  module name). Only allowed on `pub` lambdas. See
  [lg: explicit lgraph name](#lg-explicit-lgraph-name).
* `timecheck`: `true` (default) runs the timing checks; `timecheck=false`
  turns them off for that lambda. See
  [timecheck: timing-check escape hatch](#timecheck-timing-check-escape-hatch).

#### timecheck: timing-check escape hatch

`::[timecheck=false]` (old spelling `::[hdl]`) turns off **all** timing
checks in that lambda:

* the landing-cycle checks (`@[N]` on outputs and statements);
* the cycle-mix checks, including the ones through a child's declared output
  latencies;
* the same-cycle ring through a `wire` (combinational-loop) check.

Inside such a lambda every plain `reg` is cycle-0 state (a Verilog-style
flop, never a pipeline stage), and an undriven `wire` reads `x` instead of
being a compile error. The Verilog importer and the Pyrope writer set it on
every unit they produce. Hand-written code should use it only as an escape
hatch. Any value other than `true`/`false` is a compile error.

```pyrope
pub mod legacy::[timecheck=false](clk:Clock, d:U4) -> (q:U4@[0]) {
  reg r:U4 = 0
  r = d
  q = r         // OK here: 'r' is cycle-0 state, no landing-cycle check
}
```

Without `timecheck=false`, a plain body `reg` that drives a `mod` output
follows the rule of a `reg` in the output list (see
[Cycle rules for `mod` outputs](06-functions.md#cycle-rules-for-mod-outputs)):
a conditional or feedback write (a hold path: `if en { r = d }`,
`r = r + 1`) makes it state, landing at its home stage, and a register
written every cycle from its inputs lands one cycle after them. The rule is
uniform: the implicit clock and an explicit `clock_pin`/`reset_pin` alike
(the `Clock`/`Reset` signals themselves carry no cycle), a whole write and
bit-slice writes (`r#[0..<4] = d`) alike, and a read of the whole register or
of a bit slice alike, so `reg r:U4 = 0; r = d; q = r` needs `q:U4@[1]`. (A body
register read only through other logic, `q = r ^ 1`, is still cycle-0 state
today, see [Implementation status](15-tbd.md).)

#### lg: explicit lgraph name

By default, the lgraph generated for a lambda gets a compiler-mangled name
derived from the file and the declaration name. The `lg` attribute replaces
that with an explicit name — useful to fix the top-level module name or to
link against an external netlist that expects a specific module:

```pyrope
pub comb my_log::[lg="foo_mod"](a, b) -> (r) { r = a + b }
```

`lg` renames only the generated artifact, not the language-level name
(like Rust's `#[export_name]` pins a linker symbol): other files still
write `import("file.my_log")`. Rules:

* The value must be a comptime string. It may be any string accepted as an
  lgraph name, including characters that are not legal Pyrope identifiers.
* Only allowed on `pub` declarations of lambda kinds that generate an
  lgraph (`comb`, `pipe`, `mod`, `fluid`). `lg` on a private declaration
  or on a non-lambda (`const`, `reg`) is a compile error.
* Non-sticky: it names this declaration only, and does not propagate
  through assignments or aliases.
* An explicit name escapes the file-based namespacing, so two lgraphs
  resolving to the same `lg` name anywhere in the project is a compile
  error.

Unlike the [synthesis hints](#synthesis-attribute-list), `lg` is not
ignorable: every compiler flow must honor it (like bitwidth, `comptime`,
and `debug`), since other flows may link against the pinned name.


## Debug and verification attribute list

There are no edge attributes. Attributes are elaboration-time reads, but an
edge is a per-cycle runtime value, so edges are **functions**, not attributes:
`rose(sig)`, `fell(sig)`, `changed(sig)`, `stable(sig)` from the
[temporal library](09-verification.md#temporal-library) (all TBD).

`sig.[rising]`, `sig.[falling]`, `sig.[changed]` and `sig.[stable]` are not
recognized and produce the ordinary unknown-attribute error.

To wait for an edge in a test, drop the read into the wait idiom: `tick N { step;
if not rose(sig) { continue }; break }` (the `N` bound is the timeout).

See [Verification](09-verification.md) for the full temporal library and
debug constructs.


Integer type constructors set the constrained bounds. The `max`, `min`, and
`bits` attributes can be read but not written; a read returns the **declared**
constraint. The exception is `bits` of an untyped comptime integer, which is
the width of its value; an untyped runtime value reads `nil`. The actual range
computed by the bitwidth pass is readable as `bw_max`/`bw_min`, but only
inside debug statements (see [Type system](07-typesystem.md)).

```pyrope
mut opt1:Unsigned(max=300) = 0
mut opt2:Signed(min=0,max=300) = 0  // same

cassert(opt1.[max] == 300 and opt1.[min] == 0)
cassert(opt1.[bits] == 9)     // 9 bits to represent 0..300
opt1 = 200
cassert(opt1.[bits] == 9)     // still the declared type, not the value
cassert(opt1.[bw_max] == 200) // actual range: debug-only read

comptime const N = 13         // untyped comptime
cassert(N.[bits] == 4)        // width of the value 13
cassert(std.clog2(N) == 4)    // index width for 13 entries
```

## wrap and sat modifier

`wrap` and `sat` control how the right-hand side of an assignment narrows
into the left-hand side when the value would otherwise overflow. They are
**statement-level prefix modifiers** (similar to `comptime` or `debug`),
applied to each individual assignment — *not* attributes.

**The overflow rule.** When the destination has a declared type, the
bitwidth pass compares the range of the right-hand side (the `max`/`min` it
may take) with the destination's declared range. If the right-hand side may
fall outside that range, above the `max` or below the `min`, the assignment
is a compile error unless it carries `wrap` or `sat`. The error is mandatory,
and the rule is the same for every typed destination: a local (`mut`,
`const`, `wire`), a `reg`, a tuple field, a `comb`/`pipe`/`mod` output, and
an argument bound to a typed input (see below). It covers comptime values,
checked by value, and runtime values, checked on their computed range: a
`reg cnt:U8` may hold any value in `0..=255`, so `cnt + 1` may reach 256 and
`cnt += 1` is an error, while `wrap cnt += 1` is the counter idiom. A
compound assignment is checked like its expansion (`cnt += 1` is
`cnt = cnt + 1`). An untyped destination takes the range of its value, so it
never overflows. The rule makes the choice visible at every line that may
overflow.

A call's result is judged the same way. A typed output bounds what it
returns. An untyped output of a fully typed `mod`/`pipe` has one module, so it
carries the range its body derives, and the port is that wide:
`mod cnt(a:U4) -> (o@[0]) { o = a + 1 }` returns `[1, 16]`, so
`y:U8 = cnt(a=x)` is legal and `y:U4 = cnt(a=x)` is an error. The untyped
output of a template (a lambda with an untyped input or generics) is
specialized per call and promises no range: storing it into a typed
destination needs `wrap`/`sat`, or a typed output.

```pyrope
mut a:U32 = 100
mut b:U10 = 0
mut c:U5  = 0
mut d:U5  = 0

b = a               // OK, no precision lost
wrap c = a          // OK, same as c = a#[0..<5] (since 100 is 0ub1100100, c==4)
c = a               // error: 100 overflows the maximum value of 'c'

sat c = a           // OK, c == 31
c = 31
d = c + 1           // error: '32' overflows the maximum value of 'd'

wrap d = c + 1      // OK, d == 0
sat  d = c + 1      // OK, d == 31
sat  d += 1         // OK, compound assignment

sat const x:Bool = c // error: saturate only allowed in integers

reg cnt:U8 = 0
cnt += 1            // error: 'cnt' may be 255, so 'cnt + 1' may reach 256
wrap cnt += 1       // OK, 255 rolls over to 0
mut e:U8 = cnt
e = e - 1           // error: 'e' may be 0, so 'e - 1' may reach -1

comb add8(a:U8, b:U8) -> (s:U8) {
  s = a + b         // error: 'a + b' may reach 510, output 's' is U8
}
comb add8w(a:U8, b:U8) -> (s:U8) { wrap s = a + b } // OK, modulo 256
comb add9(a:U8, b:U8) -> (s:U9) { s = a + b }       // OK, 510 fits U9
```

The prefix is part of the assignment statement; it controls the narrowing
of the final RHS into the LHS. To narrow individual sub-expressions
independently, factor them into intermediate variables with their own
`wrap`/`sat` assignment.

The left-hand side can be a tuple field. The narrowing is against the
**field's** declared range, exactly as for a scalar variable:

```pyrope
reg decoded:(imm:U4, valid:Bool) = nil

wrap decoded.imm = a  // OK, same as decoded.imm = a#[0..<4] ('imm' is U4)
sat  decoded.imm = a  // OK, clamps at 15, the maximum of 'imm'
```

The prefix attaches to a plain name or to a dotted field. An entry picked
with an index cannot carry it (`wrap t[i] = a`, `wrap t[i].imm = a`):
narrow into an intermediate variable with its own `wrap`/`sat` assignment,
then store that variable into the entry.

Argument binding follows the same overflow rule as an assignment, for `comb`
and `mod`, generic or not: an argument whose range may not fit the
parameter's declared range (a `U16` into `a:U4`, or into `a:Unsigned(bits=N)`
with `N=4`) is a compile error, and an integer into a `Bool` parameter needs
an explicit `Bool(x)`. The caller narrows explicitly:

```pyrope
comb f(a:U4) -> (r:U4) { r = a }

const x:U16 = 100
const y = f(a=x)           // error: 100 overflows 'a' (U4)
const z = f(a=x#[0..<4])   // OK, explicit slice
```

## comptime modifier

Pyrope borrows the `comptime` functionality from Zig. `comptime` is a prefix
modifier that can be applied to `const` or `mut` to indicate that the variable
must be resolvable at compile/elaboration time. `comptime` alone is shorthand
for `comptime const`.

```pyrope
comptime const SIZE = 16
comptime const a = 1        // same as above
comptime mut counter = 0    // mutable at compile time (updated during elaboration)
comptime const b = a + 2    // OK, comptime const
comptime c = rand           // error: 'c' is not resolvable at compile time

cassert(SIZE == 16)
cassert(b == 3)
```

The ``.[`comptime`]`` query checks whether the current value is known at compile
time. It does not check whether the declaration used the `comptime` modifier:

```pyrope
cassert(a.[`comptime`])
const k = 2
cassert(k.[`comptime`]) // current value is known, even without the modifier
```

Casing carries no `comptime` meaning. Write the `comptime` modifier explicitly
to require compile-time evaluation; a value can be known at compile time
without that requirement on its declaration.

```pyrope
comptime const Xconst1 = 1    // comptime because of the keyword, not the casing
comptime const Xvar2 = rand   // error: 'Xvar2' is not compile time constant
```

## debug attribute

In software and more commonly in hardware, it is common to have extra
statements and state to debug the code. These debug functionality can be more
than plain assertions, they can also include code.


The `debug` attribute marks a mutable or immutable variable. At synthesis, all
the statements that use a `debug` can be removed. `debug` variables can read
from non debug variables, but non-debug variables can not read from `debug`.
This guarantees that `debug` variables, or statements, do not have any
side-effects beyond debug statements.

```pyrope
mut a = (const b::[debug]=2, const c = 3) // a.b is a debug variable
const c::[debug] = 3
```

Assignments to debug variables also bypass protection access. This means that
private tuple fields (leading underscore, like `_priv`) can be accessed
(read-only). Since `assert` marks all the results as debug, it allows to read
any variable/field regardless of `pub` or `_` privacy.


```pyrope
const x = (const _priv=3, const zz=4)

const tmp = x._priv          // error: '_priv' is private to the tuple
const tmp::[debug] = x._priv // OK, debug bypasses privacy (read-only)

assert(x._priv == 3) // OK, assert is a debug statement
```
