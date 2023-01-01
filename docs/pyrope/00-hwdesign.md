
# Hardware Design

Most language manuals/guides do not include a chapter on "what is
programming?", but Pyrope is a hardware description language or HDL.  This
document is a guideline for hardware design for software designers. The idea is
to be high level to explain the differences without going to syntactic details
in different languages.


## No Von Neumann


Most software programming languages are built to program Von Neumann CPUs. When
dealing with single-threaded code, the programmer has a sequence of "commands"
or "statements" specified in a programming language. The machine executes one
of those statements after another. There are "control flow" instructions to
select what is the following statement to execute.


Potentially more restricting, software languages have a central or distributed
"memory" concept where program data resides. For single-threaded code, there
tends to be a main unified memory.


Current CPUs follow a Von Neumann approach[^1]. Languages designed to program
CPUs have the same model to map existing hardware efficiently. Since the
languages are Von Neumann, it is logical that CPUs also evolve to keep the same
model and further improve the performance. Since CPUs and languages follow the
same Von Neumann model, software designers' mindset assumes this same concept.
This feedback loop has resulted in most languages, hardware, and developers
evolving around this model.


Neither FPGAs nor ASICs is Von Neumann machines. There is no program counter to
execute one statement after another, and there is no central memory. Those
concepts could be built on top, and this is in fact what CPUs are about. CPUs
are all about making efficient Von Neumann machines on top of FPGAs and/or
ASICs given some power/area/performance constraints.



To design a CPU or any hardware without a Von Neumann model, the standard
concepts that all languages use of main memory or single-threaded execution do
not make much sense. The reason is that the cells available in hardware are
always there. The result can be used or not, but it is always there.


At a high level, hardware designers decide the basic hardware constructs to
include in the design (adders, logic gates...) and how to connect them. Those
hardware blocks will be there all the time, and the connection is fixed too. In
contrast, a software designer needs to build efficient programs for one or more
Von Neumann CPUs.


[^1]: Multi-threaded CPUs are just an array of Von Neumann machines.


## Optimization knobs

Programming hardware and software are all about solving a problem to meet some
performance/power/cost constraints using the available resources. The
difference is that the resources in hardware and software are not the same. In
software, there are instructions; in hardware, there are cells[^2]. This
results in different optimization knobs.


Designing an efficient software program is all about deciding the sequence of
instructions to be small and fast. The computer architecture Iron's law
summarizes it well. The performance is "Instruction Count" x "Instructions Per
Cycle" x "Frequency". Since software programmers do not tend to consider the
frequency, it is all about executing fewer instructions and doing each
instruction as fast as possible. The software designer has to create a sequence
of instructions to solve a problem. Those instructions could use resources like
memory.


Instead of instructions, most hardware designers have hardware blocks or cells
like adders, multiplexors, flops, SRAMs... There are no central resources like
memory, and they have to consider frequency.


Like a software designer, the hardware designer needs to solve a problem.
Still, instead of selecting a sequence of instructions, the designer selects
the cells or hardware blocks and their interconnection. The designer divides
problems into smaller pipeline stages to have a high frequency. A design with
small cells that can achieve the desired frequency is an exemplary hardware
design[^3]. So it is all about instantiating blocks and connecting them.


In hardware, there are two big categories of blocks: Combinational and
Sequential. Combinational do not have a clock and perform operations like
adding, and, xor... Sequential has a clock.  The clock is used to remember a
value. Hence the output of a sequential block retains or memoizes the value of
previous cycles while combinational blocks have no memory or clock concept.


The hardware blocks are physical devices that need time to generate a valid
output given a change in their inputs. When combinational blocks are connected,
their maximum speed or frequency can be decided by finding the slowest path in
the combinational blocks connected. This means that sequential blocks should
separate combinational blocks to achieve higher frequency. This is called
pipelining. There are overheads of adding more sequential blocks, and the
hardware designer needs to find the correct balance given a set of constraints
like area/frequency/power.


A significant effort in hardware design goes to pipelining. Not only to find
the correct spot separating combinational blocks but because the sequential
block adds a concept of "state" or memory. Starting from a working combination
lock and randomly adding some "sequential" blocks is highly likely to generate
an incorrect result. Pipelining adds the conceptual problem that adding
sequential blocks changes the semantics and that ALL the combinational blocks
should have more or less the same frequency. Otherwise, the pipeline design is
unbalanced[^4], and the slowest pipeline decides the overall frequency.


