//------------------------------------------------------------------------------
// The confidential and proprietary information contained in this file may
// only be used by a person authorised under and to the extent permitted
// by a subsisting licensing agreement from ARM Limited.
//
//            (C) COPYRIGHT 2010-2015  ARM Limited or its affiliates.
//                ALL RIGHTS RESERVED
//
// This entire notice must be reproduced on all copies of this file
// and copies of this file may only be made by a person if such person is
// permitted to do so under the terms of a subsisting license agreement
// from ARM Limited.
//
//  Version and Release Control Information:
//
//  File Revision       : $Revision: 275084 $
//  File Date           : $Date: 2014-03-27 15:09:11 +0000 (Thu, 27 Mar 2014) $
//
//  Release Information : Cortex-M0 DesignStart-r1p0-00rel0
//------------------------------------------------------------------------------
// Verilog-2001 (IEEE Std 1364-2001)
//------------------------------------------------------------------------------
//
//------------------------------------------------------------------------------
// Cortex-M0 DesignStart processor macro cell level
//------------------------------------------------------------------------------

module cortexm0ds (
    // CLOCK AND RESETS ------------------
    input  wire             ACLK,               // Clock
    input  wire             ARESETn,            // Asynchronous reset

    //----------------- AXI - Write -----------------
    output wire             AW_VALID,           // Write request valid
    input wire              AW_READY,           // Write request ready
    output wire [2:0]       AW_SIZE,            // Write data size
    output wire [1:0]       AW_BURST,           // Write burst type
    output wire [7:0]       AW_LEN,             // Write burst length
    output wire [31:0]      AW_ADDR,            // Write address
    output wire             W_VALID,            // Write data valid
    input wire              W_READY,            // Write data ready
    output wire             W_LAST,             // Write data last
    output wire [31:0]      W_DATA,             // Write data
    input wire              B_VALID,            // Write response valid
    output wire             B_READY,            // Write response ready
    input wire  [1:0]       B_RESP,             // Write response

    //----------------- AXI - Read ------------------
    output wire             AR_VALID,           // Read request valid
    input wire              AR_READY,           // Read request ready
    output wire [2:0]       AR_SIZE,            // Read data size
    output wire [1:0]       AR_BURST,           // Read burst type
    output wire [7:0]       AR_LEN,             // Read burst length
    output wire [31:0]      AR_ADDR,            // Read address
    input wire              R_VALID,            // Read data valid
    output wire             R_READY,            // Read data ready
    input wire              R_LAST,             // Read data last
    input wire  [31:0]      R_DATA,             // Read data
    input wire  [1:0]       R_RESP,             // Read response

    // MISCELLANEOUS ---------------------
    input  wire             NMI,                // Non-maskable interrupt input
    input  wire [31:0]      IRQ,                // Interrupt request inputs
    output wire             TXEV,               // Event output (SEV executed)
    input  wire             RXEV,               // Event input
    output wire             LOCKUP,             // Core is locked-up
    output wire             SYSRESETREQ,        // System reset request
    input  wire             STCLKEN,            // SysTick SCLK clock enable
    input  wire [25:0]      STCALIB,            // SysTick calibration register value
    
    // POWER MANAGEMENT ------------------  
    output wire             SLEEPING            // Core and NVIC sleeping
    );

    // ------------------------------------------------------------
    // AHB-LITE MASTER PORT
    // ------------------------------------------------------------
    wire                HCLK;   		// 时钟信号
    wire                HRESETn;		// 复位信号
    wire [ 1:0]         HTRANS;         // 传输模式
    wire [ 2:0]         HSIZE;          // 数据宽度
    wire [ 2:0]         HBURST;         // 突发模式
    wire                HWRITE;         // 传输方向  
    wire [31:0]         HADDR;          // 地址
    wire [31:0]         HWDATA;         // 写数据
    wire                HREADY;         // 准备好
    wire [31:0]         HRDATA;         // 读数据
    wire                HRESP;          // 响应

	// 主设备测试信号
	wire [1:0]	        MC_TRANS;	    // 传输模式
	wire [2:0]	        MC_SIZE;	    // 数据宽度
	wire [2:0]	        MC_BURST;	    // burst类型
	wire 		        MC_REQ;		    // 请求信号
 	wire 				MC_AACK;		// 地址段应答信号（地址段最后一个周期）
 	wire 				MC_DACK;		// 数据段应答信号（数据段最后一个周期）
	wire 		        MC_W_R;		    // 写读信号
	wire [31:0]         MC_ADDR;	    // 地址
	wire [31:0]         MC_WDATA;	    // 写数据
	wire [31:0]         MC_RDATA;	    // 读数据
	wire	 	        MC_RESP;	    // 响应信息

    // ------------------------------------------------------------
	parameter integer ADDR_WIDTH = 32;	// 地址宽度
	parameter integer DATA_WIDTH = 32;	// 数据位宽
	parameter integer CLK_PERIOD = 10;	// 时钟周期，时钟频率为100MHz

    assign HCLK = ACLK;
    assign HRESETn = ARESETn;

    assign TXEV = 1'b0;
    assign LOCKUP = 1'b0;
    assign SYSRESETREQ = 1'b0;
    assign SLEEPING = 1'b0;

	// ------------------------------------------------------------
	// Cortex-M0 processor instantiation
	// ------------------------------------------------------------
	// 测试主控制器
	Master_Controller
		#(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .CLK_PERIOD(CLK_PERIOD))
		u_Master_Controller(
			.HCLK		(HCLK),
			.HRESETn	(HRESETn),
			
			.MC_TRANS	(MC_TRANS),	
			.MC_SIZE	(MC_SIZE),	
			.MC_BURST	(MC_BURST),	
			.MC_REQ		(MC_REQ),
			.MC_AACK	(MC_AACK),
			.MC_DACK	(MC_DACK),
			.MC_W_R		(MC_W_R),
			.MC_ADDR	(MC_ADDR),
			.MC_WDATA	(MC_WDATA),	
			.MC_RDATA	(MC_RDATA),	
			.MC_RESP	(MC_RESP)
		);

	// AHB主接口
	AHB_Lite_Master_IF 
		#(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH))
		u_AHB_MASTER_IF(
			.HCLK		(HCLK),
			.HRESETn	(HRESETn),

			.HTRANS		(HTRANS),
			.HBURST		(HBURST),
			.HSIZE		(HSIZE),
			.HWRITE		(HWRITE),
			.HADDR		(HADDR),
			.HWDATA		(HWDATA),
			.HREADY		(HREADY),
			.HRDATA		(HRDATA),
			.HRESP		(HRESP),
			
			.MC_TRANS	(MC_TRANS),
			.MC_SIZE	(MC_SIZE),
			.MC_BURST	(MC_BURST),
			.MC_REQ		(MC_REQ),
			.MC_AACK	(MC_AACK),
			.MC_DACK	(MC_DACK),
			.MC_W_R		(MC_W_R),
			.MC_ADDR	(MC_ADDR),
			.MC_WDATA	(MC_WDATA),
			.MC_RDATA	(MC_RDATA),
			.MC_RESP	(MC_RESP)
		);

 
    // ------------------------------------------------------------
    // ABH slave <-> AXI master interface
    // ------------------------------------------------------------
    ahb2axi4_if 
     u_ahb2axi4_if
    (
        // --------------------- AHB ---------------------
        .HCLK               (HCLK),
        .HRESETn            (HRESETn),
        .HSEL               (1'b1),
        .HTRANS             (HTRANS[1:0]),
        .HSIZE              (HSIZE[2:0]),
        .HBURST             (HBURST[2:0]),
        .HWRITE             (HWRITE), 
        .HREADY             (HREADY),
        .HADDR              (HADDR[31:0]),
        .HWDATA             (HWDATA[31:0]),
        .HREADYOUT          (HREADY),
        .HRDATA             (HRDATA[31:0]),
        .HRESP              (HRESP),

        // --------------------- AXI ---------------------
        .ACLK               (ACLK),
        .ARESETn            (ARESETn),
        
        //----------------- AXI - Write -----------------
        .AW_VALID           (AW_VALID),
        .AW_READY           (AW_READY),
        .AW_SIZE            (AW_SIZE),
        .AW_BURST           (AW_BURST),
        .AW_LEN             (AW_LEN),
        .AW_ADDR            (AW_ADDR),
        .W_VALID            (W_VALID),
        .W_READY            (W_READY),
        .W_LAST             (W_LAST),
        .W_DATA             (W_DATA),
        .B_VALID            (B_VALID),
        .B_READY            (B_READY),
        .B_RESP             (B_RESP),

        //----------------- AXI - Read ------------------
        .AR_VALID           (AR_VALID),
        .AR_READY           (AR_READY),
        .AR_SIZE            (AR_SIZE),
        .AR_BURST           (AR_BURST),
        .AR_LEN             (AR_LEN),
        .AR_ADDR            (AR_ADDR),
        .R_VALID            (R_VALID),
        .R_READY            (R_READY),
        .R_LAST             (R_LAST),
        .R_DATA             (R_DATA),
        .R_RESP             (R_RESP)
    );

endmodule
// ---------------------------------------------------------------
// EOF     
// ---------------------------------------------------------------
           