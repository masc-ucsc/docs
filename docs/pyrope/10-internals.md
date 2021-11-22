# Internals

This section of the document provides a series of disconnected topics about the
compiler internals that affect semantics.


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

    ```
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
    ```
    if a == 0 begin
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

+ If the node does type checks (`has`, `does`) compute the outcome

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


The previous algorithm describes the semantics, the implementation may be
different.  For example, to parallelize the algorithm, each LNAST tree can be
processed locally, and then a global top pass is performed.


[^1]: Narrowing is based on "ABCD: eliminating array bounds checks on demand"
  by Ras Bodik et al.

