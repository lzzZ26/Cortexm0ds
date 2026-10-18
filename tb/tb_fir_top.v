// tb_fir_top.v : FIR从机测试——系数INCR突发配置、DIN固定地址突发、DOUT固定地址突发读回
// 参数 CORE_TYPE 透传给 fir_top：0=串行（默认，原有单核用例）；
// 3=双核（para+sym 运行时可选，任务21双模用例：默认para非对称/切sym对称/
//   切回para再验/大系数饱和/切换无污染）
`timescale 1ns/1ps
module tb_fir_top #(
  parameter CORE_TYPE = 0
);
  wire ACLK, ARESETn;
  wire AW_SEL, AW_VALID, AW_READY; wire [2:0] AW_SIZE; wire [1:0] AW_BURST;
  wire [7:0] AW_LEN; wire [31:0] AW_ADDR;
  wire W_VALID, W_READY; wire [31:0] W_DATA; wire W_LAST;
  wire B_VALID, B_READY; wire [1:0] B_RESP;
  wire AR_SEL, AR_VALID, AR_READY; wire [2:0] AR_SIZE; wire [1:0] AR_BURST;
  wire [7:0] AR_LEN; wire [31:0] AR_ADDR;
  wire R_VALID, R_READY; wire [31:0] R_DATA; wire [1:0] R_RESP; wire R_LAST;

  reg [15:0] coeff [0:81];
  reg [31:0] golden [0:71];
  reg [15:0] coeff_asym [0:81];
  reg [15:0] coeff_gain [0:81];
  reg [31:0] golden_asym [0:1023];
  reg [31:0] golden_gain [0:1023];
  reg [31:0] gold_sel [0:1023];        // 双模用例当前相黄金
  integer i, j, err_cnt, exp_imp, out_idx, sat_cnt;

  tb_clkreset #() u_ck (.clk(ACLK), .rstn(ARESETn));

  axi_master_vip u_vip (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_SEL(AW_SEL), .AW_VALID(AW_VALID), .AW_READY(AW_READY),
    .AW_SIZE(AW_SIZE), .AW_BURST(AW_BURST), .AW_LEN(AW_LEN), .AW_ADDR(AW_ADDR),
    .W_VALID(W_VALID), .W_READY(W_READY), .W_DATA(W_DATA), .W_LAST(W_LAST),
    .B_VALID(B_VALID), .B_READY(B_READY), .B_RESP(B_RESP),
    .AR_SEL(AR_SEL), .AR_VALID(AR_VALID), .AR_READY(AR_READY),
    .AR_SIZE(AR_SIZE), .AR_BURST(AR_BURST), .AR_LEN(AR_LEN), .AR_ADDR(AR_ADDR),
    .R_VALID(R_VALID), .R_READY(R_READY), .R_DATA(R_DATA), .R_RESP(R_RESP), .R_LAST(R_LAST));

  fir_top #(.CORE_TYPE(CORE_TYPE)) u_fir (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_SEL(AW_SEL), .AW_VALID(AW_VALID), .AW_READY(AW_READY),
    .AW_SIZE(AW_SIZE), .AW_BURST(AW_BURST), .AW_LEN(AW_LEN), .AW_ADDR(AW_ADDR),
    .W_VALID(W_VALID), .W_READY(W_READY), .W_DATA(W_DATA), .W_LAST(W_LAST),
    .B_VALID(B_VALID), .B_READY(B_READY), .B_RESP(B_RESP),
    .AR_SEL(AR_SEL), .AR_VALID(AR_VALID), .AR_READY(AR_READY),
    .AR_SIZE(AR_SIZE), .AR_BURST(AR_BURST), .AR_LEN(AR_LEN), .AR_ADDR(AR_ADDR),
    .R_VALID(R_VALID), .R_READY(R_READY), .R_DATA(R_DATA), .R_RESP(R_RESP), .R_LAST(R_LAST));

  initial begin
    $readmemh("tb/data/coeff_q15.hex", coeff);
    $readmemh("tb/data/golden_q31.hex", golden);
    $readmemh("tb/data/coeff_asym_q15.hex", coeff_asym);
    $readmemh("tb/data/coeff_gain_q15.hex", coeff_gain);
    $readmemh("tb/data/golden_asym_q31.hex", golden_asym);
    $readmemh("tb/data/golden_gain_q31.hex", golden_gain);
  end

  reg [15:0] u_fir_din [0:1023];

  initial begin
    $readmemh("tb/data/input_q15.hex", u_fir_din);
  end

  generate
  if (CORE_TYPE != 3) begin : g_single
  // ================= 原有单核用例（CORE_TYPE 0/1/2，行为不变） =================
  initial begin
    err_cnt = 0;
    wait (ARESETn == 1'b1);
    @(posedge ACLK);
    // 1) 字节写CTRL（清空）——检验size=0通道
    u_vip.vip_wdata[0] = 32'h1;
    u_vip.axi_wr(32'h4002_0000, 8'd0, 2'b00, 3'b000);
    // 2) INCR突发配置82个系数
    for (i = 0; i < 82; i = i + 1) u_vip.vip_wdata[i] = {16'h0, coeff[i]};
    u_vip.axi_wr(32'h4002_0010, 8'd81, 2'b01, 3'b010);
    // 3) 逐样本半字写DIN，边推边排空DOUT（否则DOUT FIFO先满→核停等→死锁）：
    //    每推1个样本后非阻塞地回读所有可用输出，最后统一收尾
    out_idx = 0;
    for (i = 0; i < 64; i = i + 1) begin
      // 压前查STATUS bit1 DIN_FIFO_FULL，满则等
      u_vip.axi_rd(32'h4002_0004, 8'd0, 2'b00, 3'b010);
      while (u_vip.vip_rdata[0][1]) begin
        u_vip.axi_rd(32'h4002_0004, 8'd0, 2'b00, 3'b010);
      end
      u_vip.vip_wdata[0] = {16'h0, u_fir_din[i]};
      u_vip.axi_wr(32'h4002_0008, 8'd0, 2'b00, 3'b001);
      // 排空DOUT（非阻塞，空即停；每轮最多4个防止饿死推送侧）
      for (j = 0; j < 4; j = j + 1) begin
        u_vip.axi_rd(32'h4002_0004, 8'd0, 2'b00, 3'b010);
        if (u_vip.vip_rdata[0][2]) j = 4;      // DOUT_FIFO_EMPTY：无输出可读
        else begin
          u_vip.axi_rd(32'h4002_000C, 8'd0, 2'b00, 3'b010);
          if (u_vip.vip_rdata[0] !== golden[out_idx]) begin
            $display("MISMATCH[%0d] hw=%h ref=%h", out_idx, u_vip.vip_rdata[0], golden[out_idx]);
            err_cnt = err_cnt + 1;
          end
          out_idx = out_idx + 1;
        end
      end
    end
    // 4) 收尾排空：等齐64个输出
    while (out_idx < 64) begin
      u_vip.axi_rd(32'h4002_0004, 8'd0, 2'b00, 3'b010);
      while (u_vip.vip_rdata[0][2]) begin
        u_vip.axi_rd(32'h4002_0004, 8'd0, 2'b00, 3'b010);
      end
      u_vip.axi_rd(32'h4002_000C, 8'd0, 2'b00, 3'b010);
      if (u_vip.vip_rdata[0] !== golden[out_idx]) begin
        $display("MISMATCH[%0d] hw=%h ref=%h", out_idx, u_vip.vip_rdata[0], golden[out_idx]);
        err_cnt = err_cnt + 1;
      end
      out_idx = out_idx + 1;
    end
    // 黄金模型自检：冲激段前16个应等于系数×65534（Q1.15冲激量化32767）
    for (i = 1; i < 16; i = i + 1) begin
      exp_imp = $signed(coeff[i]) * 32'sd65534;   // 经integer截断到32位再比
      if (golden[i] !== exp_imp[31:0]) begin
        $display("IMPULSE MISMATCH[%0d] golden=%h", i, golden[i]);
        err_cnt = err_cnt + 1;
      end
    end
    // 5) FIXED突发路径：续推8样本（FIXED半字burst，序列连续）→ FIXED字burst读回8个
    //    先等DIN_FIFO空，保证8拍全部入FIFO（16深，8拍必不溢出）
    u_vip.axi_rd(32'h4002_0004, 8'd0, 2'b00, 3'b010);
    while (!u_vip.vip_rdata[0][0]) begin
      u_vip.axi_rd(32'h4002_0004, 8'd0, 2'b00, 3'b010);
    end
    for (i = 0; i < 8; i = i + 1) u_vip.vip_wdata[i] = {16'h0, u_fir_din[64+i]};
    u_vip.axi_wr(32'h4002_0008, 8'd7, 2'b00, 3'b001);   // FIXED半字8拍burst
    repeat (1000) @(posedge ACLK);                      // 8样本×82拍余量
    u_vip.axi_rd(32'h4002_000C, 8'd7, 2'b00, 3'b010);   // FIXED字8拍burst
    for (i = 0; i < 8; i = i + 1)
      if (u_vip.vip_rdata[i] !== golden[64+i]) begin
        $display("BURST MISMATCH[%0d] hw=%h ref=%h", i, u_vip.vip_rdata[i], golden[64+i]);
        err_cnt = err_cnt + 1;
      end
    if (err_cnt != 0) $fatal(1, "FAIL: FIR从机数据比对不一致");
    $display("PASS: FIR从机（系数INCR/数据单拍+FIXED突发/字节半字访问）");
    $finish;
  end
  end else begin : g_dual
  // ================= 双核用例（CORE_TYPE=3：para默认+sym可选） =================
  // 双模约定：CTRL bit0=CLR、bit1=模式（0=para默认/1=sym），模式位在CLR
  // 写拍锁存；每相切换均伴随CLR（清FIFO+双核移位寄存器/流水线，无脏历史）。
  // 每相黄金均从零状态起算（n=0），与golden数据生成口径一致。
  task cfg_coeff;
    input integer which;      // 0=sym 1=asym 2=gain 3=全零
    integer k;
    begin
      for (k = 0; k < 82; k = k + 1)
        u_vip.vip_wdata[k] = (which == 0) ? {16'h0, coeff[k]} :
                             (which == 1) ? {16'h0, coeff_asym[k]} :
                             (which == 2) ? {16'h0, coeff_gain[k]} :
                                            {16'h0, 16'h0000};
      u_vip.axi_wr(32'h4002_0010, 8'd81, 2'b01, 3'b010);
    end
  endtask

  // 推nsamp个样本（从input[0]起）并逐输出比对gold_sel；收尾排空
  task push_drain;
    input integer nsamp;
    integer k, q;
    begin
      out_idx = 0;
      for (k = 0; k < nsamp; k = k + 1) begin
        // 压前查STATUS bit1 DIN_FIFO_FULL，满则等
        u_vip.axi_rd(32'h4002_0004, 8'd0, 2'b00, 3'b010);
        while (u_vip.vip_rdata[0][1]) begin
          u_vip.axi_rd(32'h4002_0004, 8'd0, 2'b00, 3'b010);
        end
        u_vip.vip_wdata[0] = {16'h0, u_fir_din[k]};
        u_vip.axi_wr(32'h4002_0008, 8'd0, 2'b00, 3'b001);
        // 非阻塞排空（每轮最多4个，防止饿死推送侧）
        for (q = 0; q < 4; q = q + 1) begin
          u_vip.axi_rd(32'h4002_0004, 8'd0, 2'b00, 3'b010);
          if (u_vip.vip_rdata[0][2]) q = 4;    // DOUT FIFO空
          else begin
            u_vip.axi_rd(32'h4002_000C, 8'd0, 2'b00, 3'b010);
            if (u_vip.vip_rdata[0] !== gold_sel[out_idx]) begin
              $display("MISMATCH[%0d] hw=%h ref=%h", out_idx,
                       u_vip.vip_rdata[0], gold_sel[out_idx]);
              err_cnt = err_cnt + 1;
            end
            if (u_vip.vip_rdata[0] === 32'h7FFFFFFF ||
                u_vip.vip_rdata[0] === 32'h80000000) sat_cnt = sat_cnt + 1;
            out_idx = out_idx + 1;
          end
        end
      end
      while (out_idx < nsamp) begin
        u_vip.axi_rd(32'h4002_0004, 8'd0, 2'b00, 3'b010);
        while (u_vip.vip_rdata[0][2]) begin
          u_vip.axi_rd(32'h4002_0004, 8'd0, 2'b00, 3'b010);
        end
        u_vip.axi_rd(32'h4002_000C, 8'd0, 2'b00, 3'b010);
        if (u_vip.vip_rdata[0] !== gold_sel[out_idx]) begin
          $display("MISMATCH[%0d] hw=%h ref=%h", out_idx,
                   u_vip.vip_rdata[0], gold_sel[out_idx]);
          err_cnt = err_cnt + 1;
        end
        if (u_vip.vip_rdata[0] === 32'h7FFFFFFF ||
            u_vip.vip_rdata[0] === 32'h80000000) sat_cnt = sat_cnt + 1;
        out_idx = out_idx + 1;
      end
    end
  endtask

  initial begin
    err_cnt = 0; sat_cnt = 0;
    wait (ARESETn == 1'b1);
    @(posedge ACLK);

    // ---- ① 默认模式=para：非对称随机系数黄金回归（合规主路径） ----
    u_vip.vip_wdata[0] = 32'h1;                       // CTRL: CLR（bit1=0→para）
    u_vip.axi_wr(32'h4002_0000, 8'd0, 2'b00, 3'b000);
    cfg_coeff(1);
    for (i = 0; i < 1024; i = i + 1) gold_sel[i] = golden_asym[i];
    push_drain(64);
    if (err_cnt != 0) $fatal(1, "FAIL ①: 默认para非对称黄金比对失败 %0d处", err_cnt);
    $display("PASS ①: 默认para模式非对称系数黄金回归");
    err_cnt = 0;

    // ---- ② CTRL bit1=1+CLR → 切sym；对称系数黄金回归 ----
    u_vip.vip_wdata[0] = 32'h3;                       // CLR+模式1（sym）
    u_vip.axi_wr(32'h4002_0000, 8'd0, 2'b00, 3'b000);
    cfg_coeff(0);                                     // 对称系数（收敛于0.5）
    for (i = 0; i < 72; i = i + 1) gold_sel[i] = golden[i];
    push_drain(64);
    if (err_cnt != 0) $fatal(1, "FAIL ②: sym模式对称系数黄金比对失败 %0d处", err_cnt);
    $display("PASS ②: CLR切换sym模式黄金回归（切换清核，无脏历史）");
    err_cnt = 0;

    // ---- ③ CTRL bit1=0+CLR → 切回para；非对称系数再验（无切换污染） ----
    u_vip.vip_wdata[0] = 32'h1;                       // CLR+模式0（para）
    u_vip.axi_wr(32'h4002_0000, 8'd0, 2'b00, 3'b000);
    cfg_coeff(1);
    for (i = 0; i < 1024; i = i + 1) gold_sel[i] = golden_asym[i];
    push_drain(64);
    if (err_cnt != 0) $fatal(1, "FAIL ③: 切回para后黄金比对失败 %0d处", err_cnt);
    $display("PASS ③: CLR切回para再验（切换无污染）");
    err_cnt = 0;

    // ---- ④ 大系数集（直流增益≈61）饱和路径 ----
    u_vip.vip_wdata[0] = 32'h1;                       // CLR（清③残留历史，黄金从零态起算）
    u_vip.axi_wr(32'h4002_0000, 8'd0, 2'b00, 3'b000);
    cfg_coeff(2);
    for (i = 0; i < 1024; i = i + 1) gold_sel[i] = golden_gain[i];
    sat_cnt = 0;
    push_drain(1024);                                 // 饱和在正弦段（n≥256）
    if (err_cnt != 0) $fatal(1, "FAIL ④: 大系数黄金比对失败 %0d处", err_cnt);
    if (sat_cnt == 0) $fatal(1, "FAIL ④: 饱和路径未被压到（sat_cnt=0）");
    $display("PASS ④: 大系数饱和回归（钳位 %0d 处）", sat_cnt);
    err_cnt = 0;

    // ---- ⑤ 模式判别（证明sym核确实被选中——Important评审项） ----
    // 仅c[0]=0x4000，输入冲激x[0]=0x7FFF后接0：
    //   para: y[n]=c[0]·x[n]          → y[81]=0
    //   sym : y[n]=c[0]·(x[n]+x[n-81])→ y[81]=c[0]·x[0]=0x3FFF8000
    u_vip.vip_wdata[0] = 32'h1;                       // para+CLR
    u_vip.axi_wr(32'h4002_0000, 8'd0, 2'b00, 3'b000);
    cfg_coeff(3);                                     // 全部清零
    u_vip.vip_wdata[0] = 32'h4000;
    u_vip.axi_wr(32'h4002_0010, 8'd0, 2'b00, 3'b010); // c[0]=0x4000
    for (i = 0; i < 1024; i = i + 1) gold_sel[i] = 32'h0;
    gold_sel[0] = 32'h3FFF8000;
    push_drain(82);
    if (err_cnt != 0) $fatal(1, "FAIL ⑤a: para模式c[0]冲激比对失败 %0d处", err_cnt);
    $display("PASS ⑤a: para模式 y[81]=0（c[0]仅作用于x[n]）");
    err_cnt = 0;

    u_vip.vip_wdata[0] = 32'h3;                       // sym+CLR
    u_vip.axi_wr(32'h4002_0000, 8'd0, 2'b00, 3'b000);
    gold_sel[81] = 32'h3FFF8000;                      // sym: y[81]=c[0]·x[0]
    push_drain(82);
    if (err_cnt != 0) $fatal(1, "FAIL ⑤b: sym模式c[0]冲激比对失败 %0d处（模式未切换？）", err_cnt);
    $display("PASS ⑤b: sym模式 y[81]=c[0]×x[0]（证明sym核被选中）");

    $display("PASS: FIR从机双核模式（para默认+sym可选+CLR切换+非对称+饱和+模式判别）");
    $finish;
  end
  end
  endgenerate

  // 超时兜底
  initial begin
    #50000000 $fatal(1, "FAIL: FIR从机测试超时（50ms）");
  end
endmodule
