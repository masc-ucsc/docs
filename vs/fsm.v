
// Code from UWash CSE370
// https://courses.cs.washington.edu/courses/cse370/10sp/pdfs/lectures/15-VerilogIIPrint.pdf

module edge_detector ( input in , output out , input clk );
localparam A =0 , B =1 , C =2;

reg [1:0] state , // Current state
  nextState ; // Next state

always @ ( posedge clk ) begin
  if ( reset ) begin
    state <= A ; // Initial state
  end else begin
    state <= nextState ;
  end
end

always @ (*) begin
  nextState = state ;
  out = 0;
  case ( state )
    A : if ( in ) nextState = C ;
    else nextState = B ;
    B : if ( in ) begin
      out = 1;
      nextState = C ;
    end
    C : if (~ in ) begin
      out = 1;
      nextState = B ;
    end
    default : begin
      out = 1 ’ bX ;
      nextState = 3 ’ bX ;
    end
  endcase
end
endmodule

//---------------

let edge_detector = proc(in:bool)->(out:bool) {

  reg last_in = in

  out = last_in != in

  last_in = in
}

let edge_detector = proc(in:bool)->(out:bool) {
  out = in#[-1] != in
}

