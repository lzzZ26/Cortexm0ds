// tb_dma_channel.v : 单通道DMA零差错测试
// 用例：字对齐、源非对齐、目的非对齐、1/2/3字节、跨4KB、FIXED_SRC、FIXED_DST
// 拓扑：VIP（初始化/验证）与DMA（被测）经ic_axi_master_arb汇入同一axi_slave_mem
//       ——两主不可直连同一总线（双驱动），必须仲裁。
// 注意：源区字节模式为"地址a处字节=a>>2"（word w = w*0x01010101），
//       非对齐用例期望值按此推导；FIXED_DST用例目的地址被反复覆盖，终值=最后一拍。
`timescale 1ns/1ps
module tb_dma_channel;
  wire ACLK, ARESETn;
  // 共享总线（仲裁器输出→slave_mem/checker）
  wire AW_VALID, AW_READY, W_VALID, W_READY, W_LAST, B_VALID, B_READY;
  wire [2:0] AW_SIZE; wire [1:0] AW_BURST; wire [7:0] AW_LEN; wire [31:0] AW_ADDR, W_DATA; wire [1:0] B_RESP;
  wire AR_VALID, AR_READY, R_VALID, R_READY, R_LAST;
  wire [2:0] AR_SIZE; wire [1:0] AR_BURST; wire [7:0] AR_LEN; wire [31:0] AR_ADDR, R_DATA; wire [1:0] R_RESP;
  // VIP主口
  wire v_AW_VALID, v_AW_READY, v_W_VALID, v_W_READY, v_W_LAST, v_B_VALID, v_B_READY;
  wire [2:0] v_AW_SIZE; wire [1:0] v_AW_BURST; wire [7:0] v_AW_LEN; wire [31:0] v_AW_ADDR, v_W_DATA; wire [1:0] v_B_RESP;
  wire v_AR_VALID, v_AR_READY, v_R_VALID, v_R_READY, v_R_LAST;
  wire [2:0] v_AR_SIZE; wire [1:0] v_AR_BURST; wire [7:0] v_AR_LEN; wire [31:0] v_AR_ADDR, v_R_DATA; wire [1:0] v_R_RESP;
  wire v_AW_SEL, v_AR_SEL;
  // DMA主口
  wire d_AW_VALID, d_AW_READY, d_W_VALID, d_W_READY, d_W_LAST, d_B_VALID, d_B_READY;
  wire [2:0] d_AW_SIZE; wire [1:0] d_AW_BURST; wire [7:0] d_AW_LEN; wire [31:0] d_AW_ADDR, d_W_DATA; wire [1:0] d_B_RESP;
  wire d_AR_VALID, d_AR_READY, d_R_VALID, d_R_READY, d_R_LAST;
  wire [2:0] d_AR_SIZE; wire [1:0] d_AR_BURST; wire [7:0] d_AR_LEN; wire [31:0] d_AR_ADDR, d_R_DATA; wire [1:0] d_R_RESP;
  wire viol;
  reg  cfg_load; reg [31:0] cfg_src, cfg_dst, cfg_len, cfg_next; reg [15:0] cfg_ctrl;
  wire busy_o, done_o, err_o, req_o;

  tb_clkreset #() u_ck (.clk(ACLK), .rstn(ARESETn));

  axi_master_vip u_vip (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_SEL(v_AW_SEL), .AW_VALID(v_AW_VALID), .AW_READY(v_AW_READY),
    .AW_SIZE(v_AW_SIZE), .AW_BURST(v_AW_BURST), .AW_LEN(v_AW_LEN), .AW_ADDR(v_AW_ADDR),
    .W_VALID(v_W_VALID), .W_READY(v_W_READY), .W_DATA(v_W_DATA), .W_LAST(v_W_LAST),
    .B_VALID(v_B_VALID), .B_READY(v_B_READY), .B_RESP(v_B_RESP),
    .AR_SEL(v_AR_SEL), .AR_VALID(v_AR_VALID), .AR_READY(v_AR_READY),
    .AR_SIZE(v_AR_SIZE), .AR_BURST(v_AR_BURST), .AR_LEN(v_AR_LEN), .AR_ADDR(v_AR_ADDR),
    .R_VALID(v_R_VALID), .R_READY(v_R_READY), .R_DATA(v_R_DATA), .R_RESP(v_R_RESP), .R_LAST(v_R_LAST));

  dma_channel u_dma (
    .clk(ACLK), .rstn(ARESETn),
    .cfg_src(cfg_src), .cfg_dst(cfg_dst), .cfg_len(cfg_len), .cfg_next(cfg_next),
    .cfg_ctrl(cfg_ctrl), .cfg_load(cfg_load),
    .busy_o(busy_o), .done_o(done_o), .err_o(err_o), .req_o(req_o),
    .awvalid(d_AW_VALID), .awready(d_AW_READY), .awsize(d_AW_SIZE), .awburst(d_AW_BURST),
    .awlen(d_AW_LEN), .awaddr(d_AW_ADDR),
    .wvalid(d_W_VALID), .wready(d_W_READY), .wdata(d_W_DATA), .wlast(d_W_LAST),
    .bvalid(d_B_VALID), .bready(d_B_READY), .bresp(d_B_RESP),
    .arvalid(d_AR_VALID), .arready(d_AR_READY), .arsize(d_AR_SIZE), .arburst(d_AR_BURST),
    .arlen(d_AR_LEN), .araddr(d_AR_ADDR),
    .rvalid(d_R_VALID), .rready(d_R_READY), .rdata(d_R_DATA), .rresp(d_R_RESP), .rlast(d_R_LAST));

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
    .awvalid(AW_VALID), .awready(AW_READY), .awsize(AW_SIZE),
    .awburst(AW_BURST), .awlen(AW_LEN), .awaddr(AW_ADDR),
    .wvalid(W_VALID), .wready(W_READY), .wlast(W_LAST), .wdata(W_DATA),
    .bvalid(B_VALID), .bready(B_READY), .bresp(B_RESP),
    .arvalid(AR_VALID), .arready(AR_READY), .arsize(AR_SIZE),
    .arburst(AR_BURST), .arlen(AR_LEN), .araddr(AR_ADDR),
    .rvalid(R_VALID), .rready(R_READY), .rlast(R_LAST),
    .rdata(R_DATA), .rresp(R_RESP),
    .m0_done_cnt(), .m1_done_cnt(), .grant_imbalance());

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

  // 参考存储器镜像（期望值比对）
  reg [31:0] ref_mem [0:4095];
  integer i, t;

  task run_case;
    input [31:0] s, d, l; input [15:0] c;
    begin
      cfg_src = s; cfg_dst = d; cfg_len = l; cfg_ctrl = c; cfg_next = 0;
      @(posedge ACLK);
      // cfg_load保持2个完整沿（与调度顺序无关，通道必能采样到）
      cfg_load = 1'b1; @(posedge ACLK); @(posedge ACLK); cfg_load = 1'b0;
      // 等待完成/错误（超时兜底）
      t = 0;
      while (!done_o && !err_o && t < 100000) begin @(posedge ACLK); t = t + 1; end
      if (t >= 100000) $fatal(1, "FAIL: 用例超时 s=%h d=%h l=%h", s, d, l);
    end
  endtask

  initial begin
    cfg_load = 0; cfg_src = 0; cfg_dst = 0; cfg_len = 0; cfg_ctrl = 0; cfg_next = 0;
    wait (ARESETn == 1'b1);
    @(posedge ACLK);
    // 源数据区：0x000..0x0FF 写入可识别模式
    for (i = 0; i < 256; i = i + 1) begin
      u_vip.vip_wdata[0] = i * 32'h01010101;
      u_vip.axi_wr(i * 4, 8'd0, 2'b00, 3'b010);
      ref_mem[i] = i * 32'h01010101;
    end
    // 1) 字对齐整块拷贝 64字节 0x000->0x200
    run_case(32'h000, 32'h1000, 32'd64, 16'h0001 | 16'd5 << 5);  // GO|BURST=6拍
    for (i = 0; i < 16; i = i + 1) begin
      u_vip.axi_rd(32'h1000 + i * 4, 8'd0, 2'b00, 3'b010);
      if (u_vip.vip_rdata[0] !== ref_mem[i])
        $fatal(1, "FAIL: 用例1 dst+%0d=%h 期望=%h", i * 4, u_vip.vip_rdata[0], ref_mem[i]);
    end
    // 2) 源非对齐：src=0x003（字节偏移3），拷16字节 -> 0x1100
    //    源字节值=地址>>2，故第i字节=(3+i)>>2
    run_case(32'h003, 32'h1100, 32'd16, 16'h0001 | 16'd5 << 5);
    for (i = 0; i < 16; i = i + 1) begin
      u_vip.axi_rd(32'h1100 + i, 8'd0, 2'b00, 3'b000);   // 字节读回比对
      if (u_vip.vip_rdata[0][7:0] !== (3 + i) >> 2)
        $fatal(1, "FAIL: 用例2 字节%0d=%h 期望=%0d", i, u_vip.vip_rdata[0][7:0], (3 + i) >> 2);
    end
    // 3) 目的非对齐：dst=0x1201，拷16字节 0x000 -> 0x1201
    //    源字节值=地址>>2，故第i字节=i>>2
    run_case(32'h000, 32'h1201, 32'd16, 16'h0001 | 16'd5 << 5);
    for (i = 0; i < 16; i = i + 1) begin
      u_vip.axi_rd(32'h1201 + i, 8'd0, 2'b00, 3'b000);
      if (u_vip.vip_rdata[0][7:0] !== i >> 2)
        $fatal(1, "FAIL: 用例3 字节%0d=%h 期望=%0d", i, u_vip.vip_rdata[0][7:0], i >> 2);
    end
    // 4) 奇长：1字节、3字节、1023字节
    run_case(32'h000, 32'h1300, 32'd1, 16'h0001 | 16'd5 << 5);
    run_case(32'h000, 32'h1304, 32'd3, 16'h0001 | 16'd5 << 5);
    run_case(32'h000, 32'h1308, 32'd1023, 16'h0001 | 16'd5 << 5);
    for (i = 0; i < 1023; i = i + 1) begin
      u_vip.axi_rd(32'h1308 + i, 8'd0, 2'b00, 3'b000);
      if (u_vip.vip_rdata[0][7:0] !== i >> 2)        // 源字节值=地址>>2
        $fatal(1, "FAIL: 用例4 字节%0d=%h 期望=%0d", i, u_vip.vip_rdata[0][7:0], i >> 2);
    end
    // 5) 跨4KB边界：src=0xFF0，拷32字节（检查器必须零违规）
    run_case(32'hFF0, 32'h1400, 32'd32, 16'h0001 | 16'd5 << 5);
    // 6) FIXED_SRC：从0x004固定地址读16字 -> 0x700（len=拍数，FSIZE=2）
    run_case(32'h004, 32'h1500, 32'd16, 16'h0005 | 16'd5 << 5 | 3'd2 << 8);
    for (i = 0; i < 16; i = i + 1) begin
      u_vip.axi_rd(32'h1500 + i * 4, 8'd0, 2'b00, 3'b010);
      if (u_vip.vip_rdata[0] !== ref_mem[1]) $fatal(1, "FAIL: 用例6");
    end
    // 7) FIXED_DST：0x000起16字 -> 0x800固定地址（len=拍数）
    //    固定地址被逐字覆盖，终值=源区最后一字ref_mem[15]
    run_case(32'h000, 32'h1600, 32'd16, 16'h0009 | 16'd5 << 5 | 3'd2 << 8);
    u_vip.axi_rd(32'h1600, 8'd0, 2'b00, 3'b010);
    if (u_vip.vip_rdata[0] !== ref_mem[15]) $fatal(1, "FAIL: 用例7 终值=%h 期望=%h", u_vip.vip_rdata[0], ref_mem[15]);
    if (viol) $fatal(1, "FAIL: 协议违规");
    $display("PASS: 单通道DMA（7类用例零差错+协议零违规）");
    $finish;
  end

  // 超时兜底
  initial begin
    #200000000 $fatal(1, "FAIL: DMA通道测试超时（200ms）");
  end
endmodule
