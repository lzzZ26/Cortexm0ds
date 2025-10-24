//------------------------------------------------------------------------------
// The confidential and proprietary information contained in this file may
// only be used by a person authorised under and to the extent permitted
// by a subsisting licensing agreement from ARM Limited.
//
//            (C) COPYRIGHT 2010-2015  ARM Limited or its affiliates.
//                ALL RIGHTS RESERVED
//
// This entire notice must be reproduced on all copies of this file
// and copies of this file may only be made by a person if such person is
// permitted to do so under the terms of a subsisting license agreement
// from ARM Limited.
//
//  Version and Release Control Information:
//
//  File Revision       : $Revision: 275084 $
//  File Date           : $Date: 2014-03-27 15:09:11 +0000 (Thu, 27 Mar 2014) $
//
//  Release Information : Cortex-M0 DesignStart-r1p0-00rel0
//------------------------------------------------------------------------------
// Verilog-2001 (IEEE Std 1364-2001)
//------------------------------------------------------------------------------
//
//-----------------------------------------------------------------------------
// Abstract : System level design for the example Cortex-M0 system
//-----------------------------------------------------------------------------
// Note: This file has been modified from original CMSDK due to memory
//       map differences, and extra peripheral interrupts

`include "cmsdk_axi_memory_defs.v"

module cmsdk_mcu_system #(
    parameter filename        = "",                 // 测试程序（二进制指令代码）
    parameter BASEADDR_GPIO0  = 32'h4001_0000,      // GPIO0 peripheral base address
    parameter BASEADDR_GPIO1  = 32'h4001_1000,      // GPIO1 peripheral base address
    //parameter BASEADDR_UART4  = 32'h4001_2000,    // UART4 peripheral base address
    parameter BKPT            = 0,                  // Number of breakpoint comparators
    parameter DBG             = 0,                  // Debug configuration
    parameter NUMIRQ          = 32,                 // NUM of IRQ
    parameter SMUL            = 0,                  // Multiplier configuration
    parameter SYST            = 1,                  // SysTick
    parameter WIC             = 0,                  // Wake-up interrupt controller support
    parameter WICLINES        = 34,                 // Supported WIC lines
    parameter WPT             = 0,                  // Number of DWT comparators
    // Location of the System ROM Table.
    parameter BASEADDR_SYSROMTABLE = 32'hF000_0000
    )
    (
    input  wire               FCLK,                 // Free running clock
    input  wire               SCLK,                 // System clock
    input  wire               PORESETn,             // Power on reset
    input  wire               ACLK,                 // AXI clock(from PMU)
    input  wire               ARESETn,              // AXI and System reset
    input  wire               PCLK,                 // Peripheral clock
    input  wire               PCLKG,                // Gated Peripheral bus clock
    input  wire               PCLKEN,               // Clock divide control for AXI to APB bridge
    input  wire               PRESETn,              // Peripheral system and APB reset

    output wire               APBACTIVE,            // APB bus active (for clock gating of PCLKG)
    output wire               SLEEPING,             // Processor status - sleeping
    output wire               SLEEPDEEP,            // Processor status - deep sleep
    output wire               SYSRESETREQ,          // Processor control - system reset request
    output wire               WDOGRESETREQ,         // Watchdog reset request
    output wire               LOCKUP,               // Processor status - Locked up
    output wire               LOCKUPRESET,          // System Controller cfg - reset if lockup
    output wire               PMUENABLE,            // System Controller cfg - Enable PMU

    input  wire               uart0_rxd,            // Uart 0 receive data
    output wire               uart0_txd,            // Uart 0 transmit data
    output wire               uart0_txen,           // Uart 0 transmit data enable
    input  wire               uart1_rxd,            // Uart 1 receive data
    output wire               uart1_txd,            // Uart 1 transmit data
    output wire               uart1_txen,           // Uart 1 transmit data enable
    input  wire               uart2_rxd,            // Uart 2 receive data
    output wire               uart2_txd,            // Uart 2 transmit data
    output wire               uart2_txen,           // Uart 2 transmit data enable
    /*
    input  wire               uart4_rxd,            // Uart 4 receive data
    output wire               uart4_txd,            // Uart 4 transmit data
    output wire               uart4_txen,           // Uart 4 transmit data enable
    */
    input  wire               timer0_extin,         // Timer 0 external input
    input  wire               timer1_extin,         // Timer 1 external input

    input  wire  [15:0]       p0_in,                // GPIO 0 inputs
    output wire  [15:0]       p0_out,               // GPIO 0 outputs
    output wire  [15:0]       p0_outen,             // GPIO 0 output enables
    output wire  [15:0]       p0_altfunc,           // GPIO 0 alternate function (pin mux)
    input  wire  [15:0]       p1_in,                // GPIO 1 inputs
    output wire  [15:0]       p1_out,               // GPIO 1 outputs
    output wire  [15:0]       p1_outen,             // GPIO 1 output enables
    output wire  [15:0]       p1_altfunc,           // GPIO 1 alternate function (pin mux)

    input  wire               DFTSE                 // dummy scan enable port for synthesis
    );

    // -------------------------------
    // Internal signals
    // -------------------------------
    // System bus from core 
    wire              cm0_AWVALID;                  // core master write request valid
    wire              cm0_AWREADY;                  // core master write request ready
    wire   [2:0]      cm0_AWSIZE;                   // core master write data size
    wire   [1:0]      cm0_AWBURST;                  // core master write burst type
    wire   [7:0]      cm0_AWLEN;                    // core master write burst length
    wire   [31:0]     cm0_AWADDR;                   // core master write address
    wire              cm0_WVALID;                   // core master write data valid
    wire              cm0_WREADY;                   // core master write data ready
    wire              cm0_WLAST;                    // core master write data last
    wire   [31:0]     cm0_WDATA;                    // core master write data
    wire              cm0_BVALID;                   // core master write response valid
    wire              cm0_BREADY;                   // core master write response ready
    wire   [1:0]      cm0_BRESP;                    // core master write response
    wire              cm0_ARVALID;                  // core master read request valid
    wire              cm0_ARREADY;                  // core master read request ready
    wire   [2:0]      cm0_ARSIZE;                   // core master read data size
    wire   [1:0]      cm0_ARBURST;                  // core master read burst type
    wire   [7:0]      cm0_ARLEN;                    // core master read burst length
    wire   [31:0]     cm0_ARADDR;                   // core master read address
    wire              cm0_RVALID;                   // core master read data valid
    wire              cm0_RREADY;                   // core master read data ready
    wire              cm0_RLAST;                    // core master read data last
    wire   [31:0]     cm0_RDATA;                    // core master read data
    wire   [1:0]      cm0_RRESP;                    // core master read response

    // Bit band wrapper bus between CPU core and the reset of the system
    wire              cm_AWVALID;
    wire              cm_AWREADY;
    wire   [2:0]      cm_AWSIZE;
    wire   [1:0]      cm_AWBURST;
    wire   [7:0]      cm_AWLEN;
    wire   [31:0]     cm_AWADDR;
    wire              cm_WVALID;
    wire              cm_WREADY;
    wire              cm_WLAST;
    wire   [31:0]     cm_WDATA;
    wire              cm_BVALID;
    wire              cm_BREADY;
    wire   [1:0]      cm_BRESP;
    wire              cm_ARVALID;
    wire              cm_ARREADY;
    wire   [2:0]      cm_ARSIZE;
    wire   [1:0]      cm_ARBURST;
    wire   [7:0]      cm_ARLEN;
    wire   [31:0]     cm_ARADDR;
    wire              cm_RVALID;
    wire              cm_RREADY;
    wire              cm_RLAST;
    wire   [31:0]     cm_RDATA;
    wire   [1:0]      cm_RRESP;

    // System bus
    wire              sys_AWVALID;                  // Write request valid
    wire              sys_AWREADY;                  // Write request ready
    wire   [2:0]      sys_AWSIZE;                   // Write data size
    wire   [1:0]      sys_AWBURST;                  // Write burst type
    wire   [7:0]      sys_AWLEN;                    // Write burst length
    wire   [31:0]     sys_AWADDR;                   // Write address
    wire              sys_WVALID;                   // Write data valid
    wire              sys_WREADY;                   // Write data ready
    wire              sys_WLAST;                    // Write last
    wire   [31:0]     sys_WDATA;                    // Write data
    wire              sys_BVALID;                   // Write response valid
    wire              sys_BREADY;                   // Write response ready
    wire   [1:0]      sys_BRESP;                    // Write response
    wire              sys_ARVALID;                  // Read request valid
    wire              sys_ARREADY;                  // Read request ready
    wire   [2:0]      sys_ARSIZE;                   // Read data size
    wire   [1:0]      sys_ARBURST;                  // Read burst type
    wire   [7:0]      sys_ARLEN;                    // Read burst length
    wire   [31:0]     sys_ARADDR;                   // Read address
    wire              sys_RVALID;                   // Read data valid
    wire              sys_RREADY;                   // Read data ready
    wire              sys_RLAST;                    // Read data last
    wire   [31:0]     sys_RDATA;                    // Read data
    wire   [1:0]      sys_RRESP;                    // Read response

    // AXI default slave signals
    wire              defslv_awsel;
    wire              defslv_arsel;
    wire              defslv_AWREADY;
    wire              defslv_WREADY;
    wire              defslv_BVALID;
    wire   [1:0]      defslv_BRESP;
    wire              defslv_ARREADY;
    wire              defslv_RVALID;
    wire              defslv_RLAST;
    wire   [31:0]     defslv_RDATA;
    wire   [1:0]      defslv_RRESP;

    // System control bus interface signals
    wire              sysctrl_awsel;
    wire              sysctrl_arsel;
    wire              sysctrl_AWREADY;
    wire              sysctrl_WREADY;
    wire              sysctrl_BVALID;
    wire   [1:0]      sysctrl_BRESP;
    wire              sysctrl_ARREADY;
    wire              sysctrl_RVALID;
    wire              sysctrl_RLAST;
    wire   [31:0]     sysctrl_RDATA;
    wire   [1:0]      sysctrl_RRESP;

    // System ROM Table
    wire              sysrom_arsel;                 // AXI to System ROM Table - select
    wire              sysrom_AWREADY = 1'b1;
    wire              sysrom_WREADY  = 1'b1;
    wire              sysrom_BVALID  = 1'b1;
    wire   [1:0]      sysrom_BRESP   = 2'b11;       // 一个未被控制的错误，通常地址解码为无效地址。
    wire              sysrom_ARREADY;
    wire              sysrom_RVALID;
    wire              sysrom_RLAST;
    wire   [31:0]     sysrom_RDATA;
    wire   [1:0]      sysrom_RRESP;

    // boot loader AXI signals
    wire              boot_arsel;
    wire              boot_AWREADY;
    wire              boot_WREADY;
    wire              boot_BVALID;
    wire   [1:0]      boot_BRESP;
    wire              boot_ARREADY;
    wire              boot_RVALID;
    wire              boot_RLAST;
    wire   [31:0]     boot_RDATA;
    wire   [1:0]      boot_RRESP;

    // Flash memory AXI signals
    wire              flash_arsel;
    wire              flash_AWREADY = 1'b1;
    wire              flash_WREADY  = 1'b1;
    wire              flash_BVALID  = 1'b1;
    wire   [1:0]      flash_BRESP   = 2'b11;        // 一个未被控制的错误，通常地址解码为无效地址。
    wire              flash_ARREADY;
    wire              flash_RVALID;
    wire              flash_RLAST;
    wire   [31:0]     flash_RDATA;
    wire   [1:0]      flash_RRESP;

    // SRAM AXI signals
    wire              sram_awsel;
    wire              sram_arsel;
    wire              sram_AWREADY;
    wire              sram_WREADY;
    wire              sram_BVALID;
    wire   [1:0]      sram_BRESP;
    wire              sram_ARREADY;
    wire              sram_RVALID;
    wire              sram_RLAST;
    wire   [31:0]     sram_RDATA;
    wire   [1:0]      sram_RRESP;

    // AXI GPIO bus interface signals
    wire              gpio0_awsel;
    wire              gpio0_arsel;
    wire              gpio0_AWREADY;
    wire              gpio0_WREADY;
    wire              gpio0_BVALID;
    wire   [1:0]      gpio0_BRESP;
    wire              gpio0_ARREADY;
    wire              gpio0_RVALID;
    wire              gpio0_RLAST;
    wire   [31:0]     gpio0_RDATA;
    wire   [1:0]      gpio0_RRESP;

    // AXI GPIO bus interface signals
    wire              gpio1_awsel;
    wire              gpio1_arsel;
    wire              gpio1_AWREADY;
    wire              gpio1_WREADY;
    wire              gpio1_BVALID;
    wire   [1:0]      gpio1_BRESP;
    wire              gpio1_ARREADY;
    wire              gpio1_RVALID;
    wire              gpio1_RLAST;
    wire   [31:0]     gpio1_RDATA;
    wire   [1:0]      gpio1_RRESP;

    /*
    // AXI UART4 bus interface signals
    wire              uart4_awsel;
    wire              uart4_arsel;
    wire              uart4_AWREADY;
    wire              uart4_WREADY;
    wire              uart4_BVALID;
    wire   [1:0]      uart4_BRESP;
    wire              uart4_ARREADY;
    wire              uart4_RVALID;
    wire              uart4_RLAST;
    wire   [31:0]     uart4_RDATA;
    wire   [1:0]      uart4_RRESP;
    */

    // APB subsystem AXI interface signals
    wire              apbsys_awsel;
    wire              apbsys_arsel;
    wire              apbsys_AWREADY;
    wire              apbsys_WREADY;
    wire              apbsys_BVALID;
    wire   [1:0]      apbsys_BRESP;
    wire              apbsys_ARREADY;
    wire              apbsys_RVALID;
    wire              apbsys_RLAST;
    wire   [31:0]     apbsys_RDATA;
    wire   [1:0]      apbsys_RRESP;

    // Interrupt request
    wire   [31:0]     intisr_cm0;                   // Interrupt status register
    wire              intnmi_cm0;                   // NMI
    wire   [15:0]     gpio0_intr;                   // GPIO interrupt
    wire              gpio0_combintr;               // GPIO combined interrupt
    wire              gpio1_combintr;               // GPIO combined interrupt
    /*
    wire              uart4_TXINT;
    wire              uart4_RXINT;
    wire              uart4_TXOVRINT;
    wire              uart4_RXOVRINT;
    wire              uart4_UARTINT;
    */
    wire   [31:0]     apbsubsys_interrupt;          // APB subsys interrupt
    wire              watchdog_interrupt;           // watchdog interrupt

    // 唤醒源与boot重映射控制
    wire   [33:0]     WICSENSE;                     // 唤醒源
    wire              remap_ctrl;                   // boot重映射控制

    // event signals
    wire              TXEV;                         // 未用
    wire              RXEV;                         // 未用

    // Core debug signals
    wire              DBGRESTART;                   // 未用
    wire              DBGRESTARTED;                 // 未用
    wire              EDBGRQ;                       // 未用

    // Core status
    wire              HALTED;                       // 未用
    wire              SPECHTRANS;                   // 未用
    wire              CODENSEQ;                     // 未用
    wire              SHAREABLE;                    // 未用


    // #######################################################################
    // -------------------------------
    // instantiate the DesignStart Cortex M0 Integration Layer（CPU core）
    // -------------------------------
    cortexm0integration
    u_cortexm0integration
    (
        // CLOCK AND RESETS
        .FCLK           (FCLK),
        .SCLK           (SCLK),
        .ACLK           (ACLK),
        .DCLK           (),
        .PORESETn       (PORESETn),
        .DBGRESETn      (),
        .ARESETn        (ARESETn),
        .SWCLKTCK       (),
        .nTRST          (),

        // AXI-LITE MASTER PORT
        //---- AXI - Write -----------------
        .AW_VALID       (cm0_AWVALID),
        .AW_READY       (cm0_AWREADY),
        .AW_SIZE        (cm0_AWSIZE),
        .AW_BURST       (cm0_AWBURST),
        .AW_LEN         (cm0_AWLEN),
        .AW_ADDR        (cm0_AWADDR),
        .W_VALID        (cm0_WVALID),
        .W_READY        (cm0_WREADY),
        .W_LAST         (cm0_WLAST),
        .W_DATA         (cm0_WDATA),
        .B_VALID        (cm0_BVALID),
        .B_READY        (cm0_BREADY),
        .B_RESP         (cm0_BRESP),
        //---- AXI - Read ------------------
        .AR_VALID       (cm0_ARVALID),
        .AR_READY       (cm0_ARREADY),
        .AR_SIZE        (cm0_ARSIZE),
        .AR_BURST       (cm0_ARBURST),
        .AR_LEN         (cm0_ARLEN),
        .AR_ADDR        (cm0_ARADDR),
        .R_VALID        (cm0_RVALID),
        .R_READY        (cm0_RREADY),
        .R_LAST         (cm0_RLAST),
        .R_DATA         (cm0_RDATA),
        .R_RESP         (cm0_RRESP),

        // CODE SEQUENTIALITY AND SPECULATION
        .CODENSEQ       (),
        .CODEHINTDE     (),
        .SPECHTRANS     (),

        // DEBUG    
        .SWDITMS        (1'b0),
        .TDI            (1'b0),
        .SWDO           (),
        .SWDOEN         (),
        .TDO            (),
        .nTDOEN         (),
        .DBGRESTART     (1'b0),                     // multi-core synchronous restart from halt
        .DBGRESTARTED   (),                         // 未用
        .EDBGRQ         (1'b0),                     // multi-core synchronous halt request
        .HALTED         (),                         // 未用

        // MISC
        .NMI            (intnmi_cm0),               // Non-maskable interrupt input
        .IRQ            (intisr_cm0),               // Interrupt request inputs
        .TXEV           (),                         // Event output (SEV executed)
        .RXEV           (1'b0),                     // Event input
        .LOCKUP         (LOCKUP),                   // Core is locked-up
        .SYSRESETREQ    (SYSRESETREQ),              // System reset request
        .IRQLATENCY     (8'h00),
        .ECOREVNUM      (28'h0),

        // POWER MANAGEMENT
        .GATEHCLK       (),
        .SLEEPING       (SLEEPING),                 // Core and NVIC sleeping
        .SLEEPDEEP      (SLEEPDEEP),
        .WAKEUP         (),
        .WICSENSE       (WICSENSE),
        .SLEEPHOLDREQn  (1'b1),
        .SLEEPHOLDACKn  (),
        .WICENREQ       (1'b0),
        .WICENACK       (),
        .CDBGPWRUPREQ   (),
        .CDBGPWRUPACK   (1'b0),

        // SCAN IO  
        .SE             (1'b0),
        .RSTBYPASS      (1'b0)
    );


    // #######################################################################
    // -------------------------------
    // AXI system
    // -------------------------------

    // No bitband wrapper, direct signal connections
    assign   cm_AWVALID  = cm0_AWVALID;
    assign   cm_AWSIZE   = cm0_AWSIZE;
    assign   cm_AWBURST  = cm0_AWBURST;
    assign   cm_AWLEN    = cm0_AWLEN;
    assign   cm_AWADDR   = cm0_AWADDR;
    assign   cm_WVALID   = cm0_WVALID;
    assign   cm_WLAST    = cm0_WLAST;
    assign   cm_WDATA    = cm0_WDATA;
    assign   cm_BREADY   = cm0_BREADY;
    assign   cm_ARVALID  = cm0_ARVALID;
    assign   cm_ARSIZE   = cm0_ARSIZE;
    assign   cm_ARBURST  = cm0_ARBURST;
    assign   cm_ARLEN    = cm0_ARLEN;
    assign   cm_ARADDR   = cm0_ARADDR;
    assign   cm_RREADY   = cm0_RREADY;
    assign   cm0_AWREADY = cm_AWREADY;
    assign   cm0_WREADY  = cm_WREADY;
    assign   cm0_BVALID  = cm_BVALID;
    assign   cm0_BRESP   = cm_BRESP;
    assign   cm0_ARREADY = cm_ARREADY;
    assign   cm0_RVALID  = cm_RVALID;
    assign   cm0_RLAST   = cm_RLAST;
    assign   cm0_RDATA   = cm_RDATA;
    assign   cm0_RRESP   = cm_RRESP;

    // No DMA controller - no need to have master multiplexer
    // direct connection from core to system bus if DMA is not presented
    assign   sys_AWVALID  = cm_AWVALID;
    assign   sys_AWSIZE   = cm_AWSIZE;
    assign   sys_AWBURST  = cm_AWBURST;
    assign   sys_AWLEN    = cm_AWLEN;
    assign   sys_AWADDR   = cm_AWADDR;
    assign   sys_WVALID   = cm_WVALID;
    assign   sys_WLAST    = cm_WLAST;
    assign   sys_WDATA    = cm_WDATA;
    assign   sys_BREADY   = cm_BREADY;
    assign   sys_ARVALID  = cm_ARVALID;
    assign   sys_ARSIZE   = cm_ARSIZE;
    assign   sys_ARBURST  = cm_ARBURST;
    assign   sys_ARLEN    = cm_ARLEN;
    assign   sys_ARADDR   = cm_ARADDR;
    assign   sys_RREADY   = cm_RREADY;
    assign   cm_AWREADY   = sys_AWREADY;
    assign   cm_WREADY    = sys_WREADY;
    assign   cm_BVALID    = sys_BVALID;
    assign   cm_BRESP     = sys_BRESP;
    assign   cm_ARREADY   = sys_ARREADY;
    assign   cm_RVALID    = sys_RVALID;
    assign   cm_RLAST     = sys_RLAST;
    assign   cm_RDATA     = sys_RDATA;
    assign   cm_RRESP     = sys_RRESP;

    // -------------------------------
    // AXI address decode（译码器）
    // -------------------------------
    cmsdk_axi_addr_decode 
    #(  .BASEADDR_GPIO0       (BASEADDR_GPIO0),
        .BASEADDR_GPIO1       (BASEADDR_GPIO1),
        //.BASEADDR_UART4     (BASEADDR_UART4),
        .BOOT_LOADER_PRESENT  (1'b0),
        .BASEADDR_SYSROMTABLE (BASEADDR_SYSROMTABLE)
    )
    u_addr_decode (
        .w_addr         (sys_AWADDR),
        .r_addr         (sys_ARADDR),
        .remap_ctrl     (remap_ctrl),
        .boot_arsel     (boot_arsel),
        .flash_arsel    (flash_arsel),
        .sram_awsel     (sram_awsel),
        .sram_arsel     (sram_arsel),
        .apbsys_awsel   (apbsys_awsel),
        .apbsys_arsel   (apbsys_arsel),
        .gpio0_awsel    (gpio0_awsel),
        .gpio0_arsel    (gpio0_arsel),
        .gpio1_awsel    (gpio1_awsel),
        .gpio1_arsel    (gpio1_arsel),
       //.uart4_awsel   (uart4_awsel),
       //.uart4_arsel   (uart4_arsel),
        .sysctrl_awsel  (sysctrl_awsel),
        .sysctrl_arsel  (sysctrl_arsel),
        .sysrom_arsel   (sysrom_arsel),
        .defslv_awsel   (defslv_awsel),
        .defslv_arsel   (defslv_arsel)
    );

    // -------------------------------
    // AXI slave multiplexer（多路器）
    // -------------------------------
    cmsdk_axi_slave_mux
    #(  .PORT0_ENABLE  (1),
        .PORT1_ENABLE  (1),
        .PORT2_ENABLE  (0),
        .PORT3_ENABLE  (1),
        .PORT4_ENABLE  (1),
        .PORT5_ENABLE  (1),
        .PORT6_ENABLE  (1),
        .PORT7_ENABLE  (1),
        .PORT8_ENABLE  (1),
        .PORT9_ENABLE  (0),
        .DW            (32)
    )
    u_axi_slave_mux (
        .ACLK           (ACLK),
        .ARESETn        (ARESETn),
        .AW_SEL0        (1'b0),                     // Input Port 0
        .AW_READY0      (flash_AWREADY),
        .W_READY0       (flash_WREADY),
        .B_VALID0       (flash_BVALID),
        .B_RESP0        (flash_BRESP),
        .AR_SEL0        (flash_arsel),              // Input Port 0
        .AR_READY0      (flash_ARREADY),
        .R_VALID0       (flash_RVALID),
        .R_LAST0        (flash_RLAST),
        .R_DATA0        (flash_RDATA),
        .R_RESP0        (flash_RRESP),
        .AW_SEL1        (sram_awsel),               // Input Port 1
        .AW_READY1      (sram_AWREADY),
        .W_READY1       (sram_WREADY),
        .B_VALID1       (sram_BVALID),
        .B_RESP1        (sram_BRESP),
        .AR_SEL1        (sram_arsel),               // Input Port 1
        .AR_READY1      (sram_ARREADY),
        .R_VALID1       (sram_RVALID),
        .R_LAST1        (sram_RLAST),
        .R_DATA1        (sram_RDATA),
        .R_RESP1        (sram_RRESP),
        .AW_SEL2        (1'b0),                     // Input Port 2
        .AW_READY2      (boot_AWREADY),
        .W_READY2       (boot_WREADY),
        .B_VALID2       (boot_BVALID),
        .B_RESP2        (boot_BRESP),
        .AR_SEL2        (boot_arsel),               // Input Port 2
        .AR_READY2      (boot_ARREADY),
        .R_VALID2       (boot_RVALID),
        .R_LAST2        (boot_RLAST),
        .R_DATA2        (boot_RDATA),
        .R_RESP2        (boot_RRESP),
        .AW_SEL3        (defslv_awsel),             // Input Port 3
        .AW_READY3      (defslv_AWREADY),
        .W_READY3       (defslv_WREADY),
        .B_VALID3       (defslv_BVALID),
        .B_RESP3        (defslv_BRESP),
        .AR_SEL3        (defslv_arsel),             // Input Port 3
        .AR_READY3      (defslv_ARREADY),
        .R_VALID3       (defslv_RVALID),
        .R_LAST3        (defslv_RLAST),
        .R_DATA3        (defslv_RDATA),
        .R_RESP3        (defslv_RRESP),
        .AW_SEL4        (apbsys_awsel),             // Input Port 4
        .AW_READY4      (apbsys_AWREADY),
        .W_READY4       (apbsys_WREADY),
        .B_VALID4       (apbsys_BVALID),
        .B_RESP4        (apbsys_BRESP),
        .AR_SEL4        (apbsys_arsel),             // Input Port 4
        .AR_READY4      (apbsys_ARREADY),
        .R_VALID4       (apbsys_RVALID),
        .R_LAST4        (apbsys_RLAST),
        .R_DATA4        (apbsys_RDATA),
        .R_RESP4        (apbsys_RRESP),
        .AW_SEL5        (gpio0_awsel),              // Input Port 5
        .AW_READY5      (gpio0_AWREADY),
        .W_READY5       (gpio0_WREADY),
        .B_VALID5       (gpio0_BVALID),
        .B_RESP5        (gpio0_BRESP),
        .AR_SEL5        (gpio0_arsel),              // Input Port 5
        .AR_READY5      (gpio0_ARREADY),
        .R_VALID5       (gpio0_RVALID),
        .R_LAST5        (gpio0_RLAST),
        .R_DATA5        (gpio0_RDATA),
        .R_RESP5        (gpio0_RRESP),
        .AW_SEL6        (gpio1_awsel),              // Input Port 6
        .AW_READY6      (gpio1_AWREADY),
        .W_READY6       (gpio1_WREADY),
        .B_VALID6       (gpio1_BVALID),
        .B_RESP6        (gpio1_BRESP),
        .AR_SEL6        (gpio1_arsel),              // Input Port 6
        .AR_READY6      (gpio1_ARREADY),
        .R_VALID6       (gpio1_RVALID),
        .R_LAST6        (gpio1_RLAST),
        .R_DATA6        (gpio1_RDATA),
        .R_RESP6        (gpio1_RRESP),
        .AW_SEL7        (sysctrl_awsel),            // Input Port 7
        .AW_READY7      (sysctrl_AWREADY),
        .W_READY7       (sysctrl_WREADY),
        .B_VALID7       (sysctrl_BVALID),
        .B_RESP7        (sysctrl_BRESP),
        .AR_SEL7        (sysctrl_arsel),            // Input Port 7
        .AR_READY7      (sysctrl_ARREADY),
        .R_VALID7       (sysctrl_RVALID),
        .R_LAST7        (sysctrl_RLAST),
        .R_DATA7        (sysctrl_RDATA),
        .R_RESP7        (sysctrl_RRESP),
        .AW_SEL8        (1'b0),                     // Input Port 8
        .AW_READY8      (sysrom_AWREADY),
        .W_READY8       (sysrom_WREADY),
        .B_VALID8       (sysrom_BVALID),
        .B_RESP8        (sysrom_BRESP),
        .AR_SEL8        (sysrom_arsel),             // Input Port 8
        .AR_READY8      (sysrom_ARREADY),
        .R_VALID8       (sysrom_RVALID),
        .R_LAST8        (sysrom_RLAST),
        .R_DATA8        (sysrom_RDATA),
        .R_RESP8        (sysrom_RRESP),
        .AW_SEL9        (1'b0),                     // Input Port 9
        .AW_READY9      (1'b0),
        .W_READY9       (1'b0),
        .B_VALID9       (1'b0),
        .B_RESP9        (2'b0),
        .AR_SEL9        (1'b0),                     // Input Port 9
        .AR_READY9      (1'b0),
        .R_VALID9       (1'b0),
        .R_LAST9        (1'b0),
        .R_DATA9        (32'b0),
        .R_RESP9        (2'b0),
        /*  
        .AW_SEL9        (uart4_awsel),              // Input Port 9
        .AW_READY9      (uart4_AWREADY),
        .W_READY9       (uart4_WREADY),
        .B_VALID9       (uart4_BVALID),
        .B_RESP9        (uart4_BRESP),
        .AR_SEL9        (uart4_arsel),              // Input Port 9
        .AR_READY9      (uart4_ARREADY),
        .R_VALID9       (uart4_RVALID),
        .R_LAST9        (uart4_RLAST),
        .R_DATA9        (uart4_RDATA),
        .R_RESP9        (uart4_RRESP),
        */  
        .AW_VALID       (sys_AWVALID),
        .AW_READY       (sys_AWREADY),          // MUX Outputs
        .W_READY        (sys_WREADY),
        .B_VALID        (sys_BVALID),
        .B_RESP         (sys_BRESP),
        .AR_VALID       (sys_ARVALID),
        .AR_READY       (sys_ARREADY),
        .R_VALID        (sys_RVALID),
        .R_LAST         (sys_RLAST),
        .R_DATA         (sys_RDATA),
        .R_RESP         (sys_RRESP)
    );


    // #######################################################################
    // -------------------------------
    // 系统控制
    // -------------------------------

    // -------------------------------
    // Default slave（非访问从设备）
    // -------------------------------
    cmsdk_axi_default_slave 
    u_axi_default_slave (
        .ACLK           (ACLK),
        .ARESETn        (ARESETn),
        .AW_SEL         (defslv_awsel),
        .AW_VALID       (sys_AWVALID),
        .AW_READY       (defslv_AWREADY),
        .AW_LEN         (sys_AWLEN),
        .W_VALID        (sys_WVALID),
        .W_READY        (defslv_WREADY),
        .B_VALID        (defslv_BVALID),
        .B_READY        (sys_BREADY),
        .B_RESP         (defslv_BRESP),
        .AR_SEL         (defslv_arsel),
        .AR_VALID       (sys_ARVALID),
        .AR_READY       (defslv_ARREADY),
        .AR_LEN         (sys_ARLEN),
        .R_VALID        (defslv_RVALID),
        .R_READY        (sys_RREADY),
        .R_LAST         (defslv_RLAST),
        .R_DATA         (defslv_RDATA),
        .R_RESP         (defslv_RRESP)
    );

    // -------------------------------
    // System controller for simple Cortex-M Microcontroller system
    // -------------------------------
    cmsdk_axi_sysctrl
    u_cmsdk_axi_sysctrl
    (
        .FCLK           (FCLK),
        .PORESETn       (PORESETn),
        .ACLK           (ACLK),
        .ARESETn        (ARESETn),
        //----------------- AXI - Write -----------------
        .AW_SEL         (sysctrl_awsel),
        .AW_VALID       (sys_AWVALID),
        .AW_READY       (sysctrl_AWREADY),
        .AW_SIZE        (sys_AWSIZE),
        .AW_BURST       (sys_AWBURST),
        .AW_LEN         (sys_AWLEN),
        .AW_ADDR        (sys_AWADDR),
        .W_VALID        (sys_WVALID),
        .W_READY        (sysctrl_WREADY),
        .W_LAST         (sys_WLAST),
        .W_DATA         (sys_WDATA),
        .B_VALID        (sysctrl_BVALID),
        .B_READY        (sys_BREADY),
        .B_RESP         (sysctrl_BRESP),
        //----------------- AXI - Read ------------------
        .AR_SEL         (sysctrl_arsel),
        .AR_VALID       (sys_ARVALID),
        .AR_READY       (sysctrl_ARREADY),
        .AR_SIZE        (sys_ARSIZE),
        .AR_BURST       (sys_ARBURST),
        .AR_LEN         (sys_ARLEN),
        .AR_ADDR        (sys_ARADDR),
        .R_VALID        (sysctrl_RVALID),
        .R_READY        (sys_RREADY),
        .R_LAST         (sysctrl_RLAST),
        .R_DATA         (sysctrl_RDATA),
        .R_RESP         (sysctrl_RRESP),

        // Reset information
        .SYSRESETREQ    (SYSRESETREQ),
        .WDOGRESETREQ   (WDOGRESETREQ),
        .LOCKUP         (LOCKUP),
        // Engineering-change-order revision bits
        .ECOREVNUM      (4'h0),
        // System control signals
        .REMAP          (remap_ctrl),
        .PMUENABLE      (PMUENABLE),
        .LOCKUPRESET    (LOCKUPRESET)
    );

    // -------------------------------
    // System ROM Table
    // -------------------------------
    cmsdk_axi_sysrom_table
    #(  //.JEPID           (),
        //.JEPCONTINUATION (),
        //.PARTNUMBER      (),
        //.REVISION        (),
        .BASE              (BASEADDR_SYSROMTABLE),
        // Entry 0 = Cortex-M0+ Processor
        .ENTRY0BASEADDR    (32'hE00FF000),
        .ENTRY0PRESENT     (1'b1),
        // Entry 1 = CoreSight MTB-M0+
        .ENTRY1BASEADDR    (32'hF0200000),
        .ENTRY1PRESENT     (0))
    u_axi_sysrom_table
    (
        .ACLK           (ACLK),
        .ARESETn        (ARESETn),
        //----------------- AXI - Read ------------------
        .AR_SEL         (sysrom_arsel),
        .AR_VALID       (sys_ARVALID),
        .AR_READY       (sysrom_ARREADY),
        .AR_SIZE        (sys_ARSIZE),
        .AR_BURST       (sys_ARBURST),
        .AR_LEN         (sys_ARLEN),
        .AR_ADDR        (sys_ARADDR),
        .R_VALID        (sysrom_RVALID),
        .R_READY        (sys_RREADY),
        .R_LAST         (sysrom_RLAST),
        .R_DATA         (sysrom_RDATA),
        .R_RESP         (sysrom_RRESP),

        .ECOREVNUM      (4'h0)
    );


    // #######################################################################
    // -------------------------------
    // 存储接口
    // -------------------------------

    //----------------------------------------
    // Optional boot loader, Only use if BOOT_MEM_TYPE is not zero
    //----------------------------------------
    assign   boot_AWREADY = 1'b1;
    assign   boot_WREADY = 1'b1;
    assign   boot_BVALID = 1'b1;
    assign   boot_BRESP = 2'b11;            // 一个未被控制的错误，通常地址解码为无效地址。
    assign   boot_ARREADY = 1'b1;
    assign   boot_RVALID = 1'b1;
    assign   boot_RLAST = 1'b1;
    assign   boot_RDATA = 32'h00000000;
    assign   boot_RRESP = 2'b11;            // 一个未被控制的错误，通常地址解码为无效地址。

    //----------------------------------------
    // Flash memory
    //----------------------------------------
    cmsdk_axi_flash
    #(  .filename(filename),                // 测试程序（二进制指令代码）
        .AW(16),                            // 64K bytes flash ROM
        .WS_N(`ARM_CMSDK_ROM_MEM_WS_N),
        .WS_S(`ARM_CMSDK_ROM_MEM_WS_S))
    u_axi_flash (
        .ACLK           (ACLK),
        .ARESETn        (ARESETn),
        //----------------- AXI - Read ------------------
        .AR_SEL         (flash_arsel),
        .AR_VALID       (sys_ARVALID),
        .AR_READY       (flash_ARREADY),
        .AR_SIZE        (sys_ARSIZE),
        .AR_BURST       (sys_ARBURST),
        .AR_LEN         (sys_ARLEN),
        .AR_ADDR        (sys_ARADDR[15:0]),
        .R_VALID        (flash_RVALID),
        .R_READY        (sys_RREADY),
        .R_LAST         (flash_RLAST),
        .R_DATA         (flash_RDATA),
        .R_RESP         (flash_RRESP)
    );

    //----------------------------------------
    // SRAM
    //----------------------------------------
    cmsdk_axi_sram
    #(  .AW(16),  // 64K bytes SRAM
        .WS_N(`ARM_CMSDK_RAM_MEM_WS_N),
        .WS_S(`ARM_CMSDK_RAM_MEM_WS_S))
    u_axi_sram (
        .ACLK           (ACLK),
        .ARESETn        (ARESETn),
        //----------------- AXI - Write -----------------
        .AW_SEL         (sram_awsel),
        .AW_VALID       (sys_AWVALID),
        .AW_READY       (sram_AWREADY),
        .AW_SIZE        (sys_AWSIZE),
        .AW_BURST       (sys_AWBURST),
        .AW_LEN         (sys_AWLEN),
        .AW_ADDR        (sys_AWADDR[15:0]),
        .W_VALID        (sys_WVALID),
        .W_READY        (sram_WREADY),
        .W_LAST         (sys_WLAST),
        .W_DATA         (sys_WDATA),
        .B_VALID        (sram_BVALID),
        .B_READY        (sys_BREADY),
        .B_RESP         (sram_BRESP),
        //----------------- AXI - Read ------------------
        .AR_SEL         (sram_arsel),
        .AR_VALID       (sys_ARVALID),
        .AR_READY       (sram_ARREADY),
        .AR_SIZE        (sys_ARSIZE),
        .AR_BURST       (sys_ARBURST),
        .AR_LEN         (sys_ARLEN),
        .AR_ADDR        (sys_ARADDR[15:0]),
        .R_VALID        (sram_RVALID),
        .R_READY        (sys_RREADY),
        .R_LAST         (sram_RLAST),
        .R_DATA         (sram_RDATA),
        .R_RESP         (sram_RRESP)
    );


    // #######################################################################
    // -------------------------------
    // Peripherals（IO接口）
    // -------------------------------

    // GPIO is driven from the AXI
    cmsdk_axi_gpio
    #(  .ALTERNATE_FUNC_MASK     (16'h0000),    // No pin muxing for Port #0
        .ALTERNATE_FUNC_DEFAULT  (16'h0000)     // All pins default to GPIO
    )
    u_axi_gpio_0  (
        .FCLK           (FCLK),
        .ACLK           (ACLK),
        .ARESETn        (ARESETn),
        //----------------- AXI - Write -----------------
        .AW_SEL         (gpio0_awsel),
        .AW_VALID       (sys_AWVALID),
        .AW_READY       (gpio0_AWREADY),
        .AW_SIZE        (sys_AWSIZE),
        .AW_BURST       (sys_AWBURST),
        .AW_LEN         (sys_AWLEN),
        .AW_ADDR        (sys_AWADDR),
        .W_VALID        (sys_WVALID),
        .W_READY        (gpio0_WREADY),
        .W_LAST         (sys_WLAST),
        .W_DATA         (sys_WDATA),
        .B_VALID        (gpio0_BVALID),
        .B_READY        (sys_BREADY),
        .B_RESP         (gpio0_BRESP),
        //----------------- AXI - Read ------------------
        .AR_SEL         (gpio0_arsel),
        .AR_VALID       (sys_ARVALID),
        .AR_READY       (gpio0_ARREADY),
        .AR_SIZE        (sys_ARSIZE),
        .AR_BURST       (sys_ARBURST),
        .AR_LEN         (sys_ARLEN),
        .AR_ADDR        (sys_ARADDR),
        .R_VALID        (gpio0_RVALID),
        .R_READY        (sys_RREADY),
        .R_LAST         (gpio0_RLAST),
        .R_DATA         (gpio0_RDATA),
        .R_RESP         (gpio0_RRESP),

        .ECOREVNUM      (4'h0),             // Engineering-change-order revision bits

        .PORTIN         (p0_in),            // GPIO Interface inputs
        .PORTOUT        (p0_out),           // GPIO Interface outputs
        .PORTEN         (p0_outen),
        .PORTFUNC       (p0_altfunc),       // Alternate function control

        .GPIOINT        (gpio0_intr[15:0]), // Interrupt outputs
        .COMBINT        (gpio0_combintr)
    );

    // GPIO is driven from the AXI
    cmsdk_axi_gpio 
    #(  .ALTERNATE_FUNC_MASK     (16'h002A), // pin muxing for Port #1
        .ALTERNATE_FUNC_DEFAULT  (16'h0000)  // All pins default to GPIO
    )
    u_axi_gpio_1  (
        .FCLK           (FCLK),
        .ACLK           (ACLK),
        .ARESETn        (ARESETn),
        //----------------- AXI - Write -----------------
        .AW_SEL         (gpio1_awsel),
        .AW_VALID       (sys_AWVALID),
        .AW_READY       (gpio1_AWREADY),
        .AW_SIZE        (sys_AWSIZE),
        .AW_BURST       (sys_AWBURST),
        .AW_LEN         (sys_AWLEN),
        .AW_ADDR        (sys_AWADDR),
        .W_VALID        (sys_WVALID),
        .W_READY        (gpio1_WREADY),
        .W_LAST         (sys_WLAST),
        .W_DATA         (sys_WDATA),
        .B_VALID        (gpio1_BVALID),
        .B_READY        (sys_BREADY),
        .B_RESP         (gpio1_BRESP),
        //---------------- AXI - Read -------------------
        .AR_SEL         (gpio1_arsel),
        .AR_VALID       (sys_ARVALID),
        .AR_READY       (gpio1_ARREADY),
        .AR_SIZE        (sys_ARSIZE),
        .AR_BURST       (sys_ARBURST),
        .AR_LEN         (sys_ARLEN),
        .AR_ADDR        (sys_ARADDR),
        .R_VALID        (gpio1_RVALID),
        .R_READY        (sys_RREADY),
        .R_LAST         (gpio1_RLAST),
        .R_DATA         (gpio1_RDATA),
        .R_RESP         (gpio1_RRESP),

        .ECOREVNUM      (4'h0),             // Engineering-change-order revision bits

        .PORTIN         (p1_in),            // GPIO Interface inputs
        .PORTOUT        (p1_out),           // GPIO Interface outputs
        .PORTEN         (p1_outen),
        .PORTFUNC       (p1_altfunc),       // Alternate function control

        .GPIOINT        (),                 // Interrupt outputs
        .COMBINT        (gpio1_combintr)
    );

    /*
    // UART is driven from the AXI
    cmsdk_axi_uart
    u_axi_uart4  (
        .ACLK           (ACLK),
        .ARESETn        (ARESETn),
        //----------------- AXI - Write -----------------
        .AW_SEL         (uart4_awsel),
        .AW_VALID       (sys_AWVALID),
        .AW_READY       (uart4_AWREADY),
        .AW_SIZE        (sys_AWSIZE),
        .AW_BURST       (sys_AWBURST),
        .AW_LEN         (sys_AWLEN),
        .AW_ADDR        (sys_AWADDR),
        .W_VALID        (sys_WVALID),
        .W_READY        (uart4_WREADY),
        .W_LAST         (sys_WLAST),
        .W_DATA         (sys_WDATA),
        .B_VALID        (uart4_BVALID),
        .B_READY        (sys_BREADY),
        .B_RESP         (uart4_BRESP),
        //---------------- AXI - Read -------------------
        .AR_SEL         (uart4_arsel),
        .AR_VALID       (sys_ARVALID),
        .AR_READY       (uart4_ARREADY),
        .AR_SIZE        (sys_ARSIZE),
        .AR_BURST       (sys_ARBURST),
        .AR_LEN         (sys_ARLEN),
        .AR_ADDR        (sys_ARADDR),
        .R_VALID        (uart4_RVALID),
        .R_READY        (sys_RREADY),
        .R_LAST         (uart4_RLAST),
        .R_DATA         (uart4_RDATA),
        .R_RESP         (uart4_RRESP),

        .RXD            (uart4_rxd),
        .TXD            (uart4_txd),
        .TXEN           (uart4_txen),
        .BAUDTICK       ( ),
        .TXINT          (uart4_TXINT), 
        .RXINT          (uart4_RXINT), 
        .TXOVRINT       (uart4_TXOVRINT), 
        .RXOVRINT       (uart4_RXOVRINT), 
        .UARTINT        (uart4_UARTINT)
    );
    */

    // APB subsystem for timers, UARTs
    cmsdk_axi2apb_subsystem
    #(  .INCLUDE_APB_TIMER0      (1),       // Include simple timer #0
        .INCLUDE_APB_TIMER1      (1),       // Include simple timer #1
        .INCLUDE_APB_DUALTIMER0  (1),       // Include dual timer module
        .INCLUDE_APB_UART0       (1),       // Include simple UART #0
        .INCLUDE_APB_UART1       (1),       // Include simple UART #1
        .INCLUDE_APB_UART2       (1),       // Include simple UART #2.
        .INCLUDE_APB_WATCHDOG    (1),       // Include APB watchdog module
        .INCLUDE_APB_TEST_SLAVE  (1),
        .APB_EXT_PORT12_ENABLE   (0),
        .APB_EXT_PORT13_ENABLE   (0),
        .APB_EXT_PORT14_ENABLE   (0),
        .APB_EXT_PORT15_ENABLE   (0),
        .INCLUDE_IRQ_SYNCHRONIZER(0)
    )
    u_axi2apb_subsystem(
        .ACLK           (ACLK),
        .ARESETn        (ARESETn),
        //----------------- AXI - Write -----------------
        .AW_SEL         (apbsys_awsel),
        .AW_VALID       (sys_AWVALID),
        .AW_READY       (apbsys_AWREADY),
        .AW_SIZE        (sys_AWSIZE),
        .AW_BURST       (sys_AWBURST),
        .AW_LEN         (sys_AWLEN),
        .AW_ADDR        (sys_AWADDR),
        .W_VALID        (sys_WVALID),
        .W_READY        (apbsys_WREADY),
        .W_LAST         (sys_WLAST),
        .W_DATA         (sys_WDATA),
        .B_VALID        (apbsys_BVALID),
        .B_READY        (sys_BREADY),
        .B_RESP         (apbsys_BRESP),
        //----------------- AXI - Read ------------------
        .AR_SEL         (apbsys_arsel),
        .AR_VALID       (sys_ARVALID),
        .AR_READY       (apbsys_ARREADY),
        .AR_SIZE        (sys_ARSIZE),
        .AR_BURST       (sys_ARBURST),
        .AR_LEN         (sys_ARLEN),
        .AR_ADDR        (sys_ARADDR),
        .R_VALID        (apbsys_RVALID),
        .R_READY        (sys_RREADY),
        .R_LAST         (apbsys_RLAST),
        .R_DATA         (apbsys_RDATA),
        .R_RESP         (apbsys_RRESP),

        // APB clock and reset
        .PCLK           (PCLK),
        .PCLKG          (PCLKG),
        .PCLKEN         (PCLKEN),
        .PRESETn        (PRESETn),

        .APBACTIVE      (APBACTIVE),        // Status Output for clock gating

        // Peripherals  
        // UART 
        .uart0_rxd      (uart0_rxd),
        .uart0_txd      (uart0_txd),
        .uart0_txen     (uart0_txen),

        .uart1_rxd      (uart1_rxd),
        .uart1_txd      (uart1_txd),
        .uart1_txen     (uart1_txen),

        .uart2_rxd      (uart2_rxd),
        .uart2_txd      (uart2_txd),
        .uart2_txen     (uart2_txen),

        // Timer    
        .timer0_extin   (timer0_extin),
        .timer1_extin   (timer1_extin),

        // Interrupt outputs
        .apbsubsys_interrupt (apbsubsys_interrupt),
        .watchdog_interrupt  (watchdog_interrupt),
        // reset output
        .watchdog_reset (WDOGRESETREQ)
    );


    // #######################################################################
    // -------------------------------
    // Interrupt assignment（需要在此考虑UART4（AXI接口）的中断源分配）
    // -------------------------------
    assign intnmi_cm0        = watchdog_interrupt;
    assign intisr_cm0[ 5: 0] = apbsubsys_interrupt[ 5: 0];
    assign intisr_cm0[ 6]    = apbsubsys_interrupt[ 6]   | gpio0_combintr;
    assign intisr_cm0[ 7]    = apbsubsys_interrupt[ 7]   | gpio1_combintr;
    assign intisr_cm0[14: 8] = apbsubsys_interrupt[14: 8];
    assign intisr_cm0[15]    = apbsubsys_interrupt[15];
    //assign intisr_cm0[15]    = apbsubsys_interrupt[15]   | uart4_UARTINT;
    assign intisr_cm0[31:16] = apbsubsys_interrupt[31:16]| gpio0_intr;


endmodule
