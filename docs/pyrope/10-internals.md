# Internals

This section of the document provides a series of disconnected topics about the
compiler internals that affects semantics.

## Tuple operations


There are 3 basic operations/checks with tuples that affect many other
operations: `a in b`, `a does b`, and lambda call rules.

A tuple is either all named or all unnamed; a tuple that mixes both is an
error (see [Tuples](03-bundle.md)).

* `a in b` checks that the scalar `a` is one of the values in `b`, named or
  unnamed; field names do not participate.

* `a does b` requires `a` to provide the fields required by `b`: by name for
  two named tuples, by position for two unnamed tuples.

* lambda call matches the arguments with the definition in a third different set of rules.


```pyrope
cassert(1 in (1, 2, 3))
cassert(3 in (const a=1, const b=3))    // names do not participate
cassert(not ((const a=1) does (const a=1, const b=3)))
cassert((const a=1, const b=3) does (const a=1))
cassert((1, 2, 3) does (1, 2))          // unnamed: by position

comb f(a) -> () { puts("{a}") }
comb g(long, short) -> () { puts("{long}") }

f(a=1)             // OK
f(1)               // OK

g(long=1, short=1) // OK
g(1,1)             // error: untyped positional arguments, name them
const long=1
g(long, short=1)   // OK
const short=1
g(long, short)     // OK
```

Operators like `a == b`, `a case b`, `a equals b`, ... built on top of the previous functionality.

## Determinism

Pyrope is designed to be deterministic. This means that the result is always
the same for synthesis. Simulation is also deterministic unless the random seed
is changed or non-Pyrope (C++) calls to `procedures` add non-determinism.


Expressions are deterministic because `procedures` have an explicit order in
Pyrope. Only `functions` have a non-explicit order, but `functions` are pure
without side-effects. `puts` can be called non-deterministically but the result
is buffered and ordered at the end of the cycle to be deterministic.


The only source of non-determinism is non-Pyrope (C++) calls from `procedures`
executed at different pipeline stages. The pipeline stages could be executed in
any order, it is just that the same order must be repeated deterministically
during simulation. The non-Pyrope calls must be ``.[`comptime`]`` to affect
synthesis. So the synthesis is deterministic, but the testing like cosimulation
may not.


The same non-Pyrope calls also represent a problem for the compiler
optimizations. During the setup phase, several non-Pyrope can exist like
reading the configuration file. If the non-Pyrope calls are not deterministic,
the result could be a non-deterministic setup phase.


The idea is that the non-Pyrope API is also divided in 2 categories:
`functions` and `procedures`. A `function` can be called many times without
non-Pyrope side-effects. Pyrope guarantees that the `procedures` are called in
the same order given a source code, but does not guarantee the call order. This
guarantee order slowdowns simulation and elaboration. Whenever possible, use
`functions` instead of `procedures` for compilation speed reasons.


### Import


`import` statement allows for circular dependencies of files, but not of
variables. This means that if there is no dependency (`a imports b`), just
running `a` before `b` is enough. If there is a dependency (`a imports b` and `b
imports a`) a multiple compiler pass is proposed, but other solutions are
allowed as long as it can handle not true circular dependences.


The solution to this problem is to pick an order, and import at least three
times the files involved in the cyclic dependency. The files involved in the
cylic dependency are alphabetically sorted and called three times: (1) `a
import b`, then `b import a`; (2) `a import b` and `b import a`; (3) `a import
b` and `b import a`. Only the last import chain can perform `mod`
calls (Pyrope and non-Pyrope) and puts/debug statements.


If the result of the last two imports has the same variables, the import has
"converged", otherwise a compile error is generated. This multi-pass solution
does not address all the false paths, but the common case of having two sets of
independent variables. This should address most of the Pyrope cases because
there is no concept of "reference/pointer" which is a common source of
dependences.


### Register reference

Register reference (`regfef`) can create a dependence update between files, but this is
not a source of non-determinism because only one file can perform updates for
the register `din` pin, and all the updated register can only read the register
`q` pin.


## Dealing with unknowns


Dlop handles every operation involving unknown bits on a best-effort basis.
It may compute a precise result or leave some or all result bits unknown,
even when a more precise result could be proved. It must never produce an
incorrect definite answer: any known result bits must hold for every possible
assignment of the unknown input bits. An unknown result may conservatively
include additional possibilities; it must not exclude a possible correct
result.

This applies to arithmetic, shifts, bitwise operations, and comparisons.
There is no guarantee that Pyrope and Verilog produce identical unknown-bit
patterns, or that Dlop resolves every result Verilog can resolve. For example,
`0 * 0sb?` may resolve to zero or remain unknown, but never to a nonzero
definite value. Code must not depend on a particular amount of precision.

