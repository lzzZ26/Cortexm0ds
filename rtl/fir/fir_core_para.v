// fir_core_para.v : 通用全并行FIR核（合规基本架构主核，2026-10-19计划任务20）
// 结构：82深移位寄存器 + 82个独立系数寄存器（任意非对称系数）+ 82个16×16
//       乘法并行 + 加法树流水（82→41→21→11→6→3→2→1）。
// 与fir_core_sym同构（照抄其成熟流水/反压/饱和结构），差异：无预加器、
// 系数全82独立（对称核只认0..40）、多一级加法树、新增clr输入。
// 吞吐：1样本/拍（任意系数，非对称不降级——答疑#18合规主路径）。
// 定点：乘积 Q2.30(32bit)扩展至40bit；82项和 Q10.30(40bit)；
//       输出 Q1.31 = 和×2 取低32位（{acc[30:0],1'b0}）；
//       溢出判据：acc[39:30]≠符号扩展（|v|≥1）→ 饱和（82项可超±4，
//       必须查满[39:30]，只查[39:38]会漏判——与fir_core同口径）。
// 反压（T13裁决）：stall=dout_valid&&!dout_ready冻结整条流水+din_ready=!stall；
//       释放沿同值带valid重放一拍（下游满条件挡住重放拍，不得清valid）。
// clr（设计决策1）：1拍脉冲清移位寄存器+流水线（系数保持——切换模式后
//       系数一致由cfg广播保证，clr不清系数）。
`timescale 1ns/1ps
module fir_core_para #(
    parameter TAPS = 82,
    parameter CW   = 16,
    parameter DW   = 16
)(
    input  wire        ACLK,
    input  wire        ARESETn,
    input  wire        clr,                // 1拍脉冲：清移位寄存器+流水线
    input  wire        cfg_we,             // 系数配置写使能
    input  wire [9:0]  cfg_addr,           // 系数序号 0..81（全82，任意非对称）
    input  wire [CW-1:0] cfg_wdata,
    input  wire        din_valid,
    output wire        din_ready,          // =!stall
    input  wire [DW-1:0] din,
    output reg         dout_valid,
    input  wire        dout_ready,
    output reg  [31:0] dout
);
  reg [DW-1:0] x [0:TAPS-1];
  reg [CW-1:0] c [0:TAPS-1];
  // 注意：必须声明为signed——累加表达式含无符号操作数时整个表达式
  // （含乘法）按无符号求值（Verilog-2001规则，fir_core实测陷阱）
  reg signed [39:0] p1 [0:TAPS-1];         // 16×16乘积→40bit符号扩展 Q2.30
  reg signed [39:0] p2 [0:40];             // 82→41
  reg signed [39:0] p3 [0:20];             // 41→21
  reg signed [39:0] p4 [0:10];             // 21→11
  reg signed [39:0] p5 [0:5];              // 11→6
  reg signed [39:0] p6 [0:2];              // 6→3
  reg signed [39:0] p7 [0:1];              // 3→2
  reg signed [39:0] p8;                    // 2→1
  reg [9:0]  vpipe;                        // valid流水（10拍：数据9拍+1拍x滞后补偿）
  integer    i;

  // 饱和：Q10.30累加值 → Q1.31（=a×2取低32位；acc[39:30]≠符号扩展即溢出）
  function [31:0] sat31; input [39:0] a;
    begin
      if (a[39] == 1'b0 && a[38:30] != 9'h000)      sat31 = 32'h7FFFFFFF;
      else if (a[39] == 1'b1 && a[38:30] != 9'h1FF) sat31 = 32'h80000000;
      else                                          sat31 = {a[30:0], 1'b0};
    end
  endfunction

  // 输出反压：dout_valid=1且下游满（!dout_ready）时冻结整条流水——
  // vpipe/x/p各级/dout全部保持，din_ready拉低让上游扣住样本（T13裁决，
  // 无反压则fir_top满时丢输出、输出流跳拍错位）。
  wire stall = dout_valid && !dout_ready;
  assign din_ready = !stall;

  always @(posedge ACLK) begin
    if (!ARESETn) begin
      for (i = 0; i < TAPS; i = i + 1) x[i] <= {DW{1'b0}};
      for (i = 0; i < TAPS; i = i + 1) c[i] <= {CW{1'b0}};
      for (i = 0; i < TAPS; i = i + 1) p1[i] <= 40'sd0;
      for (i = 0; i < 41;   i = i + 1) p2[i] <= 40'sd0;
      for (i = 0; i < 21;   i = i + 1) p3[i] <= 40'sd0;
      for (i = 0; i < 11;   i = i + 1) p4[i] <= 40'sd0;
      for (i = 0; i < 6;    i = i + 1) p5[i] <= 40'sd0;
      for (i = 0; i < 3;    i = i + 1) p6[i] <= 40'sd0;
      for (i = 0; i < 2;    i = i + 1) p7[i] <= 40'sd0;
      p8 <= 40'sd0; vpipe <= 10'd0; dout_valid <= 1'b0; dout <= 32'd0;
    end else begin
      // 系数（反压冻结/clr不影响配置）
      if (cfg_we && (cfg_addr < TAPS)) c[cfg_addr] <= cfg_wdata;
      if (clr) begin
        // 设计决策1：清移位寄存器+流水线（系数保持）
        for (i = 0; i < TAPS; i = i + 1) x[i] <= {DW{1'b0}};
        for (i = 0; i < TAPS; i = i + 1) p1[i] <= 40'sd0;
        for (i = 0; i < 41;   i = i + 1) p2[i] <= 40'sd0;
        for (i = 0; i < 21;   i = i + 1) p3[i] <= 40'sd0;
        for (i = 0; i < 11;   i = i + 1) p4[i] <= 40'sd0;
        for (i = 0; i < 6;    i = i + 1) p5[i] <= 40'sd0;
        for (i = 0; i < 3;    i = i + 1) p6[i] <= 40'sd0;
        for (i = 0; i < 2;    i = i + 1) p7[i] <= 40'sd0;
        p8 <= 40'sd0; vpipe <= 10'd0; dout_valid <= 1'b0; dout <= 32'd0;
      end else if (stall) begin
        ; // 冻结：dout_valid=1保持、dout保持、整条流水保持（不消费din）
      end else begin
        // 数据移位
        if (din_valid) begin
          for (i = TAPS-1; i > 0; i = i - 1) x[i] <= x[i-1];
          x[0] <= din;
        end
        // 流水（非阻塞链；p1的x滞后1拍由vpipe多1拍补偿——同sym核T8裁决）
        for (i = 0; i < TAPS; i = i + 1)
          p1[i] <= $signed(x[i]) * $signed(c[i]);
        for (i = 0; i < 41; i = i + 1) p2[i] <= p1[2*i] + p1[2*i+1];
        for (i = 0; i < 20; i = i + 1) p3[i] <= p2[2*i] + p2[2*i+1];
        p3[20] <= p2[40];
        for (i = 0; i < 10; i = i + 1) p4[i] <= p3[2*i] + p3[2*i+1];
        p4[10] <= p3[20];
        for (i = 0; i < 5;  i = i + 1) p5[i] <= p4[2*i] + p4[2*i+1];
        p5[5] <= p4[10];
        p6[0] <= p5[0] + p5[1];
        p6[1] <= p5[2] + p5[3];
        p6[2] <= p5[4] + p5[5];
        p7[0] <= p6[0] + p6[1];
        p7[1] <= p6[2];
        p8 <= p7[0] + p7[1];
        dout <= sat31(p8);
        vpipe <= {vpipe[8:0], din_valid};
        // 数据dout在T+10可见，valid必须同沿置位——vpipe[8]对应T+9沿
        // （比sym核多一级加法树，vpipe[7]→[8]），用vpipe[9]会晚一拍，
        // 连续进样时dout已被下一拍覆盖（输出整体错位——T8裁决同机理）。
        // 反压释放沿会把同一dout值带valid重放一拍（p8冻结一拍）：
        // 下游满条件挡住重放拍（若在此清valid，连续流会被误清——
        // 每两个输出丢一个，T13实测）。
        dout_valid <= vpipe[8];
      end
    end
  end
endmodule
