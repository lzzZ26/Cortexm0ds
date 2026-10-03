// tb_arb.v : 双主并发压力测试——两主各自持续写读，全部必须完成、零协议违规、轮询公平
`timescale 1ns/1ps
module tb_arb;
  wire ACLK, ARESETn;
  wire AW_VALID, AW_READY, W_VALID, W_READY, W_LAST, B_VALID, B_READY;
  wire [2:0] AW_SIZE; wire [1:0] AW_BURST; wire [7:0] AW_LEN; wire [31:0] AW_ADDR, W_DATA; wire [1:0] B_RESP;
  wire AR_VALID, AR_READY, R_VALID, R_READY, R_LAST;
  wire [2:0] AR_SIZE; wire [1:0] AR_BURST; wire [7:0] AR_LEN; wire [31:0] AR_ADDR, R_DATA; wire [1:0] R_RESP;
  // 主0 / 主1
  wire m0_AW_VALID, m0_AW_READY, m0_W_VALID, m0_W_READY, m0_W_LAST, m0_B_VALID, m0_B_READY;
  wire [2:0] m0_AW_SIZE; wire [1:0] m0_AW_BURST; wire [7:0] m0_AW_LEN; wire [31:0] m0_AW_ADDR, m0_W_DATA; wire [1:0] m0_B_RESP;
  wire m0_AR_VALID, m0_AR_READY, m0_R_VALID, m0_R_READY, m0_R_LAST;
  wire [2:0] m0_AR_SIZE; wire [1:0] m0_AR_BURST; wire [7:0] m0_AR_LEN; wire [31:0] m0_AR_ADDR, m0_R_DATA; wire [1:0] m0_R_RESP;
  wire m1_AW_VALID, m1_AW_READY, m1_W_VALID, m1_W_READY, m1_W_LAST, m1_B_VALID, m1_B_READY;
  wire [2:0] m1_AW_SIZE; wire [1:0] m1_AW_BURST; wire [7:0] m1_AW_LEN; wire [31:0] m1_AW_ADDR, m1_W_DATA; wire [1:0] m1_B_RESP;
  wire m1_AR_VALID, m1_AR_READY, m1_R_VALID, m1_R_READY, m1_R_LAST;
  wire [2:0] m1_AR_SIZE; wire [1:0] m1_AR_BURST; wire [7:0] m1_AR_LEN; wire [31:0] m1_AR_ADDR, m1_R_DATA; wire [1:0] m1_R_RESP;
  wire AW_SEL0, AR_SEL0, AW_SEL1, AR_SEL1, viol;

  tb_clkreset #() u_ck (.clk(ACLK), .rstn(ARESETn));

  axi_master_vip u_v0 (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_SEL(AW_SEL0), .AW_VALID(m0_AW_VALID), .AW_READY(m0_AW_READY),
    .AW_SIZE(m0_AW_SIZE), .AW_BURST(m0_AW_BURST), .AW_LEN(m0_AW_LEN), .AW_ADDR(m0_AW_ADDR),
    .W_VALID(m0_W_VALID), .W_READY(m0_W_READY), .W_DATA(m0_W_DATA), .W_LAST(m0_W_LAST),
    .B_VALID(m0_B_VALID), .B_READY(m0_B_READY), .B_RESP(m0_B_RESP),
    .AR_SEL(AR_SEL0), .AR_VALID(m0_AR_VALID), .AR_READY(m0_AR_READY),
    .AR_SIZE(m0_AR_SIZE), .AR_BURST(m0_AR_BURST), .AR_LEN(m0_AR_LEN), .AR_ADDR(m0_AR_ADDR),
    .R_VALID(m0_R_VALID), .R_READY(m0_R_READY), .R_DATA(m0_R_DATA), .R_RESP(m0_R_RESP), .R_LAST(m0_R_LAST));

  axi_master_vip u_v1 (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_SEL(AW_SEL1), .AW_VALID(m1_AW_VALID), .AW_READY(m1_AW_READY),
    .AW_SIZE(m1_AW_SIZE), .AW_BURST(m1_AW_BURST), .AW_LEN(m1_AW_LEN), .AW_ADDR(m1_AW_ADDR),
    .W_VALID(m1_W_VALID), .W_READY(m1_W_READY), .W_DATA(m1_W_DATA), .W_LAST(m1_W_LAST),
    .B_VALID(m1_B_VALID), .B_READY(m1_B_READY), .B_RESP(m1_B_RESP),
    .AR_SEL(AR_SEL1), .AR_VALID(m1_AR_VALID), .AR_READY(m1_AR_READY),
    .AR_SIZE(m1_AR_SIZE), .AR_BURST(m1_AR_BURST), .AR_LEN(m1_AR_LEN), .AR_ADDR(m1_AR_ADDR),
    .R_VALID(m1_R_VALID), .R_READY(m1_R_READY), .R_DATA(m1_R_DATA), .R_RESP(m1_R_RESP), .R_LAST(m1_R_LAST));

  ic_axi_master_arb u_arb (
    .aclk(ACLK), .aresetn(ARESETn),
    .m0_awvalid(m0_AW_VALID), .m0_awready(m0_AW_READY), .m0_awsize(m0_AW_SIZE),
    .m0_awburst(m0_AW_BURST), .m0_awlen(m0_AW_LEN), .m0_awaddr(m0_AW_ADDR),
    .m0_wvalid(m0_W_VALID), .m0_wready(m0_W_READY), .m0_wlast(m0_W_LAST), .m0_wdata(m0_W_DATA),
    .m0_bvalid(m0_B_VALID), .m0_bready(m0_B_READY), .m0_bresp(m0_B_RESP),
    .m0_arvalid(m0_AR_VALID), .m0_arready(m0_AR_READY), .m0_arsize(m0_AR_SIZE),
    .m0_arburst(m0_AR_BURST), .m0_arlen(m0_AR_LEN), .m0_araddr(m0_AR_ADDR),
    .m0_rvalid(m0_R_VALID), .m0_rready(m0_R_READY), .m0_rlast(m0_R_LAST),
    .m0_rdata(m0_R_DATA), .m0_rresp(m0_R_RESP),
    .m1_awvalid(m1_AW_VALID), .m1_awready(m1_AW_READY), .m1_awsize(m1_AW_SIZE),
    .m1_awburst(m1_AW_BURST), .m1_awlen(m1_AW_LEN), .m1_awaddr(m1_AW_ADDR),
    .m1_wvalid(m1_W_VALID), .m1_wready(m1_W_READY), .m1_wlast(m1_W_LAST), .m1_wdata(m1_W_DATA),
    .m1_bvalid(m1_B_VALID), .m1_bready(m1_B_READY), .m1_bresp(m1_B_RESP),
    .m1_arvalid(m1_AR_VALID), .m1_arready(m1_AR_READY), .m1_arsize(m1_AR_SIZE),
    .m1_arburst(m1_AR_BURST), .m1_arlen(m1_AR_LEN), .m1_araddr(m1_AR_ADDR),
    .m1_rvalid(m1_R_VALID), .m1_rready(m1_R_READY), .m1_rlast(m1_R_LAST),
    .m1_rdata(m1_R_DATA), .m1_rresp(m1_R_RESP),
    .awvalid(AW_VALID), .awready(AW_READY), .awsize(AW_SIZE),
    .awburst(AW_BURST), .awlen(AW_LEN), .awaddr(AW_ADDR),
    .wvalid(W_VALID), .wready(W_READY), .wlast(W_LAST), .wdata(W_DATA),
    .bvalid(B_VALID), .bready(B_READY), .bresp(B_RESP),
    .arvalid(AR_VALID), .arready(AR_READY), .arsize(AR_SIZE),
    .arburst(AR_BURST), .arlen(AR_LEN), .araddr(AR_ADDR),
    .rvalid(R_VALID), .rready(R_READY), .rlast(R_LAST),
    .rdata(R_DATA), .rresp(R_RESP));

  axi_slave_mem #(.AW(12)) u_mem (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_VALID(AW_VALID), .AW_READY(AW_READY), .AW_SIZE(AW_SIZE),
    .AW_BURST(AW_BURST), .AW_LEN(AW_LEN), .AW_ADDR(AW_ADDR),
    .W_VALID(W_VALID), .W_READY(W_READY), .W_DATA(W_DATA), .W_LAST(W_LAST),
    .B_VALID(B_VALID), .B_READY(B_READY), .B_RESP(B_RESP),
    .AR_VALID(AR_VALID), .AR_READY(AR_READY), .AR_SIZE(AR_SIZE),
    .AR_BURST(AR_BURST), .AR_LEN(AR_LEN), .AR_ADDR(AR_ADDR),
    .R_VALID(R_VALID), .R_READY(R_READY), .R_DATA(R_DATA), .R_RESP(R_RESP), .R_LAST(R_LAST));

  axi_checker u_chk (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_VALID(AW_VALID), .AW_READY(AW_READY), .AW_SIZE(AW_SIZE),
    .AW_BURST(AW_BURST), .AW_LEN(AW_LEN), .AW_ADDR(AW_ADDR),
    .W_VALID(W_VALID), .W_READY(W_READY), .W_DATA(W_DATA), .W_LAST(W_LAST),
    .B_VALID(B_VALID), .B_READY(B_READY), .B_RESP(B_RESP),
    .AR_VALID(AR_VALID), .AR_READY(AR_READY), .AR_SIZE(AR_SIZE),
    .AR_BURST(AR_BURST), .AR_LEN(AR_LEN), .AR_ADDR(AR_ADDR),
    .R_VALID(R_VALID), .R_READY(R_READY), .R_DATA(R_DATA), .R_RESP(R_RESP), .R_LAST(R_LAST),
    .violation(viol));

  // 压力序列：两主并发持续互打（读写混合、burst与单拍混合、同一从机），各32笔
  // 注意：两个并发进程必须各自声明循环变量（模块级integer会共享导致串扰）
  initial begin : M0
    integer i, j;
    wait (ARESETn == 1'b1);
    @(posedge ACLK);
    for (j = 0; j < 32; j = j + 1) begin
      for (i = 0; i < 16; i = i + 1) u_v0.vip_wdata[i] = {j[7:0], i[7:0], j[7:0], i[7:0]};
      u_v0.axi_wr(32'h800, 8'd15, 2'b01, 3'b010);   // 16拍INCR
      u_v0.axi_rd(32'h800, 8'd15, 2'b01, 3'b010);
      for (i = 0; i < 16; i = i + 1)
        if (u_v0.vip_rdata[i] !== {j[7:0], i[7:0], j[7:0], i[7:0]})
          $fatal(1, "FAIL: 主0读回数据不一致 j=%0d i=%0d", j, i);
    end
    $display("主0完成");
  end

  initial begin : M1
    integer i, j;
    wait (ARESETn == 1'b1);
    @(posedge ACLK);
    for (j = 0; j < 32; j = j + 1) begin
      for (i = 0; i < 8; i = i + 1) u_v1.vip_wdata[i] = 32'hC0000000 + j * 32 + i;
      u_v1.axi_wr(32'h1000, 8'd7, 2'b01, 3'b010);   // 8拍INCR（与主0同打同一从机）
      u_v1.axi_rd(32'h1000, 8'd7, 2'b01, 3'b010);
      for (i = 0; i < 8; i = i + 1)
        if (u_v1.vip_rdata[i] !== 32'hC0000000 + j * 32 + i)
          $fatal(1, "FAIL: 主1读回数据不一致 j=%0d i=%0d", j, i);
    end
    $display("主1完成");
  end

  initial begin
    wait (ARESETn == 1'b1);
    // 等两主完成（用握手计数近似）：轮询VIP状态太繁琐，改以完成打印+超时兜底
    wait (u_arb.m0_done_cnt == 32'd64 && u_arb.m1_done_cnt == 32'd64);  // 每主32写+32读=64次完成
    if (viol) $fatal(1, "FAIL: 协议违规");
    if (u_arb.grant_imbalance > 32'd2) $fatal(1, "FAIL: 轮询不公平 imbalance=%0d", u_arb.grant_imbalance);
    $display("PASS: 双主并发压力测试通过（零协议违规、无死锁、轮询公平）");
    $finish;
  end

  // 超时兜底
  initial begin
    #50000000 $fatal(1, "FAIL: 压力测试超时（50ms）");
  end
endmodule