Compiler passes do not randomly replace unknowns with definite values.
Simulation resolves unknown bits to random 0/1 values; that is separate from
compile-time reasoning about all possible values.


The issue is that the most likely source of having unknowns in operations is
either during reset or due to a bug on how to handle non initialized structures
like memories.

The compiler internal transformations use a 3-state logic that includes `0`,
`1`, and `?` for each bit. Any register or memory initialized with unknowns
will generate a Verilog with the same initialization.


The compiler internals only needs to deal with unknowns during the copy
propagation or peephole optimizations. The compile goes through 2 phases: LNAST
and Lgraph.


In the compiler passes, we have the following semantics:

+ In Pyrope, there are 3 array-like structures: non-persistent arrays, register
  arrays, and custom RTL memories. Verilog and CHISEL memories get translated
  to custom RTL memories. Non-persistent Verilog/CHISEL get translated to arrays.
  In Verilog, the semantics is that an out of bounds access generates unknowns. In
  CHISEL, the `Vec` is that an out of bound access uses the first index
  of the array. A CHISEL out of bound memory is an unknown like in Verilog. These
  are the semantics applied by the compiler optimization/transformations:

    - Custom RTL memories do not allow value propagation across the array, only
      across non-persistent arrays, or register arrays explicitly marked with
      `retime=true`.

    - An out of bound RTL address drops the unused index bits. For non-power of
      two arrays, out of bounds access triggers a compile error. The code must
      be fixed to avoid access. An `if addr < mem_size { ... mem[addr] ... }`
      tends to be enough. This is to guarantee that passes like Verilog and
      CHISEL have the same semantics, and trigger likely bugs in Pyrope code.

    - An index with unknowns does not perform value propagation.

+ Arithmetic, shifts, and bitwise operations follow the best-effort rule
  above. `0ub11?0 + 0ub1` may preserve the known bits as `0ub11?1` or lose
  precision. Likewise, `0ub1?0? * -1` must cover the possible results `-8`,
  `-9`, `-12`, and `-13`; no exact output width or bit pattern is promised.

+ Equality comparisons (`==` and `!=`) follow the same rule. For example,
  `0ub1? != 0ub10` is unknown because the unknown bit can make the comparison
  either true or false. The equality identity is `a == b` iff `(a ^ b) == 0`;
  with unknowns, different evaluation paths may retain different amounts of
  precision, but neither may produce an incorrect definite result.

+ Ordered comparisons (`<=`, `<`, `>`, `>=`) resolve unknown bits on a
  best-effort basis in Dlop. A definite result must hold for every possible
  assignment of the unknown bits, but Dlop may leave the result unknown even
  when it could be proved. For example, `0ub1? > 0ub00` may produce `true` or
  unknown, but never `false`. Code must not rely on this comparison folding
  to `true`.

+ `match` statement and `unique if` will trigger a compile error if the unknown
  semantics during compiler passes can trigger 2 options simultaneously. The
  solution is to change to a sequence of `ifs` or change the code to guarantee
  no unknowns.

+ `if` statement without `unique` logical expressions that have an unknown
  (single bit) are a source of confusion. In Verilog, it depends on the
  compiler options. A classic compiler will generate `?` in all the updated
  variables.  A Tmerge option will propagate `?` only if both sides can
  generate a different value. The LNAST optimization pass will behave like the
  Tmerge when the if/mux control has unknowns:

    - If all the paths have the same constant value, the `if` is useless and
      the correct value will be used.

    - If any path has a different constant value, the generated result bits will
      have unknowns if the source bits are different or unknown.

    - If any paths are not constant, there is no LNAST optimization. Further
      Lgraph optimizations could optimize if all the mux generated values are
      proved to be the same.

+ The `for` loops are expanded, if the expression in the `for` is unknown, a
  compile error is generated.

+ The `while` loops are also expanded, if the condition on the `while` loop has
  unknowns a compile error is generated.


At the end of the LNAST generation, a Lgraph is created. Only the registers and
memory initialization are allowed to have unknowns in Lgraph.  Any invalid
(`nil`) assigned to an output or register triggers a compile error. Any unknown constant
bit is translated preserved (`0ub10?`).


The semantics on the generated simulator are similar to CHISEL, any unknowns
are randomly translated to 0 or 1 at initialization.


## Assume directive


