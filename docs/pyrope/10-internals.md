# Internals

This section of the document provides a series of disconnected topics about the
compiler internals that affect semantics.

## Determinism

Pyrope is designed to be deterministic. This means that the result is always
the same.  Notice that the `puts` command is a debugging directive, and as such
is not guarantee to be deterministic.

### Puts

If needed for debugging, the puts messages can be ordered. `puts` has an before
and after to create dependence between messages. 


### Setup section

The setup code section is called only once only if it is the top level file or
it is imported by another file. The order of the across independent files can
have many orders. This could look like lack of determinism with `puts` but they
can not have side effects because imports are by value, not reference.

### `punch`

Punch can create a dependence update between files. 

```
// file1.prp

var a:punch("A")
var b = punch("B")
b = a + 1
var c:punch("C")

assert a == 100
assert b == 101
assert c == 102

// file2.prp

var x = punch("A")
x = 100
var y:punch("B")
var z = punch("C")
z = y + 1

assert x == 100
assert y == 101
assert y == 102
```

In theory, the connections can be dependent on the previous pass value. This
will create an iterative process to solve the `punch` connections. Pyrope does
not allow this. The Setup code section is called only once and all the `punch`
commands must be `comptime` with a single pass. If they are not, a compile
error is generated.


## Dealing with unknowns


Pyrope tries to be compatible with synthesizable Verilog, as such it must
handle/understand unknowns. Compatible does not mean that it will generate the
same `?` bits as Verilog, but that it will not generate an unknown when Verilog
has known. It is allowed to generate a `0` or a `1` when the Verilog logical
equivalence check generates an `?`.


The previous definition of compatibility could allow the Pyrope compiler to
randomly replace all the unknowns by `0` or `1` when doing internal compiler
passes. It could even replace all the unknowns by `0` all the time, or even
pick the representation that generates the most efficient code.


The issue is that the most likely source of having unknowns in operations is
either during reset or due to a bug on how to handle non initialized structures
like memories.

The compiler internal transformations use a 3-state logic that includes `0`,
`1`, and `?` for each bit. Any register or memory initialized with unknowns
will generate a Verilog with the same initialization.


The compiler internals only needs to deal with unknowns during the copy
propagation or peephole optimizations. The compile goes through 2 phases: LNAST and Lgraph.


In the LNAST passes, we have the following semantics:

+ In Pyrope, there are 3 array-like structures: non persistent arrays, register
  arrays, and custom RTL memories. Verilog and CHISEL memories get translated
  to custom RTL arrays. Non persistent Verilog/CHISEL get translated to arrays.
  In Verilog the semantics is that an out of bounds access generates unknowns. In
  CHISEL, the `Vec` sematic is that an out of bound access uses the first index
  of the array. A CHISEL out of bound memory is an unknown like in Verilog. 
  The Pyrope compiler guarantees that there is no out of bound access for
  arrays but there is not guarantees for RTL memories:

    - An out of bound RTL address drops the unused index bits. If the size is
      not a power of two, the reminding index bits can access an invalid entry.
      This does not matter for the compiler optimizations because it is not
      possible to use memory contents to optimize logic.

    - Out of bound array access triggers a compile error. The code must be fixed
      to avoid the access. An `if addr < mem_size { ... mem[addr] ... }` tends
      to be enough.

    - The contents of a persistent array (`reg`) can not be used in compile
      optimization. This means that the compile is not affected by
      having unknowns at the index.

    - A index access non-persistent with unknowns sets the unknown bits to
      zero, and it is used as the index of the array. CHISEL 3.5 is not fully
      specified in this case, but Verilog states that the output is unknown.
      Pyrope picks a valid entry. In a way, Verilog has x-pesimism, Pyrope has
      x-optimism.

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
  (single bit) are a source of confusion. In Verilog it depends on the compiler
  options. A classic compiler will generate `?` in all the updated variables.  A
  Tmerge option will propagate `?` only if both sides can generate a different
  value. The LNAST optimization pass will behave like the Tmerge:

    - If all the paths have the same constant value, the `if` is useless and the correct value will be used. 

    - If any path has a different constant value, the generated result bits will
      have unknowns if the source bits are different or unknown. 

    - If any paths is not constant, there is no LNAST optimization. Further Lgraph optimizations could optimize if all the mux generated value are proved to be the same.

+ The `for` loops are expanded, if the expression in the `for` is unknown, a compile error is generated.

