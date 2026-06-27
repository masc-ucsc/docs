# Introduction

!!!WARNING
    This document explains the future Pyrope, some features are still not implemented. They are documented to guide the designers.

Pyrope is a modern hardware description language, with these focus points:

* Fast parallel and incremental elaboration
* Modern and concise language
* Avoiding hardware specific artifacts
    - Allows optional hierarchical [calls](00-hwdesign.md#instantiation-vs-execution)
    - Supports [instantiation](00-hwdesign.md#instantiation-vs-execution) optimization with typical software syntax
    - Supports [pipelining](00-hwdesign.md#pipelining) constructs
    - No mismatch [simulation vs synthesis](00-hwdesign.md#simulation-vs-synthesis)
    - Single [reset](00-hwdesign.md#reset) mechanism
    - Avoid [non-blocking](00-hwdesign.md#non-blocking-assignments) assignments
    - Checks on [invalid code](00-hwdesign.md#invalid-code)
    - Random on [multi value logic](00-hwdesign.md#multi-value-logic) when doing control flow
* Zero cost abstraction
* Help hardware verification:
    - Powerful type system
    - Hot-Reload support, powerful assertions
    - Allows Pyrope 2 Verilog, edit Verilog, Verilog 2 Pyrope, edit Pyrope...
    - Static checks as long as they not produce false positives

## Hello world

Create a directory for the project:
```bash
$ mkdir hello
$ cd hello
$ mkdir src
```

Populate the Pyrope code

`src/hello.prp`
```pyrope
test hello.world {
  puts("hello world")
}
```

Run
```bash
$ lhd sim src/hello.prp
```

All the pyrope files reside in the `src` directory. The `lhd sim` command calls LiveHD to
elaborate the pyrope files and run all the tests in the given file.


## Trivial GCD

Populate the Pyrope code

=== "Pyrope"

    src/gcd.prp:
    ```pyrope linenums="1"
    mod gcd(a:u32, b:u32) -> (reg result:u32@[0]) {
      reg x = a
      reg y = b

      if y != 0 {
        result = nil
        if x > y {
          x -= y
        } else {
          y -= x
        }
      }else{
        result = x // Unset nil
      }
    }

    type GcdModel = ( gcd: comb(v1:u32, v2:u32) -> (r:u32) )
    const gold:GcdModel = cpp("my_cpp_gcd")

    for a in 1..=100 {
      for b in 1..=100 {
        test gcd.check {
          const z = gcd(a, b)

          mut z_valid = z.[valid]
          waitfor(ref z_valid)

          assert(z == gold.gcd(v1=a, v2=b))
        }
      }
    }
    ```

    src/my_cpp_gcd.cpp
    ```c++ linenums="25"
    struct my_cpp_gcd {
      Slop<32> gcd(const Slop<32>& v1, const Slop<32>& v2) {
        auto x = v1;
        auto y = v2;
        while (y.is_known_true()) {            // y != 0
          if (x.gt_op(y).is_known_true()) {    // x > y
            x = x.sub_op(y);
          } else {
            y = y.sub_op(x);
          }
        }
        return x;                              // single output → bare Slop<32>
      }
    };
    ```

=== "CHISEL"

    ```scala linenums="1"
    import Chisel._
    import firrtl_interpreter.InterpretiveTester
    import org.scalatest.{Matchers, FlatSpec}

    object GCDCalculator {
      def computeGcd(a: Int, b: Int): (Int, Int) = {
        var x = a
        var y = b
        while(y > 0 ) {
          if (x > y) {
            x -= y
          }
          else {
            y -= x
          }
        }
        x
      }
    }

    class GCD extends Module {
      val io = new Bundle {
        val a  = UInt(INPUT,  16)
        val b  = UInt(INPUT,  16)
        val e  = Bool(INPUT)
        val z  = UInt(OUTPUT, 16)
        val v  = Bool(OUTPUT)
      }
      val x  = Reg(UInt())
      val y  = Reg(UInt())
      when   (x > y) { x := x - y }
      unless (x > y) { y := y - x }
      when (io.e) { x := io.a; y := io.b }
      io.z := x
      io.v := y === UInt(0)
    }

    class InterpreterUsageSpec extends FlatSpec with Matchers {

      "GCD" should "return correct values for a range of inputs" in {
        val s = Driver.emit(() => new GCD)

        val tester = new InterpretiveTester(s)

        for {
          i <- 1 to 100
          j <- 1 to 100
        } {
          tester.poke("io_a", i)
          tester.poke("io_b", j)
          tester.poke("io_e", 1)
          tester.step()
          tester.poke("io_e", 0)

          while (tester.peek("io_v") != BigInt(1)) {
            tester.step()
          }
          tester.expect("io_z", BigInt(GCDCalculator.computeGcd(i, j)._1))
        }
        tester.report()
      }
    }
    ```


Run
```bash
$ lhd sim gcd.prp gcd.check
```

The `gcd.prp` includes the top-level module (`gcd`) and the unit test.


* Some Pyrope features not common in other HDLs (CHISEL):

    - Pyrope is not a DSL. Most modern HDLs like CHISEL, pyMTL, pyRTL, CλaSH
      are DSL cases. In these cases, there is a host language (SCALA, or Python,
      or Haskell) that must be executed. The result of the execution is the hardware
      description which can be Verilog or some internal IR like FIRRTL in CHISEL.
      The advantage of the DSL is that it can leverage the existing language to
      have a nice hardware generator. The disadvantage is that there are 2 languages
      at once, the DSL and the host language, and that it is difficult to do
      incremental because the generated executable from the host language must be
      executed to generate the design.


    - Global type inference. In the gcd example, the input/outputs are
      inferred.

    - Synthesizable object system with runtime polymorphism

    - Immutable objects

    - Language support for several hardware constructs

* Some Pyrope features not common in other languages

    - No object references, only pass by value

    - Pipelining support

