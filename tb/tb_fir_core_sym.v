// tb_fir_core_sym.v : 对称并行FIR黄金回归+吞吐测量
// 断言：1024样本误差<0.1%；连续进样时输出间隔恒为1拍（吞吐=1样本/拍）
`timescale 1ns/1ps
module tb_fir_core_sym;
  wire clk, rstn;
  reg  cfg_we; reg  [9:0] cfg_addr; reg  [15:0] cfg_wdata;
  reg  din_valid; wire din_ready; reg  [15:0] din;
  wire dout_valid; reg  dout_ready; wire [31:0] dout;
  reg  clr;

  reg [15:0] coeff [0:81];
  reg [15:0] input_data [0:1023];
  reg [31:0] golden [0:1023];
  integer n, out_cnt, err_cnt, gap_bad, stall_cnt;
  reg [63:0] last_valid_cycle;
  reg        gap_chk;
  reg        rnd_ready;

  real hw_r, ref_r, denom;
  function real rel_err; input [31:0] hw; input [31:0] ref;
    real h, r;
    begin
      h = $itor($signed(hw)) / 2147483648.0;
      r = $itor($signed(ref)) / 2147483648.0;
      if (h >= r) h = h - r; else h = r - h;
      denom = (r < 0.0) ? -r : r;
      if (denom < 0.001) denom = 0.001;
      rel_err = h / denom;
    end
  endfunction

  tb_clkreset #() u_ck (.clk(clk), .rstn(rstn));

  // 输出反压：rnd_ready=1时每拍3/4概率接受（AXI-Stream语义：输出保持直到
  // 接受，恰好接受一次；接受拍记分板即可）；rnd_ready=0恒接受。
  always @(posedge clk) begin
    dout_ready <= rnd_ready ? (($random % 4) != 0) : 1'b1;
  end

  // 推送驱动器：AXI式握手（valid在!ready期间保持，握手完成才推进；
  // 反压沿撤valid会丢样本——修复前驱动忽略din_ready，反压相位必丢样本）
  reg        push_en;
  integer    push_n;
  always @(posedge clk) begin
    if (push_en && push_n < 1024) begin
      if (din_valid && din_ready) begin
        if (push_n + 1 < 1024) begin
          din_valid <= 1'b1;
          din       <= input_data[push_n + 1];
        end else begin
          din_valid <= 1'b0;
        end
        push_n <= push_n + 1;
      end else if (!din_valid && din_ready) begin
        din_valid <= 1'b1;
        din       <= input_data[push_n];
      end
    end else begin
      din_valid <= 1'b0;
    end
  end

  fir_core_sym #(.TAPS(82), .CW(16), .DW(16)) u_fir (
    .ACLK(clk), .ARESETn(rstn), .clr(clr),
    .cfg_we(cfg_we), .cfg_addr(cfg_addr), .cfg_wdata(cfg_wdata),
    .din_valid(din_valid), .din_ready(din_ready), .din(din),
    .dout_valid(dout_valid), .dout_ready(dout_ready), .dout(dout));

  initial begin
    $readmemh("tb/data/coeff_q15.hex", coeff);
    $readmemh("tb/data/input_q15.hex", input_data);
    $readmemh("tb/data/golden_q31.hex", golden);
  end

  initial begin
    cfg_we = 0; cfg_addr = 0; cfg_wdata = 0;
    din_valid = 0; din = 0; push_en = 0; push_n = 0;
    clr = 0; rnd_ready = 0; gap_chk = 1;
    out_cnt = 0; err_cnt = 0; last_valid_cycle = 0; gap_bad = 0; stall_cnt = 0;
    wait (rstn == 1'b1);
    @(posedge clk);
    // 配置上半系数（仅c[0..40]有效，对称假设；每项2沿保持）
    for (n = 0; n < 41; n = n + 1) begin
      @(posedge clk);
      cfg_we = 1; cfg_addr = n[9:0]; cfg_wdata = coeff[n];
      @(posedge clk);
    end
    @(posedge clk); cfg_we = 0;
    // 相位1：无反压连续流式进样→吞吐断言
    push_en = 1;
    wait (push_n == 1024);
    wait (out_cnt >= 1024);
    repeat (20) @(posedge clk);
    push_en = 0;
    if (out_cnt != 1024) $fatal(1, "FAIL: 输出不足 %0d/1024", out_cnt);
    if (err_cnt != 0) $fatal(1, "FAIL: 误差超标 %0d处", err_cnt);
    if (gap_bad != 0) $fatal(1, "FAIL: 吞吐非1样本/拍（连续段内有输出间隔≠1拍）");
    $display("PASS: 对称并行FIR黄金回归+吞吐=1样本/拍");
    // 相位2：随机输出反压（T13 stall路径；clr清核后重跑，接受拍记分板）
    clr <= 1'b1; @(posedge clk); clr <= 1'b0; @(posedge clk);
    out_cnt = 0; err_cnt = 0; stall_cnt = 0;
    push_n = 0; push_en = 1; rnd_ready = 1; gap_chk = 0;
    wait (push_n == 1024);
    wait (out_cnt >= 1024);
    repeat (20) @(posedge clk);
    push_en = 0; rnd_ready = 0;
    if (out_cnt != 1024) $fatal(1, "FAIL: 反压相位输出数=%0d（应恰好1024）", out_cnt);
    if (err_cnt != 0) $fatal(1, "FAIL: 反压相位误差超标 %0d处", err_cnt);
    if (stall_cnt == 0) $fatal(1, "FAIL: 反压未生效（stall_cnt=0，测试无效）");
    $display("PASS: 对称并行FIR随机反压（stall %0d拍，接受拍记分板全对）", stall_cnt);
    $finish;
  end

  always @(posedge clk) begin
    if (dout_valid && dout_ready) begin
      // 吞吐：连续段内相邻输出间隔必须为1拍（允许流水首尾）
      if (gap_chk && out_cnt > 80 && out_cnt < 1024) begin
        if ($time - last_valid_cycle != 20) gap_bad = 1;
      end
      last_valid_cycle = $time;
      if (out_cnt < 1024 && rel_err(dout, golden[out_cnt]) >= 0.001) begin
        $display("FAIL点位: n=%0d hw=%h ref=%h", out_cnt, dout, golden[out_cnt]);
        err_cnt = err_cnt + 1;
      end
      out_cnt = out_cnt + 1;
    end
    if (dout_valid && !dout_ready) stall_cnt = stall_cnt + 1;
  end

  // 超时兜底
  initial begin
    #10000000 $fatal(1, "FAIL: 对称FIR测试超时（10ms）");
  end
endmodule
