
# Hardware Design

Most language manuals/guides do not include a chapter on "what is
programming?", but Pyrope is a hardware description language or HDL.  This
document is a guideline for hardware design for software designers. The idea is
to be high level to explain the differences without going to syntactic details
in different languages.


## FPGA/ASIC vs CPU


Most software programming languages are build to program Von Neumann CPUs. As
such, when dealing with single threaded code, the programmer has a sequence of
"commands" or "statements" specified in a programming language. The machine
executes one of those statements after another. There are "control flow"
instructions to select what is the next statement to execute.


Potentially more restricting, software languages have a central or distributed
"memory" concept where program data resides. For single threaded code, there
tend to be a central unified memory.


Current CPUs follow a Von Neumann approach[^1] and languages designed to
program CPUs follow the same model to have a good mapping to existing hardware.
Since the languages are Von Neumann, it is logical that CPUs also evolve to
keep the same model and further improve the performance. Since CPUs and
languages follow the same Von Neumann model, software designers mindset assumes
this same concept. This feedback loop has resulted in that most languages,
hardware, and developers evolve around this model.


Neither FPGAs or ASICs are Von Neumann machines. There is no program counter to
execute one statement after another and there is no central memory. Those concepts
could be build on top, and this is in fact what CPUs are about. CPUs are all
about how to build efficient Von Neumann machines on top of FPGAs and/or ASICs
given some power/area/performance constrains.



If you want to design such CPUs or you want to directly use the existing
FPGA/ASIC without a Von Neumann machine, you need to direct the hardware
compiler without having a "central memory" and the concept of single thread of
execution does not make much sense either. The reason is that the cells
available in hardware are always there. The result can be used or not, but it
is always there.


In a high level, hardware designers decide what are the basic hardware
constructs to include in the design (adders, logic gates...) and how to connect them.
Those hardware blocks will be there all the time, and the connection is fix
too. In contrast a software designer needs to build efficient programs
to be executed by one or more Von Neumann CPUs.


[^1]: Multi-threaded CPUs are just an array of Von Neumann machines.


## Optimization knobs

Programming hardware and software is all about solving a problem to meet some
performance/power/cost constrains using the available resources. The difference
is that the resources in hardware and software are not the same. In software
there are instructions, in hardware there are cells[^2]. This results in
different optimization knobs.


When designing an efficient software program, it is all about deciding the
sequence of instructions to be small and fast. The computer architecture Iron's
law summarizes it well. The performance is "Instruction Count" x "Instructions
Per Cycle" x "Frequency". Since software programmers do not tend to consider
frequency, it is all about executing the fewer number of instructions and doing
each instruction as fast as possible. The software designer has to create a
sequence of instructions that will solve a problem. Those instructions could
use resources like memory.


For most hardware designers, instead of instructions, they have hardware blocks
or cells like adders, multiplexors, flops, SRAMs... There is no central
resources like memory, and they have to consider frequency.


Like a software designer, the hardware designer needs to solve a problem, but
instead of selecting a sequence of instructions, the designer select the cells
or hardware blocks, connected them, and divide them in smaller pipeline stages
to have a high frequency. A design with a small number of cells that can
achieve the desired frequency is a good hardware design[^3]. So it is all about
instantiating blocks and connecting them.


In hardware there are two big categories of blocks: Combinational and
Sequential. Combinational do not have clock and perform operations like adding,
and, xor... Sequential have a clock.  The clock is used to remember a value,
hence the output of a sequential block can remember the value of previous
cycles while combinational blocks have no memory or clock concept.


The hardware blocks are physical, as such, they need some time to generate a
valid output given a change in their inputs. When combinational blocks are
connected together, their maximum speed or frequency can be decided by finding
the slowest path in the combinational blocks connected together. This
means that to achieve higher frequency, combinational blocks should be
separated by sequential blocks. This is called pipelining. There are overheads
of adding more sequential blocks, and the hardware designer needs to find the
correct balance given a set of constrains like area/frequency/power.


A big effort in hardware design goes to pipelining. Not only to find the correct
spot separating combinational blocks, but because the sequential block adds a
concept of "state" or memory. Starting from a working combination block, and
adding some "sequential" blocks randomly is extremely likely to result in an
incorrect result. Pipelining not only adds the conceptual problem that adding
sequential blocks changes the semantics but that ALL the combinational
blocks should have more or less the same frequency. Otherwise, the pipeline
design is unbalanced[^4] and the overall frequency is decided by the slowest
pipeline.


