
// Import the ROHD package
import 'package:rohd/rohd.dart';

// Define a class Counter that extends ROHD's abstract Module class
class Counter extends Module {

  // For convenience, map interesting outputs to short variable names for consumers of this module
  Logic get val => output('val');

  // This counter supports any width, determined at run-time
  final int width;
  Counter(Logic en, Logic reset, Logic clk, {this.width=8, String name='counter'}) : super(name: name) {
    // Register inputs and outputs of the module in the constructor.
    // Module logic must consume registered inputs and output to registered outputs.
    en    = addInput('en', en);
    reset = addInput('reset', reset);
    clk   = addInput('clk', clk);

    var val = addOutput('val', width: width);

    // A local signal named 'nextVal'
    var nextVal = Logic(name: 'nextVal', width: width);

    // Assignment statement of nextVal to be val+1 (<= is the assignment operator)
    nextVal <= val + 1;

    // `Sequential` is like SystemVerilog's always_ff, in this case trigger on the positive edge of clk
    Sequential(clk, [
      // `If` is a conditional if statement, like `if` in SystemVerilog always blocks
      If(reset, then:[
        // the '<' operator is a conditional assignment
        val < 0
      ], orElse: [If(en, then: [
        val < nextVal
      ])])
    ]);
  }
}

//--------------------

let counter = proc(en:bool, width) {
  reg val::[bits=width] uint= 0   // reset and clock name implicit

  val::[wrap] = val + 1 when en

  ret val#[0]  // read val qpin not val din (current)
}


/// Sample usage
test xxx {
  let f = import "xxx_file"

  var val =# f.counter(en=my_enable, width=3)   // =# because the value not combinational from inputs

  assert !my_enable implies val#[1] == val   // value next cycle should be the same
}


