// tb_fir_core_para.v : 通用全并行FIR黄金回归+吞吐+CLR+cfg验证
// 用例A 对称系数集黄金回归（82全写，与sym核同口径）；
// 用例B 非对称随机系数黄金回归（任意非对称——本任务核心证明）；
// 用例C 大系数集（直流增益≈61，饱和路径+钳位计数断言）；
// 用例D 吞吐断言（连续段输出间隔恒1拍=1样本/拍）；
// 用例E 中途CLR（设计决策1：清移位寄存器+流水线，黄金比对不受污染）；
// 用例F cfg逐系数写（2沿保持——T6裁决）+全零输出+冲激索引+覆盖写回归。
// 反压口径：黄金比对阶段dout_ready恒1（与tb_fir_core_sym同构——本核沿
// sym核结构，反压释放沿同值重放一拍（T13裁决），裸TB消费者无fir_top的
// FIFO满条件挡重放，随机ready会双计/错位输出；重放机制的系统级验证
// 由tb_fir_top/tb_integ承担（任务21/22）——裁决见台账）。
// 输入握手：AXI式valid/ready（valid在ready期间保持，握手完成才推进——
// 反压沿撤valid会丢样本，实测）。
`timescale 1ns/1ps
module tb_fir_core_para;
  wire clk, rstn;
  reg  clr;
  reg  cfg_we; reg  [9:0] cfg_addr; reg  [15:0] cfg_wdata;
  reg  din_valid; wire din_ready; reg  [15:0] din;
  wire dout_valid; reg  dout_ready; wire [31:0] dout;

  reg [15:0] coeff_sym  [0:81];
  reg [15:0] coeff_asym [0:81];
  reg [15:0] coeff_gain [0:81];
  reg [15:0] input_data [0:1023];
  reg [31:0] golden_sym  [0:1023];
  reg [31:0] golden_asym [0:1023];
  reg [31:0] golden_gain [0:1023];
  reg [31:0] golden      [0:1023];     // 当前相黄金（相开始时拷贝）
  reg [31:0] imp_exp     [0:9];        // 冲激索引期望（仅c[7]=0x4000）
  integer n, out_cnt, err_cnt, gap_bad, sat_cnt, zero_err, imp_err;
  reg [63:0] last_valid_cycle;
  reg [2:0] chk_mode;                   // 0=不比对 1=黄金 2=全零 3=冲激索引
  reg       sat_chk, gap_chk;

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

  // 推送驱动器：NBA逐沿推进（T8裁决——阻塞赋值每沿改din会丢首样本）；
  // AXI式握手：valid&&ready同沿完成才推下一拍；反压沿保持valid/din待重发
  reg        push_en;
  integer    push_len;
  integer    push_n;
  always @(posedge clk) begin
    if (push_en && push_n < push_len) begin
      if (din_valid && din_ready) begin
        // 握手完成（核本沿已消费data[push_n]）：推下一拍
        if (push_n + 1 < push_len) begin
          din_valid <= 1'b1;
          din       <= input_data[push_n + 1];
        end else begin
          din_valid <= 1'b0;           // 最后一拍已消费：撤valid
        end
        push_n    <= push_n + 1;
      end else if (!din_valid && din_ready) begin
        // 空闲且可推：呈现当前拍
        din_valid <= 1'b1;
        din       <= input_data[push_n];
      end
      // else: 反压（ready=0）→ valid/din/push_n保持，样本待握手完成
    end else begin
      din_valid <= 1'b0;
    end
  end

  fir_core_para #(.TAPS(82), .CW(16), .DW(16)) u_fir (
    .ACLK(clk), .ARESETn(rstn), .clr(clr),
    .cfg_we(cfg_we), .cfg_addr(cfg_addr), .cfg_wdata(cfg_wdata),
    .din_valid(din_valid), .din_ready(din_ready), .din(din),
    .dout_valid(dout_valid), .dout_ready(dout_ready), .dout(dout));

  // 配置82系数（每项2完整时钟沿——T6裁决）；val0!=0时先写干扰值再写真值
  task cfg_load;
    input [15:0] val0;      // 0=直接写；非0=覆盖写（先干扰后真值）
    input integer which;    // 0=sym 1=asym 2=gain 3=全零
    integer k;
    begin
      for (k = 0; k < 82; k = k + 1) begin
        if (val0 != 16'h0000) begin
          @(posedge clk); cfg_we = 1; cfg_addr = k[9:0]; cfg_wdata = val0;
          @(posedge clk);
        end
        @(posedge clk); cfg_we = 1; cfg_addr = k[9:0];
        case (which)
          0: cfg_wdata = coeff_sym[k];
          1: cfg_wdata = coeff_asym[k];
          2: cfg_wdata = coeff_gain[k];
          default: cfg_wdata = 16'h0000;
        endcase
        @(posedge clk);
      end
      @(posedge clk); cfg_we = 0;
    end
  endtask

  // clr脉冲（1拍，NBA驱动）+比对状态复位（相起始用：清移位寄存器防上相样本污染）
  // 注意：clr必须用非阻塞赋值——若用阻塞赋值在posedge的active区置1/清0，
  // 与核always块在同一沿竞争，调度顺序不利时核整拍采样不到clr=1（实测：
  // 中途CLR用例稳定失败、相位起始do_clr侥幸通过——delta竞争，非RTL缺陷）
  task do_clr;
    begin
      @(posedge clk);               // 收下在途输出（不计入本相）
      clr <= 1'b1;                  // NBA：核在下一沿可靠采样到1
      @(posedge clk);               // clr拍：核内移位寄存器/流水线全清
      clr <= 1'b0;
      @(posedge clk);
      out_cnt = 0; err_cnt = 0;
    end
  endtask

  // 推送len个样本→排空；返回时若out_cnt!=len由调用方判FAIL
  task run_stream;
    input integer len;
    begin
      push_len = len; push_n = 0;
      push_en = 1;
      wait (push_n == len);
      wait (out_cnt >= len);
      repeat (20) @(posedge clk);   // 确认无多余输出
      push_en = 0;
    end
  endtask

  initial begin
    $readmemh("tb/data/coeff_q15.hex", coeff_sym);
    $readmemh("tb/data/coeff_asym_q15.hex", coeff_asym);
    $readmemh("tb/data/coeff_gain_q15.hex", coeff_gain);
    $readmemh("tb/data/input_q15.hex", input_data);
    $readmemh("tb/data/golden_q31.hex", golden_sym);
    $readmemh("tb/data/golden_asym_q31.hex", golden_asym);
    $readmemh("tb/data/golden_gain_q31.hex", golden_gain);
  end

  initial begin
    for (n = 0; n < 10; n = n + 1) imp_exp[n] = 32'h00000000;
    // c[7]=0x4000(0.5) × 冲激0x7FFF(1-2^-15) → Q1.31 = 0x3FFF8000
    imp_exp[7] = 32'h3FFF8000;
  end

  initial begin
    clr = 0;
    cfg_we = 0; cfg_addr = 0; cfg_wdata = 0;
    din_valid = 0; din = 0; dout_ready = 1;
    chk_mode = 0; sat_chk = 0; gap_chk = 0;
    out_cnt = 0; err_cnt = 0; gap_bad = 0; sat_cnt = 0;
    zero_err = 0; imp_err = 0;
    push_en = 0; push_len = 0; push_n = 0;
    last_valid_cycle = 0;
    wait (rstn == 1'b1);
    @(posedge clk);

    // ---- 用例A：对称系数集（82全写）黄金回归 ----
    cfg_load(16'h0000, 0);
    for (n = 0; n < 1024; n = n + 1) golden[n] = golden_sym[n];
    chk_mode = 1;
    do_clr;
    run_stream(1024);
    chk_mode = 0;
    if (out_cnt != 1024) $fatal(1, "FAIL A: 输出不足 %0d/1024", out_cnt);
    if (err_cnt != 0) $fatal(1, "FAIL A: 对称系数黄金回归误差超标 %0d处", err_cnt);
    $display("PASS A: 对称系数黄金回归<0.1%%");
    out_cnt = 0; err_cnt = 0;

    // ---- 用例B：非对称随机系数黄金回归（核心证明） ----
    cfg_load(16'h0000, 1);
    for (n = 0; n < 1024; n = n + 1) golden[n] = golden_asym[n];
    chk_mode = 1;
    do_clr;
    run_stream(1024);
    chk_mode = 0;
    if (out_cnt != 1024) $fatal(1, "FAIL B: 输出不足 %0d/1024", out_cnt);
    if (err_cnt != 0) $fatal(1, "FAIL B: 非对称系数黄金回归误差超标 %0d处", err_cnt);
    $display("PASS B: 非对称随机系数黄金回归<0.1%%");
    out_cnt = 0; err_cnt = 0;

    // ---- 用例C：大系数集（直流增益≈61，饱和路径+钳位断言） ----
    cfg_load(16'h0000, 2);
    for (n = 0; n < 1024; n = n + 1) golden[n] = golden_gain[n];
    chk_mode = 1; sat_chk = 1;
    do_clr;
    run_stream(1024);
    chk_mode = 0; sat_chk = 0;
    if (out_cnt != 1024) $fatal(1, "FAIL C: 输出不足 %0d/1024", out_cnt);
    if (err_cnt != 0) $fatal(1, "FAIL C: 大系数黄金回归误差超标 %0d处", err_cnt);
    if (sat_cnt == 0) $fatal(1, "FAIL C: 饱和路径未被压到（sat_cnt=0）");
    $display("PASS C: 大系数黄金回归<0.1%%（饱和钳位 %0d 处）", sat_cnt);
    out_cnt = 0; err_cnt = 0; sat_cnt = 0;

    // ---- 用例D：吞吐断言（连续段输出间隔恒1拍） ----
    gap_chk = 1;
    do_clr;
    push_len = 1024; push_n = 0; push_en = 1;
    wait (out_cnt >= 1024);
    repeat (20) @(posedge clk);
    push_en = 0; gap_chk = 0;
    if (out_cnt != 1024) $fatal(1, "FAIL D: 输出不足 %0d/1024", out_cnt);
    if (gap_bad != 0) $fatal(1, "FAIL D: 吞吐非1样本/拍（连续段内有输出间隔≠1拍）");
    $display("PASS D: 吞吐=1样本/拍");
    out_cnt = 0;

    // ---- 用例E：中途CLR（设计决策1）——跑一段→clr→全序列黄金不受污染 ----
    cfg_load(16'h0000, 1);
    for (n = 0; n < 1024; n = n + 1) golden[n] = golden_asym[n];
    chk_mode = 1;
    do_clr;
    push_len = 300; push_n = 0; push_en = 1;
    wait (push_n == 300);
    repeat (30) @(posedge clk);       // 排空在途输出
    clr <= 1'b1;                      // NBA（delta竞争，见do_clr注释）
    @(posedge clk);                   // clr拍：核全清
    clr <= 1'b0;
    @(posedge clk);
    out_cnt = 0; err_cnt = 0;         // 中途清零后从头比对
    push_len = 1024; push_n = 0; push_en = 1;
    wait (push_n == 1024);
    wait (out_cnt >= 1024);
    repeat (20) @(posedge clk);
    push_en = 0; chk_mode = 0;
    if (out_cnt != 1024) $fatal(1, "FAIL E: CLR后输出不足 %0d/1024", out_cnt);
    if (err_cnt != 0) $fatal(1, "FAIL E: CLR后黄金比对误差超标 %0d处", err_cnt);
    $display("PASS E: 中途CLR无污染");
    out_cnt = 0; err_cnt = 0;

    // ---- 用例F1：全零系数→输出全零 ----
    cfg_load(16'h0000, 3);
    chk_mode = 2;
    do_clr;
    run_stream(64);
    chk_mode = 0;
    if (out_cnt != 64) $fatal(1, "FAIL F1: 输出不足 %0d/64", out_cnt);
    if (zero_err != 0) $fatal(1, "FAIL F1: 全零系数下输出非零 %0d处", zero_err);
    $display("PASS F1: 全零系数输出全零");
    out_cnt = 0; zero_err = 0;

    // ---- 用例F2：仅写c[7]=0x4000（其余保持0），clr后冲激验证cfg_addr索引 ----
    @(posedge clk); cfg_we = 1; cfg_addr = 10'd7; cfg_wdata = 16'h4000;
    @(posedge clk);
    @(posedge clk); cfg_we = 0;
    chk_mode = 3;
    do_clr;
    run_stream(10);
    chk_mode = 0;
    if (out_cnt != 10) $fatal(1, "FAIL F2: 输出不足 %0d/10", out_cnt);
    if (imp_err != 0) $fatal(1, "FAIL F2: 冲激索引响应错 %0d处", imp_err);
    $display("PASS F2: cfg_addr索引正确（c[7]冲激响应=0x3FFF8000）");
    out_cnt = 0; imp_err = 0;

    // ---- 用例F3：覆盖写（先干扰值0x1234再真值）→黄金回归验证全部落位 ----
    cfg_load(16'h1234, 1);
    for (n = 0; n < 1024; n = n + 1) golden[n] = golden_asym[n];
    chk_mode = 1;
    do_clr;
    run_stream(1024);
    chk_mode = 0;
    if (out_cnt != 1024) $fatal(1, "FAIL F3: 输出不足 %0d/1024", out_cnt);
    if (err_cnt != 0) $fatal(1, "FAIL F3: 覆盖写后黄金回归误差超标 %0d处", err_cnt);
    $display("PASS F3: 覆盖写回归（干扰值→真值全部落位）");
    out_cnt = 0; err_cnt = 0;

    $display("PASS: 通用并行FIR全用例（对称+非对称+大系数+吞吐+CLR+cfg）");
    $finish;
  end

  // 输出收集与比对（dout_ready恒1：无反压重放，计数确定）
  always @(posedge clk) begin
    if (dout_valid && dout_ready) begin
      if (gap_chk && out_cnt > 80 && out_cnt < 1024) begin
        if ($time - last_valid_cycle != 20) gap_bad = 1;
      end
      last_valid_cycle = $time;
      case (chk_mode)
        3'd1: begin
          if (out_cnt < 1024) begin
            if (rel_err(dout, golden[out_cnt]) >= 0.001) begin
              $display("FAIL点位: n=%0d hw=%h ref=%h err=%g", out_cnt, dout,
                       golden[out_cnt], rel_err(dout, golden[out_cnt]));
              err_cnt = err_cnt + 1;
            end
            if (sat_chk && (dout === 32'h7FFFFFFF || dout === 32'h80000000))
              sat_cnt = sat_cnt + 1;
          end
        end
        3'd2: if (dout !== 32'h00000000) begin
          $display("FAIL零输出: n=%0d hw=%h", out_cnt, dout);
          zero_err = zero_err + 1;
        end
        3'd3: if (out_cnt < 10 && dout !== imp_exp[out_cnt]) begin
          $display("FAIL冲激索引: n=%0d hw=%h 期望=%h", out_cnt, dout,
                   imp_exp[out_cnt]);
          imp_err = imp_err + 1;
        end
      endcase
      out_cnt = out_cnt + 1;
    end
  end

  // 超时兜底
  initial begin
    #10000000 $fatal(1, "FAIL: 并行FIR测试超时（10ms）");
  end
endmodule
