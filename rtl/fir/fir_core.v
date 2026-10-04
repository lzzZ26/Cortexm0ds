// fir_core.v : 82抽头串行FIR核（基线版）
// 结构：数据移位寄存器(82x16) + 系数寄存器(82x16可配置) + 单MAC时间复用
// 定点：输入/系数 Q1.15；乘积 Q2.30（32bit），82项累加40位Q10.30无损；
//       输出 Q1.31 = 累加值×2 取低32位（{acc[30:0],1'b0}）；
//       溢出判据：acc[39:30]≠符号扩展（|v|≥1）→ 饱和到 Q1.31 边界。
// 性能：82拍/样本、1个乘法器（资源下限参考版）；并行版见 fir_core_sym.v
`timescale 1ns/1ps
module fir_core #(
    parameter TAPS = 82,
    parameter CW   = 16,
    parameter DW   = 16
)(
    input  wire        ACLK,
    input  wire        ARESETn,
    // 系数配置（任意时刻可写）
    input  wire        cfg_we,
    input  wire [9:0]  cfg_addr,
    input  wire [CW-1:0] cfg_wdata,
    // 数据流
    input  wire        din_valid,
    output wire        din_ready,
    input  wire [DW-1:0] din,
    output reg         dout_valid,
    input  wire        dout_ready,
    output reg  [31:0] dout
);
  reg [DW-1:0] x [0:TAPS-1];
  reg [CW-1:0] c [0:TAPS-1];
  reg [6:0]    ph;         // 0..TAPS-1 乘加相位
  reg          busy;
  // 注意：必须声明为signed——累加表达式含无符号操作数时整个表达式
  // （含乘法）按无符号求值（Verilog-2001规则）
  reg signed [39:0] acc;   // Q10.30（82项Q2.30之和）
  integer      i;

  // 饱和：Q10.30 -> Q1.31（=acc×2取低32位；acc[39:30]≠符号扩展即溢出）
  function [31:0] sat; input [39:0] a;
    begin
      if (a[39] == 1'b0 && a[38:30] != 9'h000)      sat = 32'h7FFFFFFF;
      else if (a[39] == 1'b1 && a[38:30] != 9'h1FF) sat = 32'h80000000;
      else                                          sat = {a[30:0], 1'b0};
    end
  endfunction

  // 系数配置
  always @(posedge ACLK) begin
    if (!ARESETn) begin
      for (i = 0; i < TAPS; i = i + 1) c[i] <= {CW{1'b0}};
    end else if (cfg_we) c[cfg_addr] <= cfg_wdata;
  end

  // 数据通路
  always @(posedge ACLK) begin
    if (!ARESETn) begin
      busy <= 1'b0; ph <= 7'd0; acc <= 40'd0;
      dout_valid <= 1'b0; dout <= 32'd0;
      for (i = 0; i < TAPS; i = i + 1) x[i] <= {DW{1'b0}};
    end else begin
      if (dout_valid && dout_ready) dout_valid <= 1'b0;
      if (busy) begin
        if (ph == TAPS-1) begin
          // 最后一拍：等输出槽空闲再完成（反压无损；acc与本拍乘加项合成输出）
          if (!dout_valid || dout_ready) begin
            busy <= 1'b0;
            dout <= sat(acc + $signed(x[ph]) * $signed(c[ph]));
            dout_valid <= 1'b1;
          end
        end else begin
          acc <= acc + $signed(x[ph]) * $signed(c[ph]);
          ph <= ph + 7'd1;
        end
      end else if (din_valid) begin
        for (i = TAPS-1; i > 0; i = i - 1) x[i] <= x[i-1];
        x[0] <= din;
        acc <= 40'd0;
        ph <= 7'd0;
        busy <= 1'b1;
      end
    end
  end

  assign din_ready = !busy;
endmodule
