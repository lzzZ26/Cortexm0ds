// top_pgl.v : PGL50H板级顶层——板载50MHz直连，pad隔离，复位同步
// 计分项不使用厂商提供的原语或IP核（官方答疑#5）：系统时钟直接取板载
// 50MHz晶振（设计要求≥25MHz、目标50MHz），**不例化PLL IP**。
// 板载晶振频率以实际开发板原理图为准（PGL50H盘古50K=50MHz）。
// 注意：本文件为板级模板，未上板验证（用户裁定：仿真正确即完成任务）。
//       引脚位置以实物板卡原理图和PDS约束文件为准，见fpga/pango/README.md。
`timescale 1ns/1ps
module top_pgl(
    input  wire        clk_in,          // 板载50MHz晶振
    input  wire        rst_n_in,        // 板载复位按键（低有效）
    input  wire        uart0_rxd_in,    // USB转串口TX→FPGA
    output wire        uart0_txd_out,   // FPGA→USB转串口RX
    output wire        uart2_txd_out,   // stdout（retarget默认UART2，引到第二串口或PMOD）
    output wire [15:0] led_out
);
  wire rst_n_sync;

  // 板载晶振直连（无厂商IP/原语，答疑#5）
  wire clk_sys = clk_in;

  // 复位同步（两级）
  reg r1, r2;
  always @(posedge clk_sys) begin r1 <= rst_n_in; r2 <= r1; end
  assign rst_n_sync = r2;

  soc_top #(.FILENAME("sw/firmware/fir_demo/fir_demo.hex"), .MEM_IMPL(1))
  u_soc (
    .ACLK(clk_sys), .ARESETn(rst_n_sync), .PCLK(clk_sys), .PRESETn(rst_n_sync),
    .uart0_rxd(uart0_rxd_in), .uart0_txd(uart0_txd_out), .uart0_txen(),
    .uart2_txd(uart2_txd_out), .uart2_txen(),
    .gpio0_out(led_out), .DFTSE(1'b0));

endmodule
