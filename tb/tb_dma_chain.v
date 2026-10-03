// tb_dma_chain.v : 链式传输——3段描述符自动连续执行
// 段1: 0x000->0x300 64B；段2: 0x040->0x340 64B；段3: 0x080->0x380 64B（末段IRQ_EN）
// 描述符区: 0x700起，每段5字
// 拓扑：同tb_dma_top（VIP与DMA经仲裁器入共享总线，fabric按地址分区）。
// CTRL位：[0]GO [1]IRQ_EN [2]FIXED_SRC [3]FIXED_DST [4]CHAIN [7:5]BURST
// 段1/2 CTRL=CHAIN（0x10），末段 CTRL=IRQ_EN（0x02）——计划原文0x14/0x12
// 多带了FIXED_DST/CHAIN位，与注释矛盾。
`timescale 1ns/1ps
module tb_dma_chain;
  wire ACLK, ARESETn;
  // VIP主口
  wire v_AW_SEL, v_AR_SEL, v_AW_VALID, v_AW_READY, v_W_VALID, v_W_READY, v_W_LAST;
  wire v_B_VALID, v_B_READY; wire v_AR_VALID, v_AR_READY, v_R_VALID, v_R_READY, v_R_LAST;
  wire [2:0] v_AW_SIZE, v_AR_SIZE; wire [1:0] v_AW_BURST, v_AR_BURST;
  wire [7:0] v_AW_LEN, v_AR_LEN; wire [31:0] v_AW_ADDR, v_W_DATA, v_AR_ADDR, v_R_DATA;
  wire [1:0] v_B_RESP, v_R_RESP;
  // DMA主口
  wire d_AW_VALID, d_AW_READY, d_W_VALID, d_W_READY, d_W_LAST;
  wire d_B_VALID, d_B_READY; wire d_AR_VALID, d_AR_READY, d_R_VALID, d_R_READY, d_R_LAST;
  wire [2:0] d_AW_SIZE, d_AR_SIZE; wire [1:0] d_AW_BURST, d_AR_BURST;
  wire [7:0] d_AW_LEN, d_AR_LEN; wire [31:0] d_AW_ADDR, d_W_DATA, d_AR_ADDR, d_R_DATA;
  wire [1:0] d_B_RESP, d_R_RESP;
  // 共享总线（仲裁器输出→fabric）
  wire S_AW_VALID, S_AW_READY; wire [2:0] S_AW_SIZE; wire [1:0] S_AW_BURST;
  wire [7:0] S_AW_LEN; wire [31:0] S_AW_ADDR;
  wire S_W_VALID, S_W_READY; wire [31:0] S_W_DATA; wire S_W_LAST;
  wire S_B_VALID, S_B_READY; wire [1:0] S_B_RESP;
  wire S_AR_VALID, S_AR_READY; wire [2:0] S_AR_SIZE; wire [1:0] S_AR_BURST;
  wire [7:0] S_AR_LEN; wire [31:0] S_AR_ADDR;
  wire S_R_VALID, S_R_READY; wire [31:0] S_R_DATA; wire [1:0] S_R_RESP; wire S_R_LAST;
  wire dma_irq, viol;

  tb_clkreset #() u_ck (.clk(ACLK), .rstn(ARESETn));

  axi_master_vip u_vip (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_SEL(v_AW_SEL), .AW_VALID(v_AW_VALID), .AW_READY(v_AW_READY),
    .AW_SIZE(v_AW_SIZE), .AW_BURST(v_AW_BURST), .AW_LEN(v_AW_LEN), .AW_ADDR(v_AW_ADDR),
    .W_VALID(v_W_VALID), .W_READY(v_W_READY), .W_DATA(v_W_DATA), .W_LAST(v_W_LAST),
    .B_VALID(v_B_VALID), .B_READY(v_B_READY), .B_RESP(v_B_RESP),
    .AR_SEL(v_AR_SEL), .AR_VALID(v_AR_VALID), .AR_READY(v_AR_READY),
    .AR_SIZE(v_AR_SIZE), .AR_BURST(v_AR_BURST), .AR_LEN(v_AR_LEN), .AR_ADDR(v_AR_ADDR),
    .R_VALID(v_R_VALID), .R_READY(v_R_READY), .R_DATA(v_R_DATA),
    .R_RESP(v_R_RESP), .R_LAST(v_R_LAST));

  dma_top u_dma (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_SEL(dma_aw_sel), .AW_VALID(dma_AW_VALID), .AW_READY(dma_AW_READY),
    .AW_SIZE(S_AW_SIZE), .AW_BURST(S_AW_BURST), .AW_LEN(S_AW_LEN), .AW_ADDR(S_AW_ADDR),
    .W_VALID(S_W_VALID), .W_READY(dma_W_READY), .W_DATA(S_W_DATA), .W_LAST(S_W_LAST),
    .B_VALID(dma_B_VALID), .B_READY(S_B_READY), .B_RESP(dma_B_RESP),
    .AR_SEL(dma_ar_sel), .AR_VALID(dma_AR_VALID), .AR_READY(dma_AR_READY),
    .AR_SIZE(S_AR_SIZE), .AR_BURST(S_AR_BURST), .AR_LEN(S_AR_LEN), .AR_ADDR(S_AR_ADDR),
    .R_VALID(dma_R_VALID), .R_READY(S_R_READY), .R_DATA(dma_R_DATA),
    .R_RESP(dma_R_RESP), .R_LAST(dma_R_LAST),
    .awvalid(d_AW_VALID), .awready(d_AW_READY), .awsize(d_AW_SIZE), .awburst(d_AW_BURST),
    .awlen(d_AW_LEN), .awaddr(d_AW_ADDR),
    .wvalid(d_W_VALID), .wready(d_W_READY), .wdata(d_W_DATA), .wlast(d_W_LAST),
    .bvalid(d_B_VALID), .bready(d_B_READY), .bresp(d_B_RESP),
    .arvalid(d_AR_VALID), .arready(d_AR_READY), .arsize(d_AR_SIZE), .arburst(d_AR_BURST),
    .arlen(d_AR_LEN), .araddr(d_AR_ADDR),
    .rvalid(d_R_VALID), .rready(d_R_READY), .rdata(d_R_DATA),
    .rresp(d_R_RESP), .rlast(d_R_LAST),
    .irq_o(dma_irq));

  ic_axi_master_arb u_arb (
    .aclk(ACLK), .aresetn(ARESETn),
    .m0_awvalid(v_AW_VALID), .m0_awready(v_AW_READY), .m0_awsize(v_AW_SIZE),
    .m0_awburst(v_AW_BURST), .m0_awlen(v_AW_LEN), .m0_awaddr(v_AW_ADDR),
    .m0_wvalid(v_W_VALID), .m0_wready(v_W_READY), .m0_wlast(v_W_LAST), .m0_wdata(v_W_DATA),
    .m0_bvalid(v_B_VALID), .m0_bready(v_B_READY), .m0_bresp(v_B_RESP),
    .m0_arvalid(v_AR_VALID), .m0_arready(v_AR_READY), .m0_arsize(v_AR_SIZE),
    .m0_arburst(v_AR_BURST), .m0_arlen(v_AR_LEN), .m0_araddr(v_AR_ADDR),
    .m0_rvalid(v_R_VALID), .m0_rready(v_R_READY), .m0_rlast(v_R_LAST),
    .m0_rdata(v_R_DATA), .m0_rresp(v_R_RESP),
    .m1_awvalid(d_AW_VALID), .m1_awready(d_AW_READY), .m1_awsize(d_AW_SIZE),
    .m1_awburst(d_AW_BURST), .m1_awlen(d_AW_LEN), .m1_awaddr(d_AW_ADDR),
    .m1_wvalid(d_W_VALID), .m1_wready(d_W_READY), .m1_wlast(d_W_LAST), .m1_wdata(d_W_DATA),
    .m1_bvalid(d_B_VALID), .m1_bready(d_B_READY), .m1_bresp(d_B_RESP),
    .m1_arvalid(d_AR_VALID), .m1_arready(d_AR_READY), .m1_arsize(d_AR_SIZE),
    .m1_arburst(d_AR_BURST), .m1_arlen(d_AR_LEN), .m1_araddr(d_AR_ADDR),
    .m1_rvalid(d_R_VALID), .m1_rready(d_R_READY), .m1_rlast(d_R_LAST),
    .m1_rdata(d_R_DATA), .m1_rresp(d_R_RESP),
    .awvalid(S_AW_VALID), .awready(S_AW_READY), .awsize(S_AW_SIZE),
    .awburst(S_AW_BURST), .awlen(S_AW_LEN), .awaddr(S_AW_ADDR),
    .wvalid(S_W_VALID), .wready(S_W_READY), .wlast(S_W_LAST), .wdata(S_W_DATA),
    .bvalid(S_B_VALID), .bready(S_B_READY), .bresp(S_B_RESP),
    .arvalid(S_AR_VALID), .arready(S_AR_READY), .arsize(S_AR_SIZE),
    .arburst(S_AR_BURST), .arlen(S_AR_LEN), .araddr(S_AR_ADDR),
    .rvalid(S_R_VALID), .rready(S_R_READY), .rlast(S_R_LAST),
    .rdata(S_R_DATA), .rresp(S_R_RESP),
    .m0_done_cnt(), .m1_done_cnt(), .grant_imbalance());

  // ---- fabric：地址分区 + 从机信号汇流（同tb_dma_top）----
  wire dma_aw_sel = (S_AW_ADDR[31:12] == 20'h40030);
  wire dma_ar_sel = (S_AR_ADDR[31:12] == 20'h40030);
  wire mem_AW_VALID, mem_AW_READY, mem_W_READY, mem_B_VALID;
  wire [1:0] mem_B_RESP;
  wire mem_AR_VALID, mem_AR_READY, mem_R_VALID, mem_R_LAST;
  wire [31:0] mem_R_DATA; wire [1:0] mem_R_RESP;
  wire dma_AW_VALID, dma_AW_READY, dma_W_READY, dma_B_VALID;
  wire [1:0] dma_B_RESP;
  wire dma_AR_VALID, dma_AR_READY, dma_R_VALID, dma_R_LAST;
  wire [31:0] dma_R_DATA; wire [1:0] dma_R_RESP;
  reg w_src, r_src;

  assign mem_AW_VALID = S_AW_VALID && !dma_aw_sel;
  assign dma_AW_VALID = S_AW_VALID &&  dma_aw_sel;
  assign mem_AR_VALID = S_AR_VALID && !dma_ar_sel;
  assign dma_AR_VALID = S_AR_VALID &&  dma_ar_sel;
  assign S_AW_READY = mem_AW_READY | dma_AW_READY;
  assign S_W_READY  = mem_W_READY  | dma_W_READY;
  assign S_AR_READY = mem_AR_READY | dma_AR_READY;
  assign S_B_VALID  = mem_B_VALID  | dma_B_VALID;
  assign S_R_VALID  = mem_R_VALID  | dma_R_VALID;
  assign S_B_RESP   = w_src ? dma_B_RESP : mem_B_RESP;
  assign S_R_DATA   = r_src ? dma_R_DATA : mem_R_DATA;
  assign S_R_RESP   = r_src ? dma_R_RESP : mem_R_RESP;
  assign S_R_LAST   = r_src ? dma_R_LAST : mem_R_LAST;
  always @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin w_src <= 1'b0; r_src <= 1'b0; end
    else begin
      if (S_B_VALID && S_B_READY)           w_src <= 1'b0;
      if (S_R_VALID && S_R_READY && S_R_LAST) r_src <= 1'b0;
      if (S_AW_VALID && S_AW_READY)         w_src <= dma_aw_sel;
      if (S_AR_VALID && S_AR_READY)         r_src <= dma_ar_sel;
    end
  end

  axi_slave_mem #(.AW(12)) u_mem (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_VALID(mem_AW_VALID), .AW_READY(mem_AW_READY), .AW_SIZE(S_AW_SIZE),
    .AW_BURST(S_AW_BURST), .AW_LEN(S_AW_LEN), .AW_ADDR(S_AW_ADDR),
    .W_VALID(S_W_VALID), .W_READY(mem_W_READY), .W_DATA(S_W_DATA), .W_LAST(S_W_LAST),
    .B_VALID(mem_B_VALID), .B_READY(S_B_READY), .B_RESP(mem_B_RESP),
    .AR_VALID(mem_AR_VALID), .AR_READY(mem_AR_READY), .AR_SIZE(S_AR_SIZE),
    .AR_BURST(S_AR_BURST), .AR_LEN(S_AR_LEN), .AR_ADDR(S_AR_ADDR),
    .R_VALID(mem_R_VALID), .R_READY(S_R_READY), .R_DATA(mem_R_DATA),
    .R_RESP(mem_R_RESP), .R_LAST(mem_R_LAST));

  axi_checker u_chk (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_VALID(S_AW_VALID), .AW_READY(S_AW_READY), .AW_SIZE(S_AW_SIZE),
    .AW_BURST(S_AW_BURST), .AW_LEN(S_AW_LEN), .AW_ADDR(S_AW_ADDR),
    .W_VALID(S_W_VALID), .W_READY(S_W_READY), .W_DATA(S_W_DATA), .W_LAST(S_W_LAST),
    .B_VALID(S_B_VALID), .B_READY(S_B_READY), .B_RESP(S_B_RESP),
    .AR_VALID(S_AR_VALID), .AR_READY(S_AR_READY), .AR_SIZE(S_AR_SIZE),
    .AR_BURST(S_AR_BURST), .AR_LEN(S_AR_LEN), .AR_ADDR(S_AR_ADDR),
    .R_VALID(S_R_VALID), .R_READY(S_R_READY), .R_DATA(S_R_DATA),
    .R_RESP(S_R_RESP), .R_LAST(S_R_LAST),
    .violation(viol));

  integer i, t;

  task wr_reg; input [31:0] a, d;
    begin u_vip.vip_wdata[0] = d; u_vip.axi_wr(a, 8'd0, 2'b00, 3'b010); end
  endtask
  task rd_reg; input [31:0] a;
    begin u_vip.axi_rd(a, 8'd0, 2'b00, 3'b010); end
  endtask

  initial begin
    wait (ARESETn == 1'b1);
    @(posedge ACLK);
    // 源数据
    for (i = 0; i < 64; i = i + 1) begin
      u_vip.vip_wdata[0] = 32'h5000 + i;
      u_vip.axi_wr(i * 4, 8'd0, 2'b00, 3'b010);
    end
    // 描述符区0x700：3段链表（末段CHAIN=0,IRQ_EN=1）
    // 段1 @0x700
    wr_reg(32'h700, 32'h000); wr_reg(32'h704, 32'h300);
    wr_reg(32'h708, 32'd64); wr_reg(32'h70C, 16'h0010 | 16'd5 << 5); wr_reg(32'h710, 32'h714);
    // 段2 @0x714
    wr_reg(32'h714, 32'h040); wr_reg(32'h718, 32'h340);
    wr_reg(32'h71C, 32'd64); wr_reg(32'h720, 16'h0010 | 16'd5 << 5); wr_reg(32'h724, 32'h728);
    // 段3 @0x728（末段）
    wr_reg(32'h728, 32'h080); wr_reg(32'h72C, 32'h380);
    wr_reg(32'h730, 32'd64); wr_reg(32'h734, 16'h0002 | 16'd5 << 5); wr_reg(32'h738, 32'h0);
    // 启动通道0：GO|CHAIN，NEXT=0x700
    wr_reg(32'h4003_0000 + 32'h14, 32'h700);
    wr_reg(32'h4003_0000 + 32'h0C, 16'h0011 | 16'd5 << 5);
    // 等末段中断
    t = 0;
    while (!dma_irq && t < 200000) begin @(posedge ACLK); t = t + 1; end
    if (!dma_irq) $fatal(1, "FAIL: 链式传输未在超时内完成");
    // 三段目的区逐一比对
    for (i = 0; i < 16; i = i + 1) begin
      rd_reg(32'h300 + i * 4);
      if (u_vip.vip_rdata[0] !== 32'h5000 + i)      $fatal(1, "FAIL: 段1字%0d", i);
      rd_reg(32'h340 + i * 4);
      if (u_vip.vip_rdata[0] !== 32'h5000 + 16 + i) $fatal(1, "FAIL: 段2字%0d", i);
      rd_reg(32'h380 + i * 4);
      if (u_vip.vip_rdata[0] !== 32'h5000 + 32 + i) $fatal(1, "FAIL: 段3字%0d", i);
    end
    if (viol) $fatal(1, "FAIL: 协议违规");
    $display("PASS: 3段链表自动串联执行（无CPU干预，末段中断）");
    $finish;
  end

  // 超时兜底
  initial begin
    #400000000 $fatal(1, "FAIL: 链式DMA测试超时（400ms）");
  end
endmodule
