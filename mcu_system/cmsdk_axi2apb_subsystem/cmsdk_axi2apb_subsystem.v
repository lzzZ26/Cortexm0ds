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
//------------------------------------------------------------------------------
// Abstract : APB sub system
//------------------------------------------------------------------------------
module cmsdk_axi2apb_subsystem #(
  // Parameter options for including peripherals
  parameter  INCLUDE_APB_TIMER0     = 1,  // Include simple timer #0
  parameter  INCLUDE_APB_TIMER1     = 1,  // Include simple timer #1
  parameter  INCLUDE_APB_DUALTIMER0 = 1,  // Include dual timer module
  parameter  INCLUDE_APB_UART0      = 1,  // Include simple UART #0
  parameter  INCLUDE_APB_UART1      = 1,  // Include simple UART #1
  parameter  INCLUDE_APB_UART2      = 1,  // Include simple UART #2.
                                          // Note : UART #2 is required for text messages
                                          //        display and to enable debug tester in
                                          //        debug tests
  parameter  INCLUDE_APB_WATCHDOG   = 1,  // Include APB watchdog module

  // By default the APB subsystem include a simple test slave use in ARM for
  // validation purpose.  You can remove this test slave by setting the
  // INCLUDE_APB_TEST_SLAVE paramater to 0,
  parameter  INCLUDE_APB_TEST_SLAVE = 1,

  // Enable setting for APB extension ports
  // By default, all four extension ports are not used.
  // This can be overriden by parameters at instantiations.
  parameter  APB_EXT_PORT12_ENABLE=0,
  parameter  APB_EXT_PORT13_ENABLE=0,
  parameter  APB_EXT_PORT14_ENABLE=0,
  parameter  APB_EXT_PORT15_ENABLE=0,

  // If peripherals are generated with asynchronous clock domain to ACLK of the processor
  // You might need to add synchroniser to the IRQ signal.
  // In this example APB subsystem, the IRQ synchroniser is used to all peripherals
  // when the INCLUDE_IRQ_SYNCHRONIZER parameter is set to 1. In practice you may have
  // some IRQ signals need to be synchronised and some do not.
  parameter  INCLUDE_IRQ_SYNCHRONIZER=0)
 (
// --------------------------------------------------------------------------
// Port Definitions
// --------------------------------------------------------------------------
    // AXI interface for AXI to APB bridge
    input  wire                     ACLK,           // clock
    input  wire                     ARESETn,        // reset

    input  wire                     AW_SEL,         // AXI2APB Device select
    input  wire                     AW_VALID,       // Write request valid
    output wire                     AW_READY,       // Write request ready
    input  wire [ 2:0]              AW_SIZE,        // Write data size
    input  wire [ 1:0]              AW_BURST,       // Write burst type
    input  wire [ 7:0]              AW_LEN,         // Write burst length
    input  wire [31:0]  	        AW_ADDR,        // Write address

    input  wire                     W_VALID,        // Write data valid
    output wire                     W_READY,        // Write data ready
    input  wire                     W_LAST,         // Write data last
    input  wire [31:0]  	          W_DATA,         // Write data
    output wire                     B_VALID,        // Write response valid
    input  wire                     B_READY,        // Write response ready
    output wire [ 1:0]              B_RESP,         // Write response

    input  wire                     AR_SEL,         // AXI2APB Device select
    input  wire                     AR_VALID,       // Read request valid
    output wire                     AR_READY,       // Read request ready
    input  wire [ 2:0]              AR_SIZE,        // Read data size
    input  wire [ 1:0]              AR_BURST,       // Read burst type
    input  wire [ 7:0]              AR_LEN,         // Read burst length
    input  wire [31:0]  	        AR_ADDR,        // Read address

    output wire                     R_VALID,        // Read data valid
    input  wire                     R_READY,        // Read data ready
    output wire                     R_LAST,         // Read data last
    output wire [31:0]  	        R_DATA,         // Read data
    output wire [ 1:0]              R_RESP,         // Read response

    input  wire                     PCLK,           // Peripheral clock
    input  wire                     PCLKG,          // Gate PCLK for bus interface only
    input  wire                     PCLKEN,         // Clock divider for AXI to APB bridge
    input  wire                     PRESETn,        // APB reset

    output wire                     APBACTIVE,      // APB active

    // Peripherals          
    // UART         
    input  wire                     uart0_rxd,      // UART0 RXD
    output wire                     uart0_txd,      // UART0 TXD
    output wire                     uart0_txen,     // UART0 TX enable

    input  wire                     uart1_rxd,      // UART1 RXD
    output wire                     uart1_txd,      // UART1 TXD
    output wire                     uart1_txen,     // UART1 TX enable

    input  wire                     uart2_rxd,      // UART2 RXD
    output wire                     uart2_txd,      // UART2 TXD
    output wire                     uart2_txen,     // UART2 TX enable

    // Timer            
    input  wire                     timer0_extin,   // Timer0 external input
    input  wire                     timer1_extin,   // Timer1 external input

    // Interrupt outputs            
    output wire [31:0]              apbsubsys_interrupt,  // APB subsystem interrupt
    output wire                     watchdog_interrupt,   // Watchdog interrupt
    output wire                     watchdog_reset        // Watchdog reset
    );

    // --------------------------------------------------------------------------
    // Internal wires
    // --------------------------------------------------------------------------
    wire     [15:0]  i_paddr;
    wire             i_psel;
    wire             i_penable;
    wire             i_pwrite;
    wire     [2:0]   i_pprot;
    wire     [3:0]   i_pstrb;
    wire     [31:0]  i_pwdata;

    // wire from APB slave mux to APB bridge
    wire             i_pready_mux;
    wire     [31:0]  i_prdata_mux;
    wire             i_pslverr_mux;

    // Peripheral signals
    wire             timer0_psel;
    wire     [31:0]  timer0_prdata;
    wire             timer0_pready;
    wire             timer0_pslverr;

    wire             timer1_psel;
    wire     [31:0]  timer1_prdata;
    wire             timer1_pready;
    wire             timer1_pslverr;

    wire             dualtimer2_psel;
    wire     [31:0]  dualtimer2_prdata;
    wire             dualtimer2_pready;
    wire             dualtimer2_pslverr;

    wire             watchdog_psel;
    wire     [31:0]  watchdog_prdata;
    wire             watchdog_pready;
    wire             watchdog_pslverr;

    wire             uart0_psel;
    wire     [31:0]  uart0_prdata;
    wire             uart0_pready;
    wire             uart0_pslverr;

    wire             uart1_psel;
    wire     [31:0]  uart1_prdata;
    wire             uart1_pready;
    wire             uart1_pslverr;

    wire             uart2_psel;
    wire     [31:0]  uart2_prdata;
    wire             uart2_pready;
    wire             uart2_pslverr;

    wire             test_slave_psel;
    wire     [31:0]  test_slave_prdata;
    wire             test_slave_pready;
    wire             test_slave_pslverr;

    wire             psel3;
    wire             psel7;
    wire             psel9;
    wire             psel10;

    // 扩展接口信号
    wire             ext12_psel;
    wire             ext13_psel;
    wire             ext14_psel;
    wire             ext15_psel;

    wire [31:0]      ext12_prdata;
    wire             ext12_pready;
    wire             ext12_pslverr;

    wire [31:0]      ext13_prdata;
    wire             ext13_pready;
    wire             ext13_pslverr;

    wire [31:0]      ext14_prdata;
    wire             ext14_pready;
    wire             ext14_pslverr;

    wire [31:0]      ext15_prdata;
    wire             ext15_pready;
    wire             ext15_pslverr;

    // Interrupt signals from peripherals
    wire             timer0_int;
    wire             timer1_int;
    wire             dualtimer2a_int;
    wire             dualtimer2b_int;
    wire             dualtimer2_comb_int;

    wire             uart0_txint;
    wire             uart0_rxint;
    wire             uart0_txovrint;
    wire             uart0_rxovrint;
    wire             uart0_combined_int;

    wire             uart1_txint;
    wire             uart1_rxint;
    wire             uart1_txovrint;
    wire             uart1_rxovrint;
    wire             uart1_combined_int;

    wire             uart2_txint;
    wire             uart2_rxint;
    wire             uart2_txovrint;
    wire             uart2_rxovrint;
    wire             uart2_combined_int;

    wire             uart0_overflow_int;
    wire             uart1_overflow_int;
    wire             uart2_overflow_int;

    wire             watchdog_int;
    wire             watchdog_rst;

    // Synchronized interrupt signals
    wire             i_uart0_txint;
    wire             i_uart0_rxint;
    wire             i_uart0_overflow_int;
    wire             i_uart1_txint;
    wire             i_uart1_rxint;
    wire             i_uart1_overflow_int;
    wire             i_uart2_txint;
    wire             i_uart2_rxint;
    wire             i_uart2_overflow_int;
    wire             i_timer0_int;
    wire             i_timer1_int;
    wire             i_dualtimer2_int;
    wire             i_watchdog_int;
    wire             i_watchdog_rst;

    // AXI to APB bus bridge
    axi2apb_if
    #(.ADDR_WIDTH    (16),
      .DATA_WIDTH    (32)
     )
    u_axi2apb_if(
    // AXI side
    .ACLK		      (ACLK),		
    .ARESETn	    (ARESETn),		

    .AW_SEL		    (AW_SEL),
    .AW_VALID	    (AW_VALID),
    .AW_READY	    (AW_READY),
    .AW_SIZE		  (AW_SIZE),
    .AW_BURST	    (AW_BURST),
    .AW_LEN		    (AW_LEN),
    .AW_ADDR		  (AW_ADDR[15:0]),	

    .W_VALID		  (W_VALID),
    .W_READY		  (W_READY),
    .W_LAST		    (W_LAST),
    .W_DATA		    (W_DATA),
    .B_VALID		  (B_VALID),
    .B_READY		  (B_READY),
    .B_RESP		    (B_RESP),

    .AR_SEL		    (AR_SEL),
    .AR_VALID	    (AR_VALID),
    .AR_READY	    (AR_READY),
    .AR_SIZE		  (AR_SIZE),
    .AR_BURST	    (AR_BURST),
    .AR_LEN		    (AR_LEN),
    .AR_ADDR		  (AR_ADDR[15:0]),

    .R_VALID		  (R_VALID),
    .R_READY		  (R_READY),
    .R_LAST		    (R_LAST),
    .R_DATA		    (R_DATA),
    .R_RESP		    (R_RESP),

    .APBACTIVE    (APBACTIVE),

    .PCLK		      (ACLK),		
    .PRESETn	    (ARESETn),		
    .PSEL         (i_psel),
    .PENABLE      (i_penable),
    .PSTRB        (i_pstrb),
    .PWRITE       (i_pwrite),
    .PADDR        (i_paddr[15:0]),
    .PWDATA       (i_pwdata),
    .PREADY       (i_pready_mux),
    .PRDATA       (i_prdata_mux),
    .PSLVERR      (i_pslverr_mux)
    );

  // APB slave decoder and multiplexer
  cmsdk_apb_slave_mux
    #( // Parameter to determine which ports are used
    .PORT0_ENABLE  (INCLUDE_APB_TIMER0), // timer 0
    .PORT1_ENABLE  (INCLUDE_APB_TIMER1), // timer 1
    .PORT2_ENABLE  (INCLUDE_APB_DUALTIMER0), // dual timer 0
    .PORT3_ENABLE  (0), // not used
    .PORT4_ENABLE  (INCLUDE_APB_UART0), // uart 0
    .PORT5_ENABLE  (INCLUDE_APB_UART1), // uart 1
    .PORT6_ENABLE  (INCLUDE_APB_UART2), // uart 2
    .PORT7_ENABLE  (0), // not used
    .PORT8_ENABLE  (INCLUDE_APB_WATCHDOG), // watchdog
    .PORT9_ENABLE  (0), // not used
    .PORT10_ENABLE (0), // not used
    .PORT11_ENABLE (INCLUDE_APB_TEST_SLAVE), // test slave for validation purpose
    .PORT12_ENABLE (APB_EXT_PORT12_ENABLE),
    .PORT13_ENABLE (APB_EXT_PORT13_ENABLE),
    .PORT14_ENABLE (APB_EXT_PORT14_ENABLE),
    .PORT15_ENABLE (APB_EXT_PORT15_ENABLE)
    )
    u_apb_slave_mux (
    // Inputs
    .DECODE4BIT        (i_paddr[15:12]),
    .PSEL              (i_psel),
    // PSEL (output) and return status & data (inputs) for each port
    .PSEL0             (timer0_psel),
    .PREADY0           (timer0_pready),
    .PRDATA0           (timer0_prdata),
    .PSLVERR0          (timer0_pslverr),

    .PSEL1             (timer1_psel),
    .PREADY1           (timer1_pready),
    .PRDATA1           (timer1_prdata),
    .PSLVERR1          (timer1_pslverr),

    .PSEL2             (dualtimer2_psel),
    .PREADY2           (dualtimer2_pready),
    .PRDATA2           (dualtimer2_prdata),
    .PSLVERR2          (dualtimer2_pslverr),

    .PSEL3             (psel3),
    .PREADY3           (1'b1),
    .PRDATA3           (32'h00000000),
    .PSLVERR3          (1'b0),

    .PSEL4             (uart0_psel),
    .PREADY4           (uart0_pready),
    .PRDATA4           (uart0_prdata),
    .PSLVERR4          (uart0_pslverr),

    .PSEL5             (uart1_psel),
    .PREADY5           (uart1_pready),
    .PRDATA5           (uart1_prdata),
    .PSLVERR5          (uart1_pslverr),

    .PSEL6             (uart2_psel),
    .PREADY6           (uart2_pready),
    .PRDATA6           (uart2_prdata),
    .PSLVERR6          (uart2_pslverr),

    .PSEL7             (psel7),
    .PREADY7           (1'b1),
    .PRDATA7           (32'h00000000),
    .PSLVERR7          (1'b0),

    .PSEL8             (watchdog_psel),
    .PREADY8           (watchdog_pready),
    .PRDATA8           (watchdog_prdata),
    .PSLVERR8          (watchdog_pslverr),

    .PSEL9             (psel9),
    .PREADY9           (1'b1),
    .PRDATA9           (32'h00000000),
    .PSLVERR9          (1'b0),

    .PSEL10            (psel10),
    .PREADY10          (1'b1),
    .PRDATA10          (32'h00000000),
    .PSLVERR10         (1'b0),

    .PSEL11            (test_slave_psel),
    .PREADY11          (test_slave_pready),
    .PRDATA11          (test_slave_prdata),
    .PSLVERR11         (test_slave_pslverr),

    .PSEL12            (ext12_psel),
    .PREADY12          (ext12_pready),
    .PRDATA12          (ext12_prdata),
    .PSLVERR12         (ext12_pslverr),

    .PSEL13            (ext13_psel),
    .PREADY13          (ext13_pready),
    .PRDATA13          (ext13_prdata),
    .PSLVERR13         (ext13_pslverr),

    .PSEL14            (ext14_psel),
    .PREADY14          (ext14_pready),
    .PRDATA14          (ext14_prdata),
    .PSLVERR14         (ext14_pslverr),

    .PSEL15            (ext15_psel),
    .PREADY15          (ext15_pready),
    .PRDATA15          (ext15_prdata),
    .PSLVERR15         (ext15_pslverr),

    // Output
    .PREADY            (i_pready_mux),
    .PRDATA            (i_prdata_mux),
    .PSLVERR           (i_pslverr_mux)
    );

  // -----------------------------------------------------------------
  // Timers

  generate if (INCLUDE_APB_TIMER0 == 1) begin : gen_apb_timer_0
  cmsdk_apb_timer u_apb_timer_0 (
    .PCLK              (PCLK),     // PCLK for timer operation
    .PCLKG             (PCLKG),    // Gated PCLK for bus
    .PRESETn           (PRESETn),  // Reset
    // APB interface inputs
    .PSEL              (timer0_psel),
    .PENABLE           (i_penable),
    .PWRITE            (i_pwrite),
    .PADDR             (i_paddr[11:2]),
    .PWDATA            (i_pwdata),

    .ECOREVNUM         (4'h0),// Engineering-change-order revision bits

      // APB interface outputs
    .PREADY            (timer0_pready),
    .PRDATA            (timer0_prdata),
    .PSLVERR           (timer0_pslverr),

    .EXTIN             (timer0_extin),  // External input
    .TIMERINT          (timer0_int)     // interrupt output
  );
  end else
  begin : gen_no_apb_timer_0
    assign timer0_prdata  = {32{1'b0}};
    assign timer0_pready  = 1'b1;
    assign timer0_pslverr = 1'b0;
    assign timer0_int     = 1'b0;
  end endgenerate

  generate if (INCLUDE_APB_TIMER1 == 1) begin : gen_apb_timer_1
  cmsdk_apb_timer u_apb_timer_1 (
    .PCLK              (PCLK),     // PCLK for timer operation
    .PCLKG             (PCLKG),    // Gated PCLK for bus
    .PRESETn           (PRESETn),  // Reset
    // APB interface inputs
    .PSEL              (timer1_psel),
    .PENABLE           (i_penable),
    .PWRITE            (i_pwrite),
    .PADDR             (i_paddr[11:2]),
    .PWDATA            (i_pwdata),

    .ECOREVNUM         (4'h0),// Engineering-change-order revision bits

      // APB interface outputs
    .PREADY            (timer1_pready),
    .PRDATA            (timer1_prdata),
    .PSLVERR           (timer1_pslverr),

    .EXTIN             (timer1_extin),  // External input
    .TIMERINT          (timer1_int)     // interrupt output
  );
  end else
  begin : gen_no_apb_timer_1
    assign timer1_prdata  = {32{1'b0}};
    assign timer1_pready  = 1'b1;
    assign timer1_pslverr = 1'b0;
    assign timer1_int     = 1'b0;
  end endgenerate

  // -----------------------------------------------------------------
  // Dual Timers
  generate if (INCLUDE_APB_DUALTIMER0 == 1) begin : gen_apb_dualtimers_2
  cmsdk_apb_dualtimers u_apb_dualtimers_2 (
   // Inputs
    .PCLK              (PCLKG),
    .PRESETn           (PRESETn),
    .PSEL              (dualtimer2_psel),
    .PENABLE           (i_penable),
    .PWRITE            (i_pwrite),
    .PADDR             (i_paddr[11:2]),
    .PWDATA            (i_pwdata),

    .TIMCLK            (PCLK),
    .TIMCLKEN1         (1'b1), // simple case:the timer 0 clock always enable
    .TIMCLKEN2         (1'b1), // simple case:the timer 1 clock always enable

    .ECOREVNUM         (4'h0),// Engineering-change-order revision bits

   // Outputs
    .PRDATA            (dualtimer2_prdata),

    .TIMINT1           (dualtimer2a_int), // not used
    .TIMINT2           (dualtimer2b_int), // not used
    .TIMINTC           (dualtimer2_comb_int)

  );
  end else
  begin : gen_no_apb_dualtimers_2
    assign dualtimer2_prdata   = {32{1'b0}};
    assign dualtimer2_comb_int = 1'b0;
    assign dualtimer2a_int     = 1'b0;
    assign dualtimer2b_int     = 1'b0;
  end endgenerate

  // When using peripherals with APB (AMBA 2.0), the PREADY and PSLVERR
  // signals are not required. So we connect PREADY to 1 and PSLVERR to 0.
  assign dualtimer2_pslverr = 1'b0;
  assign dualtimer2_pready  = 1'b1;

  // -----------------------------------------------------------------
  // Watchdog

  generate if (INCLUDE_APB_WATCHDOG == 1) begin : gen_apb_watchdog
  cmsdk_apb_watchdog u_apb_watchdog (
   // Inputs
    .PCLK              (PCLKG),
    .PRESETn           (PRESETn),
    .PSEL              (watchdog_psel),
    .PENABLE           (i_penable),
    .PWRITE            (i_pwrite),
    .PADDR             (i_paddr[11:2]),
    .PWDATA            (i_pwdata),

    .WDOGCLK           (PCLK),
    .WDOGCLKEN         (1'b1),
    .WDOGRESn          (PRESETn),

    .ECOREVNUM         (4'h0),// Engineering-change-order revision bits

   // Outputs
    .PRDATA            (watchdog_prdata),

    .WDOGINT           (watchdog_int),  // connect to NMI
    .WDOGRES           (watchdog_rst)   // connect to reset generator

  );
  end else
  begin : gen_no_apb_watchdog
    assign watchdog_prdata  = {32{1'b0}};
    assign watchdog_int     = 1'b0;
    assign watchdog_rst     = 1'b0;
  end endgenerate

  // When using peripherals with APB (AMBA 2.0), the PREADY and PSLVERR
  // signals are not required. So we connect PREADY to 1 and PSLVERR to 0.
  assign watchdog_pslverr = 1'b0;
  assign watchdog_pready  = 1'b1;

  // -----------------------------------------------------------------
  // UARTs
  generate if (INCLUDE_APB_UART0 == 1) begin : gen_apb_uart_0
  cmsdk_apb_uart u_apb_uart_0 (
    .PCLK              (PCLK),     // Peripheral clock
    .PCLKG             (PCLKG),    // Gated PCLK for bus
    .PRESETn           (PRESETn),  // Reset

    .PSEL              (uart0_psel),     // APB interface inputs
    .PENABLE           (i_penable),
    .PWRITE            (i_pwrite),
    .PADDR             (i_paddr[11:2]),
    .PWDATA            (i_pwdata),
    .PREADY            (uart0_pready),
    .PRDATA            (uart0_prdata),   // APB interface outputs
    .PSLVERR           (uart0_pslverr),

    .ECOREVNUM         (4'h0),// Engineering-change-order revision bits

    .RXD               (uart0_rxd),      // Receive data
    .TXD               (uart0_txd),      // Transmit data
    .TXEN              (uart0_txen),     // Transmit Enabled
    .BAUDTICK          (),   // Baud rate x16 tick output (for testing)

    .TXINT             (uart0_txint),       // Transmit Interrupt
    .RXINT             (uart0_rxint),       // Receive  Interrupt
    .TXOVRINT          (uart0_txovrint),    // Transmit Overrun Interrupt
    .RXOVRINT          (uart0_rxovrint),    // Receive  Overrun Interrupt
    .UARTINT           (uart0_combined_int) // Combined Interrupt
  );
  end else
  begin : gen_no_apb_uart_0
    assign uart0_prdata  = {32{1'b0}};
    assign uart0_pready  = 1'b1;
    assign uart0_pslverr = 1'b0;
    assign uart0_txd     = 1'b1;
    assign uart0_txen    = 1'b0;
    assign uart0_txint   = 1'b0;
    assign uart0_rxint   = 1'b0;
    assign uart0_txovrint = 1'b0;
    assign uart0_rxovrint = 1'b0;
    assign uart0_combined_int = 1'b0;
  end endgenerate

  generate if (INCLUDE_APB_UART1 == 1) begin : gen_apb_uart_1
  cmsdk_apb_uart u_apb_uart_1 (
    .PCLK              (PCLK),     // Peripheral clock
    .PCLKG             (PCLKG),    // Gated PCLK for bus
    .PRESETn           (PRESETn),  // Reset

    .PSEL              (uart1_psel),     // APB interface inputs
    .PENABLE           (i_penable),
    .PWRITE            (i_pwrite),
    .PADDR             (i_paddr[11:2]),
    .PWDATA            (i_pwdata),
    .PREADY            (uart1_pready),
    .PRDATA            (uart1_prdata),   // APB interface outputs
    .PSLVERR           (uart1_pslverr),

    .ECOREVNUM         (4'h0),// Engineering-change-order revision bits

    .RXD               (uart1_rxd),      // Receive data
    .TXD               (uart1_txd),      // Transmit data
    .TXEN              (uart1_txen),     // Transmit Enabled
    .BAUDTICK          (),   // Baud rate x16 tick output (for testing)

    .TXINT             (uart1_txint),       // Transmit Interrupt
    .RXINT             (uart1_rxint),       // Receive  Interrupt
    .TXOVRINT          (uart1_txovrint),    // Transmit Overrun Interrupt
    .RXOVRINT          (uart1_rxovrint),    // Receive  Overrun Interrupt
    .UARTINT           (uart1_combined_int) // Combined Interrupt
  );
  end else
  begin : gen_no_apb_uart_1
    assign uart1_prdata  = {32{1'b0}};
    assign uart1_pready  = 1'b1;
    assign uart1_pslverr = 1'b0;
    assign uart1_txd     = 1'b1;
    assign uart1_txen    = 1'b0;
    assign uart1_txint   = 1'b0;
    assign uart1_rxint   = 1'b0;
    assign uart1_txovrint = 1'b0;
    assign uart1_rxovrint = 1'b0;
    assign uart1_combined_int = 1'b0;
  end endgenerate

/*
  // 直接替换UART1
  generate if (INCLUDE_APB_UART1 == 1) begin : gen_apb_uart_1
  cmsdk_apb1_uart u_apb_uart_1 (
    .PCLK              (PCLK),            // Peripheral clock
    .PRESETn           (PRESETn),         // Reset

    .PSEL              (uart1_psel),      // APB interface inputs
    .PENABLE           (i_penable),
    .PWRITE            (i_pwrite),
    .PADDR             (i_paddr[11:2]),
    .PWDATA            (i_pwdata),
    .PREADY            (uart1_pready),
    .PRDATA            (uart1_prdata),    // APB interface outputs
    .PSLVERR           (uart1_pslverr),

    .RXD               (uart1_rxd),       // Receive data
    .TXD               (uart1_txd),       // Transmit data
    .TXEN              (uart1_txen),      // Transmit Enabled
    .BAUDTICK          (),   // Baud rate x16 tick output (for testing)

    .TXINT             (uart1_txint),       // Transmit Interrupt
    .RXINT             (uart1_rxint),       // Receive  Interrupt
    .TXOVRINT          (uart1_txovrint),    // Transmit Overrun Interrupt
    .RXOVRINT          (uart1_rxovrint),    // Receive  Overrun Interrupt
    .UARTINT           (uart1_combined_int) // Combined Interrupt
  );
  end else
  begin : gen_no_apb_uart_1
    assign uart1_prdata  = {32{1'b0}};
    assign uart1_pready  = 1'b1;
    assign uart1_pslverr = 1'b0;
    assign uart1_txd     = 1'b1;
    assign uart1_txen    = 1'b0;
    assign uart1_txint   = 1'b0;
    assign uart1_rxint   = 1'b0;
    assign uart1_txovrint = 1'b0;
    assign uart1_rxovrint = 1'b0;
    assign uart1_combined_int = 1'b0;
  end endgenerate
  */

  generate if (INCLUDE_APB_UART2 == 1) begin : gen_apb_uart_2
  cmsdk_apb_uart u_apb_uart_2 (
    .PCLK              (PCLK),     // Peripheral clock
    .PCLKG             (PCLKG),    // Gated PCLK for bus
    .PRESETn           (PRESETn),  // Reset

    .PSEL              (uart2_psel),     // APB interface inputs
    .PENABLE           (i_penable),
    .PWRITE            (i_pwrite),
    .PADDR             (i_paddr[11:2]),
    .PWDATA            (i_pwdata),
    .PREADY            (uart2_pready),
    .PRDATA            (uart2_prdata),   // APB interface outputs
    .PSLVERR           (uart2_pslverr),

    .ECOREVNUM         (4'h0),// Engineering-change-order revision bits

    .RXD               (uart2_rxd),      // Receive data
    .TXD               (uart2_txd),      // Transmit data
    .TXEN              (uart2_txen),     // Transmit Enabled
    .BAUDTICK          (),   // Baud rate x16 tick output (for testing)

    .TXINT             (uart2_txint),       // Transmit Interrupt
    .RXINT             (uart2_rxint),       // Receive  Interrupt
    .TXOVRINT          (uart2_txovrint),    // Transmit Overrun Interrupt
    .RXOVRINT          (uart2_rxovrint),    // Receive  Overrun Interrupt
    .UARTINT           (uart2_combined_int) // Combined Interrupt
  );
  end else
  begin : gen_no_apb_uart_2
    assign uart2_prdata  = {32{1'b0}};
    assign uart2_pready  = 1'b1;
    assign uart2_pslverr = 1'b0;
    assign uart2_txd     = 1'b1;
    assign uart2_txen    = 1'b0;
    assign uart2_txint   = 1'b0;
    assign uart2_rxint   = 1'b0;
    assign uart2_txovrint = 1'b0;
    assign uart2_rxovrint = 1'b0;
    assign uart2_combined_int = 1'b0;
  end endgenerate

  
  // -----------------------------------------------------------------
  // Test slave (for validation purpose)
  generate if (INCLUDE_APB_TEST_SLAVE == 1) begin : gen_apb_test_slave
  cmsdk_apb_test_slave u_apb_test_slave(
    .PCLK              (PCLKG),    // use Gated PCLK for bus
    .PRESETn           (PRESETn),  // Reset

    .PSEL              (test_slave_psel),     // APB interface inputs
    .PENABLE           (i_penable),
    .PWRITE            (i_pwrite),
    .PSTRB             (i_pstrb[3:0]),
    .PADDR             (i_paddr[11:2]),
    .PWDATA            (i_pwdata),
    .PREADY            (test_slave_pready),
    .PRDATA            (test_slave_prdata),   // APB interface outputs
    .PSLVERR           (test_slave_pslverr)
  );
  end else
  begin : gen_no_apb_test_slave
    assign test_slave_prdata  = {32{1'b0}};
    assign test_slave_pready  = 1'b1;
    assign test_slave_pslverr = 1'b0;
  end endgenerate

  // -----------------------------------------------------------------
  // Connection to external
  assign PENABLE = i_penable;
  assign PWRITE  = i_pwrite;
  assign PADDR   = i_paddr[11:0];
  assign PWDATA  = i_pwdata;

  assign uart0_overflow_int = uart0_txovrint|uart0_rxovrint;
  assign uart1_overflow_int = uart1_txovrint|uart1_rxovrint;
  assign uart2_overflow_int = uart2_txovrint|uart2_rxovrint;

  // 跨时钟域中断同步处理
  generate if (INCLUDE_IRQ_SYNCHRONIZER == 0) begin : gen_irq_synchroniser
    // If PCLK is synchronous to ACLK, no need to have synchronizers
    assign i_uart0_txint = uart0_txint;
    assign i_uart0_rxint = uart0_rxint;
    assign i_uart1_txint = uart1_txint;
    assign i_uart1_rxint = uart1_rxint;
    assign i_uart2_txint = uart2_txint;
    assign i_uart2_rxint = uart2_rxint;
    assign i_timer0_int  = timer0_int;
    assign i_timer1_int  = timer1_int;
    assign i_dualtimer2_int = dualtimer2_comb_int;
    assign i_uart0_overflow_int = uart0_overflow_int;
    assign i_uart1_overflow_int = uart1_overflow_int;
    assign i_uart2_overflow_int = uart2_overflow_int;
    assign i_watchdog_int = watchdog_int;
    assign i_watchdog_rst = watchdog_rst;
  end else
  begin : gen_no_irq_synchroniser
    // If IRQ source are asynchronous to ACLK, then we
    // need to add synchronizers to prevent metastability
    // on interrupt signals.
    cmsdk_irq_sync u_irq_sync_0 (
      .RSTn  (HRESETn),
      .CLK   (ACLK),
      .IRQIN (uart0_txint),
      .IRQOUT(i_uart0_txint)
      );

    cmsdk_irq_sync u_irq_sync_1 (
      .RSTn  (HRESETn),
      .CLK   (ACLK),
      .IRQIN (uart0_rxint),
      .IRQOUT(i_uart0_rxint)
      );

    cmsdk_irq_sync u_irq_sync_2 (
      .RSTn  (HRESETn),
      .CLK   (ACLK),
      .IRQIN (uart1_txint),
      .IRQOUT(i_uart1_txint)
      );

    cmsdk_irq_sync u_irq_sync_3 (
      .RSTn  (HRESETn),
      .CLK   (ACLK),
      .IRQIN (uart1_rxint),
      .IRQOUT(i_uart1_rxint)
      );

    cmsdk_irq_sync u_irq_sync_4 (
      .RSTn  (HRESETn),
      .CLK   (ACLK),
      .IRQIN (uart2_txint),
      .IRQOUT(i_uart2_txint)
      );

    cmsdk_irq_sync u_irq_sync_5 (
      .RSTn  (HRESETn),
      .CLK   (ACLK),
      .IRQIN (uart2_rxint),
      .IRQOUT(i_uart2_rxint)
      );

    cmsdk_irq_sync u_irq_sync_6 (
      .RSTn  (HRESETn),
      .CLK   (ACLK),
      .IRQIN (timer0_int),
      .IRQOUT(i_timer0_int)
      );

    cmsdk_irq_sync u_irq_sync_7 (
      .RSTn  (HRESETn),
      .CLK   (ACLK),
      .IRQIN (timer1_int),
      .IRQOUT(i_timer1_int)
      );

    cmsdk_irq_sync u_irq_sync_8 (
      .RSTn  (HRESETn),
      .CLK   (ACLK),
      .IRQIN (dualtimer2_comb_int),
      .IRQOUT(i_dualtimer2_int)
      );

    cmsdk_irq_sync u_irq_sync_9 (
      .RSTn  (HRESETn),
      .CLK   (ACLK),
      .IRQIN (uart0_overflow_int),
      .IRQOUT(i_uart0_overflow_int)
      );

    cmsdk_irq_sync u_irq_sync_10 (
      .RSTn  (HRESETn),
      .CLK   (ACLK),
      .IRQIN (uart1_overflow_int),
      .IRQOUT(i_uart1_overflow_int)
      );

    cmsdk_irq_sync u_irq_sync_11 (
      .RSTn  (HRESETn),
      .CLK   (ACLK),
      .IRQIN (uart2_overflow_int),
      .IRQOUT(i_uart2_overflow_int)
      );

    cmsdk_irq_sync u_irq_sync_12 (
      .RSTn  (HRESETn),
      .CLK   (ACLK),
      .IRQIN (watchdog_int),
      .IRQOUT(i_watchdog_int)
      );

    cmsdk_irq_sync u_irq_sync_13 (
      .RSTn  (HRESETn),
      .CLK   (ACLK),
      .IRQIN (watchdog_rst),
      .IRQOUT(i_watchdog_rst)
      );

  end endgenerate

  // Interrupt assignment（中断源分配）
  assign apbsubsys_interrupt[31:0] = {
                   {16{1'b0}},                       // 16-31 (AXI GPIO #0 individual interrupt)
                   1'b0,                             // 15 (DMA interrupt)
                   i_uart2_overflow_int,             // 14
                   i_uart1_overflow_int,             // 13
                   i_uart0_overflow_int,             // 12
                   1'b0,                             // 11
                   i_dualtimer2_int,                 // 10
                   i_timer1_int,                     // 9
                   i_timer0_int,                     // 8
                   1'b0,                             // 7 (GPIO #1 combined interrupt)
                   1'b0,                             // 6 (GPIO #0 combined interrupt)
                   i_uart2_txint,                    // 5
                   i_uart2_rxint,                    // 4
                   i_uart1_txint,                    // 3
                   i_uart1_rxint,                    // 2
                   i_uart0_txint,                    // 1
                   i_uart0_rxint};                   // 0

  assign watchdog_interrupt = i_watchdog_int;
  assign watchdog_reset     = i_watchdog_rst;

endmodule