The `assume` directive is like an `assert` but it also allows compiler
optimizations. In a way, it is a safer version of Verilog `?`. Unlike other
languages like C++23, Pyrope `assume` verifies at simulation time that the
`assume` is correct. This means that the `assume` is checked like an
`assert` but it allows the compiler to optimize based on the condition.
`asserts` do not trigger optimizations because their check can be disabled at
simulation time, and hence create mismatches between simulation and synthesis
if the compiler optimized over assertions.


=== "Verilog x-optimization"

    ```verilog
    always_comb begin // one hot mux
      case (sel)
        3’b001 : f=in0;
        3’b010 : f=in1;
        3’b100 : f=in2;
        default: f=2’b??;
      endcase
    end
    ```

=== "Pyrope `match`"

    ```pyrope
    assume(sel==1 or sel==2 or sel==4) // not needed. match sets it
    match sel {
      == 0ub001 { f = in0 }
      == 0ub010 { f = in1 }
      == 0ub100 { f = in2 }
      else      { f = 0  }
    }
    ```

=== "Generated Logic 1 bit f"

    ```pyrope
    f = (sel#[0] & in0)
      | (sel#[1] & in1)
      | (sel#[2] & in2)
    ```


Assume allows more freedom, without dangerous Verilog x-optimizations:

=== "Bad Verilog x-optimization"
    ```verilog
    if (a == 0) begin
       assert(false);
       out = '?;
    end else if (1 + a) == 1 begin // always false
       out = 1;
    end else begin
       out = 3;
    end

    array[3] = '?; // entry 3 will not be used
    // array = (1,2,3,'?,5,6,7,8)
    res = array[b]
    ```

=== "Pyrope assume"

    ```pyrope
    assume(a != 0)


    if (1 + a) != 1 { // always true
      out = 1
    }else{
      out = 3
    }

    assume(b != 3)
    // array = (1,2,3,4,5,6,7,8)
    res = array[b]
    ```

## Unknowns and synthesis constraints

Unknowns do not imply that a condition is unreachable. Use `assume` to express
constraints that the compiler may rely on when optimizing control flow.
An unknown value in a branch does not, by itself, allow the compiler to assume
that the branch cannot execute.

Each unknown bit (`?`) can resolve to 0 or 1 at simulation time. Synthesis may
choose concrete values for unspecified bits to produce a smaller or faster
circuit. This does not change Dlop's best-effort propagation rule: operations
on unknowns may retain uncertainty, but must never produce an incorrect known
result.


```pyrope
assert(cond==3)    // Runtime check; does not let the compiler assume cond == 3
mut x1 = 0sb?

if cond == 3 {
  x1 = 1
}
assert(x1==1) // Runtime check; the unknown initializer does not imply cond == 3
assert(not x1.[`comptime`])  // x1 is not a compile-time constant

mut x2 = 0sb?
assume(cond==3)
if cond == 3 {
  x2 = 1
}
cassert(x2==1)
cassert(x2.[`comptime`])
```

## LNAST optimization

The compiler has three IR levels: The high level is the parse AST, the
mid-level is the LNAST, and the low level is the Lgraph. This section explains
the main steps in the LNAST optimizations/transformations before performing
type synthesis and generating the lower level Lgraph. This is a minimum of
optimizations without them several type conflicts would be affected.


Unlike the parse AST, the LNAST nodes are guaranteed to be in topological
order. This means that a single pass that visits the children first (deep
first) is sufficient.


The work can be performed as a single "global" topographical pass starting from
the root/top, where each LNAST node performs these operations during traversal
depending on the LNAST node:


+ If the node allows, perform these node input optimization first:

    - constant folding for existing node, also be performed as instruction
      combining proceeds

    - instruction combining from sources only for same type but not beyond 128
      n-ary nodes. This step subsumes constant propagation and copy
      propagation. E.g: `a+(x-3)+1` becomes `a+x-3+1`

    - create a canonical order by sorting the inputs by name/constant. E.g: `+
      2 a b`. This simplifies the following steps but it is not needed for
      semantics. Most commutative gates (`add/sub/and/or/...`) will have a
      single constant as a result.

    - trivial simplification with constants for existing node, also performed
      as instruction combining proceeds. E.g.: `a+0 == a`, `a or true
      == true` ...

    - trivial identity simplification for existing node, also performed as
      instruction combining proceeds. E.g: `a^a == a`, `a-a=0` ...

+ If the node reads ``.[`comptime`]`` and asserts it true, trigger a compile error unless all the inputs are
  constant

    - `cassert` should satisfy the condition or a compile error is generated

+ If the node is a loop (`for`/`while`) that has at least one iteration expand
  the loop. This is an iterative process because the loop exit condition may
  depend on the loop body or functions called inside. After the loop
  expansions, no `for`, `while`, `break`, `last`, `continue` statement
  exists.