The pipelining optimization concept is very different from the software
optimization.  In software, designers care about the average. If a function is
slow and its execution requires half of the execution time, reducing the
function by half should have a 25\% performance improvement. The designer does
not need to improve very infrequently used functions. In hardware, designers
care about worst case. If a pipeline stage is slow, improving it will result in
a frequency improvement if it was the slowest, and the benefit will be just the
difference with the next slower pipeline stage, not the optimization on the
pipeline itself.


The result is that hardware and software designers need to worry about
different constrains like pipelining. Combinined with the fact that hardware
optimizations need to care about worst case, not average, it is common for
hardware designers to say that design hardware is hard.

[^2]: In this document we call cells any logic gate or flop or memory array.

[^3]: There are other constrains like power, but the same idea/problem could be said
for software design.

[^4]: Unbalance pipelines have higher overheads in power/area.


## HLS vs HDL


Hardware designers also use programming languages to specify their FPGA/ASIC
design. In the past, designers "draw" the transistor/cells/gates and had a more
visual layout to see/place where each combination and sequential block was
located. Although it is possible to do a design in such a way, it is not as
productive as using some hardware design language.


There are many popular software languages like C++, Java, Rust, swift... There
are also several hardware design languages, but they tend to fall in two
categories: HLS (High Level Synthesis) or HDLs (Hardware Description
Languages). HLS can be languages like a subset of C or Rust. The HDLs are
languages like Verilog, CHISEL, or Pyrope.


In a nutshell, HLS tries to leverage the larger Von Neumann community
(languages and humans that know to to program Von Neumann) and use compilers to
transform to efficient hardware mappings that are not Von Neumann.


As such HLS have to deal with constructs like loops and central memory. The
typical solution for loops is to use heuristics and/or directives to split the
loops in different pipeline stages. The typical solution for global memory is
to just not use it or put directives to guide them. Other constructs like
memory allocation and recursion are also avoided in HLS. When a C program is
translated to hardware, if it has pointers and uses memory, it needs directives
to indicate where the memory resides and mark potential overlap or pointer
aliasing between pointers. Otherwise, the generated translation is likely to be
inefficient.


HDLs (Hardware Description Languages) do not have a Von Neumann model. The
currently most popular HDL (Verilog) is a data flow language that does not have
a global program counter like Von Neumann languages. Instead the programmer
specifies a hierarchy of modules[^5], and then each module/function
instantiated is executed every cycle. In Verilog, the execution of each module
has a complicated set of options, but from a high level point of view, a set of
statements are executed in each module. The module executes forever being
called once each cycle.


The rest of the document assumes an HDL model, and goes over their generic
characteristics without going to specific language syntax.


[^5]: Verilog modules could be seen as functions in a software language.

## HDLs

HDLs different from software languages in that they specify a tree hierarchy of
modules, and then provide some syntax on how each module executes every cycle.


All software languages have a "main" or starting point of execution. The "main" may
call several functions which can iterate in loops, and the program finishes execution
when the main finishes. Most HDLs are different.


In HDLs the there is a "top" or entry point which provides a tree-like structure
of module instantiations. Each module has a set of statements that execute
every cycle. It resembles a bit an actor model. An actor being a module with
individual execution, but there are many differences like the tree structure of
instantiations, and the incapacity to spawn new actors. Maybe more important
key concept of actors is the blocking on message reads.  Although it is
possible to build an HLS around the actor model, popular HDLs do not.



## Hardware artifacts


In this document, a hardware artifact is a "strange" or "unexpected" behavior
for a reasonable software programmer. It is not a lack of feature in a language
like not having recursion or not having type checking or some strange syntax.
An artifact is some strange behavior different from the typical software
languages.



### Hierarchy calls

In hardware, there is a "top" or function that represents the entry point, but the
entry point is selected by some flags at compile time. It is not a language reserved
keyword.

In most HDLs like CHISEL and Verilog, the tree hierarchy is fixed. This makes
sense from a hardware point of view[^6], but this means that a module can not
be called inside a control flow statement. E.g: this code sequence is not what
a software programmer may expect:


=== "Problematic code"

    ```pyrope
    var result
    if some_opcode {
      result = do_division(a,b)
    }else{
      result = do_multiplication(a,b)
    }
    ```

=== "HLS possible solution"

    ```pyrope
    var result
    result1 = do_division(enable=some_opcode, a,b)
    result2 = do_multiplication(enable=!some_opcodea,b)
    if some_opcode {
      result = result1
    }else{
      result = result2
    }
    ```


