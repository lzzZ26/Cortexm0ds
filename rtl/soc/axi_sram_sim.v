// axi_sram_sim.v : 本项目SRAM行为模型（替代官方cmsdk_axi_sram，仿真用）
// 端口与官方cmsdk_axi_sram一致（CMSDK从机SEL风格），soc_top直接换插。
//
// 为什么新写而不复用官方模型：
//   官方cmsdk_axi_ram_beh的写地址锁存带读/写互斥
//   （RF_WAREQ = AW_SEL & AW_VALID & AW_READY & ~RF_RREQ，其中RF_RREQ=R_READY），
//   主设备在"读在途等数据（R_READY=1）"期间发起写AW时，AW锁存被静默丢弃——
//   写字节选通不锁存、数据不落存储，但B响应仍回OKAY（静默数据丢失）。
//   官方系统桥的时序恰好错开此窗口；本项目仲裁器的1拍授权延迟使CPU桥的
//   "读在途+写AW重叠"模式命中该窗口，导致栈帧压栈丢失→弹栈弹到0→HardFault
//   （实测：AW#567写0x2000FBEC=FFFFFFFF后读回0，探针证实WSTB=0000）。
//   本模型无读写互斥，AW/AR各自独立锁存，写读可安全并发。
//
// 实现要点（移植自tb/common/axi_slave_mem.v，T2/T9验证）：
//   - 字数组mem[0:2^(AW-2)-1]，字节地址w_a/r_a[AW-1:0]，字索引[AW-1:2]
//   - 字节/半字/字写按AWSIZE+地址[1:0]落通道（总线无WSTRB的CMSDK约定）
//   - INCR按(1<<size)递增、FIXED不递增；读返回整字（字节在自然通道，不移位，
//     与官方模型一致，AHB桥自行取字节）
//   - 复位后全0（与官方ram_data初始化为0一致）
//   - 仿真专用（initial块清零），FPGA阶段由BRAM封装替代（任务15/16）
`timescale 1ns/1ps
module axi_sram_sim #(parameter AW = 16)(
    input  wire        ACLK, ARESETn,
    // 写通道（AW_SEL/AR_SEL为CMSDK从机选通风格）
    input  wire        AW_SEL, AW_VALID, output reg AW_READY,
    input  wire [2:0]  AW_SIZE,  input wire [1:0] AW_BURST,
    input  wire [7:0]  AW_LEN,   input wire [AW-1:0] AW_ADDR,
    input  wire        W_VALID,  output reg W_READY,
    input  wire [31:0] W_DATA,   input wire W_LAST,
    output reg         B_VALID,  input wire B_READY, output reg [1:0] B_RESP,
    // 读通道
    input  wire        AR_SEL, AR_VALID, output reg AR_READY,
    input  wire [2:0]  AR_SIZE,  input wire [1:0] AR_BURST,
    input  wire [7:0]  AR_LEN,   input wire [AW-1:0] AR_ADDR,
    output reg         R_VALID,  input wire R_READY,
    output reg [31:0]  R_DATA,   output reg [1:0] R_RESP, output reg R_LAST
);
  reg [31:0] mem [0:(1<<(AW-2))-1];

  // 写侧：w_a=字节地址（低2位留通道），INCR按size步进
  reg [AW-1:0] w_a;   reg [7:0] w_cnt;  reg w_busy;
  reg [2:0]     w_size; reg [1:0] w_burst;   // AW握手时锁存
  // 读侧：r_a=字节地址
  reg [AW-1:0] r_a;   reg [7:0] r_cnt;  reg r_busy;
  reg [2:0]     r_size; reg [1:0] r_burst;   // AR握手时锁存

  integer i;
  initial begin
    for (i = 0; i < (1 << (AW-2)); i = i + 1) mem[i] = 32'h0;
  end

  // ================= 写通道（AW与读通道无互斥，独立锁存） =================
  always @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      w_busy <= 0; w_cnt <= 0; w_a <= 0; w_size <= 0; w_burst <= 0;
      AW_READY <= 1; W_READY <= 0; B_VALID <= 0; B_RESP <= 2'b00;
    end else begin
      B_VALID <= 1'b0;
      if (!w_busy) begin
        AW_READY <= 1'b1;
        if (AW_SEL && AW_VALID && AW_READY) begin
          w_a <= AW_ADDR; w_cnt <= AW_LEN;
          w_size <= AW_SIZE; w_burst <= AW_BURST;
          AW_READY <= 1'b0; W_READY <= 1'b1; w_busy <= 1'b1;
        end
      end else begin
        if (W_VALID && W_READY) begin
          // 按AWSIZE与字节地址低2位落通道（CMSDK无WSTRB约定）
          case (w_size)
            3'b000: case (w_a[1:0]) 2'd0: mem[w_a[AW-1:2]][7:0]   <= W_DATA[7:0];
                                    2'd1: mem[w_a[AW-1:2]][15:8]  <= W_DATA[7:0];
                                    2'd2: mem[w_a[AW-1:2]][23:16] <= W_DATA[7:0];
                                    2'd3: mem[w_a[AW-1:2]][31:24] <= W_DATA[7:0]; endcase
            3'b001: case (w_a[1])   1'b0: mem[w_a[AW-1:2]][15:0]  <= W_DATA[15:0];
                                    1'b1: mem[w_a[AW-1:2]][31:16] <= W_DATA[15:0]; endcase
            default: mem[w_a[AW-1:2]] <= W_DATA;
          endcase
          if (w_burst[0]) w_a <= w_a + (1 << w_size);   // INCR按size步进，FIXED不变
          if (w_cnt == 0) begin
            w_busy <= 1'b0; W_READY <= 1'b0; B_VALID <= 1'b1;
          end else w_cnt <= w_cnt - 8'd1;
        end
      end
    end
  end

  // ================= 读通道（消费拍预取下一拍，R_READY恒1不重复返回） =================
  always @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      r_busy <= 0; r_cnt <= 0; r_a <= 0; r_size <= 0; r_burst <= 0;
      AR_READY <= 1; R_VALID <= 0;
    end else begin
      if (!r_busy) begin
        AR_READY <= 1'b1;
        if (AR_SEL && AR_VALID && AR_READY) begin
          r_a <= AR_ADDR; r_cnt <= AR_LEN;
          r_size <= AR_SIZE; r_burst <= AR_BURST;
          AR_READY <= 1'b0; r_busy <= 1'b1;
        end
      end else begin
        if (R_VALID && R_READY) begin
          if (r_cnt == 0) begin r_busy <= 1'b0; AR_READY <= 1'b1; R_VALID <= 1'b0; end
          else begin
            r_cnt <= r_cnt - 8'd1;
            // 预取下一拍：INCR按size步进、FIXED同址（数据必须随消费更新，
            // 否则R_READY恒1时R_VALID不回0导致burst重复返回首拍）
            if (r_burst[0]) r_a <= r_a + (1 << r_size);
            R_DATA <= mem[r_burst[0] ? (r_a[AW-1:2] + 1'b1) : r_a[AW-1:2]];
            R_LAST <= (r_cnt == 1);
          end
        end else if (!R_VALID) begin
          R_VALID <= 1'b1;
          R_DATA <= mem[r_a[AW-1:2]];      // 整字返回（字节在自然通道）
          R_LAST <= (r_cnt == 0); R_RESP <= 2'b00;
        end
      end
    end
  end
endmodule
