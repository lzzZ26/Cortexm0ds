// tb_fir_top.v : FIR从机测试——系数INCR突发配置、DIN固定地址突发、DOUT固定地址突发读回
`timescale 1ns/1ps
module tb_fir_top;
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
  integer i, j, err_cnt, exp_imp, out_idx;

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

  fir_top #(.CORE_TYPE(0)) u_fir (
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
  end

  reg [15:0] u_fir_din [0:71];

  initial begin
    $readmemh("tb/data/input_q15.hex", u_fir_din);
  end

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

  // 超时兜底
  initial begin
    #50000000 $fatal(1, "FAIL: FIR从机测试超时（50ms）");
  end
endmodule