+ The `while` loops are also expanded, if the condition on the `while` loop has unknowns a compile error is generated.


At the end of the LNAST generation, a Lgraph is created. Only the registers and
memory initialization are allowed to have unknowns in Lgraph.  Any invalid
(`nil`) left triggers a compile error.  Any unknown bit is translated to zero
(`0b10?` becomes `0b100`). 


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

Values stores in registers (flop or latches) and memories (synchronous or
asynchronous) can not be used in compiler optimization passes. The reason is that
a scan-chain is allowed to replace the values.

The only way to optimize away a register or memor bit is if there is a
guarantee that the value is never used. If after compiler optimizations the
memory has no read and writes. Even just having writes the register is
preserved because it can be used to read values with the scan-chain.


## Type synthesis


The type synthesis and check is performed during the LNAST pass. This is a mid
level IR in the LiveHD compiler. The high level is the parse AST, the mid level
is the LNAST, and the low level is the Lgraph. This section explains the main
steps in the type synthesis as a way to specify Pyrope.


Pyrope uses a structural type system with global type inference. The work is
performed in a single topographical pass starting from the root/top, where each
LNAST node performs this operations during traversal depending on the LNAST
node:

+ If the node allows, perform these node input optimization steps first:

    - When the sematics allow it, sort the inputs by name/constant. E.g: `+ 0 2
      a b`. This simplifies the following steps but it is not needed for
      semantics.

    - instruction combining from sources only for same type but not beyond 128
      n-ary nodes. This step subsumes constant propagation and copy
      propagation. E.g: `a+(x-3)+1` becomes `a+x-3+1`

    - constant folding for existing node, also be performed as instruction
      combining proceeds

    - trivial simplification with constants for existing node, also performed
      as instruction combining proceeds. E.g.: `a+0 == a`, `a or true
      == true` ... 

    - trivial identity simplification for existing node, also performed as
      instruction combining proceeds. E.g: `a^a == a`, `a-a=0` ... 

+ If the node is a `comptime` trigger a compile error unless all the inputs are
  constant

    - `comptime asserts` should satisfy the condition or a compile error is
      generated

+ If the node does type checks (`equals`, `does`) compute the outcome and
  perform copy propagation. The result of this step is that the compiler is
  effectively doing flow type inference. All the types must be resolved before.
  If the `equals`/`does` was in a `if` condition, the control is decided at
  compile time.

+ If the node is a loop (`for`/`while`) that has at least one iteration expand
  the loop. This is an iterative process becasue the loop exit condition may
  depend on the loop body or functions called inside

+ If the node is a function call, iterate over the possible polymorphic calls.
  Call the first call that is valid (input types). Call the function and pass
  all the input constants needed. This requires to specialize the function
  by input constants and types. If no call matches a valid type trigger a
  compile error

+ If the node is a conditional (`if`/`match`), the pass performs narrowing[^1].

    - Delete any unreachable paths (`if false { delete his }`)

    - When the expression has these possible syntax `v >= y`, `v >
      y` or the reciprocals, restrict the Bitwidth. E.g: in the `v < y`
      restricts the `v.max = y.min-1 ; y.min = v.min + 1`

    - When the expression is an equality format `eq [and eq]*` or `eq [or
      eq]*` like `v1 == z1 and v2 != z2`, create a `v1=z1` and `v2=z2` in the
      corresponding path. This will help bitwidth and copy propagation.
      Complicated mixes of and/ors have no path optimization

    - When the expression is a single variable `a` or `!a`, set the variable
      `true` and `false` in both paths

+ If the node reads bitwidth, replace the node with the computer Bitwidth value
  (max, min, ubits, and/or sbits)

+ Compute these steps that may be needed in future steps:

    - Perform the "Mark" phase typical in dead-code-elimination (DCE) so that
      dead nodes are not generated when creating the Lgraph.

    - Compute the max/min for the output[s] using the bitwidth algorithm.
      Update the symbol table with the range. This is only needed because some
      code like polymorphism functions can read the bits.

    - Update the tuple field in the Symbol Table

    - Track the array accesses for memory/array Lgraph generation


No previous transformation could break the type checks. This means that the
copy propagation, and final lgraph translation the type checks are respected.

* All the entries on the comparator have the same type (`lhs equals rhs`)

* Left side assignments respect the assigned type (`lhs does rhs`)

