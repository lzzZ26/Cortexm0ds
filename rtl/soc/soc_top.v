// soc_top.v : 本项目SoC顶层（只实例化官方模块与新模块，不改官方文件）
// 拓扑：CPU集成层(AXI主) ─┐
//        DMA主口 ─────────┤→ ic_axi_master_arb → 官方cmsdk_axi_slave_mux
//  从机：port0=flash(0x0) port1=sram(0x2000_0000) port2=apbsys(0x4000_0000)
//        port3=gpio0(0x4001_0000) port4=fir(0x4002_0000) port5=dma_cfg(0x4003_0000)
//        port6=默认从机(DECERR)
// 官方mux只路由握手/响应：AW/AR/W通道与SIZE/LEN/ADDR由系统广播给全部从机，
// 各从机按SEL自行消费（CMSDK从机约定）。SEL由本项目ic_axi_addr_decode生成。
// 中断位序按官方源码核对：apbsubsys_interrupt[0]=UART0 RX、[1]=UART0 TX，
// [15]为官方预留的DMA槽位（dma_irq接此），[16:31]=GPIO0个位中断。
`timescale 1ns/1ps
`include "cmsdk_axi_memory_defs.v"

module soc_top #(
    parameter FILENAME = "image.hex",     // 固件hex（仿真flash/$readmemh路径相对运行目录）
    parameter MEM_IMPL = 0                // 0=cmsdk_axi_flash(仿真)
)(
    input  wire        ACLK,
    input  wire        ARESETn,
    input  wire        PCLK,
    input  wire        PRESETn,
    // UART
    input  wire        uart0_rxd,
    output wire        uart0_txd,
    output wire        uart0_txen,
    output wire        uart2_txd,         // stdout（retarget默认UART2）
    output wire        uart2_txen,
    // GPIO0（LED演示）
    output wire [15:0] gpio0_out,
    input  wire        DFTSE
);
  // ================= CPU到仲裁器 =================
  wire        cm0_AWVALID, cm0_AWREADY;
  wire [2:0]  cm0_AWSIZE;  wire [1:0] cm0_AWBURST; wire [7:0] cm0_AWLEN;
  wire [31:0] cm0_AWADDR;
  wire        cm0_WVALID, cm0_WREADY, cm0_WLAST; wire [31:0] cm0_WDATA;
  wire        cm0_BVALID, cm0_BREADY; wire [1:0] cm0_BRESP;
  wire        cm0_ARVALID, cm0_ARREADY;
  wire [2:0]  cm0_ARSIZE;  wire [1:0] cm0_ARBURST; wire [7:0] cm0_ARLEN;
  wire [31:0] cm0_ARADDR;
  wire        cm0_RVALID, cm0_RREADY, cm0_RLAST;
  wire [31:0] cm0_RDATA;   wire [1:0] cm0_RRESP;
  wire [31:0] intisr;
  wire        LOCKUP, SYSRESETREQ;
  wire        cpu_halted, cpu_sleeping;      // 调试观测（TB层次引用）

  // ================= 共享总线（仲裁器输出→slave mux主侧） =================
  wire        sys_AWVALID, sys_AWREADY;
  wire [2:0]  sys_AWSIZE;  wire [1:0] sys_AWBURST; wire [7:0] sys_AWLEN;
  wire [31:0] sys_AWADDR;
  wire        sys_WVALID, sys_WREADY, sys_WLAST; wire [31:0] sys_WDATA;
  wire        sys_BVALID, sys_BREADY; wire [1:0] sys_BRESP;
  wire        sys_ARVALID, sys_ARREADY;
  wire [2:0]  sys_ARSIZE;  wire [1:0] sys_ARBURST; wire [7:0] sys_ARLEN;
  wire [31:0] sys_ARADDR;
  wire        sys_RVALID, sys_RREADY, sys_RLAST;
  wire [31:0] sys_RDATA;   wire [1:0] sys_RRESP;

  // ================= 译码SEL =================
  wire flash_arsel, sram_awsel, sram_arsel, apbsys_awsel, apbsys_arsel;
  wire gpio0_awsel, gpio0_arsel, gpio1_awsel, gpio1_arsel;
  wire fir_awsel, fir_arsel, dma_awsel, dma_arsel;
  wire defslv_awsel, defslv_arsel;

  // ================= 各从机 =================
  wire flash_ARREADY, flash_RVALID, flash_RLAST; wire [31:0] flash_RDATA; wire [1:0] flash_RRESP;
  wire sram_AWREADY, sram_WREADY, sram_BVALID; wire [1:0] sram_BRESP;
  wire sram_ARREADY, sram_RVALID, sram_RLAST; wire [31:0] sram_RDATA; wire [1:0] sram_RRESP;
  wire apb_AWREADY, apb_WREADY, apb_BVALID; wire [1:0] apb_BRESP;
  wire apb_ARREADY, apb_RVALID, apb_RLAST; wire [31:0] apb_RDATA; wire [1:0] apb_RRESP;
  wire g0_AWREADY, g0_WREADY, g0_BVALID; wire [1:0] g0_BRESP;
  wire g0_ARREADY, g0_RVALID, g0_RLAST; wire [31:0] g0_RDATA; wire [1:0] g0_RRESP;
  wire g1_AWREADY, g1_WREADY, g1_BVALID; wire [1:0] g1_BRESP;
  wire g1_ARREADY, g1_RVALID, g1_RLAST; wire [31:0] g1_RDATA; wire [1:0] g1_RRESP;
  wire fir_AWREADY, fir_WREADY, fir_BVALID; wire [1:0] fir_BRESP;
  wire fir_ARREADY, fir_RVALID, fir_RLAST; wire [31:0] fir_RDATA; wire [1:0] fir_RRESP;
  wire dma_AWREADY, dma_WREADY, dma_BVALID; wire [1:0] dma_BRESP;
  wire dma_ARREADY, dma_RVALID, dma_RLAST; wire [31:0] dma_RDATA; wire [1:0] dma_RRESP;
  wire def_AWREADY, def_WREADY, def_BVALID; wire [1:0] def_BRESP;
  wire def_ARREADY, def_RVALID, def_RLAST; wire [31:0] def_RDATA; wire [1:0] def_RRESP;

  // ================= APB子系统 =================
  wire [31:0] apbsubsys_interrupt;
  wire        APBACTIVE;
  wire        uart2_rxd;
  assign uart2_rxd = 1'b1;

  // ================= DMA =================
  wire dma_awvalid, dma_awready; wire [2:0] dma_awsize; wire [1:0] dma_awburst;
  wire [7:0] dma_awlen; wire [31:0] dma_awaddr;
  wire dma_wvalid, dma_wready, dma_wlast; wire [31:0] dma_wdata;
  wire dma_bvalid, dma_bready; wire [1:0] dma_bresp;
  wire dma_arvalid, dma_arready; wire [2:0] dma_arsize; wire [1:0] dma_arburst;
  wire [7:0] dma_arlen; wire [31:0] dma_araddr;
  wire dma_rvalid, dma_rready, dma_rlast; wire [31:0] dma_rdata; wire [1:0] dma_rresp;
  wire dma_irq;

  // ================= GPIO0 =================
  wire [15:0] p0_in, p0_out, p0_outen, p0_altfunc;
  wire [15:0] gpio0_intr; wire gpio0_combintr;
  assign p0_in = 16'h0;
  assign gpio0_out = p0_out;

  // ================= CPU（端口连接与官方cmsdk_mcu_system逐一对齐） =================
  cortexm0integration
  u_cpu (
    // CLOCK AND RESETS
    .FCLK(ACLK), .SCLK(ACLK), .ACLK(ACLK), .DCLK(),
    .PORESETn(ARESETn), .DBGRESETn(), .ARESETn(ARESETn),
    .SWCLKTCK(), .nTRST(),
    // AXI-LITE MASTER PORT
    .AW_VALID(cm0_AWVALID), .AW_READY(cm0_AWREADY), .AW_SIZE(cm0_AWSIZE),
    .AW_BURST(cm0_AWBURST), .AW_LEN(cm0_AWLEN), .AW_ADDR(cm0_AWADDR),
    .W_VALID(cm0_WVALID), .W_READY(cm0_WREADY), .W_LAST(cm0_WLAST), .W_DATA(cm0_WDATA),
    .B_VALID(cm0_BVALID), .B_READY(cm0_BREADY), .B_RESP(cm0_BRESP),
    .AR_VALID(cm0_ARVALID), .AR_READY(cm0_ARREADY), .AR_SIZE(cm0_ARSIZE),
    .AR_BURST(cm0_ARBURST), .AR_LEN(cm0_ARLEN), .AR_ADDR(cm0_ARADDR),
    .R_VALID(cm0_RVALID), .R_READY(cm0_RREADY), .R_LAST(cm0_RLAST),
    .R_DATA(cm0_RDATA), .R_RESP(cm0_RRESP),
    // CODE SEQUENTIALITY AND SPECULATION
    .CODENSEQ(), .CODEHINTDE(), .SPECHTRANS(),
    // DEBUG
    .SWDITMS(1'b0), .TDI(1'b0), .SWDO(), .SWDOEN(), .TDO(), .nTDOEN(),
    .DBGRESTART(1'b0), .DBGRESTARTED(), .EDBGRQ(1'b0), .HALTED(cpu_halted),
    // MISC
    .NMI(1'b0), .IRQ(intisr), .TXEV(), .RXEV(1'b0),
    .LOCKUP(LOCKUP), .SYSRESETREQ(SYSRESETREQ),
    .IRQLATENCY(8'h00), .ECOREVNUM(28'h0),
    // POWER MANAGEMENT
    .GATEHCLK(), .SLEEPING(cpu_sleeping), .SLEEPDEEP(), .WAKEUP(), .WICSENSE(),
    .SLEEPHOLDREQn(1'b1), .SLEEPHOLDACKn(), .WICENREQ(1'b0), .WICENACK(),
    .CDBGPWRUPREQ(), .CDBGPWRUPACK(1'b0),
    // SCAN IO
    .SE(1'b0), .RSTBYPASS(1'b0));

  // ================= 多主仲裁 =================
  ic_axi_master_arb u_arb (
    .aclk(ACLK), .aresetn(ARESETn),
    .m0_awvalid(cm0_AWVALID), .m0_awready(cm0_AWREADY), .m0_awsize(cm0_AWSIZE),
    .m0_awburst(cm0_AWBURST), .m0_awlen(cm0_AWLEN), .m0_awaddr(cm0_AWADDR),
    .m0_wvalid(cm0_WVALID), .m0_wready(cm0_WREADY), .m0_wlast(cm0_WLAST), .m0_wdata(cm0_WDATA),
    .m0_bvalid(cm0_BVALID), .m0_bready(cm0_BREADY), .m0_bresp(cm0_BRESP),
    .m0_arvalid(cm0_ARVALID), .m0_arready(cm0_ARREADY), .m0_arsize(cm0_ARSIZE),
    .m0_arburst(cm0_ARBURST), .m0_arlen(cm0_ARLEN), .m0_araddr(cm0_ARADDR),
    .m0_rvalid(cm0_RVALID), .m0_rready(cm0_RREADY), .m0_rlast(cm0_RLAST),
    .m0_rdata(cm0_RDATA), .m0_rresp(cm0_RRESP),
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

  // ================= 地址译码 =================
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

  // ================= 从机mux（本项目ic_axi_slave_mux） =================
  // port0=flash(只读) port1=sram port2=apbsys port3=gpio0
  // port4=fir port5=dma_cfg port6=defslv port7=gpio1 port8-9禁用
  // 不用官方cmsdk_axi_slave_mux：其B/R路由选择寄存器按VALID电平锁存（非握手），
  // 多主并发下CPU取指ARVALID会在DMA读的R响应期间刷新路由，DMA收到错误从机的
  // R/R_LAST→err→传输夭折（详见ic_axi_slave_mux.v头注释）。
  ic_axi_slave_mux #(
    .PORT0_ENABLE(1), .PORT1_ENABLE(1), .PORT2_ENABLE(1), .PORT3_ENABLE(1),
    .PORT4_ENABLE(1), .PORT5_ENABLE(1), .PORT6_ENABLE(1), .PORT7_ENABLE(1),
    .PORT8_ENABLE(0), .PORT9_ENABLE(0), .DW(32))
  u_axi_slave_mux (
    .ACLK(ACLK), .ARESETn(ARESETn),
    // port0: flash/rom（只读，AW侧全0）
    .AW_SEL0(1'b0), .AW_READY0(1'b0), .W_READY0(1'b0),
    .B_VALID0(1'b0), .B_RESP0(2'b0),
    .AR_SEL0(flash_arsel), .AR_READY0(flash_ARREADY), .R_VALID0(flash_RVALID),
    .R_LAST0(flash_RLAST), .R_DATA0(flash_RDATA), .R_RESP0(flash_RRESP),
    // port1: SRAM
    .AW_SEL1(sram_awsel), .AW_READY1(sram_AWREADY), .W_READY1(sram_WREADY),
    .B_VALID1(sram_BVALID), .B_RESP1(sram_BRESP),
    .AR_SEL1(sram_arsel), .AR_READY1(sram_ARREADY), .R_VALID1(sram_RVALID),
    .R_LAST1(sram_RLAST), .R_DATA1(sram_RDATA), .R_RESP1(sram_RRESP),
    // port2: APB子系统
    .AW_SEL2(apbsys_awsel), .AW_READY2(apb_AWREADY), .W_READY2(apb_WREADY),
    .B_VALID2(apb_BVALID), .B_RESP2(apb_BRESP),
    .AR_SEL2(apbsys_arsel), .AR_READY2(apb_ARREADY), .R_VALID2(apb_RVALID),
    .R_LAST2(apb_RLAST), .R_DATA2(apb_RDATA), .R_RESP2(apb_RRESP),
    // port3: GPIO0
    .AW_SEL3(gpio0_awsel), .AW_READY3(g0_AWREADY), .W_READY3(g0_WREADY),
    .B_VALID3(g0_BVALID), .B_RESP3(g0_BRESP),
    .AR_SEL3(gpio0_arsel), .AR_READY3(g0_ARREADY), .R_VALID3(g0_RVALID),
    .R_LAST3(g0_RLAST), .R_DATA3(g0_RDATA), .R_RESP3(g0_RRESP),
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
    // port7: GPIO1（hello固件写ALTFUNCSET=0x20设置P1[5]复用，必须响应OKAY）
    .AW_SEL7(gpio1_awsel), .AW_READY7(g1_AWREADY), .W_READY7(g1_WREADY),
    .B_VALID7(g1_BVALID), .B_RESP7(g1_BRESP),
    .AR_SEL7(gpio1_arsel), .AR_READY7(g1_ARREADY), .R_VALID7(g1_RVALID),
    .R_LAST7(g1_RLAST), .R_DATA7(g1_RDATA), .R_RESP7(g1_RRESP),
    // port8-9禁用
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

  // ================= 存储 =================
  cmsdk_axi_flash #(.filename(FILENAME), .AW(16),
                    .WS_N(`ARM_CMSDK_ROM_MEM_WS_N), .WS_S(`ARM_CMSDK_ROM_MEM_WS_S))
  u_flash (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AR_SEL(flash_arsel), .AR_VALID(sys_ARVALID), .AR_READY(flash_ARREADY),
    .AR_SIZE(sys_ARSIZE), .AR_BURST(sys_ARBURST), .AR_LEN(sys_ARLEN),
    .AR_ADDR(sys_ARADDR[15:0]),
    .R_VALID(flash_RVALID), .R_READY(sys_RREADY), .R_LAST(flash_RLAST),
    .R_DATA(flash_RDATA), .R_RESP(flash_RRESP));

  // SRAM：本项目axi_sram_sim（官方cmsdk_axi_ram_beh的写锁存带读写互斥，
  // 在"读在途+写AW重叠"时静默丢写且B仍回OKAY——本项目仲裁器1拍授权延迟
  // 恰好命中该窗口致栈帧写丢失HardFault。详见axi_sram_sim.v头注释。）
  axi_sram_sim #(.AW(16))
  u_sram (
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

  // ================= APB子系统（UART0-2/Timer/WDT） =================
  cmsdk_axi2apb_subsystem u_apb (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_SEL(apbsys_awsel), .AW_VALID(sys_AWVALID), .AW_READY(apb_AWREADY),
    .AW_SIZE(sys_AWSIZE), .AW_BURST(sys_AWBURST), .AW_LEN(sys_AWLEN),
    .AW_ADDR(sys_AWADDR),
    .W_VALID(sys_WVALID), .W_READY(apb_WREADY), .W_LAST(sys_WLAST), .W_DATA(sys_WDATA),
    .B_VALID(apb_BVALID), .B_READY(sys_BREADY), .B_RESP(apb_BRESP),
    .AR_SEL(apbsys_arsel), .AR_VALID(sys_ARVALID), .AR_READY(apb_ARREADY),
    .AR_SIZE(sys_ARSIZE), .AR_BURST(sys_ARBURST), .AR_LEN(sys_ARLEN),
    .AR_ADDR(sys_ARADDR),
    .R_VALID(apb_RVALID), .R_READY(sys_RREADY), .R_LAST(apb_RLAST),
    .R_DATA(apb_RDATA), .R_RESP(apb_RRESP),
    .PCLK(PCLK), .PCLKG(PCLK), .PCLKEN(1'b1), .PRESETn(PRESETn),
    .APBACTIVE(APBACTIVE),
    .uart0_rxd(uart0_rxd), .uart0_txd(uart0_txd), .uart0_txen(uart0_txen),
    .uart1_rxd(1'b1), .uart1_txd(), .uart1_txen(),
    .uart2_rxd(uart2_rxd), .uart2_txd(uart2_txd), .uart2_txen(uart2_txen),
    .timer0_extin(1'b0), .timer1_extin(1'b0),
    .apbsubsys_interrupt(apbsubsys_interrupt), .watchdog_interrupt(), .watchdog_reset());

  // ================= GPIO0 =================
  cmsdk_axi_gpio #(.ALTERNATE_FUNC_MASK(16'h0000), .ALTERNATE_FUNC_DEFAULT(16'h0000))
  u_gpio0 (
    .FCLK(ACLK), .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_SEL(gpio0_awsel), .AW_VALID(sys_AWVALID), .AW_READY(g0_AWREADY),
    .AW_SIZE(sys_AWSIZE), .AW_BURST(sys_AWBURST), .AW_LEN(sys_AWLEN),
    .AW_ADDR(sys_AWADDR),
    .W_VALID(sys_WVALID), .W_READY(g0_WREADY), .W_LAST(sys_WLAST), .W_DATA(sys_WDATA),
    .B_VALID(g0_BVALID), .B_READY(sys_BREADY), .B_RESP(g0_BRESP),
    .AR_SEL(gpio0_arsel), .AR_VALID(sys_ARVALID), .AR_READY(g0_ARREADY),
    .AR_SIZE(sys_ARSIZE), .AR_BURST(sys_ARBURST), .AR_LEN(sys_ARLEN),
    .AR_ADDR(sys_ARADDR),
    .R_VALID(g0_RVALID), .R_READY(sys_RREADY), .R_LAST(g0_RLAST),
    .R_DATA(g0_RDATA), .R_RESP(g0_RRESP),
    .ECOREVNUM(4'h0),
    .PORTIN(p0_in), .PORTOUT(p0_out), .PORTEN(p0_outen), .PORTFUNC(p0_altfunc),
    .GPIOINT(gpio0_intr), .COMBINT(gpio0_combintr));

  // ================= GPIO1（hello固件写ALTFUNCSET设置UART2引脚复用） =================
  // 参数与官方cmsdk_mcu_system的u_axi_gpio_1一致：P1[1]/[3]/[5]（UART0/1/2 TXD）复用。
  // 本项目SoC直接暴露uart2_txd顶层输出，无引脚复用——但ALTFUNCSET写必须被接受（OKAY）。
  wire [15:0] p1_in, p1_out, p1_outen, p1_altfunc;
  wire [15:0] gpio1_intr; wire gpio1_combintr;
  assign p1_in = 16'h0;
  cmsdk_axi_gpio #(.ALTERNATE_FUNC_MASK(16'h002A), .ALTERNATE_FUNC_DEFAULT(16'h0000))
  u_gpio1 (
    .FCLK(ACLK), .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_SEL(gpio1_awsel), .AW_VALID(sys_AWVALID), .AW_READY(g1_AWREADY),
    .AW_SIZE(sys_AWSIZE), .AW_BURST(sys_AWBURST), .AW_LEN(sys_AWLEN),
    .AW_ADDR(sys_AWADDR),
    .W_VALID(sys_WVALID), .W_READY(g1_WREADY), .W_LAST(sys_WLAST), .W_DATA(sys_WDATA),
    .B_VALID(g1_BVALID), .B_READY(sys_BREADY), .B_RESP(g1_BRESP),
    .AR_SEL(gpio1_arsel), .AR_VALID(sys_ARVALID), .AR_READY(g1_ARREADY),
    .AR_SIZE(sys_ARSIZE), .AR_BURST(sys_ARBURST), .AR_LEN(sys_ARLEN),
    .AR_ADDR(sys_ARADDR),
    .R_VALID(g1_RVALID), .R_READY(sys_RREADY), .R_LAST(g1_RLAST),
    .R_DATA(g1_RDATA), .R_RESP(g1_RRESP),
    .ECOREVNUM(4'h0),
    .PORTIN(p1_in), .PORTOUT(p1_out), .PORTEN(p1_outen), .PORTFUNC(p1_altfunc),
    .GPIOINT(gpio1_intr), .COMBINT(gpio1_combintr));

  // ================= FIR / DMA =================
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
    .irq_o(dma_irq));

  // ================= 默认从机 =================
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

  // ================= 中断 =================
  // 按官方源码核对：apbsubsys_interrupt[0]=UART0 RX、[1]=UART0 TX、
  // [2]=UART1 RX、[3]=UART1 TX、[4]=UART2 RX、[5]=UART2 TX、
  // [8]=timer0、[9]=timer1、[10]=dualtimer、[15]=官方预留DMA槽位。
  // （计划原文"IRQ[0]=UART0 TX、IRQ[1]=UART0 RX"与官方位序相反，已修正。）
  assign intisr[ 5: 0] = apbsubsys_interrupt[ 5: 0];
  assign intisr[ 6]    = apbsubsys_interrupt[ 6]   | gpio0_combintr;
  assign intisr[14: 7] = apbsubsys_interrupt[14: 7];
  assign intisr[15]    = dma_irq;                  // 官方预留的DMA中断槽位
  assign intisr[31:16] = apbsubsys_interrupt[31:16] | gpio0_intr;

endmodule
