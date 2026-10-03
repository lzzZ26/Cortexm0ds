// tb_fir_core.v : FIR核黄金对比测试
// 覆盖：冲激响应==系数（×65534，因Q1.15冲激量化32767）、四段输入全序列误差<0.1%
//      （分母下限0.001满幅）、随机反压、饱和用例
`timescale 1ns/1ps
module tb_fir_core;
  wire clk, rstn;
  reg  cfg_we; reg  [9:0] cfg_addr; reg  [15:0] cfg_wdata;
  reg  din_valid; wire din_ready; reg  [15:0] din;
  wire dout_valid; reg  dout_ready; wire [31:0] dout;

  reg [15:0] coeff [0:81];
  reg [15:0] input_data [0:1023];
  reg [31:0] golden [0:1023];
  reg [31:0] out_q [0:2047];
  integer n, out_cnt, err_cnt;

  real hw_r, ref_r, err, denom;
  function real rel_err; input [31:0] hw; input [31:0] ref;
    real h, r;
    begin
      h = $itor($signed(hw)) / 2147483648.0;
      r = $itor($signed(ref)) / 2147483648.0;
      err = (h >= r) ? (h - r) : (r - h);
      denom = (r < 0.0) ? -r : r;
      if (denom < 0.001) denom = 0.001;     // 分母下限：满幅的0.1%
      rel_err = err / denom;
    end
  endfunction

  tb_clkreset #() u_ck (.clk(clk), .rstn(rstn));

  // 随机反压：每拍3/4概率接受（核在最后一拍停等，反压必须逐拍变化才不饿死）；
  // force_accept=1时强制接受（排空阶段用）
  reg force_accept;
  always @(posedge clk) begin
    dout_ready <= force_accept ? 1'b1 : (($random % 4) != 0);
  end

  fir_core #(.TAPS(82), .CW(16), .DW(16)) u_fir (
    .clk(clk), .rstn(rstn),
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
    din_valid = 0; din = 0; dout_ready = 1; force_accept = 0; out_cnt = 0; err_cnt = 0;
    wait (rstn == 1'b1);
    @(posedge clk);
    // 1) 配置系数（每项保持2个完整时钟沿，与iverilog调度顺序无关）
    for (n = 0; n < 82; n = n + 1) begin
      @(posedge clk);
      cfg_we = 1; cfg_addr = n[9:0]; cfg_wdata = coeff[n];
      @(posedge clk);
    end
    @(posedge clk); cfg_we = 0;
    // 2) 流式送输入（带随机反压与随机停顿；推送2沿保持，等待din_ready电平）
    for (n = 0; n < 1024; n = n + 1) begin
      while (!din_ready) @(posedge clk);
      din_valid = 1; din = input_data[n];
      @(posedge clk);
      @(posedge clk);
      din_valid = 0;
    end
    // 3) 等待收尾（串行核82拍/样本，余量给足）
    force_accept = 1'b1;                     // 排空阶段必须收下全部输出
    repeat (200) @(posedge clk);
    if (out_cnt < 1024) $fatal(1, "FAIL: 输出样本数不足 %0d/1024", out_cnt);
    if (err_cnt != 0) $fatal(1, "FAIL: 误差超标 %0d处", err_cnt);
    // 4) 饱和用例（Review Focus#3）：系数全0x7FFF（直流增益≈41），输入满幅，
    //    输出必须饱和在Q1.31边界，不得回绕
    @(posedge clk);
    for (n = 0; n < 82; n = n + 1) begin
      @(posedge clk); cfg_we = 1; cfg_addr = n[9:0]; cfg_wdata = 16'h7FFF;
      @(posedge clk);
    end
    @(posedge clk); cfg_we = 0;
    for (n = 0; n < 90; n = n + 1) begin
      while (!din_ready) @(posedge clk);
      din_valid = 1; din = 16'h7FFF;
      @(posedge clk);
      @(posedge clk);
      din_valid = 0;
    end
    repeat (200) @(posedge clk);
    if (dout !== 32'h7FFFFFFF) $fatal(1, "FAIL: 饱和用例输出=%h（应=0x7FFFFFFF）", dout);
    $display("PASS: 1024样本误差全部<0.1%% + 饱和用例正确");
    $finish;
  end

  // 输出收集与比对（含冲激段逐系数断言）
  always @(posedge clk) begin
    if (dout_valid && dout_ready) begin
      out_q[out_cnt] = dout;
      // 冲激段：y[n]==c[n]×65534（Q1.15冲激量化32767），与黄金逐值严格相等
      if (out_cnt < 82) begin
        if (dout !== golden[out_cnt])
          $fatal(1, "FAIL: 冲激响应[%0d]=%h 期望=%h", out_cnt, dout, golden[out_cnt]);
      end
      // 全序列相对误差
      if (out_cnt < 1024 && rel_err(dout, golden[out_cnt]) >= 0.001) begin
        $display("FAIL点位: n=%0d hw=%h ref=%h err=%g", out_cnt, dout, golden[out_cnt],
                 rel_err(dout, golden[out_cnt]));
        err_cnt = err_cnt + 1;
      end
      out_cnt = out_cnt + 1;
    end
  end
endmodule