A programmer will expect that function do_division and do_multiplication will
be instantiated, and called only if the some_opcode condition is true or false.
In hardware, both modules will be instantiated. This means that the previous
code sequence will instantiate both modules in the hierarchy. The challenge is
that many HDLs do not allow such syntax unless the function is inlined and
hence, no module is generated. The reason is that if some statement like a
`print` is inside the do_division module, the programmer will not expect a
print of the message unless the do_division is true. The fact that the module
is always instantiated, and the module always executes breaks this expected
assumption. This can be seen as a hardware artifact.


The solution to the hierarchy call artifact is that most HDLs tend to convert
to explicitly call the functions all the time, and adding an enable if there
is any side effect inside.

!!! Artifact

    Function calls inside control flow statements are either not allowed or forced to be inlined.

[^6]: new transistors can not be added at runtime.

### Pipelining


Each module function is called every cycle. Instantiated modules in the
hierarchy tree are called every cycle. This could be seen as if the "top" or
entry point is called each cycle. In a way, the whole program executes every
cycle if we ignore reset and intialization state. 


The artifact comes that calling a module or function can return the results
from previous cycle calls. To illustrate the problem, imagine a multiplier
function (mult) that takes 1 cycles to produce the results, and the programmer
has an assertion checking that it was a multiply. The result `c` is not the
current cycle `a*b` but the last cycle `a` multiplied by last cycle `b`. This
is not what would be expected in a normal software API.


=== "Problematic code"

    ```pyrope
    c = mul(a,b)
    assert c == a * b // assert fails!!
    ```

=== "HLS possible solution"

    ```pyrope
    c = mul(a,b)
    assert c == a#[-1] * b#[-1] // read last cycle #[-1] a and b
    ```

!!! Artifact

    Function results can be from other cycles


### Simulation vs Synthesis


Hardware designs tend to have extensive verification infrastructures. The
reason is that once the chip is fabricated it can not be easily be patched like
software. It may need to trash millions of dollars and take months to get the
next chip even for just a line of code patch. This is not different from software,
it is just that the cost of a bug could be potentially much higher.


The difference from software is that the "simulation" results used for
verification may be different from the hardware results generated during
"synthesis".


A mismatch between synthesis and simulation could happen due to script
directives in the synthesis scripts, or due to use language features that only
affect simulation.

=== "Problematic code"

    ```verilog
    initial begin // initial code may not be used in synthesis
       c = 3;
    end

    #3 d = 4; // delay simulation update, not synthesis update
    case (x)  // synthesis: full_case, parallel_case
    ...
    ```

=== "HLS possible solution"

    ```verilog
    // Do allow simulation code to have side-effects to synthesis code
    // Any directive should affect simulation AND synthesis (not one or the other)

    unique case(x) // do not use synthesis only directives
    ...
    ```


!!! Artifact

    Simulation and synthesis results can have different functionality



### Reset


Programmers are used to initialize their variables. Since the modules are
called every cycle, the typical software syntax for intialization does not
work. To make it worse, some languages like Verilog (and others) have two
initializations: reset and simulation setup.


Some differences between reset and software initialization:

* Reset can take many cycles
* Reset can be called many times
* Reset vs variable initialization in some languages (Verilog)

=== "Problematic code"

    ```verilog
    initial begin
       d = 1;
    end
    always @(posedge clk) begin
       if (reset) begin
         d = 2;
    ...
    ```

=== "HLS possible solution"

    ```verilog
    // Just use the reset flop values to initialize contents

    always @(posedge clk) begin
       if (reset) begin
         d = 2;
    ...
    ```

!!! Artifact

    Reset is different from variable initialization

### Non-blocking assignments


Many HDLs have what hardware designers call "non blocking assignments". The idea
is that in hardware, when assigning a variable the designer could think about
the "result at the end of this cycle" rather "update this mutable variable".

Technically, a non blocking assignment is an assignment to a variable but the
variable will be updated only at the end of the cycle. To illustrate the
concept, imagine a counter. The counter can be updated with a non-blocking
assignment, and following statements could still read the value before the
scheduled update.


=== "Problematic code"

    ```verilog
    counter <- counter + 1  // non-blocking assignment
    tmp     <- counter + 2  // non-blocking assignment
    assert tmp == (counter+1) // this may FAIL!
    ```

