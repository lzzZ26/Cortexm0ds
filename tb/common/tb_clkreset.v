// tb_clkreset.v : 50MHz时钟与复位
`timescale 1ns/1ps
module tb_clkreset #(parameter HALF_PERIOD_NS = 10.0)(
    output reg clk, output reg rstn);
  initial begin clk = 1'b0; forever #(HALF_PERIOD_NS) clk = ~clk; end
  initial begin
    rstn = 1'b0;
    #(100 * 2 * HALF_PERIOD_NS) rstn = 1'b1;   // 5个周期后释放
  end
endmodule
