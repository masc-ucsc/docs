# Internals

This section of the document provides a series of disconnected topics about the
compiler internals that affects semantics.

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
during simulation. The non-Pyrope calls must be `comptime` to affect
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
b` and `b import a`. Only the last import chain can perform procedure `proc`
calls (Pyrope and non-Pyrope) and puts/debug statements.


If the result of the last two imports has the same variables, the import has
"converged", otherwise a compile error is generated. This multi-pass solution
does not address all the false paths, but the common case of having two sets of
independent variables. This should address most of the Pyrope cases because
there is no concept of "reference/pointer" which is a common source of
dependences.


### Register Reference

Register reference can create a dependence update between files, but this is
not a source of non-determinism because only one file can perform updates for
the register `din` pin, and all the updated register can only read the register
`q` pin.


## Dealing with unknowns


Pyrope tries to be compatible with synthesizable Verilog, as such it must
handle/understand unknowns. Compatible does not mean that it will generate the
same `?` bits as Verilog, but that it will not generate an unknown when Verilog
has known. It is allowed to generate a `0` or a `1` when the Verilog logical
equivalence check generates an `?`.


The previous definition of compatibility could allow the Pyrope compiler to
randomly replace all the unknowns by `0` or `1` when doing internal compiler
passes. It could even replace all the unknowns with `0` all the time, or even
pick the representation that generates the most efficient code.


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
  CHISEL, the `Vec` sematic is that an out of bound access uses the first index
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

+ Shifts, additions and substractions propagate unknowns at computation. E.g:
  `0b11?0 + 0b1` is `0b11?1`, `0b1?0 >> 1` is `0b1?`.

+ Other arithmetic are more conservative. When an input is unknown, the result
  is unknown only respecting the sign when possible. E.g: `0b1?0? * -1` is
  `0sb1?`.

+ Logic operations behave like Verilog. `0b000111??? | 0b01?01?01?` is
  `0b01?111?1?`.

+ Equality comparisons (`==` and `!=`) use unknowns, this means that at compile
  time `0b1? != 0b10`. Comparisons is consistent with the equivalent logic
  operations `a == b` is the same as `(a ^ b) == -1`.

+ Other comparisons (`<=`, `<`, `>`, `>=`) return true if the comparison is
  true for each possible unknown bit.

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
(`nil`) to an outout or register triggers a compile error. Any unknown constant
bit is translated to zero (`0b10?` becomes `0b100`). LGraph does not have
"unknowns" outside the register/memories.


As a result of these translations, the generated simulator may have to deal
with unknowns, but only for arrays and memories explicitly non initialized
contents. The semantics on the generated simulator are similar to CHISEL, any
unknowns are randomly translated to 0 or 1 at initialization.

## Assume directive


The `assume` directive is like an `assert` but it also allows compiler optimizations.
In a way, it is a safer version of Verilog `?`.


=== "Verilog x-optimization"

    ```verilog
    always_comb begin // one hot mux
      case (sel)
        3’b001 : f=i0;
        3’b010 : f=i1;
        3’b100 : f=i2;
        default: f=2’b??;
      endcase
    end
    ```

=== "Pyrope `match`"

    ```
    assume sel==1 or sel==2 or sel==4 // not needed. match sets it
    match sel {
      == 0b001 { f = i0 }
      == 0b010 { f = i2 }
      == 0b100 { f = i3 }
    }
    ```

=== "Generated Logic 1 bit f"

    ```
    f = (sel[0] & i0)
      | (sel[1] & i1)
      | (sel[2] & i2)
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

    ```
    assume a != 0


    if (1 + a) != 1 { // always false
      out = 1
    }else{
      out = 3
    }

    assume b != 3 
    // array = (1,2,3,4,5,6,7,8)
    res = array[b]
    ```


## Registers and Memories

Values stored in registers (flop or latches) and memories (synchronous or
asynchronous) can not be used in compiler optimization passes. The reason is that
a scan chain is allowed to replace the values.


The `retime` directive indicates that the register/memory can be replicated and
used for optimization. Copy values can propagate through `retime`
register/memories.


A register or memory without explicit `retime=true` can only be optimized away
if there is no read AND no write to the register. Even just having writes the
register is preserved because it can be used to read values with the
scan-chain.

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

+ If the node is a `comptime` trigger a compile error unless all the inputs are
  constant

    - `comptime asserts` should satisfy the condition or a compile error is
      generated

+ If the node is a loop (`for`/`while`) that has at least one iteration expand
  the loop. This is an iterative process because the loop exit condition may
  depend on the loop body or functions called inside. After the loop
  expansions, no `for`, `while`, `break`, `last`, `continue`, `cont` statement
  exists.

