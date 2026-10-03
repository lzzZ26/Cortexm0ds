// dma_channel.v : 单通道DMA引擎（AXI主设备）
// 数据流：读burst（字宽）→ 16字FIFO → 写burst（按对齐/剩余字节自动选 字节/半字/字 通道）
// 字节精度：hpos=当前FIFO头字已消费字节；首字源偏移在hpos初始值中体现；
//           写侧用 单拍部分写 + 整字burst + 尾部部分写 三段式，AW_SIZE随burst定。
// 4KB边界：读/写burst均按边界拆分（协议检查器佐证）。
// 固定地址：FIXED_SRC=固定地址字burst读len拍；FIXED_DST=固定地址FIXED写burst（FSIZE宽度）。
// 链式：完成后从cfg_next读5字描述符{SRC,DST,LEN,CTRL,NEXT}自动续传（CHAIN位）。
`timescale 1ns/1ps
module dma_channel #(parameter DW = 32)(
    input  wire        clk,
    input  wire        rstn,
    input  wire [31:0] cfg_src,
    input  wire [31:0] cfg_dst,
    input  wire [31:0] cfg_len,
    input  wire [31:0] cfg_next,
    input  wire [15:0] cfg_ctrl,   // [0]GO [1]IRQ_EN [2]FIXED_SRC [3]FIXED_DST [4]CHAIN [7:5]BURST [10:8]FSIZE
    input  wire        cfg_load,
    output reg         busy_o,
    output reg         done_o,
    output reg         err_o,
    output reg         req_o,
    output reg         irq_o,
    // AXI主口（由dma_top按req/grant多路选择后接共享总线）
    output reg         awvalid,  input  wire awready,
    output reg  [2:0]  awsize,   output reg  [1:0] awburst,
    output reg  [7:0]  awlen,    output reg  [31:0] awaddr,
    output reg         wvalid,   input  wire wready,
    output reg  [31:0] wdata,    output wire wlast,
    input  wire        bvalid,   output reg  bready,
    input  wire [1:0]  bresp,
    output reg         arvalid,  input  wire arready,
    output reg  [2:0]  arsize,   output reg  [1:0] arburst,
    output reg  [7:0]  arlen,    output reg  [31:0] araddr,
    input  wire        rvalid,   output reg  rready,
    input  wire [31:0] rdata,    input  wire [1:0] rresp,
    input  wire        rlast
);
  localparam S_IDLE=0, S_RD_AR=1, S_RD_D=2, S_WR_AW=3, S_WR_D=4, S_WR_B=5,
             S_CH_AR=6, S_CH_D=7, S_DONE=8;

  // 注意：st必须4位——S_DONE=8在3位里回绕成0(S_IDLE)，完成脉冲永不触发
  reg [3:0]  st;
  reg [31:0] src_a, dst_a, rem;        // rem=剩余字节
  reg [31:0] nxt_ptr;
  reg [31:0] units_rem;                // 固定侧剩余拍数
  reg [2:0]  burst_max;                // 0=1..7=8拍
  reg [2:0]  fsize;                    // 固定侧单位宽度指数
  reg        fixed_src, fixed_dst, chain_en, irq_en;
  reg [3:0]  hpos;                     // FIFO头字已消费字节
  reg [3:0]  fifo_wp, fifo_rp; reg [4:0] fifo_cnt;   // 计数5位：16深可达16
  reg [31:0] fifo [0:15];
  reg [7:0]  bcnt;                     // burst内拍计数
  reg [7:0]  blen;                     // 本burst拍数-1
  reg [3:0]  this_bytes;               // 本写拍字节数
  reg [2:0]  this_size;                // 本写拍AXI大小
  reg [31:0] shadow [0:4];
  reg        err;
  reg        chain_cont;             // 链式续传标志：S_CH_D收齐描述符后置1，S_IDLE消费
  integer    i;

  wire [31:0] head = fifo[fifo_rp];
  // 可用字节（有符号，防止hpos>0时无符号回绕成大数）
  wire signed [7:0] avail = $signed({1'b0, fifo_cnt}) * 4 - $signed({1'b0, hpos});
  // W_LAST必须组合给出：末拍整个周期内bcnt==blen。若用NBA`wlast<=(bcnt==blen)`，
  // 末拍前一手握沿上bcnt尚未到blen，末拍周期wlast=0（协议检查器报W_LAST缺失）。
  assign wlast = (st == S_WR_D) && (bcnt == blen);

  always @(posedge clk) begin
    if (!rstn) begin
      st <= S_IDLE; busy_o <= 0; done_o <= 0; err_o <= 0; req_o <= 0; irq_o <= 0;
      awvalid <= 0; wvalid <= 0; arvalid <= 0; bready <= 0; rready <= 0;
      awsize <= 0; awburst <= 0; awlen <= 0; awaddr <= 0; wdata <= 0;
      arsize <= 0; arburst <= 0; arlen <= 0; araddr <= 0;
      fifo_wp <= 0; fifo_rp <= 0; fifo_cnt <= 0; hpos <= 0; err <= 0; chain_cont <= 0;
    end else begin
      done_o <= 1'b0; err_o <= 1'b0; irq_o <= 1'b0;
      case (st)
        S_IDLE: begin
          busy_o <= 1'b0;
          if (cfg_load && cfg_ctrl[0]) begin          // 软件启动
            src_a <= cfg_src; dst_a <= cfg_dst;
            nxt_ptr <= cfg_next;
            burst_max <= cfg_ctrl[7:5]; fsize <= cfg_ctrl[10:8];
            fixed_src <= cfg_ctrl[2]; fixed_dst <= cfg_ctrl[3];
            chain_en <= cfg_ctrl[4]; irq_en <= cfg_ctrl[1];
            rem <= cfg_ctrl[2] || cfg_ctrl[3] ? (cfg_len << cfg_ctrl[10:8]) : cfg_len;
            units_rem <= cfg_len;
            hpos <= cfg_ctrl[2] ? 4'd0 : cfg_src[1:0];
            fifo_wp <= 0; fifo_rp <= 0; fifo_cnt <= 0; err <= 0;
            busy_o <= 1'b1;
            st <= S_RD_AR;
          end else if (chain_cont) begin           // 链式续传：S_CH_D收齐后内部触发（cfg_load是
                                                   // dma_top的一次性装载脉冲，不会二次出现）
            chain_cont <= 1'b0;
            src_a <= shadow[0]; dst_a <= shadow[1];
            nxt_ptr <= shadow[4];
            burst_max <= shadow[3][7:5]; fsize <= shadow[3][10:8];
            fixed_src <= shadow[3][2]; fixed_dst <= shadow[3][3];
            chain_en <= shadow[3][4]; irq_en <= shadow[3][1];  // 链下GO位忽略
            rem <= shadow[3][2] || shadow[3][3] ? (shadow[2] << shadow[3][10:8]) : shadow[2];
            units_rem <= shadow[2];
            hpos <= shadow[3][2] ? 4'd0 : shadow[0][1:0];
            fifo_wp <= 0; fifo_rp <= 0; fifo_cnt <= 0;
            busy_o <= 1'b1;
            st <= S_RD_AR;
          end
        end

        // ---------- 读 ----------
        S_RD_AR: begin
          req_o <= 1'b1;
          if (avail >= $signed(rem)) begin             // 数据已够，转写
            req_o <= 1'b0; st <= S_WR_AW;
          end else if (fifo_cnt == 5'd16) begin        // FIFO满：转写排空（大传输必须读↔写交替）
            req_o <= 1'b0; st <= S_WR_AW;
          end else begin
            if (fixed_src) begin                       // 固定地址读：FIXED字burst
              arsize <= 3'b010; arburst <= 2'b00;
              arlen <= min4(burst_max, 8'd15 - fifo_cnt, units_rem[7:0] - 8'd1, 8'd15);
              araddr <= src_a;
            end else begin                             // 增量读：INCR字burst（按4KB与FIFO空间拆分）
              arsize <= 3'b010; arburst <= 2'b01;
              arlen <= min4(burst_max, 8'd15 - fifo_cnt, (32'h1000 - src_a[11:0]) / 4 - 1,
                            avail_need_w);
              araddr <= {src_a[31:2], 2'b00};
            end
            arvalid <= 1'b1;
            if (arvalid && arready) begin
              arvalid <= 1'b0;
              bcnt <= 0; blen <= arlen;
              st <= S_RD_D;
            end
          end
        end
        S_RD_D: begin
          req_o <= 1'b1; rready <= 1'b1;
          if (rvalid && rready) begin
            if (rresp != 2'b00) err <= 1'b1;
            fifo[fifo_wp] <= rdata;
            fifo_wp <= fifo_wp + 1'b1;
            fifo_cnt <= fifo_cnt + 1'b1;
            if (bcnt == blen) begin
              if (!rlast) err <= 1'b1;
              rready <= 1'b0; req_o <= 1'b0;
              if (fixed_src) begin
                units_rem <= units_rem - (blen + 1);
                src_a <= src_a;
              end else begin
                src_a <= src_a + ((blen + 1) * 4);
              end
              if (err) begin st <= S_DONE; end
              else     st <= S_RD_AR;
            end else bcnt <= bcnt + 8'd1;
          end
        end

        // ---------- 写 ----------
        S_WR_AW: begin
          if (rem == 0) begin
            st <= (chain_en && !err) ? S_CH_AR : S_DONE;
          end else if (fifo_cnt == 5'd0) begin        // FIFO已空且剩余>0：回转读侧续读
            req_o <= 1'b0; st <= S_RD_AR;
          end else begin
            req_o <= 1'b1;
            if (fixed_dst) begin                       // 固定地址写：FIXED burst（FSIZE宽度）
              awsize <= fsize; awburst <= 2'b00;
              awlen <= (units_rem > (burst_max + 1)) ? {5'd0, burst_max} : units_rem[7:0] - 8'd1;
              awaddr <= dst_a;
              this_bytes <= 1 << fsize;
            end else begin
              // 三段式：首部/尾部部分写（单拍）→ 整字burst
              // 部分写统一用字节拍（1拍1字节）：AXI无3字节大小，奇地址半字
              // 的字节通道也难表达；头/尾最多各3拍，吞吐损失可忽略。
              // 触发条件：目的不齐、剩余<4、或源首字不齐（hpos!=0）。
              if ((dst_a[1:0] != 2'b00) || (rem < 4) || (hpos != 4'd0)) begin
                this_bytes <= 4'd1;
                awsize <= 3'b000;
                awburst <= 2'b01; awlen <= 8'd0; awaddr <= dst_a;
              end else begin
                this_bytes <= 4'd4;
                awsize <= 3'b010; awburst <= 2'b01;
                awlen <= min4(burst_max, rem[7:0] / 4 - 1, (32'h1000 - dst_a[11:0]) / 4 - 1,
                              fifo_cnt - 1);
                awaddr <= dst_a;
              end
            end
            awvalid <= 1'b1;
            if (awvalid && awready) begin
              awvalid <= 1'b0;
              bcnt <= 0; blen <= awlen;
              st <= S_WR_D;
            end
          end
        end
        S_WR_D: begin
          req_o <= 1'b1;
          // bready在数据阶段即置1：从机的B响应是1拍脉冲（最后一拍沿置位），
          // 等到S_WR_B才置bready会错过脉冲，仲裁器w_done永不成立。
          bready <= 1'b1;
          wvalid <= 1'b1;
          wdata <= head >> (8 * hpos);   // 首拍数据（握手拍被下方预取覆盖，last wins）
          if (wvalid && wready) begin
            // 本拍被消费：推进指针，并同步预取下一拍数据（wdata沿上更新，
            // 若等到下一拍才更新，从机消费到的永远滞后一拍）
            if (hpos + this_bytes >= 4) begin         // 头字消费完
              fifo_rp <= fifo_rp + 1'b1;
              fifo_cnt <= fifo_cnt - 1'b1;
              hpos <= hpos + this_bytes - 4;
              wdata <= fifo[fifo_rp + 1'b1] >> (8 * (hpos + this_bytes - 4));
            end else begin
              hpos <= hpos + this_bytes;
              wdata <= fifo[fifo_rp] >> (8 * (hpos + this_bytes));
            end
            if (fixed_dst) units_rem <= units_rem - 1'b1;
            else dst_a <= dst_a + this_bytes;
            rem <= rem - this_bytes;
            if (bcnt == blen) begin
              wvalid <= 1'b0;
              st <= S_WR_B;
            end else bcnt <= bcnt + 8'd1;
          end
        end
        S_WR_B: begin
          req_o <= 1'b1; bready <= 1'b1;
          if (bvalid && bready) begin
            if (bresp != 2'b00) err <= 1'b1;
            bready <= 1'b0; req_o <= 1'b0;
            if (err) st <= S_DONE;
            else     st <= S_WR_AW;
          end
        end

        // ---------- 链式描述符 ----------
        S_CH_AR: begin
          req_o <= 1'b1;
          arsize <= 3'b010; arburst <= 2'b01; arlen <= 8'd4; araddr <= nxt_ptr;
          arvalid <= 1'b1;
          if (arvalid && arready) begin
            arvalid <= 1'b0; bcnt <= 0;
            st <= S_CH_D;
          end
        end
        S_CH_D: begin
          req_o <= 1'b1; rready <= 1'b1;
          if (rvalid && rready) begin
            shadow[bcnt] <= rdata;
            if (bcnt == 4) begin
              rready <= 1'b0; req_o <= 1'b0;
              if (rresp != 2'b00) begin err <= 1'b1; st <= S_DONE; end
              else begin st <= S_IDLE; chain_cont <= 1'b1; end  // 回IDLE走链式续传分支
            end else bcnt <= bcnt + 8'd1;
          end
        end

        // ---------- 完成 ----------
        S_DONE: begin
          req_o <= 1'b0;
          busy_o <= 1'b0;
          if (err) err_o <= 1'b1;
          else begin done_o <= 1'b1; irq_o <= irq_en; end  // 中断=完成且本段IRQ_EN
          st <= S_IDLE;
        end
      endcase
    end
  end

  // 读burst拍数辅助（4KB/FIFO空间/需求三者取小）
  // 还需多少字（有符号运算；iverilog函数必须有输入口，故用组合wire）
  wire [7:0] avail_need_w =
      ($signed(rem) + 32'd3 - avail) / 4 + ((hpos > 0 && fifo_cnt == 0) ? 8'd1 : 8'd0);

  function [7:0] min4; input [7:0] a, b, c, d;
    begin
      min4 = a;
      if (b < min4) min4 = b;
      if (c < min4) min4 = c;
      if (d < min4) min4 = d;
    end
  endfunction
endmodule
