`include "ahb_axi_define.v"

module AHB_Lite_Master_IF #(
	parameter integer ADDR_WIDTH = 32,				// 地址位宽
	parameter integer DATA_WIDTH = 32				// 数据位宽
)(
	// 全局信号
	input wire						HCLK,			// 时钟信号
	input wire						HRESETn,		// 复位信号

	// AHB-lite Master Interface
	output wire [1:0]				HTRANS,			// 传输模式
	output wire [2:0]				HSIZE,			// 数据宽度
	output wire [2:0]				HBURST,			// 突发模式
	output wire						HWRITE,			// 传输方向
	output wire [ADDR_WIDTH-1:0]	HADDR,			// 地址
	output wire [DATA_WIDTH-1:0]	HWDATA,			// 写数据
	input wire  					HREADY,			// 准备好
	input wire [DATA_WIDTH-1:0]		HRDATA,			// 读数据
	input wire  					HRESP,			// 响应
	
	// 仿真输入信号
	input wire [1:0]				MC_TRANS,		// 传输模式
	input wire [2:0] 				MC_SIZE,		// 数据宽度
	input wire [2:0] 				MC_BURST,		// burst类型
    input wire						MC_REQ,			// 请求信号
 	output wire						MC_ACK,			// 应答信号（数据段最后一个周期）
	input wire						MC_W_R,			// 写读信号
    input wire[ADDR_WIDTH-1:0]		MC_ADDR,		// 地址
    input wire[DATA_WIDTH-1:0]		MC_WDATA,		// 写数据
    output wire[DATA_WIDTH-1:0]		MC_RDATA,		// 读数据
    output wire	 					MC_RESP			// 错误标志 
);
	
	//---------------------<状态机参数>-------------------------------------
	localparam STA_IDLE		= 2'b01;				// 空闲
	localparam STA_ADDR		= 2'b10;				// 地址段
	//---------------------<状态定义>---------------------------------------
	reg  [1:0]              sta_cur;
	reg  [1:0]              sta_next;

	//---------------------<状态机参数>-------------------------------------
	localparam STD_IDLE		= 2'b01;				// 空闲
	localparam STD_DATA		= 2'b10;				// 数据段
	//---------------------<状态定义>---------------------------------------
	reg  [1:0]              std_cur;
	reg  [1:0]              std_next;

	// 局部变量
	wire					dataREQ;
 

	//############################# 地址段传输操作 #################################
	//----------------------------------------------------------------------
	//--   状态机第1段（状态迁移）
	//----------------------------------------------------------------------
	always @(posedge HCLK or negedge HRESETn)begin
		if(~HRESETn)begin
			sta_cur <= STA_IDLE;
		end
		else begin
			sta_cur <= sta_next;
		end
	end

	//----------------------------------------------------------------------
	//--   状态机第2段（输入对状态的影响）
	//----------------------------------------------------------------------
	always @(*) begin
		sta_next = sta_cur;			// 下面有不完全赋值，这样可以避免LATCH
		case(sta_cur)
			STA_IDLE: begin							// 空闲
				if(MC_REQ)begin						// 事务启动
					sta_next = STA_ADDR;
				end
			end
			STA_ADDR: begin							// 写地址段
				if(!MC_REQ)							// BURST传输完毕
					sta_next = STA_IDLE;
			end
			default: sta_next = STA_IDLE;			// 防御性编程
		endcase
	end

	//----------------------------------------------------------------------
	//--   状态机第3段（状态对输出的影响）
	//----------------------------------------------------------------------
	// AHB信号产生
	assign HTRANS = MC_TRANS;
	assign HSIZE  = MC_SIZE;
	assign HBURST = MC_BURST;
	assign HWRITE = MC_W_R; 						// 写
	assign HADDR  = MC_ADDR;

	// 地址段到数据段同步信号产生
	assign dataREQ = MC_REQ;

	//############################# 数据段传输操作 #################################
	//----------------------------------------------------------------------
	//--   状态机第1段（状态迁移）
	//----------------------------------------------------------------------
	always @(posedge HCLK or negedge HRESETn)begin
		if(~HRESETn)begin
			std_cur <= STD_IDLE;
		end
		else begin
			std_cur <= std_next;
		end
	end

	//----------------------------------------------------------------------
	//--   状态机第2段（输入对状态的影响）
	//----------------------------------------------------------------------
	always @(*) begin
		std_next = std_cur;			// 下面有不完全赋值，这样可以避免LATCH
		case(std_cur)
			STD_IDLE: begin							// 空闲
				if(dataREQ)
					std_next = STD_DATA;
			end
			STD_DATA: begin							// 写数据段
				if (HREADY & (!dataREQ))			// 传输完毕
					std_next = STD_IDLE;
			end
			default: std_next = STD_IDLE;			// 防御性编程
		endcase
	end

	//----------------------------------------------------------------------
	//--   状态机第3段（状态对输出的影响）
	//----------------------------------------------------------------------
	// AHB信号产生
	assign HWDATA = MC_WDATA;

	// MC信号产生
	assign MC_ACK  = ((sta_next == STA_ADDR) | (std_cur == STD_DATA)) & HREADY;
	assign MC_RDATA = HRDATA;						// 采样数据
	assign MC_RESP = HRESP;							// 出错

endmodule