The pipelining optimization concept is very different from software
optimization.  In software, designers care about the average. If a function is
slow and its execution requires half of the execution time, reducing by half
should have a 25% performance improvement. The designer does not need to
improve very infrequently used functions. In hardware, designers care about the
worst case. If a pipeline stage is slow, improving it will result in a
frequency improvement if it was the slowest. The benefit will be just the
difference with the next slower pipeline stage, not optimizing the pipeline
itself.


The result is that hardware and software designers need to worry about
different constraints like pipelining. Combined with the fact that hardware
optimizations need to care about the worst case, not average, it is common for
hardware designers to say that designing hardware is hard.

[^2]: In this document, we call any logic gate, flop, or memory array.

[^3]: There are other constraints like power, but the same idea/problem could
  be said for software design.

[^4]: Unbalance pipelines have higher overheads in power/area.


## HLS vs. HDL


Hardware designers also use programming languages to specify their FPGA/ASIC
design. In the past, designers "drew" the transistor/cells/gates and had a more
visual layout to see/place where each combination and the sequential block was
located. Although it is possible to do a design in such a way, it is not as
productive as using some hardware design language.


There are many popular software languages like C++, Java, Rust, swift... There
are also several hardware design languages, but they tend to fall into two
categories: HLS (High-Level Synthesis) or HDLs (Hardware Description
Languages). HLS can be languages like a subset of C or Rust. The HDLs are
languages like Verilog, CHISEL, or Pyrope.


In a nutshell, HLS tries to leverage the larger Von Neumann community
(languages and humans that know to program Von Neumann) and use compilers to
transform to efficient hardware mappings that are not Von Neumann.


HLS has to deal with constructs like loops and central memory. The typical
solution for loops is to use heuristics and/or directives to split the loops
into different pipeline stages. The standard solution for global memory is not
to use it or put compiler directives to guide them. Other constructs like
memory allocation and recursion are also avoided in HLS. When a C program is
translated to hardware, if it has pointers and uses memory, it needs directives
to indicate where the memory resides and mark potential overlap or pointer
aliasing between pointers. Otherwise, the generated translation is likely to be
inefficient.


HDLs (Hardware Description Languages) do not have a Von Neumann model. The
currently most popular HDL (Verilog) is a data flow language that does not have
a global program counter like Von Neumann languages. Instead, the programmer
specifies a hierarchy of modules[^5]. In Verilog, the execution of each module
has a complicated set of options, but from a high-level point of view, a group
of statements is executed in each module. The module executes forever because
it is a set of gates instantiated in the hardware design.


[^5]: Verilog modules could be seen as functions in a software language that
  can be instantiated in one or more places. The instantiation point sets a
  hierarchy of modules.


## Hardware artifacts


This section goes over several of the leading hardware artifacts that tend to
be exist in most HDLs independent of the syntax.


### Instantiation vs execution


Hardware designers decide the gates are instantiated[^5a] in the design, while
software designers focus on executing the instructions. If a set of gates is
rarely used, the hardware still has to instantiate them, and their performance
area impact is independent of the usage frequency. In software, a set of seldom
executed instructions have no performance impact. This is not the case in
hardware. As such, languages build around "instantiation" more than traditional
instruction execution.


[^5a]: Instantiation is the process of deciding which gates are fabricated or
  mapped in a given hardware design. In an ASIC, it is the process of selecting
  a set of gates that will be manufactured.


Instantiation means that the designer explicitly indicates the gates or
circuits mapped to hardware. In the vast majority of HDLs (Verilog, CHISEl,
pyRTL, VHDL...), the designer specifies a top-level module. Each module can
have a set of gates and more instantiated sub-modules.



In "software," languages have a "main" or starting execution point. The "main"
executes or calls several functions depending on the data. Functions can
iterate in loops, and the program finishes execution when the main finishes.


In contrast, most HDLs differ from software languages in that they specify an
instantiation tree hierarchy of modules, and then provide some syntax on how
each module executes independently of the other modules. 


In HDLs, the execution never ends, and the modules run independently. It
resembles a bit of an actor model. An actor is a module with individual
execution, but there are many differences like the tree structure of
instantiations and the incapacity to spawn new actors. Although it is possible
to build an HLS around the actor model without spawning capability, popular
HDLs do not.


