// axi_slave_mem.v（修正版）：行为级AXI存储从机
// 修正1：AW_SIZE/AW_BURST在AW握手时锁存（原实现用直通信号，握手后主设备可改值）
// 修正2：读路径支持FIXED突发（地址不递增，供DMA固定地址读取测试）
// 修正3：R_DATA随消费预取（R_READY恒1时R_VALID不回0，必须逐拍更新，否则burst重复返回首拍）
`timescale 1ns/1ps
module axi_slave_mem #(parameter AW = 12, parameter DW = 32)(
    input  wire        ACLK, ARESETn,
    input  wire        AW_VALID, output reg AW_READY,
    input  wire [2:0]  AW_SIZE,  input wire [1:0] AW_BURST,
    input  wire [7:0]  AW_LEN,   input wire [31:0] AW_ADDR,
    input  wire        W_VALID,  output reg W_READY,
    input  wire [DW-1:0] W_DATA, input wire W_LAST,
    output reg         B_VALID,  input wire B_READY, output reg [1:0] B_RESP,
    input  wire        AR_VALID, output reg AR_READY,
    input  wire [2:0]  AR_SIZE,  input wire [1:0] AR_BURST,
    input  wire [7:0]  AR_LEN,   input wire [31:0] AR_ADDR,
    output reg         R_VALID,  input wire R_READY,
    output reg [DW-1:0] R_DATA,  output reg [1:0] R_RESP, output reg R_LAST
);
  reg [DW-1:0] mem [0:(1<<AW)-1];
  // 注意：地址寄存器必须AW+2位——数组2^AW字=16KB，字节地址需14位；
  // 12位会在4KB以上回绕（地址寄存器截断）。
  reg [AW+1:0] w_a; reg [7:0] w_cnt; reg w_busy;   // w_a=字节地址（低位留通道）
  reg [2:0]    w_size; reg [1:0] w_burst;      // 锁存
  reg [AW+1:0] r_a; reg [7:0] r_cnt; reg r_busy;   // r_a=字节地址
  reg [1:0]    r_burst;                        // 锁存

  // 注意：数组按字索引（addr>>2，必须取[AW+1:2]共12位——4096字）；
  // INCR按+4字节步进。此前误用[AW-1:2]（10位），0x1000以上地址的字索引
  // 被截断回绕，写0x1100实际落0x100（源/目的区混叠，用例2污染源区word64-67）。
  // 计划原版把字节地址直接当字索引且+1，写读地址自洽的用例测不出，DMA用例才暴露。
  always @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      w_busy <= 0; w_cnt <= 0; w_a <= 0; w_size <= 0; w_burst <= 0;
      AW_READY <= 1; W_READY <= 0; B_VALID <= 0; B_RESP <= 2'b00;
    end else begin
      B_VALID <= 1'b0;
      if (!w_busy) begin
        AW_READY <= 1'b1;
        if (AW_VALID && AW_READY) begin
          w_a <= AW_ADDR[AW+1:0]; w_cnt <= AW_LEN;
          w_size <= AW_SIZE; w_burst <= AW_BURST;
          AW_READY <= 1'b0; W_READY <= 1'b1; w_busy <= 1'b1;
        end
      end else begin
        if (W_VALID && W_READY) begin
          case (w_size)
            3'b000: case (w_a[1:0]) 2'd0: mem[w_a[AW+1:2]][7:0]   <= W_DATA[7:0];
                                    2'd1: mem[w_a[AW+1:2]][15:8]  <= W_DATA[7:0];
                                    2'd2: mem[w_a[AW+1:2]][23:16] <= W_DATA[7:0];
                                    2'd3: mem[w_a[AW+1:2]][31:24] <= W_DATA[7:0]; endcase
            3'b001: case (w_a[1])   1'b0: mem[w_a[AW+1:2]][15:0]  <= W_DATA[15:0];
                                    1'b1: mem[w_a[AW+1:2]][31:16] <= W_DATA[15:0]; endcase
            default: mem[w_a[AW+1:2]] <= W_DATA;
          endcase
          if (w_burst[0]) w_a <= w_a + 32'd4;     // INCR递增（字节地址+4），FIXED不变
          if (w_cnt == 0) begin
            w_busy <= 1'b0; W_READY <= 1'b0; B_VALID <= 1'b1;
          end else w_cnt <= w_cnt - 8'd1;
        end
      end
    end
  end

  always @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      r_busy <= 0; r_cnt <= 0; r_a <= 0; r_burst <= 0; AR_READY <= 1; R_VALID <= 0;
    end else begin
      if (!r_busy) begin
        AR_READY <= 1'b1;
        if (AR_VALID && AR_READY) begin
          r_a <= AR_ADDR[AW+1:0]; r_cnt <= AR_LEN; r_burst <= AR_BURST;
          AR_READY <= 1'b0; r_busy <= 1'b1;
        end
      end else begin
        if (R_VALID && R_READY) begin
          if (r_cnt == 0) begin r_busy <= 1'b0; AR_READY <= 1'b1; R_VALID <= 1'b0; end
          else begin
            r_cnt <= r_cnt - 8'd1;
            // 预取下一拍：INCR递增、FIXED同址（数据必须随消费更新）
            // 读数据按地址偏移移位到低通道（AXI读约定，字节/半字读取[7:0]/[15:0]）
            if (r_burst[0]) r_a <= r_a + 32'd4;
            R_DATA <= mem[r_burst[0] ? (r_a[AW+1:2] + 1'b1) : r_a[AW+1:2]]
                      >> (8 * r_a[1:0]);
            R_LAST <= (r_cnt == 1);
          end
        end else if (!R_VALID) begin
          R_VALID <= 1'b1;
          R_DATA <= mem[r_a[AW+1:2]] >> (8 * r_a[1:0]);
          R_LAST <= (r_cnt == 0); R_RESP <= 2'b00;
        end
      end
    end
  end
endmodule