+ If the node is a function call, iterate over the possible polymorphic calls.
  Call the first call that is valid (input types). Call the function and pass
  all the input constants needed. This requires specializing the function
  by input constants and types. If no call matches a valid type trigger a
  compile error

+ Delete unreachable statements (`if false { delete his }`, `delete this when false`, ...)

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

+ If the node reads bitwidth, replace the node with the computer Bitwidth value
  (max, min, ubits, and/or sbits)

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

* All the entries on the comparator have the same type (`LHS equals RHS`)

* Left side assignments respect the assigned type (`LHS does RHS`)

* Any explicit type on any expression should respect the type (`var does type`)


The previous algorithm describes the semantics, the implementation may be
different.  For example, to parallelize the algorithm, each LNAST tree can be
processed locally, and then a global top pass is performed.


[^1]: Narrowing is based on "ABCD: eliminating array bounds checks on-demand"
  by Ras Bodik et al.


## Programming Warts

In programming languages, warts are small code fragments that have unexpected
or not great behavior. Every language has its warts. This section tries to list
the Pyrope main ones to address and learn more about the language.


### Shadowing

Pyrope does not allow shadowing, but you can still have it with tuples

```
let f1 = fun() { 1 }

let tup = (
  ,let f1 = fun() { 2 }

  ,let code = fun() {
     assert self.f1() == 2
     assert f1() == 1
  }
)
```

### Closures

Closures capture the state. In Pyrope everything is by value, so capture variables.
By default, all the upper scope variables are captured, but you can not declare
new variables in the new lambda that shadow the captures. You must restrict the
capture list.

```
var x = 3

let f1 = fun()->(:int){
   assert x == 3
   var x    // compile error. Shadow captured x
   ret 200
}
```

Captured variables keep the declared type (`var`/`let`) but the change does not
escape the local lambda.

```
var x = 3
let y = 10

let f1 = fun()->(:int){
   assert x == 3 and y == 10
   x = 10000
   //y = 100              // compile error, y is immutable
   ret x+200
}

assert x == 3

let z = f1()
assert z == 10200
assert x == 3
```

Capture variables pass the value at capture time:

```
var x = 3
var y = 10

let fun2 = fun[y]()->(:int){ // [] means capture just y
  var x  = 200
  ret y + x
}
x = 1000
assert fun2() == 203
```

### Lambda calls


Lambda calls happen whenever an identifer is followed by a tuple. Since the
tuple bundary can be dropped, this can lead to unexpected cases like:


```
assert 0 == (0)  // OK, same as assert( 0 == (0) )
assert (0) == 0  // compile error: (assert(0)) == 0 is an expression
```

It is also easy to forget that parenthesis can be ommited in simple expressions,
not when ranges or tuples are involed.

```
asssert 2 in (1,2)  // compile error, not allowed to drop parenthesis
asssert(2 in (1,2)) // OK
```

### always blocks

Tuples can have several always blocks. This can lead to confusion in the
evaluation order.


```
var x = (
  ,var v:int
  ,var always_after = proc()->(self) {
    self.v = 1
  }
)

var y = x ++ (
  ,var always_after = proc()->(self) {
    self.v = 2
  }
)

var z = (
  ,var always_after = proc()->(self) {
    self.v = 3
  }
) ++ x

assert x.v == 1
assert y.v == 2
assert z.v == 1 // self.v = 3 executes before self.v = 1
```

### Unknowns


Pyrope respects the same semantics as Verilog with unknowns. As such, there can
be many unexpected behaviors in these cases. The difference is that in Pyrope
everything is initialized and unknowns (`0sb?`) can happen only when explicitly
enabled.


The compare respects Verilog semantics. This means that it is true if and only
if all the possible values are true, which is quite counter-intuitive behavior
for programmers not used to 4 value logic.

```
assert !(0sb? == 0)
assert !(0sb? != 0)
assert !(0sb? == 0sb?)
assert !(0sb? != 0sb?)
```

There is no way to know at run-time if a value is unknown, but a compile trick
can work. The reason is that integers can be converted to strings in a C++ API

```
var x = 0sb10?
let str = __to_string(x) // only works for compile time constants
assert x == "0sb10?"
```

### for loop

The `for` expects a tuple, and iterates over the tuple. This can lead to some
unexpected behaviour. The most strange is that ranges are always from smallest
to largest, so they do not allow to create a decreasing iterator.


