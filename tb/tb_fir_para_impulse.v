// tb_fir_para_impulse.v : Q18验收波形——通用并行核 + 冲激响应
// 默认非对称系数；可用参数切对称系数（tb_fir_para_impulse_sym包装）。
// 原理：输入首样本为冲激 0x7FFF、其后为 0；FIR 前 82 个输出即冲激响应，
//       应逐个等于 c[n]×0x7FFF（Q1.31）——对称系数左右镜像、非对称明显不同。
// 自检：前82个输出与 golden 前82行**逐位相等**（单乘积精确）。
`timescale 1ns/1ps
module tb_fir_para_impulse #(
  parameter COEFF_FILE  = "tb/data/coeff_asym_q15.hex",
  parameter GOLDEN_FILE = "tb/data/golden_asym_q31.hex",
  parameter VCD_FILE    = "sim_out/q18_impulse.vcd",
  parameter CSV_FILE    = "sim_out/q18_impulse.csv",
  parameter TAG         = "asym"
);
  wire clk, rstn;
  reg  clr;
  reg  cfg_we; reg [9:0] cfg_addr; reg [15:0] cfg_wdata;
  reg  din_valid; wire din_ready; reg [15:0] din;
  wire dout_valid; reg dout_ready; wire [31:0] dout;

  reg [15:0] coeff [0:81];
  reg [31:0] golden [0:1023];
  integer n, out_cnt, err_cnt, fd;
  reg [31:0] cap [0:127];

  tb_clkreset #() u_ck (.clk(clk), .rstn(rstn));

  fir_core_para #(.TAPS(82), .CW(16), .DW(16)) u_fir (
    .ACLK(clk), .ARESETn(rstn), .clr(clr),
    .cfg_we(cfg_we), .cfg_addr(cfg_addr), .cfg_wdata(cfg_wdata),
    .din_valid(din_valid), .din_ready(din_ready), .din(din),
    .dout_valid(dout_valid), .dout_ready(dout_ready), .dout(dout));

  initial begin
    $readmemh(COEFF_FILE, coeff);
    $readmemh(GOLDEN_FILE, golden);
  end

  // VCD：只dump本TB顶层信号（clk/din/dout/valid/clr/cfg），GTKWave直接可看
  initial begin
    $dumpfile(VCD_FILE);
    $dumpvars(1, tb_fir_para_impulse);
  end

  initial begin
    clr = 0; cfg_we = 0; cfg_addr = 0; cfg_wdata = 0;
    din_valid = 0; din = 0; dout_ready = 1;
    out_cnt = 0; err_cnt = 0;
    wait (rstn == 1'b1);
    // 配置82个非对称系数（每项2沿保持，NBA脉冲）
    for (n = 0; n < 82; n = n + 1) begin
      @(negedge clk);
      cfg_we = 1; cfg_addr = n[9:0]; cfg_wdata = coeff[n];
      @(negedge clk);
      cfg_we = 0;
    end
    // CLR（NBA，避免与核always的delta竞争）
    @(negedge clk); clr <= 1'b1;
    @(negedge clk); clr <= 1'b0;
    // 冲激 + 81个零（82样本），negedge驱动保证posedge稳定
    for (n = 0; n < 82; n = n + 1) begin
      @(negedge clk);
      din_valid = 1;
      din = (n == 0) ? 16'h7FFF : 16'h0000;
    end
    @(negedge clk); din_valid = 0;
    // 排空
    wait (out_cnt >= 82);
    repeat (20) @(posedge clk);

    // 写CSV供绘图
    fd = $fopen(CSV_FILE, "w");
    $fdisplay(fd, "n,y_q31");
    for (n = 0; n < 82; n = n + 1)
      $fdisplay(fd, "%0d,%08X", n, cap[n]);
    $fclose(fd);

    // 自检：前82个输出与golden_asym前82行逐位相等
    for (n = 0; n < 82; n = n + 1)
      if (cap[n] !== golden[n]) begin
        $display("MISMATCH n=%0d hw=%h ref=%h", n, cap[n], golden[n]);
        err_cnt = err_cnt + 1;
      end
    if (out_cnt != 82) $fatal(1, "FAIL: 输出数=%0d（应82）", out_cnt);
    if (err_cnt != 0) $fatal(1, "FAIL: 冲激响应与golden不符 %0d处", err_cnt);
    $display("PASS Q18波形[%0s]: 82抽头冲激响应与golden逐位相等", TAG);
    $display("y[0]=%h  y[40]=%h  y[81]=%h", cap[0], cap[40], cap[81]);
    $display("VCD=%0s  CSV=%0s", VCD_FILE, CSV_FILE);
    $finish;
  end

  always @(posedge clk) begin
    if (dout_valid && dout_ready) begin
      if (out_cnt < 128) cap[out_cnt] = dout;
      out_cnt = out_cnt + 1;
    end
  end

  initial begin
    #5000000 $fatal(1, "FAIL: Q18波形仿真超时");
  end
endmodule