In most HDLs, the instantiated tree hierarchy is fixed. This makes sense from a
hardware point of view[^6], but this means that a module can not be called
inside a control flow statement. A common mistake from designers learning HDLs
is to call a module conditionally. E.g., this code sequence is not what a
software programmer may expect:


=== "Problematic code"

    ```pyrope
    var result = 0
    if some_opcode {
      result = do_division(a,b)
    }else{
      result = do_multiplication(a,b)
    }
    ```

=== "Possible solution"

    ```pyrope
    var result = 0
    var result1 = do_division(a,b)
    var result2 = do_multiplication(a,b)
    if some_opcode {
      result = result1
    }else{
      result = result2
    }
    ```


A software programmer thinks about executing instructions. The previous syntax
looks like execute or call `do_division` when `some_opcode` is true, but it is
impossible to do in most HDLs because they are centered around instantiation,
not execution. For synthesizable code, none of the most popular HDLs like
Verilog, VHDL, CHISEL, pyRTL allow the instantiation of a module in a
conditional. Some like Verilog have `functions` but those are inlined. When
called, they can be seen as a macro preprocessor that inserts the function
statements.


HDLs force the designer to spicy the instantiation unconditionally, and then
the `if` selects between the instantiations. Even though HDLs look like they
execute instructions, they do not; it is all about cell instantiation and how
to connect those instances. The `if` is not a branch instruction, it is a
multiplexor instantiation. The `do_division` is not a function call; it
instantiates a circuit or module.


!!! Artifact

    Function calls inside control flow statements are either not allowed or
    forced to be inlined.


!!! Artifact

    HDLs look like instruction execution, but they are about circuit
    instantiation.

[^6]: Transistors can not be added at runtime.

### Pipelining


Pipelining is adding registers in combinational circuits to create smaller
critical paths and hence higher frequency designs. It is essential to hardware
design, and there is not much related to it in software design flows.


To illustrate the problem, imagine a pipelined multiplier function (mult) that
takes one cycle to produce the results, and the programmer has an assertion
checking that it was a multiply. The result `c` is not the current cycle `a*b`
but the last cycle `a` multiplied by the last cycle `b`. This is not what would
be expected in a software API.


=== "Problematic code"

    ```pyrope
    var c = mul(a,b)
    assert c == a * b // assert fails!!
    ```

=== "HLS possible solution"

    ```pyrope
    var c = mul(a,b)
    assert c == a#[-1] * b#[-1] // read last cycle #[-1] a and b
    ```

If actors execution resembles concurrent module instantiation execution,
async/await resembles pipelining. In async/await, the results of a function are
not available at the function return. In HDLs, there is no await, and the
results from previous cycles are output by the module instance. 



Pipelining is not restricted to just function or module instantiations. A the
module itself can have a set of registers, and different variables/wires have
the results from different cycles. It is up to the designer to manage it, and
it is one of the primary complexity sources of hardware design and
verification.


!!! Artifact

    Different variables or wires can have results from other cycles due to
    pipelining.


### Simulation vs synthesis


Hardware designs tend to have extensive verification infrastructures. The
reason is that once the chip is fabricated, it can not be easily be patched
like software. It may need to trash millions of dollars and take months to get
the next chip, even for just a line of code patch. This is not different from
software; it is just that the cost of a bug could be potentially much higher.


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

    ```Verilog
    // Do allow simulation code to have side-effects on synthesis code
    // directives affect simulation AND synthesis (not one or the other)

    unique case(x) // do not use synthesis only directives
    ...
    ```


!!! Artifact

    Simulation and synthesis results can have different functionality



### Reset


Programmers are used to initializing their variables. Since the modules are
called every cycle, the typical software syntax for initialization does not
work. To make it worse, some languages like Verilog (and others) have two
initializations: reset and simulation setup.


Some differences between reset and software initialization:

* Reset can take many cycles
* Reset can be called many times
* Reset vs. variable initialization in some languages (Verilog)

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

    ```Verilog
    // Just use the reset flop values to initialize contents

    always @(posedge clk) begin
       if (reset) begin
         d = 2;
    ...
    ```

!!! Artifact

    Reset is different from variable initialization

### Non-blocking assignments


