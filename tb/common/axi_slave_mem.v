// axi_slave_mem.v : 行为级AXI存储从机（无SEL主口视图）
// 写：AW/W握手后按AWSIZE+地址[1:0]落通道；读：1拍延迟流式返回
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
  reg [AW-1:0]  w_a; reg [7:0] w_cnt; reg w_busy;
  reg [AW-1:0]  r_a; reg [7:0] r_cnt; reg r_busy;

  // 组合读出（通道合并用）
  wire [DW-1:0] rd_w = mem[w_a];
  integer i;

  // ---- 写通道 ----
  always @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      w_busy <= 0; w_cnt <= 0; w_a <= 0; AW_READY <= 1; W_READY <= 0; B_VALID <= 0; B_RESP <= 2'b00;
    end else begin
      B_VALID <= 1'b0;
      if (!w_busy) begin
        AW_READY <= 1'b1;
        if (AW_VALID && AW_READY) begin
          w_a <= AW_ADDR[AW-1:0]; w_cnt <= AW_LEN; w_busy <= 1'b1;
          AW_READY <= 1'b0; W_READY <= 1'b1;
        end
      end else begin
        if (W_VALID && W_READY) begin
          // 按AWSIZE与地址低2位写通道
          case (AW_SIZE)
            3'b000: case (w_a[1:0]) 2'd0: mem[w_a][7:0]   <= W_DATA[7:0];
                                    2'd1: mem[w_a][15:8]  <= W_DATA[7:0];
                                    2'd2: mem[w_a][23:16] <= W_DATA[7:0];
                                    2'd3: mem[w_a][31:24] <= W_DATA[7:0]; endcase
            3'b001: case (w_a[1])   1'b0: mem[w_a][15:0]  <= W_DATA[15:0];
                                    1'b1: mem[w_a][31:16] <= W_DATA[15:0]; endcase
            default: mem[w_a] <= W_DATA;
          endcase
          if (AW_BURST[0]) w_a <= w_a + 1'b1;      // INCR
          if (w_cnt == 0) begin
            w_busy <= 1'b0; W_READY <= 1'b0; B_VALID <= 1'b1;
          end else w_cnt <= w_cnt - 8'd1;
        end
      end
    end
  end

  // ---- 读通道（1拍延迟）----
  always @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      r_busy <= 0; r_cnt <= 0; r_a <= 0; AR_READY <= 1; R_VALID <= 0;
    end else begin
      if (!r_busy) begin
        AR_READY <= 1'b1;
        if (AR_VALID && AR_READY) begin
          r_a <= AR_ADDR[AW-1:0]; r_cnt <= AR_LEN; r_busy <= 1'b1;
          AR_READY <= 1'b0;
        end
      end else begin
        if (R_VALID && R_READY) begin
          r_a <= r_a + 1'b1;                    // 从机存储简化按INCR
          if (r_cnt == 0) begin r_busy <= 1'b0; AR_READY <= 1'b1; R_VALID <= 1'b0; end
          else begin
            r_cnt <= r_cnt - 8'd1;
            // 预取下一拍：R_READY恒1时R_VALID不回0，数据必须随消费更新
            R_DATA <= mem[r_a + 1'b1];
            R_LAST <= (r_cnt == 1);
          end
        end else if (!R_VALID) begin
          R_VALID <= 1'b1; R_DATA <= mem[r_a]; R_LAST <= (r_cnt == 0); R_RESP <= 2'b00;
        end
      end
    end
  end
endmodule
