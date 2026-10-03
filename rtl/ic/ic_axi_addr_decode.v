// ic_axi_addr_decode.v : 本项目AXI地址译码（官方地图 + FIR + DMA）
//  0x0000_0000-0x0000_FFFF  Flash/ROM（固件，只读）
//  0x2000_0000-0x2000_FFFF  SRAM（64K）
//  0x4000_0000-0x4000_FFFF  APB子系统（UART0-2/Timer/WDT，经官方axi2apb桥）
//  0x4001_0000-0x4001_0FFF  GPIO0
//  0x4001_1000-0x4001_1FFF  GPIO1
//  0x4002_0000-0x4002_0FFF  FIR（新增）
//  0x4003_0000-0x4003_0FFF  DMA配置（新增）
//  其余                      默认从机（DECERR）
`timescale 1ns/1ps
module ic_axi_addr_decode(
    input  wire [31:0] w_addr,
    input  wire [31:0] r_addr,
    output wire        flash_arsel,           // Flash只读，无写选通
    output wire        sram_awsel,  sram_arsel,
    output wire        apbsys_awsel, apbsys_arsel,
    output wire        gpio0_awsel, gpio0_arsel,
    output wire        gpio1_awsel, gpio1_arsel,
    output wire        fir_awsel,   fir_arsel,
    output wire        dma_awsel,   dma_arsel,
    output wire        defslv_awsel, defslv_arsel
);
  assign flash_arsel  = (r_addr[31:16] == 16'h0000);

  assign sram_awsel   = (w_addr[31:16] == 16'h2000);
  assign sram_arsel   = (r_addr[31:16] == 16'h2000);

  assign apbsys_awsel = (w_addr[31:16] == 16'h4000);
  assign apbsys_arsel = (r_addr[31:16] == 16'h4000);

  assign gpio0_awsel  = (w_addr[31:12] == 20'h40010);
  assign gpio0_arsel  = (r_addr[31:12] == 20'h40010);
  assign gpio1_awsel  = (w_addr[31:12] == 20'h40011);
  assign gpio1_arsel  = (r_addr[31:12] == 20'h40011);

  assign fir_awsel    = (w_addr[31:12] == 20'h40020);
  assign fir_arsel    = (r_addr[31:12] == 20'h40020);
  assign dma_awsel    = (w_addr[31:12] == 20'h40030);
  assign dma_arsel    = (r_addr[31:12] == 20'h40030);

  assign defslv_awsel = ~(sram_awsel | apbsys_awsel | gpio0_awsel |
                          gpio1_awsel | fir_awsel | dma_awsel);
  assign defslv_arsel = ~(flash_arsel | sram_arsel | apbsys_arsel |
                          gpio0_arsel | gpio1_arsel | fir_arsel | dma_arsel);
endmodule
