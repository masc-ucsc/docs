module top(input a, input b, output c, output d);

wire tmp;
wire bar;

sub1 i1(a, tmp, bar, b);
sub2 i2(c, tmp, bar, d);

endmodule

