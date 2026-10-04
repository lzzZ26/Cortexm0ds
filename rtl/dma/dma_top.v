// dma_top.v : 6通道DMA控制器
// 结构：6×dma_channel + 通道仲裁（burst粒度轮询）+ CMSDK从机配置口 + 中断聚合
// 通道仲裁：req_o在burst边界（读写切换点）下拉，授权随之下放并按轮询转授；
//           被授权通道的AXI主口信号经mux上共享总线，未授权通道ready门控。
// 寄存器：通道n基址 0x4003_0000+n*0x20：SRC/DST/LEN/CTRL/STATUS/NEXT；
//         全局 0x4003_0100 INT_STATUS（读）、0x4003_0104 INT_CLR（写1清）。
// 注意：通道号在低12位地址的[8:5]（n*0x20），寄存器号在[4:0]——计划原文
//       用[11:8]/[6:0]译码，除通道0外全部失效。
`timescale 1ns/1ps
module dma_top(
    input  wire        ACLK,
    input  wire        ARESETn,
    // 配置口（CMSDK从机风格；接官方slave mux输出，SEL由译码器给出）
    input  wire        AW_SEL, AW_VALID, output reg AW_READY,
    input  wire [2:0]  AW_SIZE, input wire [1:0] AW_BURST,
    input  wire [7:0]  AW_LEN,  input wire [31:0] AW_ADDR,
    input  wire        W_VALID, output reg W_READY,
    input  wire [31:0] W_DATA,  input wire W_LAST,
    output reg         B_VALID, input wire B_READY, output reg [1:0] B_RESP,
    input  wire        AR_SEL, AR_VALID, output reg AR_READY,
    input  wire [2:0]  AR_SIZE, input wire [1:0] AR_BURST,
    input  wire [7:0]  AR_LEN,  input wire [31:0] AR_ADDR,
    output reg         R_VALID, input wire R_READY,
    output reg  [31:0] R_DATA,  output reg [1:0] R_RESP, output reg R_LAST,
    // AXI主口
    output wire        awvalid, input wire awready,
    output wire [2:0]  awsize,  output wire [1:0] awburst,
    output wire [7:0]  awlen,   output wire [31:0] awaddr,
    output wire        wvalid,  input wire wready,
    output wire [31:0] wdata,   output wire wlast,
    input  wire        bvalid,  output wire bready,
    input  wire [1:0]  bresp,
    output wire        arvalid, input wire arready,
    output wire [2:0]  arsize,  output wire [1:0] arburst,
    output wire [7:0]  arlen,   output wire [31:0] araddr,
    input  wire        rvalid,  output wire rready,
    input  wire [31:0] rdata,   input wire [1:0] rresp,
    input  wire        rlast,
    // 中断
    output wire        irq_o
);
  // ---- 通道信号 ----
  reg  [31:0] ch_src [0:5], ch_dst [0:5], ch_len [0:5], ch_next [0:5];
  reg  [15:0] ch_ctrl [0:5];
  reg         ch_load [0:5];
  wire        ch_busy [0:5], ch_done [0:5], ch_err [0:5], ch_req [0:5], ch_irq [0:5];
  reg  [31:0] ch_done_q [0:5], ch_err_q [0:5];
  wire        ch_awvalid [0:5], ch_wvalid [0:5], ch_wlast [0:5], ch_arvalid [0:5];
  wire        ch_awready [0:5], ch_wready [0:5], ch_bvalid [0:5],
              ch_arready [0:5], ch_rvalid [0:5], ch_rlast [0:5];
  wire        ch_bready [0:5], ch_rready [0:5];
  wire [2:0]  ch_awsize [0:5], ch_arsize [0:5];
  wire [1:0]  ch_awburst [0:5], ch_arburst [0:5];
  wire [7:0]  ch_awlen [0:5], ch_arlen [0:5];
  wire [31:0] ch_awaddr [0:5], ch_wdata [0:5], ch_araddr [0:5], ch_rdata [0:5];
  wire [1:0]  ch_bresp [0:5], ch_rresp [0:5];

  genvar g;
  generate
    for (g = 0; g < 6; g = g + 1) begin : ch
      dma_channel u_ch (
        .ACLK(ACLK), .ARESETn(ARESETn),
        .cfg_src(ch_src[g]), .cfg_dst(ch_dst[g]), .cfg_len(ch_len[g]),
        .cfg_next(ch_next[g]), .cfg_ctrl(ch_ctrl[g]), .cfg_load(ch_load[g]),
        .busy_o(ch_busy[g]), .done_o(ch_done[g]), .err_o(ch_err[g]), .req_o(ch_req[g]),
        .irq_o(ch_irq[g]),
        .awvalid(ch_awvalid[g]), .awready(ch_awready[g]), .awsize(ch_awsize[g]),
        .awburst(ch_awburst[g]), .awlen(ch_awlen[g]), .awaddr(ch_awaddr[g]),
        .wvalid(ch_wvalid[g]), .wready(ch_wready[g]), .wdata(ch_wdata[g]), .wlast(ch_wlast[g]),
        .bvalid(ch_bvalid[g]), .bready(ch_bready[g]), .bresp(ch_bresp[g]),
        .arvalid(ch_arvalid[g]), .arready(ch_arready[g]), .arsize(ch_arsize[g]),
        .arburst(ch_arburst[g]), .arlen(ch_arlen[g]), .araddr(ch_araddr[g]),
        .rvalid(ch_rvalid[g]), .rready(ch_rready[g]), .rdata(ch_rdata[g]),
        .rresp(ch_rresp[g]), .rlast(ch_rlast[g]));
    end
  endgenerate

  // ---- 通道仲裁（burst粒度轮询）----
  // 释放：当前授权通道req下拉（该通道处于读↔写切换点，无在途事务）。
  // 轮询：从上一授权通道+1起找第一个请求者。计划原文`gnt<=gnt+1`在释放时
  //       清零gnt，只会反复授权1号通道（0号饿死）——改为组合扫描。
  reg [2:0] gnt;
  reg       gnt_valid;
  reg [2:0] nxt_gnt;
  wire      any_req = ch_req[0] | ch_req[1] | ch_req[2] | ch_req[3] | ch_req[4] | ch_req[5];
  always @* begin
    nxt_gnt = gnt;
    case (gnt)
      3'd0: begin
        if      (ch_req[1]) nxt_gnt = 3'd1;
        else if (ch_req[2]) nxt_gnt = 3'd2;
        else if (ch_req[3]) nxt_gnt = 3'd3;
        else if (ch_req[4]) nxt_gnt = 3'd4;
        else if (ch_req[5]) nxt_gnt = 3'd5;
        else if (ch_req[0]) nxt_gnt = 3'd0;
      end
      3'd1: begin
        if      (ch_req[2]) nxt_gnt = 3'd2;
        else if (ch_req[3]) nxt_gnt = 3'd3;
        else if (ch_req[4]) nxt_gnt = 3'd4;
        else if (ch_req[5]) nxt_gnt = 3'd5;
        else if (ch_req[0]) nxt_gnt = 3'd0;
        else if (ch_req[1]) nxt_gnt = 3'd1;
      end
      3'd2: begin
        if      (ch_req[3]) nxt_gnt = 3'd3;
        else if (ch_req[4]) nxt_gnt = 3'd4;
        else if (ch_req[5]) nxt_gnt = 3'd5;
        else if (ch_req[0]) nxt_gnt = 3'd0;
        else if (ch_req[1]) nxt_gnt = 3'd1;
        else if (ch_req[2]) nxt_gnt = 3'd2;
      end
      3'd3: begin
        if      (ch_req[4]) nxt_gnt = 3'd4;
        else if (ch_req[5]) nxt_gnt = 3'd5;
        else if (ch_req[0]) nxt_gnt = 3'd0;
        else if (ch_req[1]) nxt_gnt = 3'd1;
        else if (ch_req[2]) nxt_gnt = 3'd2;
        else if (ch_req[3]) nxt_gnt = 3'd3;
      end
      3'd4: begin
        if      (ch_req[5]) nxt_gnt = 3'd5;
        else if (ch_req[0]) nxt_gnt = 3'd0;
        else if (ch_req[1]) nxt_gnt = 3'd1;
        else if (ch_req[2]) nxt_gnt = 3'd2;
        else if (ch_req[3]) nxt_gnt = 3'd3;
        else if (ch_req[4]) nxt_gnt = 3'd4;
      end
      default: begin
        if      (ch_req[0]) nxt_gnt = 3'd0;
        else if (ch_req[1]) nxt_gnt = 3'd1;
        else if (ch_req[2]) nxt_gnt = 3'd2;
        else if (ch_req[3]) nxt_gnt = 3'd3;
        else if (ch_req[4]) nxt_gnt = 3'd4;
        else if (ch_req[5]) nxt_gnt = 3'd5;
      end
    endcase
  end
  always @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin gnt <= 3'd0; gnt_valid <= 1'b0; end
    else begin
      if (gnt_valid && !ch_req[gnt]) begin      // 释放（可能立即转授）
        gnt <= nxt_gnt;
        gnt_valid <= any_req;
      end else if (!gnt_valid) begin            // 新授权
        gnt <= nxt_gnt;
        gnt_valid <= any_req;
      end
    end
  end

  // ---- 主口mux（未授权valid=0；数据直通由valid门控语义保护）----
  assign awvalid = gnt_valid ? ch_awvalid[gnt] : 1'b0;
  assign awsize  = ch_awsize [gnt];
  assign awburst = ch_awburst[gnt];
  assign awlen   = ch_awlen  [gnt];
  assign awaddr  = ch_awaddr [gnt];
  assign wvalid  = gnt_valid ? ch_wvalid[gnt] : 1'b0;
  assign wdata   = ch_wdata  [gnt];
  assign wlast   = ch_wlast  [gnt];
  assign arvalid = gnt_valid ? ch_arvalid[gnt] : 1'b0;
  assign arsize  = ch_arsize [gnt];
  assign arburst = ch_arburst[gnt];
  assign arlen   = ch_arlen  [gnt];
  assign araddr  = ch_araddr [gnt];
  // bready/rready必须取被授权通道的信号——计划原文把1'b1硬接到通道的输出口
  // （多驱动冲突），且未授权通道的ready若被透传会吞掉他人的B/R响应。
  assign bready  = gnt_valid ? ch_bready[gnt] : 1'b1;
  assign rready  = gnt_valid ? ch_rready[gnt] : 1'b1;

  generate
    for (g = 0; g < 6; g = g + 1) begin : rdymux
      assign ch_awready[g] = (gnt_valid && gnt == g[2:0]) ? awready  : 1'b0;
      assign ch_wready [g] = (gnt_valid && gnt == g[2:0]) ? wready   : 1'b0;
      assign ch_bvalid [g] = (gnt_valid && gnt == g[2:0]) ? bvalid   : 1'b0;
      assign ch_bresp  [g] = bresp;
      assign ch_arready[g] = (gnt_valid && gnt == g[2:0]) ? arready  : 1'b0;
      assign ch_rvalid [g] = (gnt_valid && gnt == g[2:0]) ? rvalid   : 1'b0;
      assign ch_rdata  [g] = rdata;
      assign ch_rresp  [g] = rresp;
      assign ch_rlast  [g] = (gnt_valid && gnt == g[2:0]) ? rlast   : 1'b0;
    end
  endgenerate

  // ---- 中断与状态 ----
  reg [5:0] int_status;
  reg [5:0] int_clr;
  integer   i;
  always @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      int_status <= 0;
      for (i = 0; i < 6; i = i + 1) begin
        ch_done_q[i] <= 0; ch_err_q[i] <= 0;
      end
    end else begin
      for (i = 0; i < 6; i = i + 1) begin
        // 中断=通道完成脉冲且本段IRQ_EN（链式末段由描述符IRQ_EN驱动，
        // 非链式由寄存器IRQ_EN驱动——通道内irq_o=done&&irq_en统一覆盖）
        if (ch_irq[i]) int_status[i] <= 1'b1;
        if (ch_done[i]) ch_done_q[i] <= 1'b1;
        if (ch_err[i])  ch_err_q[i]  <= 1'b1;
        if (int_clr[i]) int_status[i] <= 1'b0;
      end
    end
  end
  assign irq_o = |int_status;

  // ---- 配置从机（写寄存器/读寄存器，复用fir_top的写法）----
  localparam WS_IDLE = 2'd0, WS_DATA = 2'd1, WS_RESP = 2'd2;
  reg [1:0] ws; reg w_sel; reg [31:0] w_a; reg [7:0] w_cnt; reg [1:0] w_burst;
  reg [2:0] w_size;                    // AW握手时锁存（W阶段AW_SIZE可能已变）
  localparam RS_IDLE = 2'd0, RS_DATA = 2'd1;
  reg [1:0] rs; reg r_sel; reg [31:0] r_a; reg [7:0] r_cnt; reg [1:0] r_burst;

  always @(posedge ACLK) begin
    if (!ARESETn) begin
      ws <= WS_IDLE; AW_READY <= 0; W_READY <= 0; B_VALID <= 0; B_RESP <= 0;
      w_sel <= 0; w_a <= 0; w_cnt <= 0; w_burst <= 0; int_clr <= 0;
      for (i = 0; i < 6; i = i + 1) begin
        ch_src[i] <= 0; ch_dst[i] <= 0; ch_len[i] <= 0; ch_ctrl[i] <= 0;
        ch_next[i] <= 0; ch_load[i] <= 0;
      end
    end else begin
      for (i = 0; i < 6; i = i + 1) ch_load[i] <= 1'b0;
      int_clr <= 6'b0;
      case (ws)
        WS_IDLE: begin
          AW_READY <= 1;
          if (AW_VALID && AW_READY) begin
            w_sel <= AW_SEL; w_a <= AW_ADDR; w_cnt <= AW_LEN; w_burst <= AW_BURST;
            w_size <= AW_SIZE;
            AW_READY <= 0; W_READY <= 1; ws <= WS_DATA;
          end
        end
        WS_DATA: begin
          if (W_VALID && W_READY) begin
            if (w_sel && w_size == 3'b010) begin
              // 通道寄存器：通道号=addr[8:5]（n*0x20），寄存器号=addr[4:0]
              for (i = 0; i < 6; i = i + 1) begin
                if (w_a[8:5] == i[2:0] && w_a[11:0] < 12'h100) begin
                  case (w_a[4:0])
                    5'h00: ch_src[i]  <= W_DATA;
                    5'h04: ch_dst[i]  <= W_DATA;
                    5'h08: ch_len[i]  <= W_DATA;
                    5'h14: ch_next[i] <= W_DATA;
                    5'h0C: begin
                      ch_ctrl[i] <= W_DATA[15:0];
                      if (W_DATA[0]) ch_load[i] <= 1'b1;    // GO
                    end
                    5'h10: begin                              // STATUS只读
                    end
                  endcase
                end
              end
              if (w_a[11:0] == 12'h104) int_clr <= W_DATA[5:0]; // INT_CLR
            end
            if (w_burst[0]) w_a <= w_a + 32'd4;
            if (w_cnt == 0) begin ws <= WS_RESP; W_READY <= 0; B_VALID <= 1; end
            else w_cnt <= w_cnt - 8'd1;
          end
        end
        WS_RESP: if (B_VALID && B_READY) begin B_VALID <= 0; ws <= WS_IDLE; end
      endcase
    end
  end

  // ---- 读状态机（单拍读R_LAST必须为1：首拍即末拍判定在RS_DATA顶部给出）----
  always @(posedge ACLK) begin
    if (!ARESETn) begin
      rs <= RS_IDLE; AR_READY <= 0; R_VALID <= 0; R_RESP <= 0; R_LAST <= 0;
      r_sel <= 0; r_a <= 0; r_cnt <= 0; r_burst <= 0;
    end else begin
      case (rs)
        RS_IDLE: begin
          AR_READY <= 1;
          if (AR_VALID && AR_READY) begin
            r_sel <= AR_SEL; r_a <= AR_ADDR; r_cnt <= AR_LEN; r_burst <= AR_BURST;
            AR_READY <= 0; rs <= RS_DATA;
          end
        end
        RS_DATA: begin
          R_VALID <= 1;
          R_LAST <= (r_cnt == 0);           // 首拍即末拍判定（握手拍被下方分支覆盖）
          if (R_VALID && R_READY) begin
            if (r_burst[0]) r_a <= r_a + 32'd4;
            if (r_cnt == 0) begin rs <= RS_IDLE; R_VALID <= 0; R_LAST <= 0; AR_READY <= 1; end
            else begin r_cnt <= r_cnt - 8'd1; if (r_cnt == 1) R_LAST <= 1; end
          end
        end
      endcase
    end
  end

  // ---- 读数据（R_RESP恒0，仅由时序块复位驱动，避免双驱动）----
  always @* begin
    R_DATA = 32'h0;
    if (rs == RS_DATA && r_sel) begin
      if (r_a[11:0] == 12'h100) R_DATA = {26'h0, int_status};        // INT_STATUS
      else begin
        for (i = 0; i < 6; i = i + 1) begin
          if (r_a[8:5] == i[2:0] && r_a[11:0] < 12'h100) begin
            case (r_a[4:0])
              5'h00: R_DATA = ch_src[i];
              5'h04: R_DATA = ch_dst[i];
              5'h08: R_DATA = ch_len[i];
              5'h0C: R_DATA = {16'h0, ch_ctrl[i]};
              5'h14: R_DATA = ch_next[i];
              5'h10: R_DATA = {29'h0, ch_err_q[i], ch_done_q[i], ch_busy[i]};
            endcase
          end
        end
      end
    end
  end
endmodule