```
let s:string="hell"
for i,idx in s {
  let v = match idx {
   == 0 { "h" }
   == 1 { "e" }
   == 2 { "l" }
   == 3 { "l" }
  }
  assert v == i
}

let t = (1,2,3)
for i,idx in t {
  let v = match idx {
   == 0 { 1 }
   == 1 { 2 }
   == 2 { 3 }
  }
  assert v == i
}

let r=2..<5
for i,idx in r {
  let v = match idx {
   == 0 { 2 }
   == 1 { 3 }
   == 2 { 4 }
  }
  assert v == i
}

let r2=4..=2 by -1
assert r == r2
for i,idx in r2 {
  let v = match idx {
   == 0 { 2 }
   == 1 { 3 }
   == 2 { 4 }
  }
  assert v == i
}

for i in 2..<5 {
  let ri = 2+(4-i) // reverse index
  // 2 == (2..<5).trailing_one
  // 4 == (2..<5).leading_one
  let v = match idx {
   == 0 { 4 }
   == 1 { 3 }
   == 2 { 2 }
  }
  assert v == ri
}

for i,idx in 123 {
  assert i == 123 and idx==0
}
```

### Bit order

Ranges are sets, this creates potentially unexpected results in reverse `for`
iterators, but also in bit section:

```
let v = 0xF0

assert v@[0] == 0
assert v@[4] == 1

assert v@[3..=4] == 0b010 == v@[3,4]
assert v@[4..=3 by -1] == 0b010
assert v@[4,3] == 0b001
```

### Initialization

Registers and variables are initialized to zero by default, but the reset logic
can change to a more traditional Verilog with uninitialized (`0sb?`) contents.


```
reg r_ver = (
  ,always_reset = proc()->(self){ self = 0sb? }
)
reg r
var v

assert v == 0 and r == 0

assert !(r_ver != 0)    // 0sb? != 0 evaluates false
assert !(r_ver == 0)    // 0sb? == 0 evaluates false too
assert !(r_ver != 0sb?) // 0sb? != 0sb? evaluates false too
assert !(r_ver == 0sb?) // 0sb? == 0sb? evaluates false too

assert r_ver == something unless r_ver.reset  // do not check during reset
```


The reset for arrays may take several cycles to take effect, this can
lead to unexpected results during the reset period.

```
var arr:[] = (0,1,2,3,4,5,6,7)

assert arr[0] == 0 and arr[7] == 7 // always works

reg mem:[] = (0,1,2,3,4,5,6,7)

assert mem[7] == 7 // FAIL, this may fail during reset
assert mem[7] == 7 unless mem.reset // OK
```


Registers have reset code, which creates un-expected code:

```
reg v:u32 = 33

assert v == 33 // this will fail after reset

v = 1
```

### Unexpected calls


Lambdas with no inputs are called when referenced. This is not the case for
lambdas with inputs. This difference can show when passing a lambda as argument
to another lambda.

```
let args = fun(x) { puts "args:{}", b ; ret 1}
let here = fun()  { puts "here" ; ret 3}

let call = fun(f:fun){ ret f } 

let x0 = call here           // same as call(here), prints "here"
let x1 = call args           // same as call(args), nothing printed
assert x0      == 3          // nothing printed
assert x1("b") == 1          // prints "args:b"
```

The reason is that variables can be exposed, and future refactors can change
the variable for an attribute getter. The behavior is respected by evaluating
the lambda on use. The evaluation will happen before the call even when an
explicit lambda is created.

```
let x3 = call fun() {here}   // prints "here" 
assert x3 == 3               // nothing printed
```


### `if` is an expression

Since `if`, `for`, `match` are expressions, you can build some strange code:

```
if if x == 3 { true }else{ false } {
  puts "x is 3"
}
```

### Legal but weird

The variable `http` has a type `8080` followed by a comment
(`//masc.soe.ucsc.edu`)

```
let http:8080//masc.soe.ucsc.edu

assert http == 8080
```

There is no `--` operator in Pyrope, but there is a `-` which can be followed
by a negative number `-3`.

```
let v = (3)--3
assert v == 6
```

### Return tuple

Pyrope everything is a tuple, but return value can be unexpected if 1 or 2
return values happen.

```
let ret1 = fun()->(a) {
  a = 1
}

let ret2 = fun()->(a,b) {
  a = 2
  b = 3
}

let a1 = ret1()
assert a1 == 1 // NOT a1.a == 1

let a2 = ret2()
assert a2.a == 2 and a2.b == 3

let x1,x2 = ret2()
assert x1 == 2 and x2 == 3
```

