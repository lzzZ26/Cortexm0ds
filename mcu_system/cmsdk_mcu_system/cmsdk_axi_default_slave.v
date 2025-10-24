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
//-----------------------------------------------------------------------------
// Abstract : AXI-Lite Default Slave
//-----------------------------------------------------------------------------
//
// Returns an error response when selected for a transfer
//

module cmsdk_axi_default_slave(
	// 全局信号
	input 	wire 					ACLK,			// 时钟	
	input 	wire 					ARESETn,		// 复位	
	// 写请求通道
	input 	wire 					AW_SEL,			// 写片选
 	input 	wire 					AW_VALID,		// 写请求有效
	output 	wire 					AW_READY,		// 写请求就绪
	input   wire [7:0]				AW_LEN,			// 写操作拍数
	// 写数据通道
	input 	wire 					W_VALID,		// 写数据有效
	output 	wire 					W_READY,		// 写数据就绪
	// 写响应通道
	output 	wire 					B_VALID,		// 写响应有效
	input 	wire 					B_READY,		// 写响应就绪
	output 	wire [1:0] 				B_RESP,			// 写响应
	// 读请求通道
	input 	wire 					AR_SEL,			// 读片选
	input 	wire 					AR_VALID,		// 读请求有效
	output 	wire 					AR_READY,		// 读请求就绪
	// 读数据通道
	output 	wire 					R_VALID,		// 读数据有效
	input 	wire 					R_READY,		// 读数据就绪
	output 	wire 					R_LAST,			// 最后一拍数据
	input   wire [7:0]              AR_LEN,			// 读操作拍数
	output 	wire [31:0] 			R_DATA,			// 读数据
	output 	wire [1:0] 				R_RESP			// 读响应
);

	//---------------------<状态机参数>-------------------------------------
	localparam STWA_IDLE	= 3'b001;				// 写请求空闲
	localparam STWA_REQ		= 3'b010;				// 写请求
	localparam STWA_WAIT	= 3'b100;				// 写请求等待
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


	//############################# 写操作 #################################
	reg						B_VALID_D1, B_READY_D1;
	always @(posedge ACLK or negedge ARESETn) begin
		if(!ARESETn) begin
			B_VALID_D1 <= 1'b0;
			B_READY_D1 <= 1'b0;
		end
		else begin
			B_VALID_D1 <= B_VALID;					// 延迟一拍
			B_READY_D1 <= B_READY;					// 延迟一拍
		end
	end

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
		stwa_next = stwa_cur;		// 下面有不完全赋值，这样可以避免LATCH
		case(stwa_cur)
			STWA_IDLE: begin						// 写请求空闲
				if(AW_SEL & AW_VALID)				// 写请求
					stwa_next = STWA_REQ;
			end
			STWA_REQ: begin							// 写请求通道
				stwa_next = STWA_WAIT;
			end
			STWA_WAIT: begin						// 写请求同步
				if(B_VALID_D1 & B_READY_D1)begin
					if(AW_SEL & AW_VALID)			// 单拍流水
						stwa_next = STWA_REQ;
					else							// 单拍非流水
						stwa_next = STWA_IDLE;
				end
			end
			default: stwa_next = STWA_IDLE;			// 防御性编程
		endcase
	end

	//----------------------------------------------------------------------
	//--   写请求状态机第3段（状态对输出的影响）
	//----------------------------------------------------------------------
	// AXI信号产生
	assign AW_READY = (stwa_next == STWA_REQ) ? 1'b1 : 1'b0;	// 写请求准备好

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
		stw_next = stw_cur;			// 下面有不完全赋值，这样可以避免LATCH
		case(stw_cur)
			STW_IDLE: begin							// 写数据空闲
				if(AW_SEL & W_VALID)				// 写数据请求
					stw_next = STW_DATA;
			end
			STW_DATA: begin							// 写数据通道
				if(w_beatCNT >= AW_LEN)				// 单拍或者BUSRT最后一拍
					stw_next = STW_RESP;
				else								// BUSRT写
					stw_next = STW_BURST;
			end
			STW_BURST: begin						// BURST写
				if(W_VALID)
					stw_next = STW_DATA;
			end
			STW_RESP: begin							// 写响应通道
				if(B_READY_D1)begin
					if(AW_SEL & W_VALID)			// 单拍流水
						stw_next = STW_DATA;
					else							// 单拍非流水或者BUSRT最后一拍
						stw_next = STW_IDLE;
				end
			end
			default: stw_next = STW_IDLE;			// 防御性编程
		endcase
	end

	// BUSRT写操作拍数计数
	always @(posedge ACLK or negedge ARESETn) begin
		if(!ARESETn) begin
			w_beatCNT <= 'h0; 
		end
		else if((stw_cur == STW_DATA) ||(stw_cur == STW_BURST)) begin
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
	assign W_READY = (stw_next == STW_DATA) ? 1'b1 : 1'b0;	// 写数据准备好

	assign B_VALID = (stw_next == STW_RESP) ? 1'b1 : 1'b0;	// 写响应准备好
	assign B_RESP = 2'b11;   		// 一个未被控制的错误，通常地址解码为无效地址。


	//############################# 读操作 #################################
	//----------------------------------------------------------------------
	//--   状态机第1段（状态迁移）
	//----------------------------------------------------------------------
	always @(posedge ACLK or negedge ARESETn)begin
		if(!ARESETn)begin
			str_cur <= STR_IDLE;
		end
		else begin
			str_cur <= str_next;
		end
	end

	//----------------------------------------------------------------------
	//--   状态机第2段（输入对状态的影响）
	//----------------------------------------------------------------------
	always @(*)begin
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
				if(r_beatCNT < AR_LEN)				// BURST读
					str_next = STR_BURST;
				else if(AR_SEL & AR_VALID)			// 单拍流水
					str_next = STR_REQ;
				else								// 单拍非流水或者BURST最后一拍
					str_next = STR_IDLE;
			end
			STR_BURST: begin						// BURST读
				str_next = STR_DATA;
			end
			default: str_next = STR_IDLE;			// 防御性编程
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
			r_beatCNT <= r_beatCNT + 1;		    	// 完成一拍
		end
	end

	//----------------------------------------------------------------------
	//--   状态机第3段（状态对输出的影响）
	//----------------------------------------------------------------------
	// AXI信号产生
	assign AR_READY = (str_next == STR_REQ) ? 1'b1 : 1'b0;		// 读请求准备好

	assign R_VALID = (str_next == STR_DATA) ? 1'b1 : 1'b0;		// 读数据准备好
	assign R_LAST = R_VALID & R_READY & (r_beatCNT == AR_LEN);	// 最后一拍数据
    assign R_DATA = 32'h00000000; 		// Default slave do not have read data
	assign R_RESP = 2'b11;   			// 一个未被控制的错误，通常地址解码为无效地址。

endmodule
