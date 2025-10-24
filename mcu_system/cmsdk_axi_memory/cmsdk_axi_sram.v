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
//  File Revision       : $Revision: $
//  File Date           : $Date: $
//
//  Release Information : Cortex-M0 DesignStart-r1p0-00rel0
//------------------------------------------------------------------------------
// Verilog-2001 (IEEE Std 1364-2001)
//------------------------------------------------------------------------------
//
//-----------------------------------------------------------------------------
// Abstract : Simple AXI SRAM model wrapper
//-----------------------------------------------------------------------------
`include "cmsdk_axi_memory_defs.v"

module cmsdk_axi_sram #(
  parameter filename = "",
  parameter AW       = 16,                          // Address width
  parameter WS_N     = 0,                           // First access wait state
  parameter WS_S     = 0                            // Subsequent access wait state
 )
 (
  input wire                          ACLK,         // Clock
  input wire                          ARESETn,      // Reset

  //----------------- AXI - Write -----------------
  input wire		                  AW_SEL,       // 写片选
  input wire                          AW_VALID,     // 写请求有效
  output wire                         AW_READY,     // 写请求就绪
  input wire   [2:0]                  AW_SIZE,      // 写数据宽度
  input wire   [1:0]                  AW_BURST,     // 写burst类型
  input wire   [7:0]                  AW_LEN,       // 写burst长度
  input wire   [AW-1:0]               AW_ADDR,      // 写地址

  input wire                          W_VALID,      // 写数据有效
  output wire                         W_READY,      // 写数据就绪
  input wire                          W_LAST,       // 写数据最后一拍
  input wire   [31:0]                 W_DATA,       // 写数据

  output wire                         B_VALID,      // 写响应有效
  input wire                          B_READY,      // 写响应就绪
  output wire  [1:0]                  B_RESP,       // 写响应

  //----------------- AXI - Read ------------------
  input wire                          AR_SEL,       // 读片选
  input wire                          AR_VALID,     // 读请求有效
  output wire                         AR_READY,     // 读请求就绪
  input wire   [2:0]                  AR_SIZE,      // 读数据宽度
  input wire   [1:0]                  AR_BURST,     // 读突发类型
  input wire   [7:0]                  AR_LEN,       // 读突发长度
  input wire   [AW-1:0]               AR_ADDR,      // 读地址

  output wire                         R_VALID,      // 读数据有效
  input wire                          R_READY,      // 读数据就绪
  output wire                         R_LAST,       // 读数据最后一拍
  output wire  [31:0]                 R_DATA,       // 读数据
  output wire  [1:0]                  R_RESP        // 读响应
  );


  // Behavioral SRAM model
  cmsdk_axi_ram_beh
  #(.filename(filename),
    .AW(AW),
    .WS_N(WS_N),
    .WS_S(WS_S)
    )
  u_axi_ram_beh (
    .ACLK        (ACLK),
    .ARESETn     (ARESETn),
    //----------------- AXI - Write -----------------
    .AW_SEL      (AW_SEL),
    .AW_VALID    (AW_VALID),
    .AW_READY    (AW_READY),
    .AW_SIZE     (AW_SIZE),
    .AW_LEN      (AW_LEN),
    .AW_BURST    (AW_BURST),
    .AW_ADDR     (AW_ADDR),
    .W_VALID     (W_VALID),
    .W_READY     (W_READY),
    .W_LAST      (W_LAST),
    .W_DATA      (W_DATA),
    .B_VALID     (B_VALID),
    .B_READY     (B_READY),
    .B_RESP      (B_RESP),
    //----------------- AXI - Read ------------------
    .AR_SEL      (AR_SEL),
    .AR_VALID    (AR_VALID),
    .AR_READY    (AR_READY),
    .AR_SIZE     (AR_SIZE),
    .AR_LEN      (AR_LEN),
    .AR_BURST    (AR_BURST),
    .AR_ADDR     (AR_ADDR),
    .R_VALID     (R_VALID),
    .R_READY     (R_READY),
    .R_LAST      (R_LAST),
    .R_DATA      (R_DATA),
    .R_RESP      (R_RESP)
  );


endmodule

