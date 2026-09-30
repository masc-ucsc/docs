# LNAST

This chapter shows current Pyrope-to-LNAST translation using small programs
compiled with `lhd`. Each Pyrope block is a standalone input; its first comment
names the file to save. The excerpts below come from actual dumps, not proposed
optimizations. They were checked against the local LiveHD checkout on
2026-09-30.

LNAST is an intermediate representation. Its node shapes, temporary names and
rewrites can change without changing Pyrope semantics. See the language chapters
for the source-language rules.

## Reproducing the dumps

Set `LHD` to the LiveHD binary you want to inspect, save a Pyrope example, and
run it in a fresh work directory:

```bash
LHD=/path/to/livehd/bazel-bin/lhd/lhd
"$LHD" compile values.prp \
  --dump parse,lnast \
  --emit-dir lnast-dump:values-dump \
  --workdir values-work \
  > values.result.json 2> values.trace.txt
```

`--dump parse` prints the LNAST immediately after the front end; despite the
name, this is LNAST, not the parser's concrete syntax tree. `--dump lnast`
prints the post-upass tree. Both go to stderr with stage labels. The
`lnast-dump:` directory contains post-upass textual `.lnast` files; `ln:` is
the binary interchange form. Check the command's exit status and diagnostics:
a parse dump alone does not establish that elaboration succeeded.

An invocation requesting only LNAST outputs need not lower to hardware. To
check graph lowering too, add `--emit-dir lg:values-lg`, or use ordinary
`lhd compile` without the LNAST-only output selection. The runtime examples
below were also checked with an `lg:` output.

For readability, excerpts omit tree-drawing glyphs, source-span annotations,
the dump's outer display quotes, and enclosing `top`/`stmts` containers.
Indentation still shows parent/child relationships. Each excerpt states its
stage; any additional omissions are stated locally. `const` with no payload
is printed that way by the dumper; it is not a missing line in the example.

## Variable names

The front end uses user names and generated references such as `%x_0`. Later
passes can introduce inlining prefixes and SSA suffixes such as
`work___ssa_1`. The spelling of generated names is not a user-facing contract;
LNAST is not guaranteed to keep every user assignment under one unchanged name.
Backticked source identifiers remain distinguishable in the dump.

The following program checks declarations, updates, and a backticked name:

```pyrope
// values.prp
const x = 3 + 1
mut z:U8 = 4
z = z + 2
const `foo x` = x + z
cassert(`foo x` == 10)
```

**post-parse excerpt.**

```lnast
plus
  ref %x_0
  const 3
  const 1
declare
  ref x
  prim_type_none
  const
store
  ref x
  ref %x_0
declare
  ref z
  prim_type_int
    const 0xff
    const 0
  const mut
store
  ref z
  const 4
plus
  ref %z_0
  ref z
  const 2
store
  ref z
  ref %z_0
```

`declare` records the name, type, and qualifier. In this post-parse dump the
immutable qualifier has an empty `const` payload, while the mutable qualifier
is `const mut`. Initialization is a separate `store`. `prim_type_int` stores
maximum then minimum, so `U8` is represented by `0xff` and `0`.

The final `cassert` succeeds. Constant propagation removes the arithmetic and
known assertion; the remaining post-upass statements are:

**post-upass excerpt.**

```lnast
declare
  ref x
  prim_type_none
  const
declare
  ref z
  prim_type_int
    const 0xff
    const 0
  const mut
declare
  ref `foo x`
  prim_type_none
  const
store
  ref z
  const 6
```

This illustrates why a post-upass dump is not a transcript of all source
operations: known values can live in the compiler's value tables, and folded
expressions need not remain as statements.

### Registers

Registers carry a different declaration qualifier and retain their reset
value. This small module also shows a typed output and wrapping update:

```pyrope
// register.prp
mod counter(enable:Bool) -> (reg count:U4@[0] = 0) {
  if enable { wrap count += 1 }
}
```

