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
// Simple AXI to IOP Bridge (for use with the IOP GPIO to make an AXI GPIO).
// 不支持BURST传输
//-----------------------------------------------------------------------------

module cmsdk_axi_to_iop
(
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

  // IOP Interface
  output reg                    IOSEL,      // Decode for peripheral
  output reg                    IOTRANS,    // I/O transaction
  output reg                    IOWRITE,    // I/O transfer direction
  output reg  [1:0]             IOSIZE,     // I/O transfer size
  output reg  [11:0]            IOADDR,     // I/O transfer address
  output wire [31:0]            IOWDATA,    // I/O write data bus
  input wire  [31:0]            IORDATA     // I/0 read data bus
  );

  // ----------------------------------------------------------
  // Read/write control logic
  // ----------------------------------------------------------

  // registered ASEL, update only if selected to reduce toggling
  always @(posedge ACLK or negedge ARESETn)
  begin
    if (~ARESETn)
      IOSEL <= 1'b0;
    else
      IOSEL <= AW_SEL | AR_SEL;
  end

  // registered address, update only if selected to reduce toggling
  always @(posedge ACLK or negedge ARESETn)
  begin
    if (~ARESETn)
      IOADDR <= {12{1'b0}};
    else if (AW_VALID)   // write
      IOADDR <= AW_ADDR[11:0];
    else if (AR_VALID)   // read
      IOADDR <= AR_ADDR[11:0];
  end

  // Data phase write control
  always @(posedge ACLK or negedge ARESETn)
  begin
    if (~ARESETn)
      IOWRITE <= 1'b0;
    else if (AW_VALID)   // write
      IOWRITE <= 1'b1;
    else if (AR_VALID)   // read
      IOWRITE <= 1'b0;
  end

  // registered hsize, update only if selected to reduce toggling
  always @(posedge ACLK or negedge ARESETn)
  begin
    if (~ARESETn)
      IOSIZE <= {2{1'b0}};
    else if (AW_VALID)   // write
      IOSIZE <= AW_SIZE[1:0];
    else if (AR_VALID)   // read
      IOSIZE <= AR_SIZE[1:0];
  end

  // registered TRANS, update only if selected to reduce toggling
  always @(posedge ACLK or negedge ARESETn)
  begin
    if (~ARESETn)
      IOTRANS <= 1'b0;
    else
      IOTRANS <= (AW_VALID & AW_READY) | (AR_VALID & AR_READY);
  end

  assign AW_READY = 1'b1;
  assign IOWDATA = W_DATA;
  assign W_READY  = 1'b1;
  assign B_VALID  = 1'b1;
  assign B_RESP   = 2'b00;      // OKAY

  assign AR_READY = 1'b1;
  assign R_VALID  = 1'b1;
  assign R_LAST   = 1'b1;
  assign R_DATA   = IORDATA;
  assign R_RESP   = 2'b00;      // OKAY

endmodule
