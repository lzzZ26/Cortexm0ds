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
// Abstract : Memory model definitions
//-----------------------------------------------------------------------------

//------------------------------------------------------------------------------
// Memory types
//------------------------------------------------------------------------------
// Constants for ROM types - Match to cmsdk_ahb_rom.v
  //  0) AXI_ROM_NONE             - memory not present
  //  1) AXI_ROM_BEH_MODEL        - behavioral ROM memory
  //  2) AXI_ROM_FPGA_SRAM_MODEL  - behavioral FPGA SRAM model with SRAM wrapper
  //  3) AXI_ROM_FLASH32_MODEL    - behavioral 32-bit flash memory
  //  4) AXI_ROM_FLASH16_MODEL    - behavioral 16-bit flash memory

`define AXI_ROM_NONE             0
`define AXI_ROM_BEH_MODEL        1
`define AXI_ROM_FPGA_SRAM_MODEL  2
`define AXI_ROM_FLASH32_MODEL    3
`define AXI_ROM_FLASH16_MODEL    4


// Constants for RAM types - Match to cmsdk_ahb_ram.v
  //  0) AXI_RAM_NONE             - memory not present
  //  1) AXI_RAM_BEH_MODEL        - behavioral RAM memory
  //  2) AXI_RAM_FPGA_SRAM_MODEL  - behavioral SRAM model with SRAM wrapper
  //  3) AXI_RAM_EXT_SRAM16_MODEL - for benchmarking using 16-bit external asynchronous SRAM
  //  4) AXI_RAM_EXT_SRAM8_MODEL - for benchmarking using 8-bit external asynchronous SRAM

`define AXI_RAM_NONE             0
`define AXI_RAM_BEH_MODEL        1
`define AXI_RAM_FPGA_SRAM_MODEL  2
`define AXI_RAM_EXT_SRAM16_MODEL 3
`define AXI_RAM_EXT_SRAM8_MODEL  4

// Memory wait state parameters - used by behaviorial model if applicable*/
   // Boot ROM non-sequential and sequential waitstate
`define ARM_CMSDK_BOOT_MEM_WS_N   0
`define ARM_CMSDK_BOOT_MEM_WS_S   0

// ROM non-sequential and sequential waitstate
`define ARM_CMSDK_ROM_MEM_WS_N    0
`define ARM_CMSDK_ROM_MEM_WS_S    0

// RAM non-sequential and sequential waitstate
`define ARM_CMSDK_RAM_MEM_WS_N    0
`define ARM_CMSDK_RAM_MEM_WS_S    0