+ If the node is a function call, iterate over the possible polymorphic calls.
  Call the first call that is valid (input types). Call the function and pass
  all the input constants needed. This requires specializing the function
  by input constants and types. If no call matches a valid type trigger a
  compile error

+ Delete unreachable statements (`if false { delete this }`, ...)

+ Compute these steps that may be needed in future steps:

    - Perform the "Mark" phase typical in dead-code-elimination (DCE) so that
      dead nodes are not generated when creating the Lgraph.

    - Update the tuple field in the Symbol Table

    - Track the array accesses for memory/array Lgraph generation

### Type synthesis

The type synthesis and check are performed during the LNAST pass. Pyrope uses a
structural type system with global type inference.

The type inference should be performed as the same time as the LNAST
optimization traverses the tree. It can not be a separate pass because there
can be interactions between the LNAST optimization and the Type synthesis.
These are the additional checks performed for type synthesis:


+ If the node does type checks (`equals`, `does`) compute the outcome and
  perform copy propagation. The result of this step is that the compiler is
  effectively doing flow-type inference. All the types must be resolved before.
  If the `equals`/`does` was in a `if` condition, the control is decided at
  compile time.

+ If the node reads bitwidth, replace the node with the corresponding value
  (`max`/`min`/`bits` from the declared constraint; debug-only
  `bw_max`/`bw_min` from the computed bitwidth)

    - Compute the max/min for the output[s] using the bitwidth algorithm.
      Update the symbol table with the range. This is only needed because some
      code like polymorphism functions can read the bits.

+ If the node is a conditional (`if`/`match`), the pass performs narrowing[^1].

    - When the expression has these possible syntax `v >= y`, `v >
      y` or the reciprocals, restrict the Bitwidth. E.g: in the `v < y`
      restricts the `v.max = y.min-1 ; y.min = v.min + 1`

    - When the expression is an equality format `eq [and eq]*` or `eq [or
      eq]*` like `v1 == z1 and v2 != z2`, create a `v1=z1` and `v2=z2` in the
      corresponding path. This will help bitwidth and copy propagation.
      Complicated mixes of and/or have no path optimization

    - When the expression is a single variable `a` or `!a`, set the variable
      `true` and `false` in both paths


No previous transformation could break the type checks. This means that the
copy propagation, and final lgraph translation the type checks are respected.

* Comparator operands share the same basic type (both `integer`, both
  `String`, ...), but not necessarily the same `max/min`. Comparison is
  value-based, so any two integers are comparable regardless of their ranges; a
  comparison whose ranges cannot overlap folds to a constant. `integer` vs
  `Bool` (or any other basic-type mismatch) is still an error.

* Left side assignments respect the assigned type (`LHS does RHS`)

* Any explicit type on any expression should respect the type (`mut does type`)


The previous algorithm describes the semantics, the implementation may be
different.  For example, to parallelize the algorithm, each LNAST tree can be
processed locally, and then a global top pass is performed.


[^1]: Narrowing is based on "ABCD: eliminating array bounds checks on-demand"
  by Ras Bodik et al.


## Programming warts

In programming languages, warts are small code fragments that have unexpected
or not great behavior. Every language has its warts. This section tries to list
the Pyrope main ones to address and learn more about the language.


### Shadowing

Pyrope does not allow shadowing in code blocks or lambda bodies. Tuple methods
can still refer to their receiver through an explicit `self` argument, so
method-local names do not need to shadow tuple fields.

```pyrope
comb f1() -> (r) { r = 1 }

const tup = (
  comb f1(self) -> (r) { r = 2 },
  comb code(self) -> () {
     cassert(self.f1() == 2)
     cassert(f1() == 1)
  }
)
```

### Comptime lexical scope

Pyrope lambdas do not have runtime closures or explicit capture lists. Name
lookup is lexical, but a nested lambda cannot read a **runtime** binding of an
enclosing scope: a `const` computed from a runtime value (`const s = a + 1`
with `a` an input), a `mut`, `reg`, or `wire`, an input of the enclosing
lambda, or the element of a `for` over runtime values (`for x in (a, b)`).
Reading one is a compile error. Pass those values as normal inputs, or place
them in an explicit tuple/object and pass that object.