**post-upass excerpt — body of register.counter; io omitted.**

```lnast
declare
  ref count
  prim_type_int
    const 15
    const 0
  const reg
  const 0
if
  ref enable
  stmts
    plus
      ref %count_0
      ref count
      const 1
    get_mask
      ref %count_1
      ref %count_0
      const 15
    store
      ref count
      ref %count_1
```

Here the declaration includes `const reg` and reset value `0`. The `wrap`
update has become arithmetic followed by a mask of `15` before the store.
A dump of the whole unit also includes `io` metadata; this is separate from
the body statements.

## Tuples

A tuple is all named or all positional. In the parsed tree, named entries
are `store` children of `tuple_add`; positional entries are value children.
`tuple_get` reads fields or positions, and a field write is a `store` with a
field path between the base and the new value.

```pyrope
// tuples.prp
mut pair = (mut left:U4=2, const right:U4=3)
pair.left = 4
const selected = pair.left
const positional = (1, 2)
const joined = (...positional, 3)
const nested = (const inner=(const value=7))
cassert(selected == 4)
cassert(joined == (1, 2, 3))
cassert(nested.inner.value == 7)
```

**post-parse excerpt.**

```lnast
tuple_add
  ref %pair_0
  store
    ref left
    const 2
  store
    ref right
    const 3
tuple_get
  ref %pair_1
  ref %pair_0
  const left
declare
  ref %pair_1
  prim_type_none
  const mut
type_spec
  ref %pair_1
  prim_type_int
    const 15
    const 0
tuple_get
  ref %pair_2
  ref %pair_0
  const right
type_spec
  ref %pair_2
  prim_type_int
    const 15
    const 0
declare
  ref pair
  prim_type_none
  const mut
store
  ref pair
  ref %pair_0
store
  ref pair
  const left
  const 4
```

The `mut left` field is represented by a field reference followed by its
mutable declaration; its width and the immutable `right` field's width are
recorded by `type_spec`. The outer binding's `declare` and `store` follow
construction of the tuple.

The same input gives these read, splice, and nested-read nodes (intervening
bindings and assertions omitted):

**post-parse excerpt.**

```lnast
tuple_get
  ref %selected_0
  ref pair
  const left
fcall
  ref %joined_0
  ref __fkind__tuple_spread
  ref positional
tuple_concat
  ref %joined_2
  ref %joined_0
  ref %joined_1
tuple_get
  ref %167467691_0
  ref nested
  const inner
  const value
```

The splice is initially marked by a call to `__fkind__tuple_spread`, then
combined with the following positional entry by `tuple_concat`. After
elaboration the marker can become a plain copy. A nested field path can be
carried by one `tuple_get`; nested tuple construction itself uses intermediate
`tuple_add` results. The compiler may flatten field paths in later dumps.

Named-field merge and positional append rules are described in
[Tuples](03-bundle.md). They are not additional `in`/`cassert` statements
inserted after every splice.

## Attributes

Attribute syntax produces separate `attr_set` and `attr_get` statements,
not children attached to a `ref`. For `attr_set`, the base comes first and
the value last, with the attribute path between them. For `attr_get`, the
destination precedes the base and path.

Attributes are compile-time metadata. The unfinished fluid design uses
`valid` and `retry` for runtime handshake signals and derives `fire` from
them; see [Attributes](04b-attributes.md) and [Fluid](06d-fluid.md).

```pyrope
// attributes.prp
const a::[tag=3, marked] = 1
const tag = a.[tag]
const k = 2
cassert(tag == 3)
cassert(a.[marked])
cassert(k.[`comptime`])
const d::[debug] = 3
const result = d + 100
cassert(result.[debug])
```

**post-parse excerpt.**

```lnast
declare
  ref a
  prim_type_none
  const
attr_set
  ref a
  const tag
  const 3
attr_set
  ref a
  const marked
  const true
store
  ref a
  const 1
attr_get
  ref %tag_0
  ref a
  const tag
```