* Any explicit type on any expression should respect the type (`var does type`)


The previous algorithm describes the semantics, the implementation may be
different.  For example, to parallelize the algorithm, each LNAST tree can be
processed locally, and then a global top pass is performed.


[^1]: Narrowing is based on "ABCD: eliminating array bounds checks on demand"
  by Ras Bodik et al.


## Programming Warts

In programming languages, warts are small code fragments that have unexpected
or not great behavior. Every language has its warts. This section tries to list
the Pyrope main ones to address and learn more about the language.


### Shadowing

Pyrope does not allow shadowing, but you can still have it with tuples

```
let fun = {|| 1 }

let tup = (
  ,let fun = {|| 2}

  ,let code = {||
     assert self.fun() == 2
     assert fun() == 1
  }
)
```

### Closures

Closures capture state. In Pyrope everything is by value, so capture variables.
By default, all the upper scope variables are captured, but you can not declare
new variables in the new lambda that shadow the captures. You must restrict the
capture list.

```
var x = 3

let fun = {|()->:int|
   assert x == 3
   var x    // compile error. Shadow captured x
   return 200
}
```

Captured variables keep the declared type (`var`/`let`) but the change does not
escape the local lambda.

```
var x = 3
let y = 10

let fun = {|()->:int|
   assert x == 3 and y == 10
   x = 10000
   //y = 100              // compile error, y is immutable
   return x+200
}

assert x == 3

let z = fun()
assert z == 10200
assert x == 3
```

Capture variables pass the value at capture time:

```
var x = 3
var y = 10

let fun2 = {|[y]()->:int| // [] means capture just y
  var x  = 200
  return y + x
}
x = 1000
assert fun2() == 203
```

### always blocks

Tuples can have several always blocks. This can lead to confusion in the
evaluation order.


```
var x = (
  ,var v:int
  ,var always_after = {||
    self.v = 1
  }
)

var y = x ++ (
  ,var always_after = {||
    self.v = 2
  }
)

var z = (
  ,var always_after = {||
    self.v = 3
  }
) ++ x

assert x.v == 1
assert y.v == 2
assert z.v == 1 // self.v = 3 executes before self.v = 1
```

### Unknowns


Pyrope respects the same semantics as Verilog with unknowns. As such, there can
be many un-expected behaviors in these cases. The difference is that in Pyrope
everything is initialized and unknowns (`0sb?`) can happen only when explicitly
enabled.


The compare respects Verilog semantics. This means that it is true if and only
if all the possible values are true, which is quite counter-intuitive bahavior
for programmers not used to 4 value logic.

```
assert !(0sb? == 0)
assert !(0sb? != 0)
assert !(0sb? == 0sb?)
assert !(0sb? != 0sb?)
```

There is no way to known at run-time if a value is unknown, but a compile trick
can work. The reason is that integers can be converted to strings in a C++ API

```
var x = 0sb10?
let str = __to_string(x) // only works for compile time constants
assert x == "0sb10?"
```

### Initialization

Registers and variables are initialized to zero by default, but the reset logic
can change to a more traditional Verilog with uninitialized (`0sb?`) contents.


```
reg r_ver = (
  ,always_reset = {||} // do nothing
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
result to unexpected results during the reset period.

```
var arr:[] = {0,1,2,3,4,5,6,7}

assert arr[0] == 0 and arr[7] == 7 // always works

reg mem:[] = {0,1,2,3,4,5,6,7}

assert mem[7] == 7 // FAIL, this may fail during reset
assert mem[7] == 7 unless mem.reset // OK
```


Registers have reset code, which create un-expected code:

```
reg v:u32 = 33

assert v == 33 // this will fail after reset

v = 1
```

### Unexpected calls


```
let fun = {|| puts "here" ; return 3}
let have = {|f| f() }

let x = have fun   // same as have(fun), nothing printed
assert x == 3      // prints "here"

let y = have fun() // same as have(fun()), prints "here"
assert x == 3      // nothing printed
```

### Unexpected return


Return has an optional exit value

```
let fun1 = {|()->(out)|
  out = 100
  return {
    3
  }
}

let fun2 = {|()->(out)|
  out = 100
  return 
  {  // code never reached
    3
  }
}

assert fun1() == 3
assert fun2() == 100

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


A lambda can return an empty lambda, and then both get called in a single
useless line of code (spaces are not needed).

```
{|| {||} }()()  // does nothing
```