Comptime bindings are different: they are elaboration-time names, not hardware
resources. Visible comptime bindings from enclosing scopes are available
lexically inside lambda bodies and signatures: `comptime const` declarations,
a plain `const` whose value is a compile-time constant (`const k = 2`,
`const w = N * 4` over a comptime `N` or a generic, a const computed from such
consts), the generics of an enclosing lambda, the index of an enclosing `for`
(and its element when the iterable is comptime), imports, types, and lambdas.
A generic argument is a compile-time value too: binding a generic to a
runtime value (`g<N=a>`) is an error at the call. The
compiler records every lexical comptime reference as an explicit dependency of
the lambda (it recomputes the value inside the lambda from the same
declarations), so the dependency is still visible to elaboration and
incremental compilation without a user-written capture list. A comptime value
computed from a runtime binding (`comptime const K = a.[bits]` with `a` an
input) cannot be recomputed inside the nested lambda, so reading it there is
an error too.

A name with no accessible declaration — never declared, declared later, or
out of scope — is a compile error at the read in every context (bodies,
signatures and port widths, generic defaults and generic arguments,
attributes, tuple fields, test blocks). It never reads as `nil` and never
becomes a hidden input.

```pyrope
comptime const W = 32
const math = import("lib.math")// imports are comptime aliases

comb add<N=W>(a:Unsigned(bits=N), b:Unsigned(bits=N)) -> (result) {
  result = a + b
}

pipe do_arith(op:math.OpType, a:U32, b:U32) -> (result:U32) {
  match op {
    case math.AddOp { wrap result = a + b }
    else { result = 0 }
  }
}
```

Because runtime closures are not implicit, the following is an error:

```pyrope
mut x = 3

comb f() -> (result:Signed) {
  result = x       // error: runtime outer variable is not visible in lambda
}
mod outer(a:U8) -> (y:U8@[0]) {
  const k = a + 2                   // computed from the input `a`: a runtime value
  comb g() -> (r:U9) { r = k }      // error: `k` is a runtime value
  comb inner() -> (r:U8) { r = a }  // error: `a` is an input of the enclosing lambda
  y = inner()
}
```

Use an explicit input or tuple field instead:

```pyrope
comb f(x:Signed) -> (result:Signed) {
  result = x
}
```

### Lambda arguments


Lambda calls happen whenever an identifer is followed by a parenthesized list of
expressions. Verification statements use the same explicit grouping style.
Avoid the old compact form because it can make the boundary between the
statement and the checked expression unclear:


```pyrope
cassert(0 == (0)) // OK
assert((0) == 0)  // OK
```

It is also easy to forget that parentheses can be omitted in simple expressions,
but not when ranges or tuples are involved. Keep the verification condition
inside the statement parentheses:

```pyrope
assert(2 in 1,2)    // error: not allowed to drop tuple parentheses
cassert(2 in (1,2)) // OK
```

### Multiple tuples


The evaluation order is always the same program order starting from the top
module. Remember that the `init` method is the constructor, called even when
there is no initial value set (`nil`). The `init` constructor is an implicit
hook and must be `comb`; stateful or pipelined behavior must be modeled with
explicit methods. After construction, reads and writes are structural.



```pyrope
const I1_t = (
  mut i1_field:U32 = 1,
  mut i2_field:U32 = 2,
  comb init(ref self, a) {
     self.i1_field = a
  }
)
const I2_t = (
  mut i1_field:S32 = 11,
  comb init(ref self, a) {
     self.i1_field = a
  }
)

const X_t = (
  mut first:I1_t = nil,
  mut second:I2_t = nil
)

mut top = (
  comb init(ref self) {
    mut x:X_t = nil   // fields keep defaults; first then second in program order
    cassert(x.first.i1_field == 1)
    cassert(x.first.i2_field == 2)
    cassert(x.second.i1_field == 11)

    x.first = I1_t(400)  // explicit construction calls init

    cassert(x.first.i1_field == 400)
    cassert(x.first.i2_field == 2)
    cassert(x.second.i1_field == 11)

    x.second = I2_t(1000)

    cassert(x.first.i1_field == 400)
    cassert(x.first.i2_field == 2)
    cassert(x.second.i1_field == 1000)
  }
)
```


If a lambda in the hierarchy does not have an `init`/constructor, the program order
follows tuple scope in tuple ordered assignment.



### Unknowns


