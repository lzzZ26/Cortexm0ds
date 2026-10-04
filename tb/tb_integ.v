// tb_integ.v : 集成验证TB（不含CPU核）——VIP替代CPU作为主设备
// 互连拓扑与soc_top完全一致（ic_axi_master_arb + ic_axi_slave_mux +
// ic_axi_addr_decode + axi_sram_sim + fir_top(对称核) + dma_top + 默认从机×2），
// 仅去掉CPU/APB/GPIO/flash（对应区域挂默认从机，访问得DECERR不致挂死）。
// 对应赛题"三个层级验证"第二层：集成验证（不含CPU核，编写Testbench进行验证）。
// 验证链：SRAM往返 → VIP配82系数 → VIP写1024样本入SRAM → DMA ch0搬入FIR
// （FIXED_DST单拍，T14死锁裁定）→ 等首样本入DIN再GO ch1（防DOUT空读死锁，
// 与固件GO顺序一致）→ ch1回收DOUT入SRAM → 轮询STATUS DONE → VIP读回
// 与黄金模型比对<0.1%（严0.0977%）+协议检查器零违规。
`timescale 1ns/1ps
module tb_integ;
  wire ACLK, ARESETn;
  // VIP（主0，替代CPU）
  wire       AW_SELv, AW_VALIDv, AW_READYv, W_VALIDv, W_READYv, W_LASTv, B_VALIDv, B_READYv;
  wire [2:0] AW_SIZEv; wire [1:0] AW_BURSTv; wire [7:0] AW_LENv;
  wire [31:0] AW_ADDRv, W_DATAv; wire [1:0] B_RESPv;
  wire       AR_SELv, AR_VALIDv, AR_READYv, R_VALIDv, R_READYv, R_LASTv;
  wire [2:0] AR_SIZEv; wire [1:0] AR_BURSTv; wire [7:0] AR_LENv;
  wire [31:0] AR_ADDRv, R_DATAv; wire [1:0] R_RESPv;
  // DMA主口（主1）
  wire       dma_awvalid, dma_awready; wire [2:0] dma_awsize; wire [1:0] dma_awburst;
  wire [7:0] dma_awlen; wire [31:0] dma_awaddr;
  wire       dma_wvalid, dma_wready, dma_wlast; wire [31:0] dma_wdata;
  wire       dma_bvalid, dma_bready; wire [1:0] dma_bresp;
  wire       dma_arvalid, dma_arready; wire [2:0] dma_arsize; wire [1:0] dma_arburst;
  wire [7:0] dma_arlen; wire [31:0] dma_araddr;
  wire       dma_rvalid, dma_rready, dma_rlast; wire [31:0] dma_rdata; wire [1:0] dma_rresp;
  // 共享总线（仲裁器输出→mux主侧）
  wire       sys_AWVALID, sys_AWREADY; wire [2:0] sys_AWSIZE; wire [1:0] sys_AWBURST;
  wire [7:0] sys_AWLEN; wire [31:0] sys_AWADDR;
  wire       sys_WVALID, sys_WREADY, sys_WLAST; wire [31:0] sys_WDATA;
  wire       sys_BVALID, sys_BREADY; wire [1:0] sys_BRESP;
  wire       sys_ARVALID, sys_ARREADY; wire [2:0] sys_ARSIZE; wire [1:0] sys_ARBURST;
  wire [7:0] sys_ARLEN; wire [31:0] sys_ARADDR;
  wire       sys_RVALID, sys_RREADY, sys_RLAST; wire [31:0] sys_RDATA; wire [1:0] sys_RRESP;
  // 译码SEL与各从机
  wire flash_arsel, sram_awsel, sram_arsel, apbsys_awsel, apbsys_arsel;
  wire gpio0_awsel, gpio0_arsel, gpio1_awsel, gpio1_arsel;
  wire fir_awsel, fir_arsel, dma_awsel, dma_arsel, defslv_awsel, defslv_arsel;
  wire sram_AWREADY, sram_WREADY, sram_BVALID; wire [1:0] sram_BRESP;
  wire sram_ARREADY, sram_RVALID, sram_RLAST; wire [31:0] sram_RDATA; wire [1:0] sram_RRESP;
  wire fir_AWREADY, fir_WREADY, fir_BVALID; wire [1:0] fir_BRESP;
  wire fir_ARREADY, fir_RVALID, fir_RLAST; wire [31:0] fir_RDATA; wire [1:0] fir_RRESP;
  wire dma_AWREADY, dma_WREADY, dma_BVALID; wire [1:0] dma_BRESP;
  wire dma_ARREADY, dma_RVALID, dma_RLAST; wire [31:0] dma_RDATA; wire [1:0] dma_RRESP;
  wire def_AWREADY, def_WREADY, def_BVALID; wire [1:0] def_BRESP;
  wire def_ARREADY, def_RVALID, def_RLAST; wire [31:0] def_RDATA; wire [1:0] def_RRESP;
  wire f0_AWREADY, f0_WREADY, f0_BVALID; wire [1:0] f0_BRESP;   // port0默认从机(0x0区)
  wire f0_ARREADY, f0_RVALID, f0_RLAST; wire [31:0] f0_RDATA; wire [1:0] f0_RRESP;
  wire viol;

  tb_clkreset #() u_ck (.clk(ACLK), .rstn(ARESETn));

  axi_master_vip u_vip (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_SEL(AW_SELv), .AW_VALID(AW_VALIDv), .AW_READY(AW_READYv),
    .AW_SIZE(AW_SIZEv), .AW_BURST(AW_BURSTv), .AW_LEN(AW_LENv), .AW_ADDR(AW_ADDRv),
    .W_VALID(W_VALIDv), .W_READY(W_READYv), .W_DATA(W_DATAv), .W_LAST(W_LASTv),
    .B_VALID(B_VALIDv), .B_READY(B_READYv), .B_RESP(B_RESPv),
    .AR_SEL(AR_SELv), .AR_VALID(AR_VALIDv), .AR_READY(AR_READYv),
    .AR_SIZE(AR_SIZEv), .AR_BURST(AR_BURSTv), .AR_LEN(AR_LENv), .AR_ADDR(AR_ADDRv),
    .R_VALID(R_VALIDv), .R_READY(R_READYv), .R_DATA(R_DATAv), .R_RESP(R_RESPv), .R_LAST(R_LASTv));

  // 多主仲裁（与soc_top同）
  ic_axi_master_arb u_arb (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .m0_awvalid(AW_VALIDv), .m0_awready(AW_READYv), .m0_awsize(AW_SIZEv),
    .m0_awburst(AW_BURSTv), .m0_awlen(AW_LENv), .m0_awaddr(AW_ADDRv),
    .m0_wvalid(W_VALIDv), .m0_wready(W_READYv), .m0_wlast(W_LASTv), .m0_wdata(W_DATAv),
    .m0_bvalid(B_VALIDv), .m0_bready(B_READYv), .m0_bresp(B_RESPv),
    .m0_arvalid(AR_VALIDv), .m0_arready(AR_READYv), .m0_arsize(AR_SIZEv),
    .m0_arburst(AR_BURSTv), .m0_arlen(AR_LENv), .m0_araddr(AR_ADDRv),
    .m0_rvalid(R_VALIDv), .m0_rready(R_READYv), .m0_rlast(R_LASTv),
    .m0_rdata(R_DATAv), .m0_rresp(R_RESPv),
    .m1_awvalid(dma_awvalid), .m1_awready(dma_awready), .m1_awsize(dma_awsize),
    .m1_awburst(dma_awburst), .m1_awlen(dma_awlen), .m1_awaddr(dma_awaddr),
    .m1_wvalid(dma_wvalid), .m1_wready(dma_wready), .m1_wlast(dma_wlast), .m1_wdata(dma_wdata),
    .m1_bvalid(dma_bvalid), .m1_bready(dma_bready), .m1_bresp(dma_bresp),
    .m1_arvalid(dma_arvalid), .m1_arready(dma_arready), .m1_arsize(dma_arsize),
    .m1_arburst(dma_arburst), .m1_arlen(dma_arlen), .m1_araddr(dma_araddr),
    .m1_rvalid(dma_rvalid), .m1_rready(dma_rready), .m1_rlast(dma_rlast),
    .m1_rdata(dma_rdata), .m1_rresp(dma_rresp),
    .awvalid(sys_AWVALID), .awready(sys_AWREADY), .awsize(sys_AWSIZE),
    .awburst(sys_AWBURST), .awlen(sys_AWLEN), .awaddr(sys_AWADDR),
    .wvalid(sys_WVALID), .wready(sys_WREADY), .wlast(sys_WLAST), .wdata(sys_WDATA),
    .bvalid(sys_BVALID), .bready(sys_BREADY), .bresp(sys_BRESP),
    .arvalid(sys_ARVALID), .arready(sys_ARREADY), .arsize(sys_ARSIZE),
    .arburst(sys_ARBURST), .arlen(sys_ARLEN), .araddr(sys_ARADDR),
    .rvalid(sys_RVALID), .rready(sys_RREADY), .rlast(sys_RLAST),
    .rdata(sys_RDATA), .rresp(sys_RRESP),
    .m0_done_cnt(), .m1_done_cnt(), .grant_imbalance());

  // 地址译码（与soc_top同）
  ic_axi_addr_decode u_dec (
    .w_addr(sys_AWADDR), .r_addr(sys_ARADDR),
    .flash_arsel(flash_arsel),
    .sram_awsel(sram_awsel), .sram_arsel(sram_arsel),
    .apbsys_awsel(apbsys_awsel), .apbsys_arsel(apbsys_arsel),
    .gpio0_awsel(gpio0_awsel), .gpio0_arsel(gpio0_arsel),
    .gpio1_awsel(gpio1_awsel), .gpio1_arsel(gpio1_arsel),
    .fir_awsel(fir_awsel), .fir_arsel(fir_arsel),
    .dma_awsel(dma_awsel), .dma_arsel(dma_arsel),
    .defslv_awsel(defslv_awsel), .defslv_arsel(defslv_arsel));

  // 从机复用器（与soc_top同，port2/3/7未实例化从机故禁用）
  ic_axi_slave_mux #(
    .PORT0_ENABLE(1), .PORT1_ENABLE(1), .PORT2_ENABLE(0), .PORT3_ENABLE(0),
    .PORT4_ENABLE(1), .PORT5_ENABLE(1), .PORT6_ENABLE(1), .PORT7_ENABLE(0),
    .PORT8_ENABLE(0), .PORT9_ENABLE(0), .DW(32))
  u_mux (
    .ACLK(ACLK), .ARESETn(ARESETn),
    // port0: 0x0区域（本TB无flash，挂默认从机防挂死）
    .AW_SEL0(1'b0), .AW_READY0(f0_AWREADY), .W_READY0(f0_WREADY),
    .B_VALID0(f0_BVALID), .B_RESP0(f0_BRESP),
    .AR_SEL0(flash_arsel), .AR_READY0(f0_ARREADY), .R_VALID0(f0_RVALID),
    .R_LAST0(f0_RLAST), .R_DATA0(f0_RDATA), .R_RESP0(f0_RRESP),
    // port1: SRAM
    .AW_SEL1(sram_awsel), .AW_READY1(sram_AWREADY), .W_READY1(sram_WREADY),
    .B_VALID1(sram_BVALID), .B_RESP1(sram_BRESP),
    .AR_SEL1(sram_arsel), .AR_READY1(sram_ARREADY), .R_VALID1(sram_RVALID),
    .R_LAST1(sram_RLAST), .R_DATA1(sram_RDATA), .R_RESP1(sram_RRESP),
    // port2/3禁用
    .AW_SEL2(1'b0), .AW_READY2(1'b0), .W_READY2(1'b0), .B_VALID2(1'b0), .B_RESP2(2'b0),
    .AR_SEL2(1'b0), .AR_READY2(1'b0), .R_VALID2(1'b0), .R_LAST2(1'b0),
    .R_DATA2(32'b0), .R_RESP2(2'b0),
    .AW_SEL3(1'b0), .AW_READY3(1'b0), .W_READY3(1'b0), .B_VALID3(1'b0), .B_RESP3(2'b0),
    .AR_SEL3(1'b0), .AR_READY3(1'b0), .R_VALID3(1'b0), .R_LAST3(1'b0),
    .R_DATA3(32'b0), .R_RESP3(2'b0),
    // port4: FIR
    .AW_SEL4(fir_awsel), .AW_READY4(fir_AWREADY), .W_READY4(fir_WREADY),
    .B_VALID4(fir_BVALID), .B_RESP4(fir_BRESP),
    .AR_SEL4(fir_arsel), .AR_READY4(fir_ARREADY), .R_VALID4(fir_RVALID),
    .R_LAST4(fir_RLAST), .R_DATA4(fir_RDATA), .R_RESP4(fir_RRESP),
    // port5: DMA配置
    .AW_SEL5(dma_awsel), .AW_READY5(dma_AWREADY), .W_READY5(dma_WREADY),
    .B_VALID5(dma_BVALID), .B_RESP5(dma_BRESP),
    .AR_SEL5(dma_arsel), .AR_READY5(dma_ARREADY), .R_VALID5(dma_RVALID),
    .R_LAST5(dma_RLAST), .R_DATA5(dma_RDATA), .R_RESP5(dma_RRESP),
    // port6: 默认从机
    .AW_SEL6(defslv_awsel), .AW_READY6(def_AWREADY), .W_READY6(def_WREADY),
    .B_VALID6(def_BVALID), .B_RESP6(def_BRESP),
    .AR_SEL6(defslv_arsel), .AR_READY6(def_ARREADY), .R_VALID6(def_RVALID),
    .R_LAST6(def_RLAST), .R_DATA6(def_RDATA), .R_RESP6(def_RRESP),
    // port7-9禁用
    .AW_SEL7(1'b0), .AW_READY7(1'b0), .W_READY7(1'b0), .B_VALID7(1'b0), .B_RESP7(2'b0),
    .AR_SEL7(1'b0), .AR_READY7(1'b0), .R_VALID7(1'b0), .R_LAST7(1'b0),
    .R_DATA7(32'b0), .R_RESP7(2'b0),
    .AW_SEL8(1'b0), .AW_READY8(1'b0), .W_READY8(1'b0), .B_VALID8(1'b0), .B_RESP8(2'b0),
    .AR_SEL8(1'b0), .AR_READY8(1'b0), .R_VALID8(1'b0), .R_LAST8(1'b0),
    .R_DATA8(32'b0), .R_RESP8(2'b0),
    .AW_SEL9(1'b0), .AW_READY9(1'b0), .W_READY9(1'b0), .B_VALID9(1'b0), .B_RESP9(2'b0),
    .AR_SEL9(1'b0), .AR_READY9(1'b0), .R_VALID9(1'b0), .R_LAST9(1'b0),
    .R_DATA9(32'b0), .R_RESP9(2'b0),
    // 共享主侧
    .AW_VALID(sys_AWVALID), .AW_READY(sys_AWREADY),
    .W_READY(sys_WREADY),
    .B_VALID(sys_BVALID), .B_READY(sys_BREADY), .B_RESP(sys_BRESP),
    .AR_VALID(sys_ARVALID), .AR_READY(sys_ARREADY),
    .R_VALID(sys_RVALID), .R_LAST(sys_RLAST), .R_DATA(sys_RDATA), .R_RESP(sys_RRESP),
    .R_READY(sys_RREADY));

  // SRAM（本项目axi_sram_sim，与soc_top同）
  axi_sram_sim #(.AW(16)) u_sram (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_SEL(sram_awsel), .AW_VALID(sys_AWVALID), .AW_READY(sram_AWREADY),
    .AW_SIZE(sys_AWSIZE), .AW_BURST(sys_AWBURST), .AW_LEN(sys_AWLEN),
    .AW_ADDR(sys_AWADDR[15:0]),
    .W_VALID(sys_WVALID), .W_READY(sram_WREADY), .W_LAST(sys_WLAST), .W_DATA(sys_WDATA),
    .B_VALID(sram_BVALID), .B_READY(sys_BREADY), .B_RESP(sram_BRESP),
    .AR_SEL(sram_arsel), .AR_VALID(sys_ARVALID), .AR_READY(sram_ARREADY),
    .AR_SIZE(sys_ARSIZE), .AR_BURST(sys_ARBURST), .AR_LEN(sys_ARLEN),
    .AR_ADDR(sys_ARADDR[15:0]),
    .R_VALID(sram_RVALID), .R_READY(sys_RREADY), .R_LAST(sram_RLAST),
    .R_DATA(sram_RDATA), .R_RESP(sram_RRESP));

  // FIR（对称核，与soc_top同）
  fir_top #(.CORE_TYPE(1)) u_fir (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_SEL(fir_awsel), .AW_VALID(sys_AWVALID), .AW_READY(fir_AWREADY),
    .AW_SIZE(sys_AWSIZE), .AW_BURST(sys_AWBURST), .AW_LEN(sys_AWLEN),
    .AW_ADDR(sys_AWADDR),
    .W_VALID(sys_WVALID), .W_READY(fir_WREADY), .W_LAST(sys_WLAST), .W_DATA(sys_WDATA),
    .B_VALID(fir_BVALID), .B_READY(sys_BREADY), .B_RESP(fir_BRESP),
    .AR_SEL(fir_arsel), .AR_VALID(sys_ARVALID), .AR_READY(fir_ARREADY),
    .AR_SIZE(sys_ARSIZE), .AR_BURST(sys_ARBURST), .AR_LEN(sys_ARLEN),
    .AR_ADDR(sys_ARADDR),
    .R_VALID(fir_RVALID), .R_READY(sys_RREADY), .R_LAST(fir_RLAST),
    .R_DATA(fir_RDATA), .R_RESP(fir_RRESP));

  // DMA（配置口+主口，与soc_top同；irq不接——VIP轮询STATUS）
  dma_top u_dma (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_SEL(dma_awsel), .AW_VALID(sys_AWVALID), .AW_READY(dma_AWREADY),
    .AW_SIZE(sys_AWSIZE), .AW_BURST(sys_AWBURST), .AW_LEN(sys_AWLEN),
    .AW_ADDR(sys_AWADDR),
    .W_VALID(sys_WVALID), .W_READY(dma_WREADY), .W_LAST(sys_WLAST), .W_DATA(sys_WDATA),
    .B_VALID(dma_BVALID), .B_READY(sys_BREADY), .B_RESP(dma_BRESP),
    .AR_SEL(dma_arsel), .AR_VALID(sys_ARVALID), .AR_READY(dma_ARREADY),
    .AR_SIZE(sys_ARSIZE), .AR_BURST(sys_ARBURST), .AR_LEN(sys_ARLEN),
    .AR_ADDR(sys_ARADDR),
    .R_VALID(dma_RVALID), .R_READY(sys_RREADY), .R_LAST(dma_RLAST),
    .R_DATA(dma_RDATA), .R_RESP(dma_RRESP),
    .awvalid(dma_awvalid), .awready(dma_awready), .awsize(dma_awsize),
    .awburst(dma_awburst), .awlen(dma_awlen), .awaddr(dma_awaddr),
    .wvalid(dma_wvalid), .wready(dma_wready), .wdata(dma_wdata), .wlast(dma_wlast),
    .bvalid(dma_bvalid), .bready(dma_bready), .bresp(dma_bresp),
    .arvalid(dma_arvalid), .arready(dma_arready), .arsize(dma_arsize),
    .arburst(dma_arburst), .arlen(dma_arlen), .araddr(dma_araddr),
    .rvalid(dma_rvalid), .rready(dma_rready), .rdata(dma_rdata), .rresp(dma_rresp),
    .rlast(dma_rlast),
    .irq_o());

  // 默认从机×2：port6（defslv区域）+port0（flash区域，本TB无flash防挂死）
  cmsdk_axi_default_slave u_defslv (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_SEL(defslv_awsel), .AW_VALID(sys_AWVALID), .AW_READY(def_AWREADY),
    .AW_LEN(sys_AWLEN),
    .W_VALID(sys_WVALID), .W_READY(def_WREADY),
    .B_VALID(def_BVALID), .B_READY(sys_BREADY), .B_RESP(def_BRESP),
    .AR_SEL(defslv_arsel), .AR_VALID(sys_ARVALID), .AR_READY(def_ARREADY),
    .AR_LEN(sys_ARLEN),
    .R_VALID(def_RVALID), .R_READY(sys_RREADY), .R_LAST(def_RLAST),
    .R_DATA(def_RDATA), .R_RESP(def_RRESP));
  cmsdk_axi_default_slave u_defslv0 (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_SEL(1'b0), .AW_VALID(sys_AWVALID), .AW_READY(f0_AWREADY),
    .AW_LEN(sys_AWLEN),
    .W_VALID(sys_WVALID), .W_READY(f0_WREADY),
    .B_VALID(f0_BVALID), .B_READY(sys_BREADY), .B_RESP(f0_BRESP),
    .AR_SEL(flash_arsel), .AR_VALID(sys_ARVALID), .AR_READY(f0_ARREADY),
    .AR_LEN(sys_ARLEN),
    .R_VALID(f0_RVALID), .R_READY(sys_RREADY), .R_LAST(f0_RLAST),
    .R_DATA(f0_RDATA), .R_RESP(f0_RRESP));

  // 协议检查器（挂在仲裁器共享主口）
  axi_checker u_chk (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_VALID(sys_AWVALID), .AW_READY(sys_AWREADY), .AW_SIZE(sys_AWSIZE),
    .AW_BURST(sys_AWBURST), .AW_LEN(sys_AWLEN), .AW_ADDR(sys_AWADDR),
    .W_VALID(sys_WVALID), .W_READY(sys_WREADY), .W_DATA(sys_WDATA), .W_LAST(sys_WLAST),
    .B_VALID(sys_BVALID), .B_READY(sys_BREADY), .B_RESP(sys_BRESP),
    .AR_VALID(sys_ARVALID), .AR_READY(sys_ARREADY), .AR_SIZE(sys_ARSIZE),
    .AR_BURST(sys_ARBURST), .AR_LEN(sys_ARLEN), .AR_ADDR(sys_ARADDR),
    .R_VALID(sys_RVALID), .R_READY(sys_RREADY), .R_DATA(sys_RDATA), .R_RESP(sys_RRESP), .R_LAST(sys_RLAST),
    .violation(viol));

  // ================= 激励数据 =================
  reg [15:0] coeff [0:81];
  reg [31:0] in_mem [0:1023];
  reg [31:0] gmem [0:1023];
  initial begin
    $readmemh("tb/data/coeff_q15.hex", coeff);
    $readmemh("tb/data/input_q15.hex", in_mem);
    $readmemh("tb/data/golden_q31.hex", gmem);
  end

  // ================= 激励与判定 =================
  integer i, blk, poll, bad_cnt;
  reg [31:0] s0, s1;
  initial begin
    wait (ARESETn == 1'b1);
    @(posedge ACLK);

    // 1) SRAM往返自检（16拍INCR写+读回，走完整互连）
    for (i = 0; i < 16; i = i + 1) u_vip.vip_wdata[i] = 32'hCAFE0000 + i;
    u_vip.axi_wr(32'h20003000, 8'd15, 2'b01, 3'b010);
    u_vip.axi_rd(32'h20003000, 8'd15, 2'b01, 3'b010);
    for (i = 0; i < 16; i = i + 1)
      if (u_vip.vip_rdata[i] !== 32'hCAFE0000 + i)
        $fatal(1, "FAIL: SRAM往返拍%0d=%h", i, u_vip.vip_rdata[i]);
    $display("集成-SRAM往返16拍INCR正确");

    // 2) FIR清零+配置82系数（6×16拍INCR，超出0x158的写被FIR忽略）
    u_vip.vip_wdata[0] = 32'h1;
    u_vip.axi_wr(32'h40020000, 8'd0, 2'b00, 3'b010);      // CTRL CLR
    for (blk = 0; blk < 6; blk = blk + 1) begin
      for (i = 0; i < 16; i = i + 1)
        u_vip.vip_wdata[i] = (blk * 16 + i < 82) ? {16'h0, coeff[blk * 16 + i]} : 32'h0;
      u_vip.axi_wr(32'h40020010 + blk * 64, 8'd15, 2'b01, 3'b010);
    end
    $display("集成-82系数配置完成");

    // 3) 写1024输入样本入SRAM（0x20001000，64×16拍INCR）
    for (blk = 0; blk < 64; blk = blk + 1) begin
      for (i = 0; i < 16; i = i + 1) u_vip.vip_wdata[i] = in_mem[blk * 16 + i];
      u_vip.axi_wr(32'h20001000 + blk * 64, 8'd15, 2'b01, 3'b010);
    end
    $display("集成-1024输入样本入SRAM完成");

    // 4) DMA ch0：SRAM→FIR DIN（FIXED_DST，FSIZE=2整字/拍，BURST=0——T14死锁裁定）
    u_vip.vip_wdata[0] = 32'h20001000; u_vip.axi_wr(32'h40030000, 8'd0, 2'b00, 3'b010);
    u_vip.vip_wdata[0] = 32'h40020008; u_vip.axi_wr(32'h40030004, 8'd0, 2'b00, 3'b010);
    u_vip.vip_wdata[0] = 32'd1024;     u_vip.axi_wr(32'h40030008, 8'd0, 2'b00, 3'b010);
    u_vip.vip_wdata[0] = 32'h0000020B; u_vip.axi_wr(32'h4003000C, 8'd0, 2'b00, 3'b010); // GO

    // 5) 等首样本入FIR DIN再GO ch1（防DOUT空读挂起挡死ch0，与固件GO顺序一致）
    poll = 0;
    u_vip.axi_rd(32'h40020004, 8'd0, 2'b00, 3'b010);
    while ((u_vip.vip_rdata[0] & 32'h1) && (poll < 100000)) begin
      u_vip.axi_rd(32'h40020004, 8'd0, 2'b00, 3'b010);
      poll = poll + 1;
    end
    if (poll >= 100000) $fatal(1, "FAIL: FIR DIN首样本等待超时");

    // 6) DMA ch1：FIR DOUT→SRAM（FIXED_SRC，FSIZE=2）
    u_vip.vip_wdata[0] = 32'h4002000C; u_vip.axi_wr(32'h40030020, 8'd0, 2'b00, 3'b010);
    u_vip.vip_wdata[0] = 32'h20002000; u_vip.axi_wr(32'h40030024, 8'd0, 2'b00, 3'b010);
    u_vip.vip_wdata[0] = 32'd1024;     u_vip.axi_wr(32'h40030028, 8'd0, 2'b00, 3'b010);
    u_vip.vip_wdata[0] = 32'h00000207; u_vip.axi_wr(32'h4003002C, 8'd0, 2'b00, 3'b010); // GO

    // 7) 轮询ch0/ch1 STATUS bit1=DONE
    poll = 0; s0 = 32'h0; s1 = 32'h0;
    while ((((s0 & 32'h2) == 0) || ((s1 & 32'h2) == 0)) && (poll < 1000000)) begin
      u_vip.axi_rd(32'h40030010, 8'd0, 2'b00, 3'b010); s0 = u_vip.vip_rdata[0];
      u_vip.axi_rd(32'h40030030, 8'd0, 2'b00, 3'b010); s1 = u_vip.vip_rdata[0];
      poll = poll + 1;
    end
    if (poll >= 1000000) $fatal(1, "FAIL: DMA完成等待超时 ch0=%h ch1=%h", s0, s1);
    $display("集成-DMA搬运完成（ch0=%h ch1=%h）", s0, s1);

    // 8) 读回out_buf（0x20002000，64×16拍）与黄金模型比对<0.1%
    bad_cnt = 0;
    for (blk = 0; blk < 64; blk = blk + 1) begin
      u_vip.axi_rd(32'h20002000 + blk * 64, 8'd15, 2'b01, 3'b010);
      for (i = 0; i < 16; i = i + 1) begin : cmp
        reg signed [31:0] hw_v, g_v, d_v;
        reg [31:0] a_d, a_g;
        hw_v = u_vip.vip_rdata[i];
        g_v  = gmem[blk * 16 + i];
        d_v  = hw_v - g_v;
        a_d = (d_v < 0) ? -d_v : d_v;      // 阈值同tb_soc：|hw-ref|>|ref|/1024
        a_g = (g_v < 0) ? -g_v : g_v;      // 即误差>0.0977%（严于0.1%）
        if (a_d > (a_g >> 10)) begin
          bad_cnt = bad_cnt + 1;
          if (bad_cnt <= 8)
            $display("INTEG-ERR i=%0d hw=%h ref=%h", blk * 16 + i, hw_v, g_v);
        end
      end
    end
    if (bad_cnt != 0)
      $fatal(1, "FAIL: FIR误差超标样本数=%0d（阈值0.1%%）", bad_cnt);

    if (viol) $fatal(1, "FAIL: 协议检查器有违规");
    $display("PASS: 集成验证（无CPU）——SRAM往返+82系数配置+1024样本FIR滤波黄金比对<0.1%%+协议零违规");
    $finish;
  end

  // 超时兜底
  initial begin
    #20000000;
    $fatal(1, "FAIL: 集成验证超时（20ms）");
  end
endmodule
