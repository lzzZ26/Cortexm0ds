// tb_soc_smoke.v : SoC冒烟——CPU从flash启动hello固件，UART2打印Hello world
// 验证链：CPU取指(flash)→AHB2AXI4桥→仲裁器→官方slave mux→APB桥→UART2→捕获
// 注意：官方hello.hex用HSTM高速测试模式（CTRL=0x41，位宽=1个ACLK拍=20ns），
//       UART捕获必须按ACLK拍采样（与官方cmsdk_uart_capture同机制），
//       不能按9600/3.125M波特采样（uart_bfm是波特采样，此TB不适用）。
`timescale 1ns/1ps
module tb_soc_smoke;
  parameter MEM_IMPL = 0;   // 0=cmsdk_axi_flash(仿真) 1=axi_rom(FPGA路径，-P覆盖测试)
  wire ACLK, ARESETn;
  wire PCLK, PRESETn;
  wire uart0_rxd, uart0_txd, uart0_txen, uart2_txd, uart2_txen;
  wire [15:0] gpio0_out;

  tb_clkreset #() u_ck (.clk(ACLK), .rstn(ARESETn));   // 20ns周期=50MHz（与固件一致）

  assign PCLK = ACLK;                                  // PCLK=HCLK（官方clkctrl同）
  assign PRESETn = ARESETn;

  soc_top #(.FILENAME("software/testcodes/hello/hello.hex"), .MEM_IMPL(MEM_IMPL))
  u_soc (
    .ACLK(ACLK), .ARESETn(ARESETn), .PCLK(PCLK), .PRESETn(PRESETn),
    .uart0_rxd(uart0_rxd), .uart0_txd(uart0_txd), .uart0_txen(uart0_txen),
    .uart2_txd(uart2_txd), .uart2_txen(uart2_txen),
    .gpio0_out(gpio0_out), .DFTSE(1'b0));

  assign uart0_rxd = 1'b1;            // 无外部输入

  // UART2拍采样捕获（与官方cmsdk_uart_capture同机制：9位移位寄存器，
  // start位到达bit0时取[8:1]为字节；HSTM位宽=1拍，必须每拍采样）
  reg [8:0] cap_shift;
  reg [7:0] cap_q [0:255];
  reg [7:0] cap_wptr;
  always @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      cap_shift <= 9'h1FF; cap_wptr <= 8'h00;
    end else begin
      if (cap_shift[0] == 1'b0) begin                 // start位到达bit0：字节就绪
        cap_q[cap_wptr] <= cap_shift[8:1];
        cap_wptr <= cap_wptr + 8'h01;
        cap_shift <= 9'h1FF;
      end else begin
        cap_shift <= {uart2_txd, cap_shift[8:1]};
      end
    end
  end

  reg [7:0] cap_rptr;
  initial cap_rptr = 8'h00;

  // 收集一行文本
  reg [7:0] rx_byte;
  reg [8*64-1:0] line;
  integer li;
  task get_line;
    begin
      li = 0; line = 0; rx_byte = 8'h00;
      while (rx_byte != 8'h0A) begin
        wait (cap_rptr != cap_wptr);                 // 等字节入队
        rx_byte = cap_q[cap_rptr];
        cap_rptr = cap_rptr + 8'h01;
        if (rx_byte != 8'h0A) begin                  // 换行结束（2001无return）
          line = (line << 8) | rx_byte;
          li = li + 1;
        end
      end
    end
  endtask

  initial begin
    #100000;                                            // 等复位与启动
    get_line;                                           // 第一行应为 "Hello world"
    // 11字节左移累计后前6字节在[87:40]（计划原文line[39:0]是末5字节"world"）
    if (li < 11 || line[87:40] != "Hello ") begin
      $display("首行=%0s", line);
      $fatal(1, "FAIL: 未捕获Hello world");
    end
    $display("PASS: SoC冒烟——CPU启动、UART2输出Hello world");
    $finish;
  end

  // 超时兜底（本项目仲裁器每事务多1-2拍，全流程约460us；2ms余量充足）
  initial begin
    #2000000;
    $fatal(1, "FAIL: 冒烟超时（2ms）");
  end
endmodule