An attribute with no explicit value is set to `true`. ``k.[`comptime`]`` tests
whether the current value is known at compile time, not whether `k` was
declared with the `comptime` modifier.

The `debug` propagation assertion in this program also passes. Attribute
propagation is attribute-specific: do not generalize it into a claim that
all attributes are sticky, or that arithmetic removes every attribute.

### Sticky attributes

This separate test checks a user attribute copied directly, then removed by
arithmetic and bit selection. It complements the sticky `debug` test above:

```pyrope
// attribute_copy.prp
const a::[tag=3] = 4
const copy = a
const arithmetic = a + 0
const bits = a#[..]
cassert(copy.[tag] == 3)
cassert(arithmetic.[tag] == nil)
cassert(bits.[tag] == nil)
```

All three assertions pass. These are examples of current propagation
behavior; the attribute's own rules determine whether it survives a
particular operation.

## Bit selection

The following runtime function preserves the selected values in the
post-upass tree. Its assertions independently check the sum and the patched
word for a concrete input:

```pyrope
// bits.prp
comb bits(foo:U8, xx:U4) -> (yy:U4, patched:U8) {
  mut work:U8 = foo
  work#[1..=2] = xx#[0..<2]
  yy = foo#[5] + xx#[1..<4]
  patched = work
}
cassert(bits(foo=32, xx=10).yy == 6)
cassert(bits(foo=32, xx=10).patched == 36)
```

**post-upass excerpt — body of bits.bits; io and type_spec nodes omitted.**

```lnast
declare
  ref work
  prim_type_int
    const 0xff
    const 0
  const mut
store
  ref work
  ref foo
get_mask
  ref %work_0
  ref xx
  const 3
set_mask
  ref %work_1
  ref work
  const 6
  ref %work_0
store
  ref work___ssa_1
  ref %work_1
get_mask
  ref %yy_0
  ref foo
  const 32
get_mask
  ref %yy_1
  ref xx
  const 14
plus
  ref %yy_2
  ref %yy_0
  ref %yy_1
store
  ref yy
  ref %yy_2
store
  ref patched
  ref work___ssa_1
```

The mask operand in these LNAST nodes is a bit mask, not a bit index:

| Source selection | Mask in this dump |
|---|---|
| `xx#[0..<2]` | `3` (`0ub11`) |
| `work#[1..=2]` | `6` (`0ub110`) |
| `foo#[5]` | `32` (`0ub100000`) |
| `xx#[1..<4]` | `14` (`0ub1110`) |

`get_mask(dst, value, mask)` extracts and right-justifies the selected bits.
`set_mask(dst, old_value, mask, replacement)` creates the patched value;
the following `store` binds it. In this dump SSA renames the updated `work`
to `work___ssa_1`.

The `plus` consumes `%yy_0` and `%yy_1`, the two extracted values. It does
not add a range object or the mask itself. A single-bit read at index 5
therefore cannot be rewritten as `get_mask(..., 5)`.

This LNAST representation should not be confused with a lower-level helper's
API: a helper can receive interval bounds even when the LNAST node carries
a mask. Pyrope selectors accept an index or a range; a list of disjoint
indices is not an alternate bit-order notation.

### Sign extension and reductions

These operations first select the requested bit vector:

```pyrope
// reductions.prp
comb reductions(v:U8) -> (s:S5, any:U1, all:U1, parity:U1, count:U3) {
  s = v#sext[..=4]
  any = v#|[..=4]
  all = v#&[..=4]
  parity = v#^[..=4]
  count = v#+[..=4]
}
cassert(reductions(31).s == -1)
cassert(reductions(31).all == 1)
cassert(reductions(31).count == 5)
```

**post-upass excerpt — signed selection; type_spec omitted.**

```lnast
get_mask
  ref %s_1
  ref v
  const 31
sext
  ref %s_4
  ref %s_1
  const 4
store
  ref s
  ref %s_4
```

