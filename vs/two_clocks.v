
module two_clocks(input a, input a_clk, input b, input b_clk, input c, output reg led_on);

reg [7:0] total_a;
reg [7:0] total_b;

always @(posedge a_clk) begin
  if (a) begin
    total_a = total_a + 1;
  end
end

always @(posedge b_clk) begin
  if (b) begin
    total_b = total_b + 1;
  end
end

always_comb begin
  led_on = 0;
  if (c) begin
    led_on = total_a != total_b;
  end
end

endmodule
