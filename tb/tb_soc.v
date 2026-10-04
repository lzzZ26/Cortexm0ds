// tb_soc.v : 系统级验证——加载fir_demo.hex：UART0回显核对+UART2输出标记断言
// UART2 stdout：固件retarget用HSTM模式（位宽=1拍），必须拍采样捕获（同tb_soc_smoke）。
// UART0回显：固件用3.125M正常模式（BAUDDIV=16），BFM按3.125M波特收发，握手式逐字符。
// 判定：回显64字符全对+固件标记（ECHO PASS/DMA PASS/FIR DONE，无FAIL）+
//       FIR输出黄金比对（TB读SRAM的out_buf与tb/data/golden_q31.hex逐样本比，
//       相对误差<0.1%——out_buf字索引0x011A随固件链接地址，固件打印"out="行备查）。
`timescale 1ns/1ps
module tb_soc;
  wire ACLK, ARESETn;
  wire PCLK, PRESETn;
  wire uart0_rxd, uart0_txd, uart0_txen, uart2_txd, uart2_txen;
  wire [15:0] gpio0_out;

  tb_clkreset #() u_ck (.clk(ACLK), .rstn(ARESETn));

  assign PCLK = ACLK;
  assign PRESETn = ARESETn;

  soc_top #(.FILENAME("sw/firmware/fir_demo/fir_demo.hex"), .MEM_IMPL(0))
  u_soc (
    .ACLK(ACLK), .ARESETn(ARESETn), .PCLK(PCLK), .PRESETn(PRESETn),
    .uart0_rxd(uart0_rxd), .uart0_txd(uart0_txd), .uart0_txen(uart0_txen),
    .uart2_txd(uart2_txd), .uart2_txen(uart2_txen),
    .gpio0_out(gpio0_out), .DFTSE(1'b0));

  // ================= UART0回显：BFM发64字符并逐一核对（握手式） =================
  uart_bfm #(.CLK_PERIOD_NS(20.0), .BAUD(3125000)) u0_bfm (.txd(uart0_rxd), .rxd(uart0_txd));

  reg [7:0] echo_byte;
  integer echo_i;
  initial begin
    wait (saw_banner == 1'b1);                  // 等固件横幅（UART0已初始化）再发字符
    #1000;                                      // 留固件进回显循环的余量
    for (echo_i = 0; echo_i < 64; echo_i = echo_i + 1) begin
      u0_bfm.uart_tx(8'h30 + (echo_i % 10));    // '0'..'9'循环
      u0_bfm.uart_rx(echo_byte);
      if (echo_byte !== 8'h30 + (echo_i % 10))
        $fatal(1, "FAIL: 回显第%0d字符=%h", echo_i, echo_byte);
    end
    $display("回显64字符全部正确");
  end

  // ================= UART2 stdout：拍采样捕获+行收集+标记判定 =================
  reg [8:0] cap_shift;
  reg [7:0] cap_q [0:511];
  reg [8:0] cap_wptr;
  always @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      cap_shift <= 9'h1FF; cap_wptr <= 9'h000;
    end else begin
      if (cap_shift[0] == 1'b0) begin             // start位到达bit0：字节就绪
        cap_q[cap_wptr] <= cap_shift[8:1];
        cap_wptr <= cap_wptr + 9'h001;
        cap_shift <= 9'h1FF;
      end else begin
        cap_shift <= {uart2_txd, cap_shift[8:1]};
      end
    end
  end

  reg [8:0] cap_rptr;
  initial cap_rptr = 9'h000;

  // 黄金模型（任务5生成：双精度参考量化到Q1.31）
  reg [31:0] gmem [0:1023];
  initial $readmemh("tb/data/golden_q31.hex", gmem);

  reg [8*63:0] cur_line;
  integer cli;
  reg saw_banner, saw_echo, saw_dma, saw_fir, saw_fail;
  reg done;
  reg [7:0] rx_byte;
  initial begin
    saw_banner = 0; saw_echo = 0; saw_dma = 0; saw_fir = 0; saw_fail = 0; done = 0;
    while (!done) begin
      cur_line = 0; cli = 0; rx_byte = 8'h00;
      while (rx_byte != 8'h0A) begin
        wait (cap_rptr != cap_wptr);             // 等字节入队
        rx_byte = cap_q[cap_rptr];
        cap_rptr = cap_rptr + 9'h001;
        if (rx_byte != 8'h0A) begin
          cur_line = (cur_line << 8) | rx_byte;
          cli = cli + 1;
        end
      end
      $display("LINE: %0s", cur_line);
      // 判定标记（行内子串匹配）
      if (line_has("Demo"))      saw_banner = 1;   // 横幅=固件已初始化UART0
      if (line_has("ECHO PASS")) saw_echo = 1;
      if (line_has("DMA PASS"))  saw_dma  = 1;
      if (line_has("FIR DONE"))  saw_fir  = 1;
      if (line_has("FAIL"))      saw_fail = 1;
      if (saw_fir || saw_fail) done = 1;
    end
  end

  // 行内子串匹配（cur_line/cli为全局，函数读取）
  function line_has;
    input [8*63:0] key;
    integer i, j, key_len; reg hit;
    begin
      key_len = 0;
      while (key[key_len*8 +: 8] !== 8'h00 && key_len < 63) key_len = key_len + 1;
      line_has = 0;
      for (i = 0; i <= cli - key_len; i = i + 1) begin
        hit = 1'b1;
        for (j = 0; j < key_len; j = j + 1)
          if (cur_line[(i + j)*8 +: 8] !== key[j*8 +: 8]) hit = 1'b0;
        if (hit) line_has = 1'b1;
      end
    end
  endfunction

  // ================= 指标监视（T14）：FIR从机侧握手统计 =================
  // din_push/dout_pop为fir_top内部组合信号（含w_sel/r_sel门控，比裸W/R握手
  // 更严——共享总线上其他从机的握手不会误计数）。DIN写=ch0输入搬运，
  // DOUT读=ch1输出回收。系统延迟口径=首样本DIN→首样本DOUT（计划Step1代码
  // 口径；计划总览"末DIN→首DOUT"对流水式FIR不适用，差值为负）。
  reg [63:0] t_first_din, t_last_din, t_first_dout, t_last_dout;
  reg [31:0] din_cnt, dout_cnt;
  wire mon_din  = u_soc.u_fir.din_push;
  wire mon_dout = u_soc.u_fir.dout_pop;
  always @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      t_first_din = 0; t_last_din = 0; t_first_dout = 0; t_last_dout = 0;
      din_cnt = 0; dout_cnt = 0;
    end else begin
      if (mon_din) begin
        if (din_cnt == 0) t_first_din = $time;
        t_last_din = $time;
        din_cnt = din_cnt + 1;
      end
      if (mon_dout) begin
        if (dout_cnt == 0) t_first_dout = $time;
        t_last_dout = $time;
        dout_cnt = dout_cnt + 1;
      end
    end
  end

  // ================= 最终判定 =================
  initial begin
    wait (done == 1'b1);
    if (!saw_echo) $fatal(1, "FAIL: 缺ECHO PASS标记");
    if (!saw_dma)  $fatal(1, "FAIL: 缺DMA PASS标记");
    if (!saw_fir)  $fatal(1, "FAIL: 缺FIR DONE标记");
    if (saw_fail)  $fatal(1, "FAIL: 固件报告失败");
    begin : fir_check
      integer gi;
      reg signed [31:0] hw_v, g_v, d_v;
      reg [31:0] a_d, a_g;
      integer bad_cnt;
      bad_cnt = 0;
      for (gi = 0; gi < 1024; gi = gi + 1) begin
        // out_buf在SRAM的字索引：0x20000468>>2=0x011A（固件main里static数组
        // 链接地址，改固件须同步——固件打印"out="行备查）
        hw_v = u_soc.u_sram.mem[16'h011A + gi[9:0]];
        g_v  = gmem[gi];
        d_v  = hw_v - g_v;
        a_d = (d_v < 0) ? -d_v : d_v;      // 相对误差判定：|hw-ref| > |ref|/1024
        a_g = (g_v < 0) ? -g_v : g_v;      // 即误差>0.0977%（严于0.1%）
        if (a_d > (a_g >> 10)) begin
          bad_cnt = bad_cnt + 1;
          if (bad_cnt <= 8)
            $display("FIRERR i=%0d hw=%h ref=%h diff=%h", gi, hw_v, g_v, a_d);
        end
      end
      if (bad_cnt != 0)
        $fatal(1, "FAIL: FIR误差超标样本数=%0d（阈值0.1%%）", bad_cnt);
      $display("FIR黄金比对：1024样本全部<0.1%%（严格阈值0.0977%%）");
    end
    // ================= 指标输出（T14）：监视计数器来自指标监视块 =================
    begin : metrics
      real thr, lat1, bw;
      if (din_cnt != 32'd1024) $fatal(1, "FAIL: DIN监视计数=%0d（期望1024）", din_cnt);
      if (dout_cnt != 32'd1024) $fatal(1, "FAIL: DOUT监视计数=%0d（期望1024）", dout_cnt);
      thr  = $itor(dout_cnt) / (($itor(t_last_dout - t_first_dout) / 20.0) + 1.0);
      lat1 = $itor(t_first_dout - t_first_din) / 1000.0;
      bw   = 8192000.0 / $itor(t_last_dout - t_first_din);
      if (thr <= 0.0 || thr > 1.25) $fatal(1, "FAIL: FIR吞吐量异常=%f samples/cycle", thr);
      if (lat1 <= 0.0 || lat1 > 100.0) $fatal(1, "FAIL: 系统延迟异常=%f us", lat1);
      if (bw <= 0.0 || bw > 2000.0) $fatal(1, "FAIL: DMA带宽异常=%f MB/s", bw);
      $display("===== 指标（50MHz仿真）=====");
      $display("DIN样本=%0d DOUT样本=%0d", din_cnt, dout_cnt);
      $display("FIR吞吐量 = %.4f samples/cycle", thr);
      $display("系统延迟(首DIN→首DOUT) = %.2f us", lat1);
      $display("DMA带宽(FIR阶段4KB进+4KB出) = %.2f MB/s", bw);
      $display("===== 指标结束 =====");
    end
    $display("PASS: 固件回显+DMA自检+FIR软硬协同全部通过");
    $finish;
  end

  // ================= 超时兜底（固件全流程~4ms：回显+DMA自检+FIR软硬协同） =================
  initial begin
    #20000000;
    $fatal(1, "FAIL: 系统级验证超时（20ms）");
  end
endmodule
