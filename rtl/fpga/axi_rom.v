// axi_rom.v : FPGA用只读ROM（CMSDK从机风格，替代仿真flash模型用于板级）
// $readmemh初始值在PDS综合时推断为BRAM/ROM初值（若工具不支持initial初始化，
// 改为厂商IP生成.coe——以PDS文档为准，接口不变）。
//
// 与计划原文的两处修正（T15实证）：
// 1. 窄读通道摆放：官方ram_beh语义=数据摆在地址对应字节通道、未选通道=0
//    （AHB2AXI桥不搬通道，窄读错摆会使CPU取到错字节）。
// 2. AR_READY按AR_SEL门控：共享总线上AR对全部从机广播，不门控会接手
//    其它从机的事务（幻影读，fir_top同病已修，见其头注释）。
`timescale 1ns/1ps
module axi_rom #(
    parameter FILENAME = "image.hex",
    parameter AW = 16                       // 64K字节
)(
    input  wire        ACLK,
    input  wire        ARESETn,
    input  wire        AR_SEL,
    input  wire        AR_VALID, output reg AR_READY,
    input  wire [2:0]  AR_SIZE,  input wire [1:0] AR_BURST,
    input  wire [7:0]  AR_LEN,   input wire [AW-1:0] AR_ADDR,
    output reg         R_VALID,  input wire R_READY,
    output wire [31:0] R_DATA,   output wire [1:0] R_RESP,
    output wire        R_LAST
);
  // 内存=字节数组（与官方cmsdk_axi_ram_beh一致）：objcopy -O verilog的hex
  // 是字节流格式（每行16字节，小端字序），$readmemh按token装入字节数组
  // 正好吻合；若按32位字数组装载则字节序全错（实测hello.hex的rom[0]
  // 读回0x00000000而SP应为0x2000FC00，冒烟超时）。读时按通道拼小端字。
  // 零填充：未覆盖位置=0（与PDS综合后BRAM初值一致，仿真不留X）。
  reg [7:0] rom_b [0:(1<<AW)-1];
  integer ri;
  initial begin
    for (ri = 0; ri < (1<<AW); ri = ri + 1) rom_b[ri] = 8'h00;
    if (FILENAME != "") $readmemh(FILENAME, rom_b);
  end
  reg [AW-3:0] r_a;                       // 字索引
  reg [7:0]  r_cnt;                       // 剩余拍数（AR_LEN起）
  reg [1:0]  r_burst;
  reg [2:0]  r_size;
  reg [1:0]  r_b2;                        // AR地址低2位（窄读通道）
  reg [3:0]  r_lane;                      // 字节通道选通（官方ram_beh语义）
  reg        r_busy;

  // 通道选通：字节=地址低2位单通道；半字=按bit1双通道；其余全通道
  reg [3:0] lane_nxt;
  always @* begin
    case (AR_SIZE)
      3'b000: lane_nxt = 4'b0001 << AR_ADDR[1:0];
      3'b001: lane_nxt = AR_ADDR[1] ? 4'b1100 : 4'b0011;
      default: lane_nxt = 4'b1111;
    endcase
  end

  // 读数据（组合）：通道N=字地址字节N（小端），未选通道=0
  assign R_DATA = { r_lane[3] ? rom_b[{r_a, 2'b00} + 3] : 8'h00,
                    r_lane[2] ? rom_b[{r_a, 2'b00} + 2] : 8'h00,
                    r_lane[1] ? rom_b[{r_a, 2'b00} + 1] : 8'h00,
                    r_lane[0] ? rom_b[{r_a, 2'b00}]     : 8'h00 };
  assign R_RESP = 2'b00;
  // R_LAST必须组合：末拍在整个周期内r_cnt==0。若寄存`R_LAST<=(r_cnt==0)`，
  // 接受倒数第二拍的沿上r_cnt尚未减到0，末拍呈现R_LAST=0（检查器报缺失，
  // 实测于本TB INCR/FIXED突发）。
  assign R_LAST = r_busy && (r_cnt == 0);

  always @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      r_busy <= 1'b0; r_cnt <= 0; r_a <= 0; r_burst <= 0;
      r_size <= 3'b010; r_b2 <= 0; r_lane <= 4'b1111;
      AR_READY <= 1'b0; R_VALID <= 1'b0;
    end else begin
      if (!r_busy) begin
        AR_READY <= AR_SEL;                // SEL门控（见头注释修正2）
        if (AR_VALID && AR_READY) begin
          r_a <= AR_ADDR[AW-1:2]; r_cnt <= AR_LEN; r_burst <= AR_BURST;
          r_size <= AR_SIZE; r_b2 <= AR_ADDR[1:0]; r_lane <= lane_nxt;
          AR_READY <= 1'b0; r_busy <= 1'b1;
        end
      end else begin
        if (R_VALID && R_READY) begin
          if (r_burst[0]) r_a <= r_a + 1'b1;    // INCR：下一字
          if (r_cnt == 0) begin                 // 末拍消费完：回IDLE
            r_busy <= 1'b0; AR_READY <= 1'b0; R_VALID <= 1'b0;
          end else begin
            r_cnt <= r_cnt - 8'd1;
          end
        end else if (!R_VALID) begin
          R_VALID <= 1'b1;                      // 1拍初始延迟后连续出拍
        end
      end
    end
  end
endmodule
