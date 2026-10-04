// fir_top.v : FIR的AXI从机封装（CMSDK SEL风格）
// 寄存器：CTRL/STATUS/DIN/DOUT/COEF[0..81]（见任务接口说明）
// 写：AW握手锁存选择与地址，逐拍W落寄存器/FIFO（INCR逐拍加4、FIXED不变）；
//     最后一拍后回B（BRESP=OKAY）。读：DOUT区FIXED突发=每拍弹一个样本。
// 注意：读通道每拍都置R_LAST（含单拍读，AXI要求末拍R_LAST=1）。
`timescale 1ns/1ps
module fir_top #(
    parameter CORE_TYPE = 0      // 0=fir_core(串行) 1=fir_core_sym(对称并行)
)(
    input  wire        ACLK,
    input  wire        ARESETn,
    // 写通道（CMSDK从机风格）
    input  wire        AW_SEL,
    input  wire        AW_VALID, output reg  AW_READY,
    input  wire [2:0]  AW_SIZE,  input  wire [1:0] AW_BURST,
    input  wire [7:0]  AW_LEN,   input  wire [31:0] AW_ADDR,
    input  wire        W_VALID,  output reg  W_READY,
    input  wire [31:0] W_DATA,   input  wire W_LAST,
    output reg         B_VALID,  input  wire B_READY,
    output reg  [1:0]  B_RESP,
    // 读通道
    input  wire        AR_SEL,
    input  wire        AR_VALID, output reg  AR_READY,
    input  wire [2:0]  AR_SIZE,  input  wire [1:0] AR_BURST,
    input  wire [7:0]  AR_LEN,   input  wire [31:0] AR_ADDR,
    output reg         R_VALID,  input  wire R_READY,
    output reg  [31:0] R_DATA,   output reg  [1:0] R_RESP,
    output reg         R_LAST
);
  // ---- FIFO ----
  localparam DIN_DEPTH  = 16;
  localparam DOUT_DEPTH = 16;
  reg [15:0] din_fifo  [0:DIN_DEPTH-1];
  reg [31:0] dout_fifo [0:DOUT_DEPTH-1];
  // 注意：计数必须5位——16深FIFO计数可达16，4位会在16回绕破坏空/满检测
  reg [3:0]  din_wp, din_rp; reg [4:0] din_cnt;
  reg [3:0]  dot_wp, dot_rp; reg [4:0] dot_cnt;

  // ---- 写状态机 ----
  localparam WS_IDLE = 2'd0, WS_DATA = 2'd1, WS_RESP = 2'd2;
  reg [1:0]  ws;
  reg        w_sel;                    // AW握手时锁存的选中
  reg [31:0] w_a;                      // 当前拍地址
  reg [7:0]  w_cnt;                    // 剩余拍数
  reg [1:0]  w_burst;
  reg [2:0]  w_size;                   // AW握手时锁存（W阶段AW_SIZE可能已变）

  // ---- 读状态机 ----
  localparam RS_IDLE = 2'd0, RS_DATA = 2'd1;
  reg [1:0]  rs;
  reg        r_sel;
  reg [31:0] r_a;
  reg [7:0]  r_cnt;
  reg [1:0]  r_burst;

  // ---- 核与连接 ----
  // 注意：cfg_*必须在generate之前声明（后置声明会被当作1位隐式网）
  reg        cfg_we; reg [9:0] cfg_addr; reg [15:0] cfg_wdata;
  reg [15:0] coef_reg [0:81];
  integer    i;
  wire        core_din_valid = (din_cnt != 0);
  wire [15:0] core_din = din_fifo[din_rp];
  wire        core_din_ready;
  wire        core_dout_valid;
  wire [31:0] core_dout;
  wire [31:0] ctrl_reg;                // bit0=CLR（写1清空）
  reg         clr_pulse;
  // 组合弹/压信号：FIFO指针与计数统一在本块更新——若读块单独更新dot_cnt，
  // 同拍"核输出入队+DOUT弹出"会竞争（读块在后，弹的-1覆盖推的+1），计数
  // 漂移变低，写指针越过未读样本覆盖输出（实测输出流跳拍）；din侧同理
  // （推写在后覆盖弹的-1，计数虚高，核消费陈旧样本）。
  wire dout_pop = (rs == RS_DATA) && R_VALID && R_READY && r_sel && (r_a[11:0] == 12'h00C);
  wire din_push = (ws == WS_DATA) && W_VALID && W_READY && w_sel && (w_a[11:0] == 12'h008);

  generate
    if (CORE_TYPE == 0) begin : core
      fir_core #(.TAPS(82), .CW(16), .DW(16)) u_core (
        .clk(ACLK), .rstn(ARESETn),
        .cfg_we(cfg_we), .cfg_addr(cfg_addr), .cfg_wdata(cfg_wdata),
        .din_valid(core_din_valid), .din_ready(core_din_ready), .din(core_din),
        .dout_valid(core_dout_valid), .dout_ready(dot_cnt != DOUT_DEPTH), .dout(core_dout));
    end else begin : core_sym
      fir_core_sym #(.TAPS(82), .CW(16), .DW(16)) u_core (
        .clk(ACLK), .rstn(ARESETn),
        .cfg_we(cfg_we), .cfg_addr(cfg_addr), .cfg_wdata(cfg_wdata),
        .din_valid(core_din_valid), .din_ready(core_din_ready), .din(core_din),
        .dout_valid(core_dout_valid), .dout_ready(dot_cnt != DOUT_DEPTH), .dout(core_dout));
    end
  endgenerate

  // 写：每拍落寄存器/FIFO（组合出本拍写目标）
  always @(posedge ACLK) begin
    if (!ARESETn) begin
      ws <= WS_IDLE; AW_READY <= 1'b0; W_READY <= 1'b0; B_VALID <= 1'b0; B_RESP <= 2'b00;
      w_sel <= 0; w_a <= 0; w_cnt <= 0; w_burst <= 0;
      din_wp <= 0; din_rp <= 0; din_cnt <= 0;
      dot_wp <= 0; dot_rp <= 0; dot_cnt <= 0;
      cfg_we <= 0; cfg_addr <= 0; cfg_wdata <= 0; clr_pulse <= 0;
      for (i = 0; i < 82; i = i + 1) coef_reg[i] <= 16'h0;
    end else begin
      clr_pulse <= 1'b0; cfg_we <= 1'b0;
      // 核输出入FIFO（与读侧弹出同拍时计数不变——互斥见dout_pop声明注释）
      if (core_dout_valid && (dot_cnt != DOUT_DEPTH)) begin
        dout_fifo[dot_wp] <= core_dout;
        dot_wp <= dot_wp + 1'b1;
        if (!dout_pop) dot_cnt <= dot_cnt + 1'b1;
      end
      if (dout_pop) begin
        dot_rp <= dot_rp + 1'b1;
        if (!(core_dout_valid && (dot_cnt != DOUT_DEPTH))) dot_cnt <= dot_cnt - 1'b1;
      end
      // 核取输入（与W侧压样本同拍时计数不变——互斥见din_push声明注释）
      if (core_din_valid && core_din_ready) begin
        din_rp <= din_rp + 1'b1;
        if (!din_push) din_cnt <= din_cnt - 1'b1;
      end
      case (ws)
        WS_IDLE: begin
          // 仅接受选中事务：AW_READY按AW_SEL门控（总线AW对全部从机广播，
          // 不门控会偷走其它从机的写事务——与AR侧同理，实测幻影事务会让
          // 读状态机抓走CPU的SRAM读，DOUT读被夹带延迟）
          AW_READY <= AW_SEL;
          if (AW_VALID && AW_READY) begin
            w_sel <= AW_SEL; w_a <= AW_ADDR; w_cnt <= AW_LEN; w_burst <= AW_BURST;
            w_size <= AW_SIZE;
            AW_READY <= 1'b0; W_READY <= 1'b1;
            ws <= WS_DATA;
          end
        end
        WS_DATA: begin
          // DIN满反压：din_fifo满时W_READY拉低停等（否则写会被丢弃——
          // 核输出侧反压冻结期间DIN不再消费，满即丢样本，实测冻结窗口丢输入）
          if ((w_a[11:0] == 12'h008) && (din_cnt == DIN_DEPTH)) W_READY <= 1'b0;
          else W_READY <= 1'b1;
          if (W_VALID && W_READY) begin
            if (w_sel) begin
              // 地址在0x4002_0000区域的寄存器写
              casez (w_a[11:0])
                12'h008: begin                          // DIN：压样本（满时W_READY已停等）
                  din_fifo[din_wp] <= (w_size[0]) ?
                      (w_a[1] ? W_DATA[31:16] : W_DATA[15:0]) : W_DATA[15:0];
                  din_wp <= din_wp + 1'b1;
                  if (!(core_din_valid && core_din_ready)) din_cnt <= din_cnt + 1'b1;
                end
                12'h000: if (W_DATA[0]) clr_pulse <= 1'b1;   // CTRL CLR
                12'h004, 12'h00C: ;                          // STATUS/DOUT：忽略写
                default: begin
                  if ((w_a[11:0] >= 12'h010) && (w_a[11:0] < 12'h158) && (w_size == 3'b010)) begin
                    coef_reg[(w_a[11:0] - 12'h010) >> 2] <= W_DATA[15:0];
                    cfg_we <= 1'b1;
                    cfg_addr <= (w_a[11:0] - 12'h010) >> 2;
                    cfg_wdata <= W_DATA[15:0];
                  end
                end
              endcase
            end
            if (w_burst[0]) w_a <= w_a + 32'd4;     // INCR
            if (w_cnt == 0) begin
              ws <= WS_RESP; W_READY <= 1'b0; B_VALID <= 1'b1; B_RESP <= 2'b00;
            end else w_cnt <= w_cnt - 8'd1;
          end
        end
        WS_RESP: begin
          if (B_VALID && B_READY) begin
            B_VALID <= 1'b0; ws <= WS_IDLE;
            AW_READY <= 1'b0;        // 返回IDLE首拍不留敞口（WS_IDLE按AW_SEL重开）
          end
        end
      endcase
      if (clr_pulse) begin                       // 清空
        din_wp <= 0; din_rp <= 0; din_cnt <= 0;
        dot_wp <= 0; dot_rp <= 0; dot_cnt <= 0;
      end
    end
  end

  // 读状态机（每拍按r_cnt置R_LAST，单拍读亦为1）
  // 注意：DOUT弹出在本拍直接做——组合R_DATA读的是旧dot_rp（本拍条目），
  //       NBA推进指针供下一拍；经r_pop两拍延迟会重复返回同一条目。
  always @(posedge ACLK) begin
    if (!ARESETn) begin
      rs <= RS_IDLE; AR_READY <= 1'b0; R_VALID <= 1'b0; R_RESP <= 2'b00; R_LAST <= 1'b0;
      r_sel <= 0; r_a <= 0; r_cnt <= 0; r_burst <= 0;
    end else begin
      case (rs)
        RS_IDLE: begin
          // 仅接受选中事务（同WS_IDLE的AW_SEL门控；实测无门控时读状态机
          // 抓走CPU对SRAM的轮询读，rs被幻影事务占用）
          AR_READY <= AR_SEL;
          if (AR_VALID && AR_READY) begin
            r_sel <= AR_SEL; r_a <= AR_ADDR; r_cnt <= AR_LEN; r_burst <= AR_BURST;
            AR_READY <= 1'b0;
            rs <= RS_DATA;
          end
        end
        RS_DATA: begin
          // DOUT读在FIFO空时保持R_VALID=0等待数据：空读返回dout_fifo[dot_rp]
          // 旧值（不弹指针），DMA会采到X/重复样本（实测ch1首8读命中空FIFO，
          // out_buf[0..7]全X、偶发重拍，输出流整体错位）
          if (!r_sel || (r_a[11:0] != 12'h00C) || (dot_cnt != 0)) R_VALID <= 1'b1;
          R_LAST  <= (r_cnt == 0);
          if (R_VALID && R_READY) begin
            // DOUT弹出在本块外的dout_pop完成（与入队统一更新，见声明注释）
            if (r_burst[0]) r_a <= r_a + 32'd4;
            if (r_cnt == 0) begin
              rs <= RS_IDLE; R_VALID <= 1'b0; R_LAST <= 1'b0;
              AR_READY <= 1'b0;      // 返回IDLE首拍不留敞口（RS_IDLE按AR_SEL重开）
            end else begin
              r_cnt <= r_cnt - 8'd1;
            end
          end
        end
      endcase
    end
  end

  // 读数据（组合）
  always @* begin
    R_DATA = 32'h0; R_RESP = 2'b00;
    if (rs == RS_DATA && r_sel) begin
      casez (r_a[11:0])
        12'h000: R_DATA = 32'h0;                       // CTRL只写
        12'h004: R_DATA = {28'h0, dot_cnt == DOUT_DEPTH, dot_cnt == 0, din_cnt == DIN_DEPTH, din_cnt == 0};
        12'h00C: R_DATA = dout_fifo[dot_rp];           // DOUT
        default: if ((r_a[11:0] >= 12'h010) && (r_a[11:0] < 12'h158))
                   R_DATA = {16'h0, coef_reg[(r_a[11:0] - 12'h010) >> 2]};
      endcase
    end
  end
endmodule
