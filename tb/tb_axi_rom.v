// tb_axi_rom.v : FPGA用只读ROM自检TB（任务15增补——计划T15以板上验收为准，
// 上板被裁定跳过（用户：仿真正确即完成任务），axi_rom的验证只能靠仿真）
// 覆盖：字单拍读/窄读通道摆放（字节@奇地址、半字@2对齐，按官方ram_beh语义：
//       数据在地址对应通道、未选通道=0）/INCR与FIXED突发/末字地址/协议检查零违规。
// 激励文件tb/data/rom_test.hex：rom[i]=32'h04030201+i*32'h10101010（字节可辨识）。
`timescale 1ns/1ps
module tb_axi_rom;
  wire ACLK, ARESETn;
  wire       AR_SEL, AR_VALID, AR_READY, R_VALID, R_READY, R_LAST;
  wire [2:0] AR_SIZE; wire [1:0] AR_BURST; wire [7:0] AR_LEN;
  wire [31:0] AR_ADDR, R_DATA; wire [1:0] R_RESP;
  wire AW_SEL, AW_VALID, AW_READY, W_VALID, W_READY, W_LAST, B_VALID, B_READY;
  wire [2:0] AW_SIZE; wire [1:0] AW_BURST; wire [7:0] AW_LEN;
  wire [31:0] AW_ADDR, W_DATA; wire [1:0] B_RESP;
  wire viol;

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

  axi_rom #(.FILENAME("tb/data/rom_test.hex"), .AW(16)) u_rom (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AR_SEL(AR_SEL), .AR_VALID(AR_VALID), .AR_READY(AR_READY),
    .AR_SIZE(AR_SIZE), .AR_BURST(AR_BURST), .AR_LEN(AR_LEN), .AR_ADDR(AR_ADDR[15:0]),
    .R_VALID(R_VALID), .R_READY(R_READY), .R_LAST(R_LAST),
    .R_DATA(R_DATA), .R_RESP(R_RESP));

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

  // 期望字：rom[i]=32'h04030201+i*32'h10101010
  function [31:0] exp_word;
    input [15:0] idx;
    begin
      exp_word = 32'h04030201 + idx * 32'h10101010;
    end
  endfunction

  integer i;
  reg [31:0] e1;   // 期望字临时变量（函数调用不能直接部分选择）
  initial begin
    wait (ARESETn == 1'b1);
    @(posedge ACLK);
    // 1) 字单拍读（0x0、0x8、末字0xFFFC）
    u_vip.axi_rd(32'h0000, 8'd0, 2'b00, 3'b010);
    if (u_vip.vip_rdata[0] !== exp_word(0)) $fatal(1, "FAIL: 字读@0x0 =%h 期望%h", u_vip.vip_rdata[0], exp_word(0));
    u_vip.axi_rd(32'h0008, 8'd0, 2'b00, 3'b010);
    if (u_vip.vip_rdata[0] !== exp_word(2)) $fatal(1, "FAIL: 字读@0x8 =%h 期望%h", u_vip.vip_rdata[0], exp_word(2));
    u_vip.axi_rd(32'hFFFC, 8'd0, 2'b00, 3'b010);
    if (u_vip.vip_rdata[0] !== exp_word(16383)) $fatal(1, "FAIL: 字读@0xFFFC =%h 期望%h", u_vip.vip_rdata[0], exp_word(16383));
    // 2) 窄读通道摆放：字节@0x5（通道1=rom[1][15:8]，其余0）
    // 注意：Verilog-2001不允许函数调用结果直接做部分选择（exp_word(1)[15:8]
    // 会被iverilog -g2001拒绝），先存入临时变量再取位段。
    e1 = exp_word(1);
    u_vip.axi_rd(32'h0005, 8'd0, 2'b00, 3'b000);
    if (u_vip.vip_rdata[0] !== {8'h00, 8'h00, e1[15:8], 8'h00})
      $fatal(1, "FAIL: 字节读@0x5 =%h（期望字节在通道1）", u_vip.vip_rdata[0]);
    // 3) 半字@0x6（通道2/3=rom[1][31:16]）
    u_vip.axi_rd(32'h0006, 8'd0, 2'b00, 3'b001);
    if (u_vip.vip_rdata[0] !== {e1[31:16], 16'h0000})
      $fatal(1, "FAIL: 半字读@0x6 =%h（期望半字在通道2/3）", u_vip.vip_rdata[0]);
    // 4) INCR突发8拍 @0x20
    u_vip.axi_rd(32'h0020, 8'd7, 2'b01, 3'b010);
    for (i = 0; i < 8; i = i + 1)
      if (u_vip.vip_rdata[i] !== exp_word(8 + i))
        $fatal(1, "FAIL: INCR突发@0x20 拍%0d =%h 期望%h", i, u_vip.vip_rdata[i], exp_word(8 + i));
    // 5) FIXED突发4拍 @0x10（每拍同字）
    u_vip.axi_rd(32'h0010, 8'd3, 2'b00, 3'b010);
    for (i = 0; i < 4; i = i + 1)
      if (u_vip.vip_rdata[i] !== exp_word(4))
        $fatal(1, "FAIL: FIXED突发@0x10 拍%0d =%h 期望%h", i, u_vip.vip_rdata[i], exp_word(4));
    if (viol) $fatal(1, "FAIL: 协议检查器有违规");
    $display("PASS: axi_rom自检通过（字/窄读通道/INCR/FIXED突发/协议零违规）");
    $finish;
  end
endmodule
