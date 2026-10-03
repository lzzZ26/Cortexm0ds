// axi_master_vip.v : AXI主设备VIP（Verilog-2001 task级）
// 用法：先填 vip_wdata[0..len]，再调 axi_wr；axi_rd 结果读 vip_rdata
// 注意：SEL 输出供从机直测（恒1）；接仲裁器主口时 SEL 悬空即可
// 握手实现：地址通道由task置VALID后，以"每沿握手采样always块"的标志推进
//          （从机READY常高/节流均无死锁）；W数据通道由always块逐拍驱动
//          （task仅填队列+发go），数据推进与调度顺序无关。
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

  // ---- 握手采样：每沿锁存（VALID&&READY）；读数据随握手锁存供task取用 ----
  reg        aw_hs, b_hs, ar_hs, r_hs;
  reg [31:0] r_latch;
  always @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      aw_hs <= 1'b0; b_hs <= 1'b0; ar_hs <= 1'b0; r_hs <= 1'b0; r_latch <= 32'h0;
    end else begin
      aw_hs <= AW_VALID && AW_READY;
      b_hs  <= B_VALID  && B_READY;
      ar_hs <= AR_VALID && AR_READY;
      r_hs  <= R_VALID  && R_READY;
      if (R_VALID && R_READY) r_latch <= R_DATA;
    end
  end

  // ---- W通道驱动器：task填w_q后置w_go（本块启动时自清，NBA同批无竞争）----
  reg [31:0] w_q [0:255];
  reg [7:0]  w_idx, w_total;
  reg        w_go;
  always @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      W_VALID <= 1'b0; W_DATA <= 32'h0; W_LAST <= 1'b0;
      w_idx <= 8'd0; w_total <= 8'd0; w_go <= 1'b0;
    end else begin
      if (w_go && !W_VALID) begin                    // 启动新burst
        w_go <= 1'b0;
        W_VALID <= 1'b1; w_idx <= 8'd0;
        W_DATA <= w_q[0]; W_LAST <= (w_total == 8'd0);
      end else if (W_VALID && W_READY) begin         // 逐拍推进
        if (w_idx == w_total) begin
          W_VALID <= 1'b0;
        end else begin
          w_idx <= w_idx + 8'd1;
          W_DATA <= w_q[w_idx + 8'd1];
          W_LAST <= (w_idx + 8'd1 == w_total);
        end
      end
    end
  end

  // 复位态：VALID/SEL 全低，READY 全高
  initial begin
    AW_SEL=0; AW_VALID=0; AW_SIZE=0; AW_BURST=0; AW_LEN=0; AW_ADDR=0;
    B_READY=1;
    AR_SEL=0; AR_VALID=0; AR_SIZE=0; AR_BURST=0; AR_LEN=0; AR_ADDR=0;
    R_READY=1;
    w_go=0;
  end

  // 写：AW握手 -> 队列装载+W突发 -> B
  task axi_wr(input [31:0] addr, input [7:0] len, input [1:0] burst, input [2:0] size);
    integer i;
    begin
      @(posedge ACLK);
      aw_hs = 1'b0; AW_SEL = 1'b1; AW_VALID = 1'b1;
      AW_ADDR = addr; AW_LEN = len; AW_BURST = burst; AW_SIZE = size;
      while (!aw_hs) @(posedge ACLK);
      AW_VALID = 1'b0; AW_SEL = 1'b0;
      for (i = 0; i <= len; i = i + 1) w_q[i] = vip_wdata[i];
      w_total = len;
      @(posedge ACLK);
      w_go = 1'b1;
      while (!b_hs) @(posedge ACLK);
      if (B_RESP != 2'b00) $display("VIP: 写响应错误 BRESP=%b @%0t", B_RESP, $time);
    end
  endtask

  // 读：AR握手 -> 逐拍收R（数据经r_latch锁存，与调度顺序无关）
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
