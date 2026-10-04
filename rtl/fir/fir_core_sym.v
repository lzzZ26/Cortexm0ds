// fir_core_sym.v : 对称系数并行FIR（决赛性能/创新版，对应"81阶→41次乘加"）
// 线性相位对称系数 c[k]==c[TAPS-1-k]：预加 x[k]+x[81-k]（17位）后乘系数，
// 41个乘法并行 + 加法树流水（41→21→11→6→3→2→1）。
// 吞吐：1样本/拍；输出侧反压（FIFO满时冻结流水、din_ready拉低，无损）。
// 定点：预加 Q2.15(17bit)×系数 Q1.15 → 乘积 Q3.30(33bit)；
//       41项和 Q10.30(40bit)；输出 Q1.31 = 和×2 取低32位；
//       溢出判据：acc[39:30]≠符号扩展（|v|≥1）→ 饱和（与fir_core同口径）。
`timescale 1ns/1ps
module fir_core_sym #(
    parameter TAPS = 82,
    parameter CW   = 16,
    parameter DW   = 16
)(
    input  wire        ACLK,
    input  wire        ARESETn,
    input  wire        cfg_we,
    input  wire [9:0]  cfg_addr,               // 0..40（上半系数；≥41忽略）
    input  wire [CW-1:0] cfg_wdata,
    input  wire        din_valid,
    output wire        din_ready,
    input  wire [DW-1:0] din,
    output reg         dout_valid,
    input  wire        dout_ready,
    output reg  [31:0] dout
);
  localparam H = TAPS / 2;                     // 41
  reg [DW-1:0] x [0:TAPS-1];
  reg [CW-1:0] c [0:H-1];
  reg signed [32:0] p1 [0:H-1];                // 预加×系数 → Q3.30
  reg signed [39:0] p2 [0:20];                 // 41→21
  reg signed [39:0] p3 [0:10];                 // 21→11
  reg signed [39:0] p4 [0:5];                  // 11→6
  reg signed [39:0] p5 [0:2];                  // 6→3
  reg signed [39:0] p6 [0:1];                  // 3→2
  reg signed [39:0] p7;                        // 2→1
  reg [8:0]  vpipe;                            // valid流水（9拍，比数据多1拍补偿x滞后）
  integer    i;

  // 饱和：Q10.30累加值 → Q1.31（=a×2取低32位；acc[39:30]≠符号扩展即溢出）
  function [31:0] sat31; input [39:0] a;
    begin
      if (a[39] == 1'b0 && a[38:30] != 9'h000)      sat31 = 32'h7FFFFFFF;
      else if (a[39] == 1'b1 && a[38:30] != 9'h1FF) sat31 = 32'h80000000;
      else                                          sat31 = {a[30:0], 1'b0};
    end
  endfunction

  // 输出反压：dout_valid=1且下游FIFO满（!dout_ready）时冻结整条流水——
  // vpipe/x/p各级/dout全部保持，din_ready拉低让上游din_fifo扣住样本。
  // 无反压则核继续消费输入而输出被fir_top丢弃（满时丢输出，实测输出流
  // 跳拍错位）。
  wire stall = dout_valid && !dout_ready;
  assign din_ready = !stall;

  always @(posedge ACLK) begin
    if (!ARESETn) begin
      for (i = 0; i < TAPS; i = i + 1) x[i] <= {DW{1'b0}};
      for (i = 0; i < H;    i = i + 1) c[i] <= {CW{1'b0}};
      for (i = 0; i < H;    i = i + 1) p1[i] <= 33'sd0;
      for (i = 0; i < 21;   i = i + 1) p2[i] <= 40'sd0;
      for (i = 0; i < 11;   i = i + 1) p3[i] <= 40'sd0;
      for (i = 0; i < 6;    i = i + 1) p4[i] <= 40'sd0;
      for (i = 0; i < 3;    i = i + 1) p5[i] <= 40'sd0;
      for (i = 0; i < 2;    i = i + 1) p6[i] <= 40'sd0;
      p7 <= 40'sd0; vpipe <= 9'd0; dout_valid <= 1'b0; dout <= 32'd0;
    end else begin
      // 系数（反压冻结不影响配置）
      if (cfg_we && (cfg_addr < H)) c[cfg_addr] <= cfg_wdata;
      if (stall) begin
        ; // 冻结：dout_valid=1保持、dout保持、整条流水保持（不消费din）
      end else begin
        // 数据移位
        if (din_valid) begin
          for (i = TAPS-1; i > 0; i = i - 1) x[i] <= x[i-1];
          x[0] <= din;
        end
        // 流水（非阻塞链；p1的x滞后1拍由vpipe多1拍补偿）
        for (i = 0; i < H; i = i + 1)
          p1[i] <= ($signed(x[i]) + $signed(x[TAPS-1-i])) * $signed(c[i]);
        for (i = 0; i < 20; i = i + 1) p2[i] <= p1[2*i] + p1[2*i+1];
        p2[20] <= p1[40];
        for (i = 0; i < 10; i = i + 1) p3[i] <= p2[2*i] + p2[2*i+1];
        p3[10] <= p2[20];
        for (i = 0; i < 5;  i = i + 1) p4[i] <= p3[2*i] + p3[2*i+1];
        p4[5] <= p3[10];
        for (i = 0; i < 2;  i = i + 1) p5[i] <= p4[2*i] + p4[2*i+1];
        p5[2] <= p4[4] + p4[5];
        p6[0] <= p5[0] + p5[1];
        p6[1] <= p5[2];
        p7 <= p6[0] + p6[1];
        dout <= sat31(p7);
        vpipe <= {vpipe[7:0], din_valid};
        // 注意：数据dout在T+9可见，valid必须同沿置位——vpipe[7]对应T+8沿，
        // 用vpipe[8]会晚一拍，连续进样时dout已被下一拍覆盖（输出整体错位）。
        // 反压释放沿会把同一dout值带valid重放一拍（p7冻结一拍）：fir_top侧
        // 抓取后计数回满、dout_ready落0，重放拍被满条件挡住不会入FIFO
        // （若在此清valid，连续流会被误清——每两个输出丢一个，实测T8回归
        // 512/1024）。
        dout_valid <= vpipe[7];
      end
    end
  end
endmodule
