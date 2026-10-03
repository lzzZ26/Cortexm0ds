// uart_bfm.v : UART BFM（9600 8N1，与官方retarget默认一致）
`timescale 1ns/1ps
module uart_bfm #(parameter CLK_PERIOD_NS = 20.0, BAUD = 9600)(
    output reg txd, input wire rxd);
  localparam BIT_NS = 1_000_000_000.0 / BAUD;

  task uart_tx(input [7:0] ch);
    integer i;
    begin
      txd = 1'b0;                      // 起始位
      #(BIT_NS);
      for (i = 0; i < 8; i = i + 1) begin
        txd = ch[i];
        #(BIT_NS);
      end
      txd = 1'b1;                      // 停止位
      #(BIT_NS);
    end
  endtask

  task uart_rx(output [7:0] ch);
    integer i;
    begin
      @(negedge rxd);                  // 起始位下降沿
      #(BIT_NS / 2.0);                 // 到起始位中点
      #(BIT_NS);                       // 到bit0中点
      for (i = 0; i < 8; i = i + 1) begin
        ch[i] = rxd;
        #(BIT_NS);
      end
    end
  endtask
endmodule
