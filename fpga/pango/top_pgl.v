// top_pgl.v : Logos-2板级顶层——PLL产生系统时钟，pad隔离，复位同步
// 板载晶振频率以实际开发板原理图为准（示例按50MHz写）。
// 注意：本文件为板级模板，未上板验证（用户裁定：仿真正确即完成任务）。
//       引脚位置与PLL IP名以实物板卡和PDS模板为准，见fpga/pango/README.md。
`timescale 1ns/1ps
module top_pgl(
    input  wire        clk_in,          // 板载晶振
    input  wire        rst_n_in,        // 板载复位按键（低有效）
    input  wire        uart0_rxd_in,    // USB转串口TX→FPGA
    output wire        uart0_txd_out,   // FPGA→USB转串口RX
    output wire        uart2_txd_out,   // stdout（retarget默认UART2，引到第二串口或PMOD）
    output wire [15:0] led_out
);
  wire clk_sys, clk_locked, rst_n_sync;

  // PLL：50MHz→100MHz（先50MHz直连保功能，提频见README步骤5；
  //        IP名/端口按PDS的PLL IP模板修改）
  GTP_CLKPLL #(.FREQ_IN(50.0), .FREQ_OUT(100.0)) u_pll (
    .clkin(clk_in), .clkout(clk_sys), .lock(clk_locked));   // IP名以PDS模板为准

  // 复位同步（两级）
  reg r1, r2;
  always @(posedge clk_sys) begin r1 <= rst_n_in & clk_locked; r2 <= r1; end
  assign rst_n_sync = r2;

  soc_top #(.FILENAME("sw/firmware/fir_demo/fir_demo.hex"), .MEM_IMPL(1))
  u_soc (
    .ACLK(clk_sys), .ARESETn(rst_n_sync), .PCLK(clk_sys), .PRESETn(rst_n_sync),
    .uart0_rxd(uart0_rxd_in), .uart0_txd(uart0_txd_out), .uart0_txen(),
    .uart2_txd(uart2_txd_out), .uart2_txen(),
    .gpio0_out(led_out), .DFTSE(1'b0));

endmodule