Every operation involving unknowns follows the best-effort rule in
[Dealing with unknowns](#dealing-with-unknowns): Dlop may resolve a result or
leave it unknown, but never produce an incorrect definite answer. In Pyrope,
everything is initialized and unknowns (`0sb?`) arise from explicitly supplied
unknown bits.


Comparisons involving unknown bits can yield an unknown boolean (`0sb?`),
including comparisons of identical unknown patterns.
Ordered comparisons may resolve to a definite result when Dlop can prove it,
but this is best-effort: `0ub1? > 0ub00` can be `true` or unknown, never
`false`. An unknown boolean cannot satisfy a `cassert`, so a mathematically
provable comparison involving unknown bits is not guaranteed to pass one.

At compile time, inspect the printable representation to check unknown bits:

```pyrope
const x = 0sb10?
cassert("{x:b}" == "10?")
const flag = 0sb? == 0       // legal: binds the unknown result 0sb?
cassert(flag)               // error: unknown is not true
```

### for loop

The `for` iterates over tuple entries or range values. Ranges run from smallest
to largest; a descending range such as `5..<0` is not legal. For reverse
iteration, compute a reverse index as shown below.


```pyrope
const t = (1,2,3)
for (idx,i) in t {
  const v = match idx {
   == 0 { 1 }
   == 1 { 2 }
   == 2 { 3 }
   else { 0 }
  }
  cassert(v == i)
}

const r=2..<5
for (idx,i) in r {
  const v = match idx {
   == 0 { 2 }
   == 1 { 3 }
   == 2 { 4 }
   else { 0 }
  }
  cassert(v == i)
}

const r2=2..=6 step 2
cassert(r2 == (2,4,6))
for (idx,i) in r2 {
  const v = match idx {
   == 0 { 2 }
   == 1 { 4 }
   == 2 { 6 }
   else { 0 }
  }
  cassert(v == i)
}

for i in 2..<5 {
  const ri = 2+(4-i) // reverse index
  // 2 == (2..<5).trailing_one
  // 4 == (2..<5).leading_one
  const v = match idx {
   == 0 { 4 }
   == 1 { 3 }
   == 2 { 2 }
   else { 0 }
  }
  cassert(v == ri)
}

for (idx,i) in (123,) {  // a scalar 1-tuple enumerates to a single (0, value)
  cassert(i == 123 and idx==0)
}
```

### Bit selection and packing

The bit selection operator `#[sel]` takes a single expression: a bit index, a
close-range like `3..=4`, an open range like `3..`, or any expression that
evaluates to one of those (including a conditional). Multi-entry tuple indices
like `#[3,4]` are not supported: a positional tuple does have a canonical bit
order, but `#[3,4]` is a *set* of bit positions, and a set has none — `#[4,3]`
names the same one, and nothing says which end of the result each bit lands at.

```pyrope
const v = 0xF0

cassert(v#[0] == 0)
cassert(v#[4] == 1)       // unsigned output
cassert(v#sext[4] == -1)  // signed output

cassert(v#[3..=4] == 0ub10)
cassert(v#sext[3..=4] == 0sb10 == -2)
```

`x#[..]` selects every bit, so it is the full bit vector of `x`, and that one
idea is also how bits are packed and unpacked. When `x` is a tuple or an array,
its bit vector is the packing of its entries. When `x` is an integer and the
destination is a declared ordered value, that same bit vector is laid back into
the destination's entries. Packing and unpacking are not two operators — they
are one bit vector read in the two directions — and there is no separate
concatenation operator carrying a bit order of its own.

The first entry of a positional tuple or array occupies the **lowest** bits,
and each later entry stacks above it. This holds in both directions, and it is
not a convention invented for packing: it is the direction that every other bit
spelling in the language already runs. `x#[0]` is the least significant bit, a
bit range is written low-to-high (`x#[3..=6]`, never `6..=3`). What comes
first in the positional tuple sits at the bottom of the word. Strings are
opaque and cannot be packed.

```pyrope
const stages:[4]U4 = (0ub0001, 0ub0010, 0ub0100, 0ub1000)
const inp:U4 = 0ub1111

// stages[0] at bit 0, then stages[1], stages[2], stages[3], and inp on top
cassert((...stages, inp)#[..] == 0ub1111_1000_0100_0010_0001)

// inp at bit 0 instead, and every stage shifts up by 4
cassert((inp, ...stages)#[..] == 0ub1000_0100_0010_0001_1111)
```

That direction is worth reading twice when arriving from SystemVerilog or
Chisel, because it is the reverse of `{a, b, c}` and `Cat(a, b, c)`, where the
first argument lands in the high bits. Pyrope keeps a single direction for bits
everywhere, so transcribing a Verilog concatenation means reversing its
argument order.

Inside a tuple being packed, an entry that is itself a tuple or an array is a
compile error: splice it with `...`, so that `#[..]` only ever sees a flat
entry list. A nested entry would need an inner layout that the source never
states, and the splice makes that layout visible at the point where it is
chosen.

```pyrope
const regw:U20 = (...stages, inp)#[..] // OK: `...` flattens the array into entries
const bad = (stages, inp)#[..]         // error: splice the array entry -- `...stages`
const all:U16 = stages#[..]            // OK: `stages` IS the tuple being packed
```

Each entry's width comes from its **declared type** — never from its value,
never from an inferred range, and never from a literal's spelling. Narrowing
one entry would shift every entry above it, so the width has to be something
the source states rather than something the compiler measures. The packed total
is exactly the sum of the entry widths.

```pyrope
const a:U4 = 0ub101      // a FOUR-bit entry: the type says 4, not the literal's 3
const b:U8 = 1

const c:U12 = (a, b)#[..]
cassert(c == 0ub0000_0001_0101)   // `b` above `a`, because entry 0 is at bit 0
```

A destination that declares a different width is an error in both directions,
never a zero-extension and never a silent truncation:

```pyrope
const wide:U13   = (a, b)#[..]  // error: 13 != 12; a layout is never silently padded
const narrow:U11 = (a, b)#[..]  // error: 11 != 12; nor silently truncated
wrap const e:U10 = (a, b)#[..]  // OK, the top 2 bits are dropped, and the line says so
sat const f:U10  = (a, b)#[..]  // error: saturation has no meaning for a bit layout
```

`wrap` is the only escape hatch, and it is the same statement-level modifier
that governs [every other narrowing
assignment](04b-attributes.md#wrap-and-sat-modifier): it permits dropping the
high bits, on the line that loses them. Widening has no such escape hatch
because no modifier can invent bits, and `sat` is rejected exactly as
`sat x:Bool` is, since a layout has no magnitude to saturate towards.

Every entry must therefore name something declared. An untyped variable is an
error even when its initializer looks sized, and so is a literal or an
expression written directly as an entry. Bind it to a typed name first:

```pyrope
const u = 0ub101                // u has no declared type
const w1:U12 = (u, b)#[..]      // error: entry `u` has no declared bit width
const w2:U12 = (a, 0ub01)#[..]  // error: a literal entry has no declared type
const w3:U13 = (a, b + 1)#[..]  // error: `b + 1` has no declared width

const one:U8 = 1
const d:U12 = (a, one)#[..]     // OK -- `one` declares the 8-bit window
```

A tuple with **two or more named fields** has no bit vector, at any depth.
Named-tuple equality is by key and independent of spelling order, so packing
one would publish the compiler's canonical key order as a bit layout, a layout
that nobody wrote and that no source line pins down. Select the fields in the
order you want instead. A tuple with **exactly one** named field has no order
to get wrong, and stays legal in both directions.

```pyrope
const pt = (const lo:U4 = 3, const hi:U4 = 1)

const q:U8 = pt#[..]              // error: two named fields have no bit order
const w:U8 = (pt.lo, pt.hi)#[..]  // OK: the order is in the source
cassert(w == 0ub0001_0011)

const one_named = (const only:U4 = 3)
cassert(one_named#[..] == 3)      // a single name cannot be misordered
```

For the same reason, an unpack destination is a declared **type**, never a list
of names on the left of an `=`. A destructuring pattern says what the pieces
are called, not how wide they are or where they sit:

```pyrope
const b8:U8 = 0ub1010_0110

const x:[2]U4 = b8#[..]         // OK: the array type states the layout
cassert(x[0] == 0ub0110 and x[1] == 0ub1010)

const (lo:U4, hi:U4) = b8#[..]  // error: destructuring slots never carry types
```

Signedness on unpack comes from the declared entry type, and each entry is
extended from its own window rather than from the word:

```pyrope
const s:[2]S4 = b8#[..]
cassert(s[0] == 6 and s[1] == -6)   // 0ub1010 read as a 4-bit signed entry
```

The exact-width rule holds here too, with `wrap` again the one way to lose a
bit in the open:

```pyrope
const nine:U9 = 0ub1_1010_0110

const y1:[2]U4 = nine#[..]       // error: 8 != 9; bit 8 has nowhere to land
wrap const y2:[2]U4 = nine#[..]  // OK, bit 8 is dropped, and the line says so
```

Uniform entries are what an array destination expresses. Mixed widths have no
packing spelling on purpose, because no type states "8 bits and then 4" for a
destructuring, so the ranges are written out:

```pyrope
const packed:U12 = 0ub1010_0110_0011

const lo_byte = packed#[0..=7]
const hi_nib  = packed#[8..=11]
cassert(lo_byte == 0ub0110_0011 and hi_nib == 0ub1010)
```

Because a tuple *is* its bit vector, the whole `#<mod>[range]` family applies
to it. There is no separate list of which suffixes accept a tuple: the operand
is a word, and the modifiers do to that word what they do to any other word.
Packing keeps every entry inside its own declared window, so a negative entry
contributes that window and nothing above it. The packed word is always
non-negative, and a destination meant to be read as a signed word takes
`#sext[..]`, so the reinterpretation is written rather than assumed.

```pyrope
const pair:[2]S4 = (1, -1)             // 0ub0001 at the bottom, 0ub1111 above it

cassert(pair#[..]     == 0ub1111_0001) // the packed word, always non-negative
cassert(pair#sext[..] == -15)          // the same bits, reinterpreted as signed
cassert(pair#[4..=7]  == 0ub1111)      // a sub-range of the packed word

cassert(pair#|[..]    == 1)            // or-reduce over the packed bits
cassert(pair#^[..]    == 1)            // xor-reduce: an odd number of ones
cassert(pair#+[..]    == 5)            // popcount
cassert(pair#&[0..<8] == 0)            // and-reduce over a close range
```

The last line is the usual signed-number caution rather than anything about
tuples: `#[..]` is non-negative, so its infinite high bits are zero and an
and-reduce over the open range is always `0`. Close the range when the
intention is to reduce the layout itself.

A `range` is the one type that keeps its own answer for `#[..]`. Its bit vector
is a set membership encoding — bit `i` is set when `i` belongs to the range —
not a positional packing:

```pyrope
cassert(1..=3 == (1,2,3))          // a range compares equal to its values...
cassert((1..=3)#[..] == 0ub1110)   // ...but its bit vector is the one-hot set
```

Those two lines are worth reading together, because the spec calls the operands
equal and still gives them different words. That is intentional. `#[..]` asks
the type for a bit vector: a `range` answers with the set encoding described in
[Variables](04-variables.md), while a positional tuple answers with the packing
of its entries. The tuple side never reaches a competing answer anyway, since
`(1,2,3)` is a list of untyped literals that declares no entry widths and
cannot be packed at all.

Packing is not the only way to state a layout. The explicit bit-assignment
idiom names each destination range instead. The destination must declare its
width, and every bit must be driven exactly once, so undriven (`nil`) bits and
overlapping writes are compile errors. It makes the layout local and
unambiguous, it is the right choice when the pieces land at addresses you want
to read off the page, and it doubles as an independent statement of the packing
order:

```pyrope
const a4:U4 = 0ub1010
const b2:U2 = 0ub01
const c1:U1 = 0ub1

mut r:U7 = nil
r#[0]     = c1
r#[1..=2] = b2
r#[3..=6] = a4
cassert(r == 0ub1010_01_1)

cassert((c1, b2, a4)#[..] == r)  // the same layout, stated as a packing
```

A pure bit reversal has no layout to state — it is a permutation — so it stays
a `for` loop with explicit indices:

```pyrope
comb reverse(x:Unsigned) -> (total:Unsigned) {
  mut t:Unsigned = nil
  for i in 0..<x.[bits] {
    t#[i] = x#[x.[bits]-1-i]
  }
  total = t
}
cassert(reverse(0ub10110) == 0ub01101)
```

### Unexpected calls

Passing a lambda argument with a `ref` does not have any side effect because
lambdas without arguments need to be explicitly called or just passed as
reference.


```pyrope
comb args(x) -> (r) { puts("args:{x}"); r = 1 }
comb here()  -> (r) { puts("here");   r = 3 }

type NullaryInt = comb() -> (r:Signed)
comb call_now(f:NullaryInt)   -> (r:Signed)     { r = f() }
comb call_defer(f:NullaryInt) -> (g:NullaryInt) { g = f }

const x0 = call_now(here)          // prints "here"
const e1 = call_now(args)          // error: args needs arguments
const x1 = call_defer(here)        // nothing printed
const e2 = call_defer(args)        // error: args needs arguments
cassert(x0  == 3)                 // nothing printed
cassert(x1  == 3)                 // nothing printed

const x2 = call_now(ref here)      // prints "here"
const e3 = call_now(ref args)      // error: args needs arguments
const x3 = call_defer(ref here)    // nothing printed
const x4 = call_defer(ref args)    // nothing printed
cassert(x2  == 3)                 // nothing printed
cassert(x3()  == 3)               // prints "here"
assert(x3  == 3)                  // error: explicit call needed
assert(x4  == 1)                  // error: args needs arguments
cassert(x4("xx") == 1)            // prints "args:xx"

```


### `if` is an expression

Since `if`, `for`, `match` are expressions, you can build some strange code:

```pyrope
if if x == 3 { true }else{ false } {
  puts("x is 3")
}
```

### Legal but weird

There is no `--` operator in Pyrope, but there is a `-` which can
be followed by a negative number `-3`.

```pyrope
const v = (3)--3
assert(v == 6)
```
