// axi_master_vip.v : AXI主设备VIP（Verilog-2001 task级）
// 用法：先填 vip_wdata[0..len]，再调 axi_wr；axi_rd 结果读 vip_rdata
// 注意：SEL 输出供从机直测（恒1）；接仲裁器主口时 SEL 悬空即可
// 握手实现：task在时钟沿置VALID后，由独立的握手采样always块把每沿的
//          (VALID&&READY)锁存为标志，task等标志推进。从机READY常高或
//          节流两种情形均无死锁（计划原版"置VALID后立即查READY"在
//          iverilog调度下会在握手沿看到已撤除的READY而死等）。
`timescale 1ns/1ps
module axi_master_vip(
    input  wire        ACLK,
    input  wire        ARESETn,
    // 写地址
    output reg         AW_SEL, AW_VALID,
    input  wire        AW_READY,
    output reg  [2:0]  AW_SIZE,  output reg [1:0] AW_BURST,
    output reg  [7:0]  AW_LEN,   output reg [31:0] AW_ADDR,
    // 写数据
    output reg         W_VALID,  input wire W_READY,
    output reg  [31:0] W_DATA,   output reg W_LAST,
    // 写响应
    input  wire        B_VALID,  output reg B_READY,
    input  wire [1:0]  B_RESP,
    // 读地址
    output reg         AR_SEL, AR_VALID,
    input  wire        AR_READY,
    output reg  [2:0]  AR_SIZE,  output reg [1:0] AR_BURST,
    output reg  [7:0]  AR_LEN,   output reg [31:0] AR_ADDR,
    // 读数据
    input  wire        R_VALID,  output reg R_READY,
    input  wire [31:0] R_DATA,   input wire [1:0] R_RESP,
    input  wire        R_LAST
);
  reg [31:0] vip_wdata [0:255];
  reg [31:0] vip_rdata [0:255];

  // 握手采样：每沿锁存（VALID&&READY）；读数据随握手锁存供task取用
  reg        aw_hs, w_hs, b_hs, ar_hs, r_hs;
  reg [31:0] r_latch;
  always @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      aw_hs <= 1'b0; w_hs <= 1'b0; b_hs <= 1'b0;
      ar_hs <= 1'b0; r_hs <= 1'b0; r_latch <= 32'h0;
    end else begin
      aw_hs <= AW_VALID && AW_READY;
      w_hs  <= W_VALID  && W_READY;
      b_hs  <= B_VALID  && B_READY;
      ar_hs <= AR_VALID && AR_READY;
      r_hs  <= R_VALID  && R_READY;
      if (R_VALID && R_READY) r_latch <= R_DATA;
    end
  end

  // 复位态：VALID/SEL 全低，READY 全高
  initial begin
    AW_SEL=0; AW_VALID=0; AW_SIZE=0; AW_BURST=0; AW_LEN=0; AW_ADDR=0;
    W_VALID=0; W_DATA=0; W_LAST=0;
    B_READY=1;
    AR_SEL=0; AR_VALID=0; AR_SIZE=0; AR_BURST=0; AR_LEN=0; AR_ADDR=0;
    R_READY=1;
  end

  // 写：AW握手 -> 逐拍W -> B
  task axi_wr(input [31:0] addr, input [7:0] len, input [1:0] burst, input [2:0] size);
    integer beat;
    begin
      @(posedge ACLK);
      aw_hs = 1'b0; AW_SEL = 1'b1; AW_VALID = 1'b1;
      AW_ADDR = addr; AW_LEN = len; AW_BURST = burst; AW_SIZE = size;
      while (!aw_hs) @(posedge ACLK);
      AW_VALID = 1'b0; AW_SEL = 1'b0;
      for (beat = 0; beat <= len; beat = beat + 1) begin
        W_VALID = 1'b1; W_DATA = vip_wdata[beat];
        W_LAST  = (beat == len);
        w_hs = 1'b0;
        while (!w_hs) @(posedge ACLK);
      end
      W_VALID = 1'b0;
      while (!b_hs) @(posedge ACLK);
      if (B_RESP != 2'b00) $display("VIP: 写响应错误 BRESP=%b @%0t", B_RESP, $time);
    end
  endtask

  // 读：AR握手 -> 逐拍收R
  task axi_rd(input [31:0] addr, input [7:0] len, input [1:0] burst, input [2:0] size);
    integer beat;
    begin
      @(posedge ACLK);
      ar_hs = 1'b0; AR_SEL = 1'b1; AR_VALID = 1'b1;
      AR_ADDR = addr; AR_LEN = len; AR_BURST = burst; AR_SIZE = size;
      while (!ar_hs) @(posedge ACLK);
      AR_VALID = 1'b0; AR_SEL = 1'b0;
      for (beat = 0; beat <= len; beat = beat + 1) begin
        r_hs = 1'b0;
        while (!r_hs) @(posedge ACLK);
        vip_rdata[beat] = r_latch;
      end
    end
  endtask
endmodule