The selected five-bit vector uses mask `31`. `sext` takes the sign-bit
position in that selected vector, here `4`. The other outputs use the
following nodes after their own `get_mask`:

| Pyrope | LNAST operation |
|---|---|
| `v#\|[..=4]` | `red_or` |
| `v#&[..=4]` | `red_and` |
| `v#^[..=4]` | `red_xor` |
| `v#+[..=4]` | `popcount` |

The dump contains separate selections for these outputs; it does not promise
that the front end has already shared one selection among all five.

## Direct LNAST/Lgraph call

Cell calls such as `__sum` are normal Pyrope calls with the cell's pin names
as arguments. They appear as `fcall` before folding or lowering. See the
[call example below](#lambda-call) for the actual argument layout.

The old `LNAST(a=("let", ...))` injection example is not supported by the
current front end. A direct compile reports `undefined-call` for `LNAST`;
it does not inject a `let` node. To inspect compiler IR, use the dump commands
above.

## Basic operators

This program exercises the arithmetic, bitwise, comparison, and Boolean
operators before they fold:

```pyrope
// operators.prp
const a = 12
const b = 3
const sum = a + b
const difference = a - b
const product = a * b
const quotient = a / b
const remainder = a % b
const band = a & b
const bor = a | b
const bxor = a ^ b
const left = a << 1
const right = a >> 1
const neg = -b
const inv = ~a
const p = true
const q = false
const both = p and q
const either = p or q
const implication = p implies q
const not_implication = not (p implies q)
const nand = ~(a & b)
const eq = a == b
const ne = a != b
const lt = a < b
const le = a <= b
const gt = a > b
const ge = a >= b
cassert(sum == 15 and difference == 9 and product == 36)
cassert(quotient == 4 and remainder == 0)
cassert(left == 24 and right == 6 and neg == -3 and inv == -13)
cassert(not both and either and not implication and not_implication)
```

The post-parse nodes use a destination followed by their operands:

| Pyrope expression | Node or node sequence |
|---|---|
| `a + b`, `a - b`, `a * b`, `a / b`, `a % b` | `plus`, `minus`, `mult`, `div`, `mod` |
| `a & b`, `a \| b`, `a ^ b` | `bit_and`, `bit_or`, `bit_xor` |
| `a << b`, `a >> b` | `shl`, `sra` |
| `-a` | `minus` with operands `0`, `a` |
| `~a` | `bit_not` |
| `a == b`, `a != b` | `eq`, `ne` |
| `a < b`, `a <= b`, `a > b`, `a >= b` | `lt`, `le`, `gt`, `ge` |
| `p and q`, `p or q`, `not p` | `log_and`, `log_or`, `log_not` |

These are translation shapes, not a guarantee that every operand/type
combination lowers to hardware. In particular, hardware modulo has the
restrictions described in [Basic syntax](02-basics.md).

### Unary

Elaboration can add type-dependent operands. An unsigned four-bit complement
has an explicit flip width in its post-upass `bit_not`:

```pyrope
// bit_not.prp
comb invert(a:U4) -> (y:U4) { y = ~a }
cassert(invert(3) == 12)
```

**post-upass excerpt — body of bit_not.invert.**

```lnast
bit_not
  ref %y_0
  ref a
  const 4
store
  ref y
  ref %y_0
```

## Complex operators

Logical implication is emitted as `log_not` followed by `log_or`.
Negating an implication adds a further `log_not`; the post-parse tree does
not substitute the hand-simplified expression `p and not q`. These are the
nodes from the operator test, with the intervening result bindings omitted:

**post-parse excerpt.**

```lnast
log_not
  ref %implication_0
  ref p
log_or
  ref %implication_1
  ref %implication_0
  ref q
log_not
  ref %not_implication_0
  ref p
log_or
  ref %not_implication_1
  ref %not_implication_0
  ref q
log_not
  ref %not_implication_2
  ref %not_implication_1
```

Similarly, `~(a & b)` produces `bit_and` followed by `bit_not`; the
corresponding negated OR and XOR use their own bitwise nodes. Later passes
may fold or rewrite these expressions.

### Tuple/Set operators

Membership produces an `in` node. The operand types determine its meaning;
a tuple/range membership test is not universally interchangeable with a
bitwise AND. Tuple splicing uses the spread marker and `tuple_concat`
shown in [Tuples](#tuples).

### Range operator

Ranges use inclusive endpoints in LNAST. The front end subtracts one from
an exclusive end, or computes `start + count - 1` for a counted range.
An explicit positive `step` is a separate call rather than a fourth child
of the `range` node. Ranges compare directly with unnamed tuples:

```pyrope
// ranges.prp
const r = 1..=3
const exclusive = 1..<4
const counted = 1..+3
const stepped = 0..=6 step 2
const joined = (...r, 4)
cassert(r == (1, 2, 3))
cassert(r == exclusive and r == counted)
cassert(stepped == (0, 2, 4, 6))
cassert(2 in r)
cassert(joined == (1, 2, 3, 4))
```

**post-parse excerpt.**

```lnast
range
  ref %r_0
  const 1
  const 3
minus
  ref %exclusive_0
  const 4
  const 1
range
  ref %exclusive_1
  const 1
  ref %exclusive_0
plus
  ref %counted_0
  const 1
  const 3
minus
  ref %counted_1
  ref %counted_0
  const 1
range
  ref %counted_2
  const 1
  ref %counted_1
range
  ref %stepped_0
  const 0
  const 6
fcall
  ref %stepped_1
  const step
  ref %stepped_0
  const 2
```

The assertions confirm `(1, 2, 3)` for all three unstepped spellings and
`(0, 2, 4, 6)` for the stepped one. The old `a..<=b by 2` and `a to b`
spellings are not current syntax.

### Type operators

Structural operations have dedicated nodes. In particular, the front end
emits `equals` and `case` directly; it does not expand them into the
`does`/`in`/`log_and` diagrams from older versions of this chapter.

```pyrope
// types.prp
const a = (const x=1, const y=2)
const b = (const x=1)
const has_x = a has 'x'
const covers = a does b
const same_type = a equals a
const matches = a case a
cassert(has_x and covers and same_type and matches)
```

**post-parse excerpt.**

```lnast
has
  ref %has_x_0
  ref a
  const 'x'
does
  ref %covers_0
  ref a
  ref b
equals
  ref %same_type_0
  ref a
  ref a
case
  ref %matches_0
  ref a
  ref a
```

`has` tests field existence, `does` checks structural coverage, `equals`
checks type equivalence, and `case` performs the structural/value match.
Their language rules are in [Type system](07-typesystem.md); the dedicated
node names do not make them ordinary integer comparison operations.

## if/unique if

Branch nodes contain condition/body pairs, followed by an optional final
`stmts` for `else`. An ordinary chain uses `if`; a unique chain uses `uif`.
This runtime example keeps all three forms visible after elaboration:

```pyrope
// control.prp
comb choose(a:U4) -> (priority:U5, parallel:U5, matched:U5) {
  priority = 0
  if a < 3 { priority = a + 1 }
  elif a > 12 { priority = 20 }
  parallel = 0
  unique if a == 1 { parallel = 10 }
  elif a == 2 { parallel = 20 }
  matched = match a {
    == 1 { 10 }
    == 2 { 20 }
    else { 0 }
  }
}
cassert(choose(1).priority == 2)
cassert(choose(2).parallel == 20)
cassert(choose(3).matched == 0)
```

**post-upass excerpt — priority and unique chains from control.choose; io omitted.**

```lnast
store
  ref priority
  const 0
gt
  ref %2188985937_0
  ref a
  const 12
lt
  ref %3010617009_0
  ref a
  const 3
if
  ref %3010617009_0
  stmts
    plus
      ref %priority_0
      ref a
      const 1
    store
      ref priority
      ref %priority_0
  ref %2188985937_0
  stmts
    store
      ref priority
      const 20
store
  ref parallel
  const 0
eq
  ref %3385895541_0
  ref a
  const 2
eq
  ref %3375548154_0
  ref a
  const 1
uif
  ref %3375548154_0
  stmts
    store
      ref parallel
      const 10
  ref %3385895541_0
  stmts
    store
      ref parallel
      const 20
```

The printed order of pure condition calculations can differ from source
order; the condition/body order within `if` determines priority. `uif`
records the unique-branch construct. This dump does not contain a synthetic
`shl`/`popcount`/`assume` sequence before it. Do not treat that old explanatory
sequence as emitted LNAST.

## match

The `match` in the same program also becomes `uif`. An expression-valued
match writes a common temporary in each arm and then assigns the result:

**post-upass excerpt — match from control.choose.**

```lnast
eq
  ref %matched_2
  ref a
  const 2
eq
  ref %matched_1
  ref a
  const 1
uif
  ref %matched_1
  stmts
    store
      ref %matched_0
      const 10
  ref %matched_2
  stmts
    store
      ref %matched_0
      const 20
  stmts
    store
      ref %matched_0
      const 0
store
  ref matched
  ref %matched_0
```

The explicit `else { 0 }` is preserved as the final `stmts` arm. The
compiler does not replace an explicit catch-all with `assert(false)`.
Exhaustiveness and uniqueness rules belong to the source construct; see
[match](05b-statements.md#unique-parallel-conditional-match).

## Scope

An initializer is evaluated before its condition. Its declarations are visible
from their declaration through the remaining `if`/`elif`/`else` chain, `match`,
or `while`, and are out of scope after that construct. Reading or assigning them
afterward is a compile error.
Lowering an `elif` initializer before the arm bodies does not make its variables
visible to an earlier arm: reading one there is a read-before-declaration error.
See [Variable scope](04-variables.md#variable-scope) for the language rules.

```pyrope
// scope.prp
mut total = 0
if const limit=3; limit > 2 {
  total = limit
}
cassert(total == 3)
```

**post-parse excerpt.**

```lnast
if
  const true
  stmts
    declare
      ref limit
      prim_type_none
      const
    store
      ref limit
      const 3
    gt
      ref %2940350924_0
      ref limit
      const 2
    if
      ref %2940350924_0
      stmts
        store
          ref total
          ref limit
```

The outer `if true` creates the initializer scope. It uses the normal branch
merge to preserve writes to enclosing variables such as `total`; elaboration
folds away this always-taken condition. The assertion checks `total == 3`.
Adding `cassert(limit == 3)` after the `if` is an undefined-variable error,
even though the initializer and branch condition are known at compile time.

## while/loop/for

LNAST has both `while` and `for` nodes. It is not limited to `while`, and
elaboration does not always expand every hardware loop into repeated source
statements. The following comptime examples do expand and fold:

```pyrope
// loops.prp
mut i = 0
loop {
  i += 1
  if i == 3 { break }
}
cassert(i == 3)
mut sum = 0
while mut j=0; j < 3 {
  sum += j
  j += 1
}
cassert(sum == 3)
mut enumerated = 0
for (index, value) in (2, 4, 6) {
  enumerated += index + value
}
cassert(enumerated == 15)
mut stepped_sum = 0
for value in 0..=6 step 2 { stepped_sum += value }
cassert(stepped_sum == 12)
```

**post-parse excerpt — while loop; initializer scope and initialization omitted.**

```lnast
while
  ref %1721491827_0
  stmts
    lt
      ref %1721491827_1
      ref j
      const 3
    if
      ref %1721491827_1
      stmts
        plus
          ref %sum_0
          ref sum
          ref j
        store
          ref sum
          ref %sum_0
        plus
          ref %j_0
          ref j
          const 1
        store
          ref j
          ref %j_0
      stmts
        break
          ref %1826580722_2
```

The condition is calculated before the `while` and again inside it. The
inner `if` executes the body or breaks. An unconditional `loop` uses the
same machinery with an always-true condition. `break` carries an internal
reference in the dump; it is not a returned Pyrope value.

The enumeration loop is represented directly as:

**post-parse excerpt — enumeration; tuple construction omitted.**

```lnast
for
  ref value
  ref %3800684521_0
  stmts
    plus
      ref %enumerated_0
      ref index
      ref value
    plus
      ref %enumerated_1
      ref enumerated
      ref %enumerated_0
    store
      ref enumerated
      ref %enumerated_1
  const val
  ref index
```

The child order is value binding, iterable, body, iteration mode, and
optional index/key bindings. The source `(index, value)` binding therefore
is not the same order as the first two children of the `for` node.

```pyrope
// for_key.prp
const tup = (const left=2, const right=4)
mut sum = 0
for (index, value, key) in tup { sum += value }
cassert(sum == 6)
```

For this three-name binding, the parsed node ends with `const val`,
`ref index`, and `ref key`. The sum assertion passes; named-tuple ordering
should not be inferred from this order-independent sum.

```pyrope
// for_ref.prp
mut tup = (1, 2, 3)
for value in ref tup { value += 1 }
cassert(tup == (2, 3, 4))
```

**post-parse excerpt.**

```lnast
for
  ref value
  ref tup
  stmts
    plus
      ref %value_0
      ref value
      const 1
    store
      ref value
      ref %value_0
  const ref
```

The `const ref` mode requests write-back to the original tuple. Its
post-upass body contains stores to tuple positions 0, 1, and 2, and the
assertion confirms `(2, 3, 4)`.

### Compact hardware loops

A typed accumulator can keep a hardware loop compact under the default
`compile.unroll=false` policy:

```pyrope
// compact_loop.prp
comb sum_lanes(a:[4]U4) -> (y:U8) {
  mut total:U8 = 0
  for i in 0..<4 { wrap total += a[i] }
  y = total
}
cassert(sum_lanes((1, 2, 3, 4)) == 10)
```

**post-upass excerpt — rolled_for from compact_loop.sum_lanes.**

```lnast
rolled_for
  ref i
  const 0
  const 1
  const 4
  const
  const
  tuple_add
    store
      ref total__carry_in
      const total__carry_out
  stmts
    tuple_get
      ref %total_0
      ref a
      ref i
    plus
      ref %total_1
      ref total
      ref %total_0
    fcall
      ref %total_2
      ref wrap
      store
        ref v
        ref %total_1
      store
        ref type
        ref total
    store
      ref total
      ref %total_2
  stmts
    fcall
      ref %u_loop_0_r
      ref compact_loop.sum_lanes.__loop0
      store
        ref __inst_name
        const u_loop_0
      store
        ref a
        ref a
      store
        ref total__carry_in
        ref total
      store
        ref __valid
        const true
    store
      ref total
      ref %u_loop_0_r
```

This dump also contains the generated unit
`compact_loop.sum_lanes.__loop0`. The retained loop records the iteration
bounds and the accumulator's carry connection. `compile.unroll=true`
requests source expansion; loops that are not eligible for compact lifting
can expand under either setting. A finite hardware loop is not necessarily
an eagerly unrolled LNAST tree.

To build a tuple with a loop, use an explicit mutable accumulator and splice
entries into it, as described in [for](05b-statements.md#loop-for). The old
claim that `cont`/`brk` carry comprehension values is not an emitted-node
contract.

## puts/print

Interpolation is built before the printing call. In the parsed tree below,
a `String` call receives literal fragments and interpolated operands:

```pyrope
// strings.prp
const num = 2
const color = "blue"
const text = "I have {num} {color} potatoes"
cassert(text == "I have 2 blue potatoes")
cputs(text)
puts(text)
print("count={num}")
```

**post-parse excerpt.**

```lnast
fcall
  ref %text_0
  ref String
  const 'I have '
  ref num
  const ' '
  ref color
  const ' potatoes'
fcall
  ref %2917045464_0
  ref cputs
  ref text
fcall
  ref %318168145_0
  ref puts
  ref text
fcall
  ref %3932631745_0
  ref String
  const 'count='
  ref num
fcall
  ref %1055615812_0
  ref print
  ref %3932631745_0
```

The text assertion passes, and `cputs` reports `I have 2 blue potatoes`
during compilation. A post-upass tree can fold the string construction and
consume compile-time calls; absence of an `fcall` there is not by itself a
simulation trace. The snippet checks translation and constant evaluation,
not the execution of runtime `puts`/`print`. There is no separate
`format(...)` built-in in this example.

## Lambda call

Named arguments are `store` children of the `fcall` itself. A bare argument
can remain a bare `ref` in the parsed tree; argument binding is resolved by
the compiler, not by wrapping every source call in one prebuilt named tuple.

```pyrope
// calls.prp
comb add(a:U4, b:U4) -> (sum:U5) { sum = a + b }
const a:U4 = 2
const result = add(a, b=3)
const cell = __sum(`as`=(1, 2, 3))
cassert(result == 5)
cassert(cell == 6)
```

**post-parse excerpt.**

```lnast
fcall
  ref %result_0
  ref add
  ref a
  store
    ref b
    const 3
tuple_add
  ref %cell_0
  const 1
  const 2
  const 3
fcall
  ref %cell_1
  ref __sum
  store
    ref as
    ref %cell_0
```

The `add` call contains the bare `ref a` and a named `store b`; the cell
call contains a named `store as` referring to the positional operand tuple.
Both assertions pass.

A post-parse file can contain an `fdef` marker with `__streamed_comb` or
`__streamed_mod` and an opaque body identifier. The lambda body is materialized
later as its own unit. For example, the post-upass dump includes `calls.add`,
whose body is:

**post-upass excerpt — body of calls.add; io omitted.**

```lnast
plus
  ref %sum_0
  ref a
  ref b
store
  ref sum
  ref %sum_0
```

The surrounding unit can instead contain an inlined call with folded
operands. Do not confuse the streamed marker, the specialized/inlined call,
and the materialized lambda unit: they are different views of the same
source at different stages.

## Assertions in the dump

Assertions are not ordinary `fcall` nodes in the current parsed tree. The
node name is `cassert`, with a marker distinguishing the source operation:

```pyrope
// assertions.prp
const k = 2
cassert(k == 2)
assert(k > 0)
assume(k < 3)
```

**post-parse excerpt.**

```lnast
eq
  ref %3023404487_0
  ref k
  const 2
cassert
  ref %3023404487_0
  const __fkind__cassert
gt
  ref %1078686553_0
  ref k
  const 0
cassert
  ref %1078686553_0
lt
  ref %3061419811_0
  ref k
  const 3
cassert
  ref %3061419811_0
  const __fkind__assume
```

`__fkind__cassert` identifies the compile-time assertion;
`__fkind__assume` identifies the assumption; plain `assert` has no such
marker here. Sharing an IR node does not give them identical semantics.
All conditions in this input are known and disappear after verification.
See [Assertions](05-assert.md) for formal obligations and the TBD runtime
fallback for design-body assertions in `lhd sim`.

## Validation scope

The examples above were compiled individually with fresh work directories,
and both parse and post-upass dumps were inspected. All their `cassert`
checks passed. The bit-selection, reduction, conditional, register, call,
unsigned-complement, and compact-loop examples also completed graph lowering.
These checks establish the shown translations and concrete results; they do
not establish that every feature or operand combination has a hardware
implementation. In particular, this chapter supplies no lowering claim for
unfinished fluid support.
