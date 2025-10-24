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

module cmsdk_axi_gpio
 #(// Parameter to define valid bit pattern for Alternate functions
   // If an I/O pin does not have alternate function its function mask
   // can be set to 0 to reduce gate count.
   //
   // By default every bit can have alternate function
   parameter  ALTERNATE_FUNC_MASK = 16'hFFFF,

   // Default alternate function settings
   parameter  ALTERNATE_FUNC_DEFAULT = 16'h0000,

   // By default use little endian
   parameter  BE = 0
  )

// ----------------------------------------------------------------------------
// Port Definitions
// ----------------------------------------------------------------------------
  (
  input  wire                   FCLK,       // Clock
  input  wire                   ACLK,       // Clock
  input  wire                   ARESETn,    // Reset

  //----------------- AXI - Write -----------------
  input  wire                   AW_SEL,     // SEL
  input wire                    AW_VALID,
  output wire                   AW_READY,
  input wire   [2:0]            AW_SIZE,
  input wire   [1:0]            AW_BURST,
  input wire   [7:0]            AW_LEN,
  input wire   [31:0]           AW_ADDR,

  input wire                    W_VALID,
  output wire                   W_READY,
  input wire                    W_LAST,
  input wire   [31:0]           W_DATA,

  output wire                   B_VALID,
  input wire                    B_READY,
  output wire  [1:0]            B_RESP,

  //----------------- AXI - Read ------------------
  input  wire                   AR_SEL,     // SEL
  input wire                    AR_VALID,
  output wire                   AR_READY,
  input wire   [2:0]            AR_SIZE,
  input wire   [1:0]            AR_BURST,
  input wire   [7:0]            AR_LEN,
  input wire   [31:0]           AR_ADDR,

  output wire                   R_VALID,
  input wire                    R_READY,
  output wire                   R_LAST,
  output wire  [31:0]           R_DATA,
  output wire  [1:0]            R_RESP,

  input wire  [3:0]             ECOREVNUM,  // Engineering-change-order revision bits
 
  // Port interface
  input wire  [15:0]            PORTIN,     // GPIO Interface input
 
  // Outputs 
  output wire [15:0]            PORTOUT,    // GPIO output
  output wire [15:0]            PORTEN,     // GPIO output enable
  output wire [15:0]            PORTFUNC,   // Alternate function control
 
  output wire [15:0]            GPIOINT,    // Interrupt output for each pin
  output wire                   COMBINT   // Combined interrupt
  );
  
// ----------------------------------------------------------------------------
// Internal wires
// ----------------------------------------------------------------------------

   wire                  IOSEL;      // Decode for peripheral
   wire                  IOTRANS;    // I/O transaction
   wire                  IOWRITE;    // I/O transfer direction
   wire  [1:0]           IOSIZE;     // I/O transfer size
   wire [11:0]           IOADDR;     // I/O transfer address
   wire [31:0]           IOWDATA;    // I/O write data bus
   wire [31:0]           IORDATA;    // I/0 read data bus

// ----------------------------------------------------------------------------
// Block Instantiations
// ----------------------------------------------------------------------------
  // Convert AXI Lite protocol to simple I/O port interface
  cmsdk_axi_to_iop
    u_axi_to_gpio  (
    .ACLK          (ACLK),
    .ARESETn       (ARESETn),
    //----------------- AXI - Write -----------------
    .AW_SEL        (AW_SEL),
    .AW_VALID      (AW_VALID),
    .AW_READY      (AW_READY),
    .AW_SIZE       (AW_SIZE),
    .AW_BURST      (AW_BURST),
    .AW_LEN        (AW_LEN),
    .AW_ADDR       (AW_ADDR),
    .W_VALID       (W_VALID),
    .W_READY       (W_READY),
    .W_LAST        (W_LAST),
    .W_DATA        (W_DATA),
    .B_VALID       (B_VALID),
    .B_READY       (B_READY),
    .B_RESP        (B_RESP),
    //----------------- AXI - Read ------------------
    .AR_SEL        (AR_SEL),
    .AR_VALID      (AR_VALID),
    .AR_READY      (AR_READY),
    .AR_SIZE       (AR_SIZE),
    .AR_BURST      (AR_BURST),
    .AR_LEN        (AR_LEN),
    .AR_ADDR       (AR_ADDR),
    .R_VALID       (R_VALID),
    .R_READY       (R_READY),
    .R_LAST        (R_LAST),
    .R_DATA        (R_DATA),
    .R_RESP        (R_RESP),

    // GPIO interface
    .IOSEL         (IOSEL),
    .IOTRANS       (IOTRANS),
    .IOWRITE       (IOWRITE),
    .IOSIZE        (IOSIZE),
    .IOADDR        (IOADDR[11:0]),
    .IOWDATA       (IOWDATA),
    .IORDATA       (IORDATA)
    );

  // GPIO module with I/O port interface
  cmsdk_iop_gpio #(
    .ALTERNATE_FUNC_MASK     (ALTERNATE_FUNC_MASK),
    .ALTERNATE_FUNC_DEFAULT  (ALTERNATE_FUNC_DEFAULT), // All pins default to GPIO
    .BE                      (BE))
    u_iop_gpio  (
    // GPIO interface
    .ACLK         (ACLK),
    .ARESETn      (ARESETn),
    .FCLK         (FCLK),
    .IOSEL        (IOSEL),
    .IOTRANS      (IOTRANS),
    .IOSIZE       (IOSIZE),
    .IOWRITE      (IOWRITE),
    .IOADDR       (IOADDR[11:0]),
    .IOWDATA      (IOWDATA),
    .IORDATA      (IORDATA),

    .ECOREVNUM    (ECOREVNUM),// Engineering-change-order revision bits

    // Port interface
    .PORTIN       (PORTIN),   // GPIO Interface inputs
    .PORTOUT      (PORTOUT),  // GPIO Interface outputs
    .PORTEN       (PORTEN),
    .PORTFUNC     (PORTFUNC), // Alternate function control

    .GPIOINT      (GPIOINT),  // Interrupt outputs
    .COMBINT      (COMBINT)
  );

endmodule
