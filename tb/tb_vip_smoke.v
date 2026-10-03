// tb_vip_smoke.v : VIP自测——写读往返，检查器必须零违规
`timescale 1ns/1ps
module tb_vip_smoke;
  wire       ACLK, ARESETn;
  wire       AW_VALID, AW_READY, W_VALID, W_READY, W_LAST, B_VALID, B_READY;
  wire [2:0] AW_SIZE; wire [1:0] AW_BURST; wire [7:0] AW_LEN;
  wire [31:0] AW_ADDR, W_DATA; wire [1:0] B_RESP;
  wire       AR_VALID, AR_READY, R_VALID, R_READY, R_LAST;
  wire [2:0] AR_SIZE; wire [1:0] AR_BURST; wire [7:0] AR_LEN;
  wire [31:0] AR_ADDR, R_DATA; wire [1:0] R_RESP;
  wire       AW_SEL, AR_SEL, viol;

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

  integer i;
  initial begin
    u_vip.vip_wdata[0] = 32'h12345678;
    u_vip.vip_wdata[1] = 32'hA5A55A5A;
    u_vip.vip_wdata[2] = 32'hDEADBEEF;
    wait (ARESETn == 1'b1);
    @(posedge ACLK);
    u_vip.axi_wr(32'h100, 8'd2, 2'b01, 3'b010);   // 3拍INCR字写
    u_vip.axi_wr(32'h200, 8'd0, 2'b00, 3'b000);   // 单拍字节写
    u_vip.axi_rd(32'h100, 8'd2, 2'b01, 3'b010);   // 读回
    if (u_vip.vip_rdata[0] !== 32'h12345678 ||
        u_vip.vip_rdata[1] !== 32'hA5A55A5A ||
        u_vip.vip_rdata[2] !== 32'hDEADBEEF) begin
      $fatal(1, "FAIL: VIP往返数据不一致");
    end
    if (viol) $fatal(1, "FAIL: 协议检查器有违规");
    $display("PASS: VIP自测通过（写读往返+协议零违规）");
    $finish;
  end
endmodule