Many HDLs have what hardware designers call "non-blocking assignments". The idea
is that in hardware, when assigning a variable, the designer could think about
the "result at the end of this cycle" rather than "update this mutable variable".

Technically, a nonblocking assignment is an assignment to a variable, but the
variable will be updated only at the end of the cycle. To illustrate the
concept, imagine a counter. The counter can be updated with a non-blocking
assignment and following statements could still read the value before the
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


HDLs can generate invalid code that can not be fabricated, or it is strongly
recommended not to be fabricated. Examples are:

* Combinational loops. Creating a loop with combinational logic is generally
  considered a bug (only a few circuits could accept this). If the
  combinational loop is inside a mux, it can be difficult to catch during
  verification unless a good toggle coverage results.

* Implicit latches. Some HDLs like Verilog can generate code with implicit
  latches. Since the module is executed each time, variables with a missing
  initialization can remember results from the last cycles generating implicit
  latches. Most ASIC tools do not accept this, and it is considered a bug.

* Bogus flow. Any compile (software or hardware) can have bugs, but because
  hardware compilers tend to have a smaller user base; they have more bugs than
  typical software compilers. Since this cost of fixing a bug is also higher,
  the solution is to have an additional verification or logical equivalence
  test.


If the compile generates an executable in software flows, it is considered a
valid executable unless invalid assembly directives are used. In most HDLs,
this is not the case due to constructs like combinational loops.


!!! Artifact

    HDLs can generate invalid synthesis and/or simulation code.


### Multi value logic


Software designers are used to binary numbers with 0s and 1s. In many HDLs,
there are more than two possible states for each bit. In languages like
Verilog, there are four states: `0`, `1`, `?` or `z`. Where `?` is a "quantum"
like state indicating that it is both zero and one simultaneously, and the `z`
indicates that it is in high impedance, which means that nobody is writing the
value. Some languages like VHDL have even more states.


The challenge is that when running code, the result may be unexpected. There
are many discussions on addressing what the community calls "x-propagation."
There is no agreement on the best solution. The reason for not removing `?` is
that some large structures will not be initialized because of overheads.
Although widely considered dangerous, some engineers like the `?` to allow more
freedom to the synthesis tools[^7]


There are three leading solutions categories:

* Allow `?` and run many simulations with different x-propagation rules.
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

[^7]: This is very controversial, and many companies coding styles do not allow
  the use of `?` to improve synthesis results.


!!! Artifact

    HDLs can operate over non-binary logic


## Simpler HDL constructs

Not everything is more challenging in HDLs when compared with software programming
languages. These are some differences that can make the HDLs simpler:


### Unlimited precision


High-performance software must adjust to the hardware, and as such, there are
several integer types (int, short, long).  The result is that the programmer
tends to be careful with overflows and type conversion. This is not a problem
in hardware. If a 113 bits adder is needed, it can be synthesized. If only a 7
bits adder is required; the synthesis can create the smaller adder too.

Some HLS may have different integer sizes, but it is either a "strange" design
the decision or just as a type check so that no unnecessary hardware is generated.


Overflow is a source of many subtle bugs. For example, experience programmers
write `a + (b-a))/2` not the expected `(a+b)/2` because of integer overflow
semantics. HDLs can handle this like unlimited precision scripting languages
without the overhead.


### No pointers

Memory and pointer management is big issue in most languages. Either garbage
collection, manual, or alternative approaches.  Since there is no global
memory, there is no memory to manage. Maybe even more important, there is no
need for pointers. This avoids another set of problems like null dereferencing.

### No destructors

Since there is no global memory, there is no need to have garbage collection or
the associated object destruction. If a "hardware resource" is utilized, it can
not be recycled. As a result, the destructor may not make sense in hardware.


### Pass by value

Most software languages support passing function arguments either by value or
reference. This is done to avoid copying the object that may reside in memory.
Again, HLS has no memory. Therefore it is not as problematic. 

Most HDLs only support passing by value. This is not a drawback but avoid
another source of bugs without the cost overhead that it will represent in a
Vonn Neumann machine.


### No recursion

Most HDLs support recursion at compile-time but not at runtime. The reason is
that there is no "stack memory". If the depth is bound, it can support run-time
recursion, but the potentially sizeable combinational path would be "strange".
Only manageable with retiming. As a result, most HDLs do not support runtime
recursion.


