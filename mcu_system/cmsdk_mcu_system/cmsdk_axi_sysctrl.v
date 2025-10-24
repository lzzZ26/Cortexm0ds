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
// Abstract : System controller for simple Cortex-M Microcontroller system
//            不支持BURSt传输
//-----------------------------------------------------------------------------
//-------------------------------------
// Programmer's model
// -------------------------------
// 0x000 RW    MEM_CTRL
//      bit [  0]  REMAP - default value 1
// 0x004 RW    PMU_CTRL
//      bit [  0]  PMUENABLE - default value 0
// 0x008 R/W   SYS_CTRL
//      bit [  0]  LOCKUPRESETEN - default value 0
// 0x00C --    Not used
//
// 0x010 R/Wc  Reset Information
//      bit [  2]  LOCKUPRESET
//      bit [  1]  WDOGRESETREQ
//      bit [  0]  SYSRESETREQ
//
//-------------------------------------
`include "cmsdk_mcu_defs.v"

module cmsdk_axi_sysctrl #(
  parameter  BE = 0                                 // By default use little endian
  )
  (
  input  wire               FCLK,                   // Free running clock
  input  wire               PORESETn,               // power on reset
  input  wire               ACLK,                   // system bus clock
  input  wire               ARESETn,                // system bus reset

  //----------------- AXI - Write -----------------
  input  wire               AW_SEL,                 // AXI peripheral select
  input wire                AW_VALID,               // Write request valid
  output wire               AW_READY,               // Write request ready
  input wire   [2:0]        AW_SIZE,                // Write data size
  input wire   [1:0]        AW_BURST,               // Write data burst type
  input wire   [7:0]        AW_LEN,                 // Write data burst length
  input wire   [31:0]       AW_ADDR,                // Write address

  input wire                W_VALID,                // Write data valid
  output wire               W_READY,                // Write data ready
  input wire                W_LAST,                 // Write data last
  input wire   [31:0]       W_DATA,                 // Write data

  output wire               B_VALID,                // Write response valid
  input wire                B_READY,                // Write response ready
  output wire  [1:0]        B_RESP,                 // Write response

  //----------------- AXI - Read ------------------
  input  wire               AR_SEL,                 // AXI peripheral select
  input wire                AR_VALID,               // Read request valid
  output wire               AR_READY,               // Read request ready
  input wire   [2:0]        AR_SIZE,                // Read data size
  input wire   [1:0]        AR_BURST,               // Read data burst type
  input wire   [7:0]        AR_LEN,                 // Read data burst length
  input wire   [31:0]       AR_ADDR,                // Read address

  output wire               R_VALID,                // Read response valid
  input wire                R_READY,                // Read response ready
  output wire               R_LAST,                 // Read data last
  output wire  [31:0]       R_DATA,                 // Read data
  output wire  [1:0]        R_RESP,                 // Read response

   // Reset information
  input  wire               SYSRESETREQ,            // System reset request
  input  wire               WDOGRESETREQ,           // Watchdog reset request
  input  wire               LOCKUP,                 // CPU locked up

   //ECO revision number
  input  wire  [3:0]        ECOREVNUM,              // ECO revision number

   // System control signals
  output wire               REMAP,                  // memory remap
  output wire               PMUENABLE,              // Power Management Unit enable, will be disabled in design start version
  output wire               LOCKUPRESET             // Enable reset if lockup
  );

// --------------------------------------------------------------------------
// Port Definitions
// --------------------------------------------------------------------------

//Local parameter for IDs,
localparam  ARM_CMSDK_CM0_SYSCTRL_PID4 = {32'h00000004}; // 0xFD0 : PID 4
localparam  ARM_CMSDK_CM0_SYSCTRL_PID5 = {32'h00000000}; // 0xFD4 : PID 5
localparam  ARM_CMSDK_CM0_SYSCTRL_PID6 = {32'h00000000}; // 0xFD8 : PID 6
localparam  ARM_CMSDK_CM0_SYSCTRL_PID7 = {32'h00000000}; // 0xFDC : PID 7
localparam  ARM_CMSDK_CM0_SYSCTRL_PID0 = {32'h00000026}; // 0xFE0 : PID 0 part number[7:0]
localparam  ARM_CMSDK_CM0_SYSCTRL_PID1 = {32'h000000B8}; // 0xFE4 : PID 1 [7:4] jep106_id_3_0. [3:0] part number [11:8]
localparam  ARM_CMSDK_CM0_SYSCTRL_PID2 = {32'h0000001B}; // 0xFE8 : PID 2 [7:4] revision, [3] jedec_used. [2:0] jep106_id_6_4
localparam  ARM_CMSDK_CM0_SYSCTRL_PID3 = {32'h00000000}; // 0xFEC : PID 3
localparam  ARM_CMSDK_CM0_SYSCTRL_CID0 = {32'h0000000D}; // 0xFF0 : CID 0
localparam  ARM_CMSDK_CM0_SYSCTRL_CID1 = {32'h000000F0}; // 0xFF4 : CID 1 PrimeCell class
localparam  ARM_CMSDK_CM0_SYSCTRL_CID2 = {32'h00000005}; // 0xFF8 : CID 2
localparam  ARM_CMSDK_CM0_SYSCTRL_CID3 = {32'h000000B1}; // 0xFFC : CID 3
// Note : Customer changing the design should modify
// - jep106 value (www.jedec.org)
// - part number (customer define)
// - Optional revision and modification number (e.g. rXpY)

  // --------------------------------------------------------------------------
  // Internal wires
  // --------------------------------------------------------------------------
  reg                       reg_remap;              // memory remap
  wire                      reg_pmuenable;          // Power Management Unit enable
  reg                       reg_lockupreset;        // Enable reset if lockup
  reg [ 2:0]                reg_resetinfo;          // Reset information
  reg [31:0]                read_mux;               // read mux
  reg [31:0]                read_mux_le;            // little endian of read mux

  wire                      bigendian = (BE!=0) ? 1'b1 : 1'b0;
  wire                      axi_write_addr;         // 写地址
  wire                      axi_read_addr;          // 读地址
  wire                      axi_write_data;         // 写数据
  wire                      axi_read_data;          // 读数据
  reg                       reg_write_enable;       // Write enable
  reg                       reg_read_enable;        // Read enable
  reg  [11:2]               reg_awaddr, reg_araddr;
  reg  [ 2:0]               reg_awsize, reg_arsize;
  reg  [31:0]               WDATALE;                // Little endian version of W_DATA
  wire [ 3:0]               nxt_wbyte_strobe;       // Write byte strobe next
  reg  [ 3:0]               reg_wbyte_strobe;       // Write byte strobe

  // ----------------------------------------------------------
  // AXI写操作接口
  // ----------------------------------------------------------
  assign AW_READY = 1'b1;
  assign W_READY = 1'b1;
  assign B_VALID = 1'b1;
  assign B_RESP = 2'b00;      // OKAY

  // ----------------------------------------------------------
  // AXI读操作接口
  // ----------------------------------------------------------
  assign AR_READY = 1'b1;
  assign R_VALID  = 1'b1;
  assign R_LAST   = 1'b1;
  assign R_DATA   = read_mux;
  assign R_RESP   = 2'b00;    // OKAY

  // ----------------------------------------------------------
  // Write/read control logic
  // ----------------------------------------------------------
  assign axi_write_addr = AW_SEL & AW_VALID & AW_READY;   // 写地址
  assign axi_write_data = W_VALID & W_READY;              // 写数据
  assign axi_read_addr  = AR_SEL & AR_VALID & AR_READY;   // 读地址
  assign axi_read_data  = R_VALID & R_READY;              // 读数据

  // registered address, update only if selected to reduce toggling
  always @(posedge ACLK or negedge ARESETn)
  begin
    if (~ARESETn)
      reg_awaddr <= {10{1'b0}};
    else if (axi_write_addr)
      reg_awaddr <= AW_ADDR[11:2];
  end
  always @(posedge ACLK or negedge ARESETn)
  begin
    if (~ARESETn)
      reg_araddr <= {10{1'b0}};
    else if (axi_read_addr)
      reg_araddr <= AR_ADDR[11:2];
  end

  // registered size, update only if selected to reduce toggling
  always @(posedge ACLK or negedge ARESETn)
  begin
    if (~ARESETn)
      reg_awsize <= {2{1'b0}};
    else if (axi_write_addr)
      reg_awsize <= AW_SIZE[1:0];
  end
  always @(posedge ACLK or negedge ARESETn)
  begin
    if (~ARESETn)
      reg_arsize <= {2{1'b0}};
    else if (axi_read_addr)
      reg_arsize <= AR_SIZE[1:0];
  end

  // Data phase write/read enable
  always @(posedge ACLK or negedge ARESETn)
  begin
    if (~ARESETn)
      reg_write_enable <= 1'b0;
    else if (W_READY)
      reg_write_enable <= axi_write_data;
  end
  always @(posedge ACLK or negedge ARESETn)
  begin
    if (~ARESETn)
      reg_read_enable  <= 1'b0;
    else if (R_VALID)
      reg_read_enable  <= axi_read_data;
  end

  // Generate byte strobes to allow the GPIO registers to handle different transfer sizes
  assign nxt_wbyte_strobe[0] = (AW_SIZE[1] | ((AW_ADDR[1]==1'b0) & AW_SIZE[0]) | (AW_ADDR[1:0]==2'b00)) & axi_write_addr;
  assign nxt_wbyte_strobe[1] = (AW_SIZE[1] | ((AW_ADDR[1]==1'b0) & AW_SIZE[0]) | (AW_ADDR[1:0]==2'b01)) & axi_write_addr;
  assign nxt_wbyte_strobe[2] = (AW_SIZE[1] | ((AW_ADDR[1]==1'b1) & AW_SIZE[0]) | (AW_ADDR[1:0]==2'b10)) & axi_write_addr;
  assign nxt_wbyte_strobe[3] = (AW_SIZE[1] | ((AW_ADDR[1]==1'b1) & AW_SIZE[0]) | (AW_ADDR[1:0]==2'b11)) & axi_write_addr;

  // Address phase byte lane strobe
  always @(posedge ACLK or negedge ARESETn)
  begin
    if (~ARESETn)
      reg_wbyte_strobe  <= 4'b0000;
    else if (axi_write_addr)
      reg_wbyte_strobe  <= nxt_wbyte_strobe;
  end


  // ----------------------------------------------------------
  // 写寄存器操作
  // ----------------------------------------------------------
  // Write endian conversion
  always @(bigendian or reg_awsize or W_DATA)
  begin
    if ((bigendian)&(reg_awsize==3'b10))            // 4个字节
      WDATALE = {W_DATA[ 7: 0],W_DATA[15: 8],W_DATA[23:16],W_DATA[ 31:24]};
    else if ((bigendian)&(reg_awsize==3'b01))       // 2个字节
      WDATALE = {W_DATA[23:16],W_DATA[ 31:24],W_DATA[ 7: 0],W_DATA[15: 8]};
    else
      WDATALE = W_DATA;
   end

  // Remap register
  wire   reg_remap_write;
  assign reg_remap_write = reg_write_enable & (reg_awaddr[11:2]== 10'h000) & reg_wbyte_strobe[0];

  //  registering stage
  always @(posedge ACLK or negedge ARESETn)
  begin
    if (~ARESETn)
      reg_remap <= 1'b1;
    else if (reg_remap_write)
      reg_remap <= WDATALE[0];
  end

  // PMUENABLE register
  // Power management unit not available with Cortex-M0 DesignStart.
  // PMU control is disabled
  assign reg_pmuenable = 1'b0;

  // LOCKUPRESETEN register
  wire   reg_lockupreset_write;
  assign reg_lockupreset_write = reg_write_enable & (reg_awaddr[11:2]== 10'h002) & reg_wbyte_strobe[0];

  //  registering stage
  always @(posedge ACLK or negedge ARESETn)
  begin
    if (~ARESETn)
      reg_lockupreset <= 1'b0;
    else if (reg_lockupreset_write)
      reg_lockupreset <= WDATALE[0];
  end

  // Reset information register
  wire   reg_resetinfo_write;
  assign reg_resetinfo_write = reg_write_enable & (reg_awaddr[11:2]== 10'h004) & reg_wbyte_strobe[0];

  // capture reset information
  wire [2:0] nxt_resetinfo;
  // Write 1 to clear
  assign nxt_resetinfo[0] = ((~(reg_resetinfo_write & WDATALE[0])) & reg_resetinfo[0]) | SYSRESETREQ;
  assign nxt_resetinfo[1] = ((~(reg_resetinfo_write & WDATALE[1])) & reg_resetinfo[1]) | WDOGRESETREQ;
  assign nxt_resetinfo[2] = ((~(reg_resetinfo_write & WDATALE[2])) & reg_resetinfo[2]) | (reg_lockupreset & LOCKUP);

  // Enable flip-flop only if it should be updated to reduce power
  wire   reg_resetinfo_en;
  assign reg_resetinfo_en = reg_resetinfo_write | SYSRESETREQ | WDOGRESETREQ | (reg_lockupreset & LOCKUP);

  //  registering stage
  always @(posedge FCLK or negedge PORESETn)
  begin
    if (~PORESETn)
      reg_resetinfo <= 3'b000;
    else if (reg_resetinfo_en)
      reg_resetinfo <= nxt_resetinfo;
  end

  // Connect to higher level
  assign REMAP     = reg_remap;
  assign PMUENABLE = reg_pmuenable;
  assign LOCKUPRESET = reg_lockupreset;
  

  // ----------------------------------------------------------
  // 读寄存器操作
  // ----------------------------------------------------------
  always @(reg_araddr or reg_remap or reg_pmuenable or ECOREVNUM or
  reg_lockupreset or reg_resetinfo or reg_read_enable)
  begin
    case (reg_read_enable)
    1'b1:
        begin
        if (reg_araddr[11:5] == 7'h00) begin
            case(reg_araddr[4:2])
            3'b000: read_mux_le = {{31{1'b0}}, reg_remap} ;
            3'b001: read_mux_le = {{31{1'b0}}, reg_pmuenable} ;
            3'b010: read_mux_le = {{31{1'b0}}, reg_lockupreset} ;
            3'b100: read_mux_le = {{29{1'b0}}, reg_resetinfo} ;
            3'b011,3'b101,3'b110,3'b111: read_mux_le = {32{1'b0}};
            default: read_mux_le = {32{1'bx}};
            endcase
        end
        else if (reg_araddr[11:6] == 6'h3F)begin
            case (reg_araddr[5:2])
            4'h4:  read_mux_le = ARM_CMSDK_CM0_SYSCTRL_PID4;  //0xFD0 Peripheral ID 4
            4'h5:  read_mux_le = ARM_CMSDK_CM0_SYSCTRL_PID5;  //0xFD4 Peripheral ID 5
            4'h6:  read_mux_le = ARM_CMSDK_CM0_SYSCTRL_PID6;  //0xFD8 Peripheral ID 6
            4'h7:  read_mux_le = ARM_CMSDK_CM0_SYSCTRL_PID7;  //0xFDC Peripheral ID 7
            4'h8:  read_mux_le = ARM_CMSDK_CM0_SYSCTRL_PID0;  //0xFE0 Peripheral ID 0
            4'h9:  read_mux_le = ARM_CMSDK_CM0_SYSCTRL_PID1;  //0xFE4 Peripheral ID 1
            4'hA:  read_mux_le = ARM_CMSDK_CM0_SYSCTRL_PID2;  //0xFE8 Peripheral ID 2
            4'hB:  read_mux_le = {ARM_CMSDK_CM0_SYSCTRL_PID3[31:8], ECOREVNUM[3:0], 4'h0}; //0xFEC Peripheral ID 3
            4'hC:  read_mux_le = ARM_CMSDK_CM0_SYSCTRL_CID0;  //0xFF0 Component ID 0
            4'hD:  read_mux_le = ARM_CMSDK_CM0_SYSCTRL_CID1;  //0xFF4 Component ID 1
            4'hE:  read_mux_le = ARM_CMSDK_CM0_SYSCTRL_CID2;  //0xFF8 Component ID 2
            4'hF:  read_mux_le = ARM_CMSDK_CM0_SYSCTRL_CID3;  //0xFFC Component ID 3
            4'h0, 4'h1, 4'h2,4'h3: read_mux_le = {32{1'b0}};
            default: read_mux_le = {32{1'bx}};
            endcase
        end
        else begin
            read_mux_le = {32{1'b0}};
        end
        end
    1'b0:// read_enable is not active
        begin
        read_mux_le = {32{1'b0}};
        end
    default:
        read_mux_le = {32{1'bx}};
    endcase
  end

  // Read endian conversion
  always @(bigendian or reg_arsize or read_mux_le)
  begin
    if ((bigendian)&(reg_arsize==2'b10))            // 4个字节
      begin
      read_mux = {read_mux_le[ 7: 0],read_mux_le[15: 8],
                  read_mux_le[23:16],read_mux_le[31:24]};
      end
    else if ((bigendian)&(reg_arsize==2'b01))       // 2个字节
      begin
      read_mux = {read_mux_le[23:16],read_mux_le[31:24],
                  read_mux_le[ 7: 0],read_mux_le[15: 8]};
      end
    else
      begin
      read_mux = read_mux_le;
      end
  end

endmodule

