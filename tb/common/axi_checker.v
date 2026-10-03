// axi_checker.v : AXI协议检查器。挂在主口上，违规即打印并置位 violation
// 检查：信号稳定（VALID等待期间不得变）、burst长度≤15、4KB边界、
//       W_LAST/R_LAST时序、burst类型。
// 实现要点：每个事务（AW/AR握手）复位本通道计数与锁存；稳定性检查按
//          "VALID=1&&READY=0的首拍锁存、后续拍比对"（跨事务不残留）。
`timescale 1ns/1ps
module axi_checker(
    input  wire        ACLK, ARESETn,
    input  wire        AW_VALID, AW_READY, input wire [2:0] AW_SIZE,
    input  wire [1:0]  AW_BURST, input wire [7:0] AW_LEN, input wire [31:0] AW_ADDR,
    input  wire        W_VALID, W_READY, input wire [31:0] W_DATA, input wire W_LAST,
    input  wire        B_VALID, B_READY, input wire [1:0] B_RESP,
    input  wire        AR_VALID, AR_READY, input wire [2:0] AR_SIZE,
    input  wire [1:0]  AR_BURST, input wire [7:0] AR_LEN, input wire [31:0] AR_ADDR,
    input  wire        R_VALID, R_READY, input wire [31:0] R_DATA,
    input  wire [1:0]  R_RESP, input wire R_LAST,
    output reg         violation
);
  reg [31:0] aw_a; reg [2:0] aw_s; reg [1:0] aw_b; reg [7:0] aw_l;
  reg [31:0] ar_a; reg [2:0] ar_s; reg [1:0] ar_b; reg [7:0] ar_l;
  reg [31:0] w_d;  reg [7:0] w_cnt;  reg w_active; reg w_pend;
  reg [31:0] r_d;  reg [7:0] r_cnt;  reg r_active; reg r_pend;

  task fail; input [255:0] msg; begin
    violation <= 1'b1;
    $display("CHECKER VIOLATION @%0t: %0s", $time, msg);
  end endtask

  function [7:0] bytes_per_beat; input [2:0] sz; begin
    bytes_per_beat = (8'b1 << sz);
  end endfunction

  always @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      violation <= 0; w_active <= 0; r_active <= 0; w_cnt <= 0; r_cnt <= 0;
      w_pend <= 0; r_pend <= 0;
      aw_a <= 0; aw_s <= 0; aw_b <= 0; aw_l <= 0;
      ar_a <= 0; ar_s <= 0; ar_b <= 0; ar_l <= 0; w_d <= 0; r_d <= 0;
    end else begin
      // ---- 写地址通道 ----
      if (AW_VALID && !AW_READY) begin
        if (!w_pend) begin                       // 等待期首拍：锁存
          w_pend <= 1'b1;
          aw_a <= AW_ADDR; aw_s <= AW_SIZE; aw_b <= AW_BURST; aw_l <= AW_LEN;
        end else begin                           // 后续拍：必须稳定
          if (aw_a != AW_ADDR || aw_s != AW_SIZE || aw_b != AW_BURST || aw_l != AW_LEN)
            fail("AW信号在等待期间变化");
        end
      end else if (AW_VALID && AW_READY) begin
        aw_a <= AW_ADDR; aw_s <= AW_SIZE; aw_b <= AW_BURST; aw_l <= AW_LEN;
        if (AW_LEN > 8'd15) fail("AWLEN>15");
        if (AW_BURST != 2'b00 && AW_BURST != 2'b01) fail("burst类型非FIXED/INCR");
        // 4KB边界
        if ((AW_LEN + 8'd1) * bytes_per_beat(AW_SIZE) > (32'h1000 - AW_ADDR[11:0]))
          fail("写burst跨4KB边界");
        w_active <= 1'b1; w_pend <= 1'b0; w_cnt <= 8'd0;   // 新事务复位计数
      end else begin
        w_pend <= 1'b0;
      end
      // ---- 写数据通道 ----
      if (w_active) begin
        if (W_VALID && !W_READY) begin
          if (!w_pend) begin
            w_pend <= 1'b1; w_d <= W_DATA;
          end else if (w_d != W_DATA) begin
            fail("W信号在等待期间变化");
          end
        end else if (W_VALID && W_READY) begin
          w_pend <= 1'b0;
          w_d <= W_DATA;
          if (w_cnt != aw_l && W_LAST) fail("W_LAST提前出现");
          if (w_cnt == aw_l && !W_LAST) fail("W_LAST缺失");
          if (w_cnt == aw_l) w_active <= 1'b0;
          else w_cnt <= w_cnt + 8'd1;
        end
      end
      // ---- 读地址通道 ----
      if (AR_VALID && !AR_READY) begin
        if (!r_pend) begin
          r_pend <= 1'b1;
          ar_a <= AR_ADDR; ar_s <= AR_SIZE; ar_b <= AR_BURST; ar_l <= AR_LEN;
        end else begin
          if (ar_a != AR_ADDR || ar_s != AR_SIZE || ar_b != AR_BURST || ar_l != AR_LEN)
            fail("AR信号在等待期间变化");
        end
      end else if (AR_VALID && AR_READY) begin
        ar_a <= AR_ADDR; ar_s <= AR_SIZE; ar_b <= AR_BURST; ar_l <= AR_LEN;
        if (AR_LEN > 8'd15) fail("ARLEN>15");
        if (AR_BURST != 2'b00 && AR_BURST != 2'b01) fail("burst类型非FIXED/INCR");
        if ((AR_LEN + 8'd1) * bytes_per_beat(AR_SIZE) > (32'h1000 - AR_ADDR[11:0]))
          fail("读burst跨4KB边界");
        r_active <= 1'b1; r_pend <= 1'b0; r_cnt <= 8'd0;
      end else begin
        r_pend <= 1'b0;
      end
      // ---- 读数据通道 ----
      if (r_active) begin
        if (R_VALID && !R_READY) begin
          if (!r_pend) begin
            r_pend <= 1'b1; r_d <= R_DATA;
          end else if (r_d != R_DATA) begin
            fail("R信号在等待期间变化");
          end
        end else if (R_VALID && R_READY) begin
          r_pend <= 1'b0;
          r_d <= R_DATA;
          if (r_cnt != ar_l && R_LAST) fail("R_LAST提前出现");
          if (r_cnt == ar_l && !R_LAST) fail("R_LAST缺失");
          if (r_cnt == ar_l) r_active <= 1'b0;
          else r_cnt <= r_cnt + 8'd1;
        end
      end
    end
  end
endmodule
