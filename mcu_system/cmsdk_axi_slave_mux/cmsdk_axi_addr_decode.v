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
// Abstract : This module performs the address decode of the ADDR from the
//            CPU and generates the HSELs for each of the target peripherals.
//            Also performs address decode for MTB
//-----------------------------------------------------------------------------
//
`include "cmsdk_mcu_defs.v"

module cmsdk_axi_addr_decode #(
  // GPIO0 peripheral base address
  parameter BASEADDR_GPIO0       = 32'h4001_0000,
  // GPIO1 peripheral base address
  parameter BASEADDR_GPIO1       = 32'h4001_1000,
  // UART4 peripheral base address
  //parameter BASEADDR_UART4     = 32'h4001_2000,

  // Generate BOOT_LOADER_PRESENT based on BOOT_MEM_TYPE
  // This is a derived parameter - do not override using instantiation
  parameter BOOT_LOADER_PRESENT  = 0,

  // Location of the System ROM Table.
  parameter BASEADDR_SYSROMTABLE = 32'hF000_0000
 )
 (
    // System Address
    input wire [31:0]       w_addr,                 // 写地址
    input wire [31:0]       r_addr,                 // 读地址
    input wire              remap_ctrl,             // Boot地址重映射控制

    // Memory Selection
    output wire             boot_arsel,             // Boot读地址选择
    output wire             flash_arsel,            // Flash读地址选择
    output wire             sram_awsel,             // SRAM写地址选择
    output wire             sram_arsel,             // SRAM读地址选择

    // Peripheral Selection
    output wire             apbsys_awsel,           // APB系统写地址选择
    output wire             apbsys_arsel,           // APB系统读地址选择
    output wire             gpio0_awsel,            // GPIO0写地址选择
    output wire             gpio0_arsel,            // GPIO0读地址选择
    output wire             gpio1_awsel,            // GPIO1写地址选择
    output wire             gpio1_arsel,            // GPIO1读地址选择
    //output wire           uart4_awsel,            // UART4写地址选择
    //output wire           uart4_arsel,            // UART4读地址选择
    output wire             sysctrl_awsel,          // 系统控制写地址选择
    output wire             sysctrl_arsel,          // 系统控制读地址选择
    output wire             sysrom_arsel,           // 系统ROM读地址选择

    // Default slave
    output wire             defslv_awsel,           // Default slave写地址选择
    output wire             defslv_arsel            // Default slave读地址选择
  );

  // AXI address decode
  // 0x00000000 - 0x0000FFFF : 64KB flash / boot firmware
  // 0x01000000 - 0x0100FFFF :  4kB boot firmware  : only 4kB is used
  // 0x20000000 - 0x2000FFFF : 64KB SRAM
  // 0x40000000 - 0x4000FFFF : 64KB APB subsystem
  // 0x40010000 - 0x4001FFFF : 64KB AXI peripherals (GPIOs, UART4, SYSCTRL)
  // 0xF0000000 - 0xF0000FFF :  4kB System ROM Table

  // ----------------------------------------------------------
  // Memory decode logic
  // ----------------------------------------------------------
  // If Boot loader is not present (BOOT_LOADER_PRESENT==0),
  // boot_arsel always 0.
  // Otherwise select if address = 0x0100xxxx or when remap_ctrl
  // is 1, and address = 0x0000xxxx
  assign boot_arsel    = (BOOT_LOADER_PRESENT==0) ? 1'b0 :
     (r_addr[31:16]==16'h0000) & (remap_ctrl==1'b1) |
     (r_addr[31:16]==16'h0100);

  assign flash_arsel   = (BOOT_LOADER_PRESENT==0) ?     // 0x00000000
    // Boot loader not present. Select if first 64KB is selected
    (r_addr[31:16]==16'h0000) :
    // Boot loader present. If boot loader is selected then flash is
    // not selected
    (r_addr[31:16]==16'h0000) & (boot_arsel==1'b0);

  assign sram_awsel    = (w_addr[31:16]==16'h2000) ? 1'b1 : 1'b0;     // 0x20000000
  assign sram_arsel    = (r_addr[31:16]==16'h2000) ? 1'b1 : 1'b0;     // 0x20000000

  // ----------------------------------------------------------
  // Peripheral Selection decode logic
  // ----------------------------------------------------------
  assign apbsys_awsel  = (w_addr[31:16]==16'h4000) ? 1'b1 : 1'b0;                    // 0x40000000
  assign apbsys_arsel  = (r_addr[31:16]==16'h4000) ? 1'b1 : 1'b0;                    // 0x40000000
  assign gpio0_awsel   = (w_addr[31:12]==BASEADDR_GPIO0[31:12]) ? 1'b1 : 1'b0;       // 0x40010000
  assign gpio0_arsel   = (r_addr[31:12]==BASEADDR_GPIO0[31:12]) ? 1'b1 : 1'b0;       // 0x40010000
  assign gpio1_awsel   = (w_addr[31:12]==BASEADDR_GPIO1[31:12]) ? 1'b1 : 1'b0;       // 0x40011000
  assign gpio1_arsel   = (r_addr[31:12]==BASEADDR_GPIO1[31:12]) ? 1'b1 : 1'b0;       // 0x40011000
  //assign uart4_awsel = (w_addr[31:12]==BASEADDR_UART4[31:12]) ? 1'b1 : 1'b0;       // 0x40012000
  //assign uart4_arsel = (r_addr[31:12]==BASEADDR_UART4[31:12]) ? 1'b1 : 1'b0;       // 0x40012000
  assign sysctrl_awsel = (w_addr[31:12]==20'h4001F) ? 1'b1 : 1'b0;                   // 0x4001F000
  assign sysctrl_arsel = (r_addr[31:12]==20'h4001F) ? 1'b1 : 1'b0;                   // 0x4001F000
  assign sysrom_arsel  = (r_addr[31:12]==BASEADDR_SYSROMTABLE[31:12]) ? 1'b1 : 1'b0; // 0xF0000000

  // ----------------------------------------------------------
  // Default slave decode logic
  // ----------------------------------------------------------
  assign defslv_awsel = ~(sram_awsel   |                // 缺省设备写片选
                          apbsys_awsel |
                          gpio0_awsel  |
                          gpio1_awsel  |//uart4_awsel |
                          sysctrl_awsel);
  assign defslv_arsel  = ~(boot_arsel  | flash_arsel  | // 缺省设备读片选
                          sram_arsel   |
                          apbsys_arsel |
                          gpio0_arsel  |
                          gpio1_arsel  |//uart4_arsel |
                          sysctrl_arsel| sysrom_arsel);


endmodule
