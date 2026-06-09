`include "ahb_axi_define.v"

module axi2apb_axi #(
	parameter integer ADDR_WIDTH = 32,				// 地址宽度
	parameter integer DATA_WIDTH = 32				// 数据位宽
)(
	// 全局信号
	input 	wire 					ACLK,			// AXI时钟
	input 	wire 					ARESETn,		// AXI复位
	// 写请求通道
	input   wire 					AW_SEL,			// 写片选
	input 	wire 					AW_VALID,		// 写请求有效
	output 	wire 					AW_READY,		// 写请求准备好
	input   wire [2:0]				AW_SIZE,		// 写数据宽度
	input   wire [1:0]				AW_BURST,		// 写传输类型
	input   wire [7:0]				AW_LEN,			// 写数据长度
	input 	wire [ADDR_WIDTH-1:0]	AW_ADDR,		// 写地址
	// 写数据通道
	input 	wire 					W_VALID,		// 写数据有效
	output 	wire 					W_READY,		// 写数据准备好
	input   wire					W_LAST,			// 写数据最后一拍
	input 	wire [DATA_WIDTH-1:0]  	W_DATA,			// 写数据
	// 写响应通道
	output 	wire 					B_VALID,		// 写响应有效
	input 	wire 					B_READY,		// 写响应准备好
	output 	wire [1:0] 				B_RESP,			// 写响应
	// 读请求通道
	input   wire 					AR_SEL,			// 读片选
	input 	wire 					AR_VALID,		// 读请求有效
	output 	wire 					AR_READY,		// 读准备好
	input   wire [2:0]              AR_SIZE,		// 读数据宽度
	input   wire [1:0]              AR_BURST,		// 读传输类型
	input   wire [7:0]              AR_LEN,			// 读传输长度
	input 	wire [ADDR_WIDTH-1:0]	AR_ADDR,		// 读地址
	// 读数据通道
	output 	wire 					R_VALID,		// 读数据有效
	input 	wire 					R_READY,		// 读数据准备好
	output  wire					R_LAST,			// 读数据最后一拍
	output 	wire [DATA_WIDTH-1:0] 	R_DATA,			// 读数据
	output 	reg [1:0] 				R_RESP,			// 读响应信息

	output wire  APBACTIVE,  // APB bus is active, for clock gating of APB bus

	// 从设备测试信号
	output wire						BC_WREQ,		// 写请求
	input wire						BC_WACK,		// 写应答
	output reg [ADDR_WIDTH-1:0] 	BC_WADDR,		// 写地址
	output wire [DATA_WIDTH-1:0] 	BC_WDATA,		// 写数据
	input wire						BC_WRESP,		// 写响应信息
	output wire						BC_RREQ,		// 读请求
	input wire						BC_RACK,		// 读应答
	output reg [ADDR_WIDTH-1:0] 	BC_RADDR,		// 读地址
	input wire [DATA_WIDTH-1:0]		BC_RDATA,		// 读数据
	input wire						BC_RRESP		// 读响应信息
);

	//---------------------<状态机参数>-------------------------------------
	localparam STWA_IDLE	= 3'b001;				// 写请求空闲
	localparam STWA_REQ		= 3'b010;				// 写请求
	localparam STWA_WAIT	= 3'b100;				// 写请求等待(请求数据同步)
	reg [2:0]               stwa_cur;
	reg [2:0]               stwa_next;

	localparam STW_IDLE		= 4'b0001;				// 写操作空闲
	localparam STW_DATA		= 4'b0010;				// 写操作数据
	localparam STW_BURST	= 4'b0100;				// BURST写等待
	localparam STW_RESP		= 4'b1000;				// 写操作响应
	reg [3:0]               stw_cur;
	reg [3:0]               stw_next;

	localparam STR_IDLE		= 5'b00001;				// 读操作空闲
	localparam STR_REQ		= 5'b00010;				// 读操作请求
	localparam STR_DATA		= 5'b00100;				// 读操作数据
	localparam STR_BURST	= 5'b01000;				// BURST读等待
	localparam STR_END		= 5'b10000;				// 读结束
	reg [4:0]               str_cur;
	reg [4:0]               str_next;

	//---------------------<局部变量定义>-------------------------------------
	reg [7:0]               w_beatCNT;				// BUSRT写操作拍数计数器
	reg [7:0]               r_beatCNT;				// BUSRT读操作拍数计数器

	// APB bus is active, for clock gating of APB bus
	assign APBACTIVE = ((stw_next != STW_IDLE) || (stw_cur != STW_IDLE) 
					 || (str_next != STR_IDLE) || (str_cur != STR_IDLE)) ? 1'b1 : 1'b0;

	//############################# 写操作 #################################
	//----------------------------------------------------------------------
	//--   写请求状态机第1段（状态迁移）
	//----------------------------------------------------------------------
	always @(posedge ACLK or negedge ARESETn) begin
		if(!ARESETn) begin
			stwa_cur <= STWA_IDLE;
		end
		else begin
			stwa_cur <= stwa_next;
		end
	end

	//----------------------------------------------------------------------
	//--   写请求状态机第2段（输入对状态的影响）
	//----------------------------------------------------------------------
	always @(*) begin
		stwa_next = stwa_cur;		// 默认保持当前状态，避免LATCH
		case(stwa_cur)
			STWA_IDLE: begin						// 写请求空闲
				if(AW_SEL & AW_VALID)				// 写请求
					stwa_next = STWA_REQ;
			end
			STWA_REQ: begin							// 写请求通道
				stwa_next = STWA_WAIT;
			end
			STWA_WAIT: begin						// 写请求同步
				if(B_VALID & B_READY)begin
					if(AW_SEL & AW_VALID)			// 单拍流水
						stwa_next = STWA_REQ;
					else							// 单拍非流水
						stwa_next = STWA_IDLE;
				end
			end
			default: stwa_next = STWA_IDLE;			// 防御性编程：异常状态恢复
		endcase
	end

	//----------------------------------------------------------------------
	//--    写请求状态机第3段（状态对输出的影响）
	//----------------------------------------------------------------------
	// AXI信号产生
	assign AW_READY = (stwa_next == STWA_REQ) ? 1'b1 : 1'b0;	// 写请求准备好

	// BC地址信号产生
	always @(*) begin
		if(stwa_next == STWA_IDLE) begin
			BC_WADDR = 'h0;
		end
		else if(stwa_next == STWA_REQ)begin
			BC_WADDR = AW_ADDR;						// 采样写首地址
		end
		else if(stwa_next == STWA_WAIT)begin
			if((W_VALID & W_READY))
				BC_WADDR = get_next_addr(BC_WADDR,AW_SIZE,AW_BURST);	// 下一拍地址
		end
	end

	//----------------------------------------------------------------------
	//--   写数据响应状态机第1段（状态迁移）
	//----------------------------------------------------------------------
	always @(posedge ACLK or negedge ARESETn) begin
		if(!ARESETn) begin
			stw_cur <= STW_IDLE;
		end
		else begin
			stw_cur <= stw_next;
		end
	end

	//----------------------------------------------------------------------
	//--   写数据响应状态机第2段（输入对状态的影响）
	//----------------------------------------------------------------------
	always @(*) begin
		stw_next = stw_cur;			// 默认保持当前状态，避免LATCH
		case(stw_cur)
			STW_IDLE: begin							// 写数据空闲
				if(AW_SEL & W_VALID)				// 写数据请求
					stw_next = STW_DATA;
			end
			STW_DATA: begin							// 写数据通道
				if(BC_WACK) begin 
                    if(w_beatCNT >= AW_LEN)	    	// 单拍或者BUSRT最后一拍
                        stw_next = STW_RESP;
                    else					    	// BUSRT写
                        stw_next = STW_BURST;
				end
			end
			STW_BURST: begin						// BURST写
				if(W_VALID)
					stw_next = STW_DATA;
			end
			STW_RESP: begin							// 写响应通道
				if(B_READY)begin
					if(AW_SEL & W_VALID)			// 单拍流水
						stw_next = STW_DATA;
					else	    					// 单拍非流水或者BUSRT最后一拍
						stw_next = STW_IDLE;
				end
			end
			default: stw_next = STW_IDLE;			// 防御性编程：异常状态恢复
		endcase
	end

	// BUSRT写操作拍数计数
	always @(posedge ACLK or negedge ARESETn) begin
		if(!ARESETn) begin
			w_beatCNT <= 'h0; 
		end
		else if((stw_cur == STW_DATA) || (stw_cur == STW_BURST)) begin
			if((W_VALID & W_READY) && (w_beatCNT < AW_LEN))
				w_beatCNT <= w_beatCNT + 1;			// 完成一拍
		end
		else
			w_beatCNT <= 'h0;						// 重置
	end

	//----------------------------------------------------------------------
	//--    写数据响应状态机第3段（状态对输出的影响）
	//----------------------------------------------------------------------
	// AXI信号产生
	assign W_READY = BC_WACK;						// 写数据就绪

	assign B_VALID = (stw_cur == STW_RESP) ? 1'b1 : 1'b0;	// 写响应有效
	assign B_RESP = {BC_WRESP, 1'b0};				// 输出写响应信息

	// BC数据信号产生
	assign BC_WREQ = (stw_next == STW_DATA) || (stw_cur == STW_DATA);	// BC写请求
	assign BC_WDATA = W_DATA;						// 采样写数据


	//############################# 读操作 #################################
	reg						BC_RACK_D1;

	always @(posedge ACLK or negedge ARESETn) begin
		if(!ARESETn) begin
			BC_RACK_D1 <= 1'b0;
		end
		else begin
			BC_RACK_D1 <= BC_RACK;					// 延迟一拍
		end
	end

	//----------------------------------------------------------------------
	//--   状态机第1段（状态迁移）
	//----------------------------------------------------------------------
	always @(posedge ACLK or negedge ARESETn) begin
		if(!ARESETn) begin
			str_cur <= STR_IDLE;
		end
		else begin
			str_cur <= str_next;
		end
	end

	//----------------------------------------------------------------------
	//--   状态机第2段（输入对状态的影响）
	//----------------------------------------------------------------------
	always @(*) begin
		str_next = str_cur;
		case(str_cur)
			STR_IDLE: begin							// 读空闲
				if(AR_SEL & AR_VALID)				// 读请求
					str_next = STR_REQ;
			end
			STR_REQ: begin							// 读请求通道
				str_next = STR_DATA;
			end
			STR_DATA: begin							// 读数据通道
				if(BC_RACK_D1)begin
                    if(r_beatCNT < AR_LEN)			// BURST读
                        str_next = STR_BURST;
					else							// 单拍或者BURST最后一拍
						str_next = STR_END;
                end
			end
			STR_BURST: begin						// BURST读
				str_next = STR_DATA;
			end
			STR_END: begin							// 单拍或者BURST最后一拍
 				if(AR_SEL & AR_VALID)				// 单拍流水
					str_next = STR_REQ;
				else								// 单拍非流水或者BURST最后一拍
					str_next = STR_IDLE;
			end
			default: str_next = STR_IDLE;			// 防御性编程：异常状态恢复
		endcase
	end

	// BUSRT读操作拍数计数
	always @(posedge ACLK or negedge ARESETn) begin
		if(!ARESETn) begin
			r_beatCNT <= 'h0; 
		end
 		else if(str_next == STR_REQ) begin
			r_beatCNT <= 'h0;						// 重置
		end
 		else if(str_next == STR_BURST) begin
			r_beatCNT <= r_beatCNT + 1;				// 完成一拍
		end
	end

	//----------------------------------------------------------------------
	//--   状态机第3段（状态对输出的影响）
	//----------------------------------------------------------------------
	// AXI信号产生
	assign AR_READY = (str_next == STR_REQ) ? 1'b1 : 1'b0;	// 读请求准备好

	assign R_VALID = BC_RREQ & BC_RACK;				// 读数据有效
	assign R_LAST = R_VALID & R_READY & (r_beatCNT == AR_LEN);	// 最后一拍数据
	assign R_DATA = BC_RDATA;						// 输出读数据

	always @(posedge ACLK or negedge ARESETn) begin
		if(!ARESETn) begin
			R_RESP <= 2'b00;
		end
		else if(str_next == STR_BURST)begin
			R_RESP[1] <= BC_RRESP;					// 输出读响应信息
		end
	end

	// BC信号产生
	assign BC_RREQ = (str_next == STR_REQ) || (str_next == STR_DATA) ;	// BC读请求

	always @(*) begin
		if(str_next == STR_IDLE) begin
			BC_RADDR = 'h0;
		end
		else if(str_next == STR_REQ)begin
			BC_RADDR = AR_ADDR;						// 采样读首地址
		end
		else if(str_next == STR_BURST)begin
			BC_RADDR = get_next_addr(BC_RADDR, AR_SIZE, AR_BURST);	// 下一拍地址
		end
	end

	//############################# 基本函数 #################################
    function [ADDR_WIDTH-1:0]   get_next_addr;		// 获取下一拍地址
        input [ADDR_WIDTH-1:0]  addr ;				// 当前地址
        input [ 2:0]            size ;				// size
        input [ 1:0]            burst; 				// burst type
     begin
        case (burst)
        `FIXED_AXI: get_next_addr = addr;     		// 固定地址
        `INCR_AXI: get_next_addr = addr + (1<<size);// 递增地址
        `WRAP_AXI: begin        					// 回绕地址——不支持
               $display($time,,"%m ERROR BURST WRAP not supported");
               end
        `RESERVED_AXI: begin        				// 保留
               get_next_addr = addr;
               $display($time,,"%m ERROR un-defined BURST %01x", burst);
               end
        endcase
    end
    endfunction

endmodule
