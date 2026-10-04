// ic_axi_slave_mux.v : 本项目AXI从机复用器（替代官方cmsdk_axi_slave_mux）
// 端口与官方mux基本一致：AW/AR/W通道与SIZE/LEN/ADDR广播给全部从机，
// 从机按SEL消费；mux只路由握手/响应（SEL组合门控READY，寄存器版路由B/R）。
//
// 为什么新写而不复用官方mux：
//   官方cmsdk_axi_slave_mux的B/R路由选择寄存器（arsel_mux_reg/awsel_mux_reg）
//   锁存条件是VALID电平而非握手。官方单主系统读事务串行，此简化安全；
//   本项目多主仲裁下，CPU的连续取指ARVALID会在DMA读的R响应期间刷新
//   arsel_mux_reg（锁存成其它从机的译码），R通道路由被抢走——DMA通道收到
//   错误从机的R/R_LAST信号→err置位→传输夭折（实测：arsel_mux_reg被刷成
//   flash译码，ch0看到R_LAST=0误判协议错误，FIFO残留10字静默终止）。
//
//   更进一步：即使只在握手沿锁存也不够——两个主机的AR可以交替握手
//   （仲裁器按事务串行化R通道，AR可超前），路由若跟随"最后握手的AR"，
//   则前一笔事务的R响应到达时路由已被后一笔AR覆盖（实测：CPU读SRAM的
//   R响应在ch1读FIR的AR握手后到达，路由=FIR，SRAM的R拍被屏蔽丢失→死锁）。
//
//   本实现：读/写各一个小事务队列（深度4，多主单事务在途+有限超前下足够）——
//   AR/AW握手沿将译码入队，R_LAST/B握手沿出队并推进路由。R/B路由严格跟随
//   "当前响应所属的事务"。
`timescale 1ns/1ps
module ic_axi_slave_mux #(
    parameter PORT0_ENABLE = 1, PORT1_ENABLE = 1, PORT2_ENABLE = 1,
    parameter PORT3_ENABLE = 1, PORT4_ENABLE = 1, PORT5_ENABLE = 1,
    parameter PORT6_ENABLE = 1, PORT7_ENABLE = 0, PORT8_ENABLE = 0,
    parameter PORT9_ENABLE = 0,
    parameter DW = 32
)(
    input  wire        ACLK, ARESETn,
    // 从机口0-9（AW_SEL/AR_SEL为译码器输出，其余与官方mux同名）
    input  wire        AW_SEL0,  input wire AW_READY0, input wire W_READY0,
    input  wire        B_VALID0, input wire [1:0] B_RESP0,
    input  wire        AR_SEL0,  input wire AR_READY0, input wire R_VALID0,
    input  wire        R_LAST0,  input wire [DW-1:0] R_DATA0, input wire [1:0] R_RESP0,
    input  wire        AW_SEL1,  input wire AW_READY1, input wire W_READY1,
    input  wire        B_VALID1, input wire [1:0] B_RESP1,
    input  wire        AR_SEL1,  input wire AR_READY1, input wire R_VALID1,
    input  wire        R_LAST1,  input wire [DW-1:0] R_DATA1, input wire [1:0] R_RESP1,
    input  wire        AW_SEL2,  input wire AW_READY2, input wire W_READY2,
    input  wire        B_VALID2, input wire [1:0] B_RESP2,
    input  wire        AR_SEL2,  input wire AR_READY2, input wire R_VALID2,
    input  wire        R_LAST2,  input wire [DW-1:0] R_DATA2, input wire [1:0] R_RESP2,
    input  wire        AW_SEL3,  input wire AW_READY3, input wire W_READY3,
    input  wire        B_VALID3, input wire [1:0] B_RESP3,
    input  wire        AR_SEL3,  input wire AR_READY3, input wire R_VALID3,
    input  wire        R_LAST3,  input wire [DW-1:0] R_DATA3, input wire [1:0] R_RESP3,
    input  wire        AW_SEL4,  input wire AW_READY4, input wire W_READY4,
    input  wire        B_VALID4, input wire [1:0] B_RESP4,
    input  wire        AR_SEL4,  input wire AR_READY4, input wire R_VALID4,
    input  wire        R_LAST4,  input wire [DW-1:0] R_DATA4, input wire [1:0] R_RESP4,
    input  wire        AW_SEL5,  input wire AW_READY5, input wire W_READY5,
    input  wire        B_VALID5, input wire [1:0] B_RESP5,
    input  wire        AR_SEL5,  input wire AR_READY5, input wire R_VALID5,
    input  wire        R_LAST5,  input wire [DW-1:0] R_DATA5, input wire [1:0] R_RESP5,
    input  wire        AW_SEL6,  input wire AW_READY6, input wire W_READY6,
    input  wire        B_VALID6, input wire [1:0] B_RESP6,
    input  wire        AR_SEL6,  input wire AR_READY6, input wire R_VALID6,
    input  wire        R_LAST6,  input wire [DW-1:0] R_DATA6, input wire [1:0] R_RESP6,
    input  wire        AW_SEL7,  input wire AW_READY7, input wire W_READY7,
    input  wire        B_VALID7, input wire [1:0] B_RESP7,
    input  wire        AR_SEL7,  input wire AR_READY7, input wire R_VALID7,
    input  wire        R_LAST7,  input wire [DW-1:0] R_DATA7, input wire [1:0] R_RESP7,
    input  wire        AW_SEL8,  input wire AW_READY8, input wire W_READY8,
    input  wire        B_VALID8, input wire [1:0] B_RESP8,
    input  wire        AR_SEL8,  input wire AR_READY8, input wire R_VALID8,
    input  wire        R_LAST8,  input wire [DW-1:0] R_DATA8, input wire [1:0] R_RESP8,
    input  wire        AW_SEL9,  input wire AW_READY9, input wire W_READY9,
    input  wire        B_VALID9, input wire [1:0] B_RESP9,
    input  wire        AR_SEL9,  input wire AR_READY9, input wire R_VALID9,
    input  wire        R_LAST9,  input wire [DW-1:0] R_DATA9, input wire [1:0] R_RESP9,
    // 共享主侧（比官方mux多B_READY/R_READY输入：响应路由队列出队需要）
    input  wire        AW_VALID, output wire AW_READY,
    output wire        W_READY,
    output wire        B_VALID,  input wire B_READY, output wire [1:0] B_RESP,
    input  wire        AR_VALID, output wire AR_READY,
    output wire        R_VALID,  output wire R_LAST,
    output wire [DW-1:0] R_DATA, output wire [1:0] R_RESP,
    input  wire        R_READY
);
  wire [9:0] awsel_mux;      // 写选择（组合，供AW/W握手）
  reg  [9:0] awsel_mux_reg;  // 写响应路由（跟随写事务队列）
  wire [9:0] arsel_mux;      // 读选择（组合，供AR握手）
  reg  [9:0] arsel_mux_reg;  // 读数据路由（跟随读事务队列）

  assign awsel_mux[0] = (PORT0_ENABLE!=0) & AW_SEL0;
  assign awsel_mux[1] = (PORT1_ENABLE!=0) & AW_SEL1;
  assign awsel_mux[2] = (PORT2_ENABLE!=0) & AW_SEL2;
  assign awsel_mux[3] = (PORT3_ENABLE!=0) & AW_SEL3;
  assign awsel_mux[4] = (PORT4_ENABLE!=0) & AW_SEL4;
  assign awsel_mux[5] = (PORT5_ENABLE!=0) & AW_SEL5;
  assign awsel_mux[6] = (PORT6_ENABLE!=0) & AW_SEL6;
  assign awsel_mux[7] = (PORT7_ENABLE!=0) & AW_SEL7;
  assign awsel_mux[8] = (PORT8_ENABLE!=0) & AW_SEL8;
  assign awsel_mux[9] = (PORT9_ENABLE!=0) & AW_SEL9;

  assign arsel_mux[0] = (PORT0_ENABLE!=0) & AR_SEL0;
  assign arsel_mux[1] = (PORT1_ENABLE!=0) & AR_SEL1;
  assign arsel_mux[2] = (PORT2_ENABLE!=0) & AR_SEL2;
  assign arsel_mux[3] = (PORT3_ENABLE!=0) & AR_SEL3;
  assign arsel_mux[4] = (PORT4_ENABLE!=0) & AR_SEL4;
  assign arsel_mux[5] = (PORT5_ENABLE!=0) & AR_SEL5;
  assign arsel_mux[6] = (PORT6_ENABLE!=0) & AR_SEL6;
  assign arsel_mux[7] = (PORT7_ENABLE!=0) & AR_SEL7;
  assign arsel_mux[8] = (PORT8_ENABLE!=0) & AR_SEL8;
  assign arsel_mux[9] = (PORT9_ENABLE!=0) & AR_SEL9;

  // ---- 事务队列：AR/AW握手入队，R_LAST/B握手出队，路由跟随队头 ----
  // 深度4：仲裁器单事务在途+有限AR超前（CPU与DMA各1-2笔），足够。
  // 指针必须3位：2位在深度4下rp=2、wp=0（回绕）时rp+1==wp会误判队列空
  // （实测：CPU读的R响应被路由屏蔽死锁），3位无此混淆（最多4项<<8容量）。
  reg [9:0] wq [0:3];
  reg [2:0] wq_wp, wq_rp;
  reg [9:0] rq [0:3];
  reg [2:0] rq_wp, rq_rp;
  always @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      awsel_mux_reg <= {10{1'b0}}; wq_wp <= 3'd0; wq_rp <= 3'd0;
      arsel_mux_reg <= {10{1'b0}}; rq_wp <= 3'd0; rq_rp <= 3'd0;
    end else begin
      if (AW_VALID && AW_READY) begin
        if (wq_wp == wq_rp) awsel_mux_reg <= awsel_mux;   // 队列空：路由立即就位
        wq[wq_wp[1:0]] <= awsel_mux;
        wq_wp <= wq_wp + 3'd1;
      end
      if (B_VALID && B_READY && (wq_wp != wq_rp)) begin
        if (wq_rp + 3'd1 != wq_wp) awsel_mux_reg <= wq[wq_rp[1:0] + 2'd1];  // 出队：路由=下一笔
        wq_rp <= wq_rp + 3'd1;
      end
      if (AR_VALID && AR_READY) begin
        if (rq_wp == rq_rp) arsel_mux_reg <= arsel_mux;   // 队列空：路由立即就位
        rq[rq_wp[1:0]] <= arsel_mux;
        rq_wp <= rq_wp + 3'd1;
      end
      if (R_VALID && R_READY && R_LAST && (rq_wp != rq_rp)) begin
        // 队列非空才出队：flash恒流R_VALID在空闲rready=1时的幻影拍会
        // 掏空队列（路由错乱致启动卡死），必须保护
        if (rq_rp + 3'd1 != rq_wp) arsel_mux_reg <= rq[rq_rp[1:0] + 2'd1]; // 出队：路由=下一笔
        rq_rp <= rq_rp + 3'd1;
      end
    end
  end

  assign AW_READY =
         (awsel_mux[0] & AW_READY0) | (awsel_mux[1] & AW_READY1) |
         (awsel_mux[2] & AW_READY2) | (awsel_mux[3] & AW_READY3) |
         (awsel_mux[4] & AW_READY4) | (awsel_mux[5] & AW_READY5) |
         (awsel_mux[6] & AW_READY6) | (awsel_mux[7] & AW_READY7) |
         (awsel_mux[8] & AW_READY8) | (awsel_mux[9] & AW_READY9);

  // W_READY组合自当前AWADDR译码（与官方一致）：W拍时主设备保持AWADDR，
  // 且仲裁器单事务在途保证AWADDR属于当前事务。
  assign W_READY =
         (awsel_mux[0] & W_READY0) | (awsel_mux[1] & W_READY1) |
         (awsel_mux[2] & W_READY2) | (awsel_mux[3] & W_READY3) |
         (awsel_mux[4] & W_READY4) | (awsel_mux[5] & W_READY5) |
         (awsel_mux[6] & W_READY6) | (awsel_mux[7] & W_READY7) |
         (awsel_mux[8] & W_READY8) | (awsel_mux[9] & W_READY9);

  assign B_VALID =
         (awsel_mux_reg[0] & B_VALID0) | (awsel_mux_reg[1] & B_VALID1) |
         (awsel_mux_reg[2] & B_VALID2) | (awsel_mux_reg[3] & B_VALID3) |
         (awsel_mux_reg[4] & B_VALID4) | (awsel_mux_reg[5] & B_VALID5) |
         (awsel_mux_reg[6] & B_VALID6) | (awsel_mux_reg[7] & B_VALID7) |
         (awsel_mux_reg[8] & B_VALID8) | (awsel_mux_reg[9] & B_VALID9);

  assign B_RESP =
         ({2{awsel_mux_reg[0]}} & B_RESP0) | ({2{awsel_mux_reg[1]}} & B_RESP1) |
         ({2{awsel_mux_reg[2]}} & B_RESP2) | ({2{awsel_mux_reg[3]}} & B_RESP3) |
         ({2{awsel_mux_reg[4]}} & B_RESP4) | ({2{awsel_mux_reg[5]}} & B_RESP5) |
         ({2{awsel_mux_reg[6]}} & B_RESP6) | ({2{awsel_mux_reg[7]}} & B_RESP7) |
         ({2{awsel_mux_reg[8]}} & B_RESP8) | ({2{awsel_mux_reg[9]}} & B_RESP9);

  assign AR_READY =
         (arsel_mux[0] & AR_READY0) | (arsel_mux[1] & AR_READY1) |
         (arsel_mux[2] & AR_READY2) | (arsel_mux[3] & AR_READY3) |
         (arsel_mux[4] & AR_READY4) | (arsel_mux[5] & AR_READY5) |
         (arsel_mux[6] & AR_READY6) | (arsel_mux[7] & AR_READY7) |
         (arsel_mux[8] & AR_READY8) | (arsel_mux[9] & AR_READY9);

  assign R_VALID =
         (arsel_mux_reg[0] & R_VALID0) | (arsel_mux_reg[1] & R_VALID1) |
         (arsel_mux_reg[2] & R_VALID2) | (arsel_mux_reg[3] & R_VALID3) |
         (arsel_mux_reg[4] & R_VALID4) | (arsel_mux_reg[5] & R_VALID5) |
         (arsel_mux_reg[6] & R_VALID6) | (arsel_mux_reg[7] & R_VALID7) |
         (arsel_mux_reg[8] & R_VALID8) | (arsel_mux_reg[9] & R_VALID9);

  assign R_LAST =
         (arsel_mux_reg[0] & R_LAST0) | (arsel_mux_reg[1] & R_LAST1) |
         (arsel_mux_reg[2] & R_LAST2) | (arsel_mux_reg[3] & R_LAST3) |
         (arsel_mux_reg[4] & R_LAST4) | (arsel_mux_reg[5] & R_LAST5) |
         (arsel_mux_reg[6] & R_LAST6) | (arsel_mux_reg[7] & R_LAST7) |
         (arsel_mux_reg[8] & R_LAST8) | (arsel_mux_reg[9] & R_LAST9);

  assign R_DATA =
         ({DW{arsel_mux_reg[0]}} & R_DATA0) | ({DW{arsel_mux_reg[1]}} & R_DATA1) |
         ({DW{arsel_mux_reg[2]}} & R_DATA2) | ({DW{arsel_mux_reg[3]}} & R_DATA3) |
         ({DW{arsel_mux_reg[4]}} & R_DATA4) | ({DW{arsel_mux_reg[5]}} & R_DATA5) |
         ({DW{arsel_mux_reg[6]}} & R_DATA6) | ({DW{arsel_mux_reg[7]}} & R_DATA7) |
         ({DW{arsel_mux_reg[8]}} & R_DATA8) | ({DW{arsel_mux_reg[9]}} & R_DATA9);

  assign R_RESP =
         ({2{arsel_mux_reg[0]}} & R_RESP0) | ({2{arsel_mux_reg[1]}} & R_RESP1) |
         ({2{arsel_mux_reg[2]}} & R_RESP2) | ({2{arsel_mux_reg[3]}} & R_RESP3) |
         ({2{arsel_mux_reg[4]}} & R_RESP4) | ({2{arsel_mux_reg[5]}} & R_RESP5) |
         ({2{arsel_mux_reg[6]}} & R_RESP6) | ({2{arsel_mux_reg[7]}} & R_RESP7) |
         ({2{arsel_mux_reg[8]}} & R_RESP8) | ({2{arsel_mux_reg[9]}} & R_RESP9);
endmodule
