// ic_axi_master_arb.v : 双主AXI轮询仲裁器（共享总线式，单事务在途）
// 写/读通道独立授权；授权保持到该事务完成（B握手 / R_LAST握手）
// 无死锁论证：每个grant的master在B/R握手后即释放；从机侧由官方slave mux+默认从机保证响应；
//             W数据仅在grant期间透传，未获授权主机的挂起WVALID不影响总线。
`timescale 1ns/1ps
module ic_axi_master_arb(
    input  wire        ACLK,
    input  wire        ARESETn,
    // ---- 主0（CPU）----
    input  wire        m0_awvalid,  output wire m0_awready,
    input  wire [2:0]  m0_awsize,   input  wire [1:0] m0_awburst,
    input  wire [7:0]  m0_awlen,    input  wire [31:0] m0_awaddr,
    input  wire        m0_wvalid,   output wire m0_wready,
    input  wire        m0_wlast,    input  wire [31:0] m0_wdata,
    output wire        m0_bvalid,   input  wire m0_bready,
    output wire [1:0]  m0_bresp,
    input  wire        m0_arvalid,  output wire m0_arready,
    input  wire [2:0]  m0_arsize,   input  wire [1:0] m0_arburst,
    input  wire [7:0]  m0_arlen,    input  wire [31:0] m0_araddr,
    output wire        m0_rvalid,   input  wire m0_rready,
    output wire        m0_rlast,    output wire [31:0] m0_rdata,
    output wire [1:0]  m0_rresp,
    // ---- 主1（DMA）----
    input  wire        m1_awvalid,  output wire m1_awready,
    input  wire [2:0]  m1_awsize,   input  wire [1:0] m1_awburst,
    input  wire [7:0]  m1_awlen,    input  wire [31:0] m1_awaddr,
    input  wire        m1_wvalid,   output wire m1_wready,
    input  wire        m1_wlast,    input  wire [31:0] m1_wdata,
    output wire        m1_bvalid,   input  wire m1_bready,
    output wire [1:0]  m1_bresp,
    input  wire        m1_arvalid,  output wire m1_arready,
    input  wire [2:0]  m1_arsize,   input  wire [1:0] m1_arburst,
    input  wire [7:0]  m1_arlen,    input  wire [31:0] m1_araddr,
    output wire        m1_rvalid,   input  wire m1_rready,
    output wire        m1_rlast,    output wire [31:0] m1_rdata,
    output wire [1:0]  m1_rresp,
    // ---- 共享主口（接官方 cmsdk_axi_slave_mux）----
    output wire        awvalid,     input  wire awready,
    output wire [2:0]  awsize,      output wire [1:0] awburst,
    output wire [7:0]  awlen,       output wire [31:0] awaddr,
    output wire        wvalid,      input  wire wready,
    output wire        wlast,       output wire [31:0] wdata,
    input  wire        bvalid,      output wire bready,
    input  wire [1:0]  bresp,
    output wire        arvalid,     input  wire arready,
    output wire [2:0]  arsize,      output wire [1:0] arburst,
    output wire [7:0]  arlen,       output wire [31:0] araddr,
    input  wire        rvalid,      output wire rready,
    input  wire        rlast,       input  wire [31:0] rdata,
    input  wire [1:0]  rresp,
    // ---- 调试/评分观测 ----
    output reg  [31:0] m0_done_cnt, m1_done_cnt,   // B/R完成计数
    output reg  [31:0] grant_imbalance              // 累计授权差绝对值
);
  // ============ 写通道仲裁 ============
  reg  w_grant;            // 当前写授权：0=主0, 1=主1
  reg  w_active;           // 写事务进行中
  reg  wrr;                // 轮询指针
  wire w_done = w_active && bvalid && bready;

  always @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin w_grant <= 1'b0; w_active <= 1'b0; wrr <= 1'b0; end
    else begin
      if (!w_active) begin
        if (m0_awvalid || m1_awvalid) begin
          if (m0_awvalid && m1_awvalid) begin w_grant <= wrr; wrr <= ~wrr; end
          else                          w_grant <= m0_awvalid ? 1'b0 : 1'b1;
          w_active <= 1'b1;
        end
      end else if (w_done) begin
        w_active <= 1'b0;
      end
    end
  end

  // 写通道mux（授权期间透传）
  assign awvalid = w_active ? (w_grant ? m1_awvalid : m0_awvalid) : 1'b0;
  assign awsize  = w_grant ? m1_awsize  : m0_awsize;
  assign awburst = w_grant ? m1_awburst : m0_awburst;
  assign awlen   = w_grant ? m1_awlen   : m0_awlen;
  assign awaddr  = w_grant ? m1_awaddr  : m0_awaddr;
  assign m0_awready = w_active && !w_grant && awready;
  assign m1_awready = w_active &&  w_grant && awready;

  assign wvalid = w_active ? (w_grant ? m1_wvalid : m0_wvalid) : 1'b0;
  assign wlast  = w_grant ? m1_wlast  : m0_wlast;
  assign wdata  = w_grant ? m1_wdata  : m0_wdata;
  assign m0_wready = w_active && !w_grant && wready;
  assign m1_wready = w_active &&  w_grant && wready;

  assign m0_bvalid = w_active && !w_grant && bvalid;
  assign m1_bvalid = w_active &&  w_grant && bvalid;
  assign m0_bresp  = bresp;
  assign m1_bresp  = bresp;
  assign bready    = w_active ? (w_grant ? m1_bready : m0_bready) : 1'b1;

  // ============ 读通道仲裁 ============
  reg  r_grant;
  reg  r_active;
  reg  rrr;
  wire r_done = r_active && rvalid && rready && rlast;

  always @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin r_grant <= 1'b0; r_active <= 1'b0; rrr <= 1'b0; end
    else begin
      if (!r_active) begin
        if (m0_arvalid || m1_arvalid) begin
          if (m0_arvalid && m1_arvalid) begin r_grant <= rrr; rrr <= ~rrr; end
          else                          r_grant <= m0_arvalid ? 1'b0 : 1'b1;
          r_active <= 1'b1;
        end
      end else if (r_done) r_active <= 1'b0;
    end
  end

  assign arvalid = r_active ? (r_grant ? m1_arvalid : m0_arvalid) : 1'b0;
  assign arsize  = r_grant ? m1_arsize  : m0_arsize;
  assign arburst = r_grant ? m1_arburst : m0_arburst;
  assign arlen   = r_grant ? m1_arlen   : m0_arlen;
  assign araddr  = r_grant ? m1_araddr  : m0_araddr;
  assign m0_arready = r_active && !r_grant && arready;
  assign m1_arready = r_active &&  r_grant && arready;

  assign m0_rvalid = r_active && !r_grant && rvalid;
  assign m1_rvalid = r_active &&  r_grant && rvalid;
  assign m0_rlast  = rlast;
  assign m1_rlast  = rlast;
  assign m0_rdata  = rdata;
  assign m1_rdata  = rdata;
  assign m0_rresp  = rresp;
  assign m1_rresp  = rresp;
  assign rready    = r_active ? (r_grant ? m1_rready : m0_rready) : 1'b1;

  // ============ 调试观测 ============
  always @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      m0_done_cnt <= 0; m1_done_cnt <= 0; grant_imbalance <= 0;
    end else begin
      if (w_done) begin
        if (!w_grant) m0_done_cnt <= m0_done_cnt + 1'b1;
        else          m1_done_cnt <= m1_done_cnt + 1'b1;
      end
      if (r_done) begin
        if (!r_grant) m0_done_cnt <= m0_done_cnt + 1'b1;
        else          m1_done_cnt <= m1_done_cnt + 1'b1;
      end
      if (w_done || r_done) begin
        if (m0_done_cnt > m1_done_cnt) grant_imbalance <= m0_done_cnt - m1_done_cnt;
        else                           grant_imbalance <= m1_done_cnt - m0_done_cnt;
      end
    end
  end
endmodule