=== "HLS possible solution"

    ```pyrope
    // Do not use non-blocking
    counter = counter + 1  // blocking assignment
    tmp     = counter + 2  // blocking assignment
    assert tmp == (counter+1) // this never fails
    ```

!!! Artifact

    Some HDLs support non-blocking assignments which are not found in software.

### Invalid code


HDLs can generate invalid code that can not be fabricated or it is strongly recommended
to not be fabricated. Examples are:

* Combinational loops. Creating a loop with combinational logic is generally
  consider a bug (only few circuits could accept this). If the combinational
  loop is inside a mux, it can be difficult to catch during verification unless a
  good toggle coverage results.

* Implicit latches. Some HDLs like Verilog can generate code with implicit
  latches. Since the module is execute each time, variables with a missing
  initialization can remember results from last cycles generating implicit
  latches. Most ASIC tools do not accept this and it is considered a bug.

* Bogus flow. Any compile (software or hardware) can have bugs, but because
  hardware compilers tend to have a smaller user base, they they to have more
  bugs than typical software compilers. Since this cost of fixing a bug is also
  higher, the solution is to have an additional verification or logical
  equivalence test.


In software flows, if the compile generates an executable, it is considered a
good executable unless invalid assembly directives are used. In some HDLs this
is not the case, and some constructs like combinational loops can happen in
most HDLs.


!!! Artifact

    HDLs can generate invalid synthesis and/or simulation code.


### Multi value logic


Software designers are used to binary numbers with 0s and 1s. In many HDLs
there are more than 2 possible stages for each bit. In languages like Verilog
there are 4 states: `0`, `1`, `?` or `z`. Where `?` is a "quantum" like state
indicating that it is both zero and one at the same time, and the `z` is to
indicate that it is in "high impedance" which means that nobody is writing the
value. Some languages like VHDL have even more states.


The challenge is that when running code, the result may be unexpected. There
are many discussion on how to address that the community calls "x-propagation". 
There is not an agreement on the best solution. The reason for not removing `?`
is that some large structures will not be initialized because they are very large,
some engineers like the `?` to allow more freedom to the synthesis tools[^7]


There are 3 main solutions categories:

* Allow `?` and run many simulation with different x-propagation rules.
* Allow `?` and randomly pick 0/1 for each `?` bit at simulation time.
* Do not allow `?`.

=== "Problematic code"

    ```verilog
    x = 0b?   // a ? state
    if x {
       puts "x is never true"
    }
    reg signed [3:0] a = -1;
    $display("%b\n", a[5:1]); // displays xx111
    ```

=== "HLS possible solution"

    ```verilog
    // there is no agreement on the community, but possible solutions:
    x = 0b? // (1): compile error
    if x {  // (2): randomly pick 1 or 0
    }
    reg signed [3:0] a = -1;
    $display("%b\n", a[5:1]); // displays 11111 (sign extend)
    ```

[^7]: This is very controversial and many companies coding style do not allow
  the use of `?` to improve synthesis results.


!!! Artifact

    HDLs can operate over non-binary logic


## Simpler HDL constructs

Not everything is harder in HDLs when compared with typical programming
languages. These are some differences that can make the HDLs simpler:


### Unlimited precision


High performance software must adjust to the hardware and as such, there are
several integer types (int, short, long).  The result is that the programmer
tends to be careful with overflows and type conversion. This is not a problem
in hardware. If a 113 bits adder is needed, it can be synthesized. If only an 7
bits adder is needed, the synthesis can create the smaller adder too.

Some HLS may have different integer sizes, but it is either a "strange" design decision
or just as a type check so that no unnecessary hardware is generated.


### No pointers

Memory and pointer management is a big issue in most languages. Either garbage
collect, manual, or alternative approaches.  Since there is no global memory,
there are no memory to manage. Maybe even more important, there is no need for
pointers. This avoid another set of problems like null dereferencing.


### Pass by value

Most software languages support to pass function arguments either by value or
reference. This is done to avoid copying the object that may reside in memory.
Again, HLS have no memory, therefore it is not as problematic. 

Most HDLs only support passing by value. This is not a drawback but avoid
another source of bugs without the cost overhead that it will represent in a
Vonn Neumann machine.


### No recursion

Most HDLs support recursion at compile time, but not at runtime. The reason is
that there is no "stack memory". It is possible to support run-time recursion
if the depth is bound, but it would be "strange" because of the potentially
large combinational path.  Only manageable with retiming. As a result, most
HDLs do not support runtime recursion.



