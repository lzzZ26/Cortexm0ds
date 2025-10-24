//---------------------------------------------------------------
// 请求（REQ）-应答（ACK）协议，信息：控制信息、地址信息、数据信息、响应信息
//             __    __    __    __    __    __    __    __
// CLK      __|  |__|  |__|  |__|  |__|  |__|  |__|  |__|  |__
//             _____
// MC_REQ   __|     |_________________________________________
//             _____       _____
// MC_ACK   __|     |_____|     |_____________________________
//            _______
// MC_ADDR  XX___A___XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
//                   ___________
// MC_WDATA XXXXXXXXX__DW_______XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
//                         _____
// MC_RDATA XXXXXXXXXXXXXXX_DR__XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
//                         _____
// MC_RESP  XXXXXXXXXXXXXXX_RR__XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
// 
//---------------------------------------------------------------
`timescale 1ns/100ps  		// 时间精度（必须有）
`include "ahb_axi_define.v"

module Master_Controller #(
	parameter integer ADDR_WIDTH = 32,				// 地址位宽
	parameter integer DATA_WIDTH = 32,				// 数据位宽
	parameter integer CLK_PERIOD = 10,				// 时钟周期，时钟频率为100MHz
	parameter integer REGS_NUM   = 256				// 存储器数量(4字节对齐)
)(
	// 全局信号
	input wire	 					clk,			// 时钟信号
	input wire 						rst_n,			// 复位信号

	// 仿真输出信号
	output reg [1:0]				MC_TRANS,		// 传输模式
	output reg [2:0]				MC_SIZE,		// 数据宽度
	output reg [2:0]				MC_BURST,		// burst类型
    output reg  					MC_REQ,			// 请求信号
 	input  wire						MC_ACK,			// 应答信号
    output reg  					MC_W_R,			// 写读信号
    output reg [ADDR_WIDTH-1:0]		MC_ADDR,		// 地址
    output reg [DATA_WIDTH-1:0]		MC_WDATA,		// 写数据
    input wire [DATA_WIDTH-1:0]		MC_RDATA,		// 读数据
	input wire  		 			MC_RESP			// 错误标志 
);

	localparam BASEADDR_Flash   = 32'h0000_0000;	// Flash起始地址，64KB
	localparam BASEADDR_SRAM    = 32'h2000_0000;	// SRAM起始地址，64KB
	localparam BASEADDR_APB     = 32'h4000_0000;	// APB子系统起始地址，64KB
	localparam BASEADDR_GPIO0   = 32'h4001_0000;	// GPIO0起始地址，4KB
	localparam BASEADDR_GPIO1   = 32'h4001_1000;	// GPIO1起始地址，4KB
	localparam BASEADDR_UART4   = 32'h4001_2000;	// UART4起始地址，4KB
	localparam BASEADDR_SYSCTRL = 32'h4001_F000;	// SYSCTRL起始地址，4KB
	localparam BASEADDR_SYSROM  = 32'hF000_0000;	// SYSROM起始地址，4KB
	localparam BASEADDR_TEST    = 32'h9000_0000;	// 无效区域测试

	// 局部变量
	reg [ADDR_WIDTH-1:0] 	BASEADDR = BASEADDR_SRAM;
	reg [DATA_WIDTH-1:0] 	DATA_MEM[0:REGS_NUM-1];	// 寄存器数组
	integer i;

	initial begin
		for (i = 0; i < REGS_NUM; i = i + 1) begin
			DATA_MEM[i] = 32'hff000000 + (i<<8);
		end
		DATA_MEM[00] = 32'ha55a_5aa5;
		DATA_MEM[01] = 32'h1111_1111;
		DATA_MEM[02] = 32'h2222_2222;
		DATA_MEM[03] = 32'h3333_3333;
		DATA_MEM[04] = 32'h4444_4444;
		DATA_MEM[05] = 32'h5555_5555;
		DATA_MEM[06] = 32'h6666_6666;
		DATA_MEM[07] = 32'h7777_7777;
		DATA_MEM[08] = 32'h8888_8888;
		DATA_MEM[09] = 32'h9999_9999;
		DATA_MEM[10] = 32'haaaa_aaaa;
		DATA_MEM[11] = 32'hbbbb_bbbb;
		DATA_MEM[12] = 32'hcccc_cccc;
		DATA_MEM[13] = 32'hdddd_dddd;
		DATA_MEM[14] = 32'heeee_eeee;
		DATA_MEM[15] = 32'hffff_ffff;
	end

	initial begin
		MC_REQ = 1'b0; 
		MC_TRANS = `IDLE;
		MC_BURST = `SINGLE;
		MC_SIZE = `BYTE_4;							// 必须4字节对齐
		MC_W_R = 1'b1;
		MC_ADDR = 'h04;
		MC_WDATA = 'h0;

		repeat(10) @(posedge clk);					// 延迟5个时钟周期等待复位完成

		// 基本传输-单拍操作-写数据
		MC_WRITE_SINGLE(BASEADDR+32'h00, 32'h5aa5_a55a);	repeat(2) @(posedge clk);
		MC_WRITE_SINGLE(BASEADDR+32'h04, 32'h1111_1111);	repeat(2) @(posedge clk);
		MC_WRITE_SINGLE(BASEADDR+32'h08, 32'h2222_2222);	repeat(2) @(posedge clk);
		MC_WRITE_SINGLE(BASEADDR+32'h0c, 32'h3333_3333);	repeat(2) @(posedge clk);
		MC_WRITE_SINGLE(BASEADDR+32'h10, 32'h4444_4444);	repeat(2) @(posedge clk);
		MC_WRITE_SINGLE(BASEADDR+32'h14, 32'h5555_5555);	repeat(2) @(posedge clk);
		MC_WRITE_SINGLE(BASEADDR+32'h18, 32'h6666_6666);	repeat(2) @(posedge clk);
		MC_WRITE_SINGLE(BASEADDR+32'h1c, 32'h7777_7777);	repeat(2) @(posedge clk);
		MC_WRITE_SINGLE(BASEADDR+32'h20, 32'h8888_8888);	repeat(2) @(posedge clk);
		MC_WRITE_SINGLE(BASEADDR+32'h24, 32'h9999_9999);	repeat(2) @(posedge clk);
		MC_WRITE_SINGLE(BASEADDR+32'h28, 32'haaaa_aaaa);	repeat(2) @(posedge clk);
		MC_WRITE_SINGLE(BASEADDR+32'h2c, 32'hbbbb_bbbb);	repeat(2) @(posedge clk);
		MC_WRITE_SINGLE(BASEADDR+32'h30, 32'hcccc_cccc);	repeat(2) @(posedge clk);
		MC_WRITE_SINGLE(BASEADDR+32'h34, 32'hdddd_dddd);	repeat(2) @(posedge clk);
		MC_WRITE_SINGLE(BASEADDR+32'h38, 32'heeee_eeee);	repeat(2) @(posedge clk);
		MC_WRITE_SINGLE(BASEADDR+32'h3c, 32'hffff_ffff);	repeat(2) @(posedge clk);
		repeat(10) @(posedge clk);	

		// 基本传输-流水操作-写数据
		MC_WRITE_FLOW;
		repeat(10) @(posedge clk);	

		// BURST传输-写数据，首地址BASEADDR+32'h80，突发类型为INCR16
		MC_WRITE_BURST(BASEADDR+32'h80, `INCR16);
		repeat(10) @(posedge clk);	

		// 基本传输-单拍操作-读数据
		MC_READ_SINGLE(BASEADDR+32'h00, 32'h5aa5_a55a);		repeat(2) @(posedge clk);
		MC_READ_SINGLE(BASEADDR+32'h04, 32'h1111_1111);		repeat(2) @(posedge clk);
		MC_READ_SINGLE(BASEADDR+32'h08, 32'h2222_2222);		repeat(2) @(posedge clk);
		MC_READ_SINGLE(BASEADDR+32'h0c, 32'h3333_3333);		repeat(2) @(posedge clk);
		MC_READ_SINGLE(BASEADDR+32'h10, 32'h4444_4444);		repeat(2) @(posedge clk);
		MC_READ_SINGLE(BASEADDR+32'h14, 32'h5555_5555);		repeat(2) @(posedge clk);
		MC_READ_SINGLE(BASEADDR+32'h18, 32'h6666_6666);		repeat(2) @(posedge clk);
		MC_READ_SINGLE(BASEADDR+32'h1c, 32'h7777_7777);		repeat(2) @(posedge clk);
		MC_READ_SINGLE(BASEADDR+32'h20, 32'h8888_8888);		repeat(2) @(posedge clk);
		MC_READ_SINGLE(BASEADDR+32'h24, 32'h9999_9999);		repeat(2) @(posedge clk);
		MC_READ_SINGLE(BASEADDR+32'h28, 32'haaaa_aaaa);		repeat(2) @(posedge clk);
		MC_READ_SINGLE(BASEADDR+32'h2c, 32'hbbbb_bbbb);		repeat(2) @(posedge clk);
		MC_READ_SINGLE(BASEADDR+32'h30, 32'hcccc_cccc);		repeat(2) @(posedge clk);
		MC_READ_SINGLE(BASEADDR+32'h34, 32'hdddd_dddd);		repeat(2) @(posedge clk);
		MC_READ_SINGLE(BASEADDR+32'h38, 32'heeee_eeee);		repeat(2) @(posedge clk);
		MC_READ_SINGLE(BASEADDR+32'h3c, 32'hffff_ffff);		repeat(2) @(posedge clk);
		repeat(10) @(posedge clk);	

		// 基本传输-流水操作-读数据
		MC_READ_FLOW;
		repeat(10) @(posedge clk);	

		// BURST传输-读数据，首地址BASEADDR+32'h80，突发类型为INCR16
		MC_READ_BURST(BASEADDR+32'h80, `INCR16);
		repeat(10) @(posedge clk);	

		// 基本传输-流水操作-写_读数据
		MC_W_R_FLOW;
		repeat(10) @(posedge clk);	

		$finish;
	end


	//----------------------------------------------------------------------
	//----------------------------------------------------------------------
	task MC_WRITE_SINGLE;	// 基本传输-单拍操作-写数据
	input [ADDR_WIDTH-1:0] 	t_addr;
	input [DATA_WIDTH-1:0] 	w_data;
	begin
		MC_WRITE_ADDR(t_addr, `NONSEQ, `SINGLE);
		MC_WRITE_DATA(t_addr, w_data);
	end
	endtask

	//----------------------------------------------------------------------
	task MC_READ_SINGLE;	// 基本传输-单拍操作-读数据
	input [ADDR_WIDTH-1:0] 	t_addr;
	input [DATA_WIDTH-1:0] 	w_data;
	begin
		MC_READ_ADDR(t_addr, `NONSEQ, `SINGLE);
		MC_READ_DATA(t_addr, w_data);		
	end
	endtask

	task MC_WRITE_FLOW;		// 基本传输-流水操作-写数据
	begin
		MC_WRITE_ADDR(BASEADDR+32'h60, `NONSEQ, `SINGLE);
		fork
			MC_WRITE_DATA(BASEADDR+32'h60, 32'hffff_3333);
			MC_WRITE_ADDR(BASEADDR+32'h64, `NONSEQ, `SINGLE);
		join
		fork
			MC_WRITE_DATA(BASEADDR+32'h64, 32'hffff_7777);
			MC_WRITE_ADDR(BASEADDR+32'h68, `NONSEQ, `SINGLE);
		join
		fork
			MC_WRITE_DATA(BASEADDR+32'h68, 32'hffff_9999);
			MC_WRITE_ADDR(BASEADDR+32'h6c, `NONSEQ, `SINGLE);
		join
		MC_WRITE_DATA(BASEADDR+32'h6c, 32'hffff_aaaa);
	end
	endtask

	task MC_READ_FLOW;		// 基本传输-流水操作-读数据
	begin
		MC_READ_ADDR(BASEADDR+32'h60, `NONSEQ, `SINGLE);
		fork
			MC_READ_DATA(BASEADDR+32'h60, 32'hffff_3333);
			MC_READ_ADDR(BASEADDR+32'h64, `NONSEQ, `SINGLE);
		join
		fork
			MC_READ_DATA(BASEADDR+32'h64, 32'hffff_7777);
			MC_READ_ADDR(BASEADDR+32'h68, `NONSEQ, `SINGLE);
		join
		fork
			MC_READ_DATA(BASEADDR+32'h68, 32'hffff_9999);
			MC_READ_ADDR(BASEADDR+32'h6c, `NONSEQ, `SINGLE);
		join
		MC_READ_DATA(BASEADDR+32'h6c, 32'hffff_aaaa);
	end
	endtask

	task MC_W_R_FLOW;		// 基本传输-流水操作-写_读数据
	begin
		MC_WRITE_ADDR(BASEADDR+32'he0, `NONSEQ, `SINGLE);
		fork
			MC_WRITE_DATA(BASEADDR+32'he0, 32'hffff_3333);
			MC_READ_ADDR(BASEADDR+32'he0, `NONSEQ, `SINGLE);
		join
		fork
			MC_READ_DATA(BASEADDR+32'he0, 32'hffff_3333);
			MC_WRITE_ADDR(BASEADDR+32'he8, `NONSEQ, `SINGLE);
		join
		fork
			MC_WRITE_DATA(BASEADDR+32'he8, 32'hffff_9999);
			MC_READ_ADDR(BASEADDR+32'he8, `NONSEQ, `SINGLE);
		join
		MC_READ_DATA(BASEADDR+32'he8, 32'hffff_9999);
	end
	endtask

	//----------------------------------------------------------------------
	task MC_WRITE_BURST;	// BURST传输-写数据
	input [ADDR_WIDTH-1:0] 	t_addr;					// 首地址
	input [2:0]				burst;					// 突发模式
	begin
		MC_WRITE_ADDR(t_addr, `NONSEQ, burst);
		for (i = 0; i < get_burst_len(burst); i = i + 1) begin
			fork
				MC_WRITE_DATA(t_addr+i*(1<<MC_SIZE), DATA_MEM[((t_addr-BASEADDR)>>2)+i]);// 前一拍数据(4字节对齐)
				MC_WRITE_ADDR(t_addr+(i+1)*(1<<MC_SIZE), `SEQ, burst);	// 当前地址(4字节对齐)
			join
		end
		MC_WRITE_DATA(t_addr+i*(1<<MC_SIZE), DATA_MEM[((t_addr-BASEADDR)>>2)+i]);// 末数据
	end
	endtask

	task MC_READ_BURST;		// BURST传输-读数据
	input [ADDR_WIDTH-1:0] 	t_addr;					// 首地址
	input [2:0]				burst;					// 突发模式
	begin
		MC_READ_ADDR(t_addr, `NONSEQ, burst);
		for (i = 0; i < get_burst_len(burst); i = i + 1) begin
			fork
				MC_READ_DATA(t_addr+i*(1<<MC_SIZE), DATA_MEM[((t_addr-BASEADDR)>>2)+i]);// 前一拍数据
				MC_READ_ADDR(t_addr+(i+1)*(1<<MC_SIZE), `SEQ, burst);	// 当前地址
			join
		end
		MC_READ_DATA(t_addr+i*(1<<MC_SIZE), DATA_MEM[((t_addr-BASEADDR)>>2)+i]);// 末数据
	end
	endtask

	//----------------------------------------------------------------------
	task MC_WRITE_ADDR;		// 写地址段
	input [ADDR_WIDTH-1:0] 	t_addr;
	input [1:0]				trans;
	input [2:0]				burst;					// 突发模式
	begin
		MC_REQ <= 1'b1;								// 写请求
		MC_ADDR <= t_addr;
		MC_TRANS <= trans;							// 单拍传输模式
		MC_BURST <= burst;							// burst类型
		MC_SIZE <= `BYTE_4;							// 宽度为32bit
		MC_W_R <= 1'b1;
		#1 wait(MC_ACK == 1);
		@(posedge clk);								// 插入等待周期
		MC_TRANS <= `IDLE;							// 单拍传输模式
		MC_REQ <= 1'b0;								// 写请求结束
	end
	endtask

	task MC_WRITE_DATA;		// 写数据段
	input [ADDR_WIDTH-1:0] 	t_addr;
	input [DATA_WIDTH-1:0] 	w_data;
	begin
		$display("MC_WRITE---addr: %h; wdata: %h", t_addr, w_data);
		MC_WDATA <= w_data;
		#1 wait(MC_ACK == 1);
		@(posedge clk);								// 插入等待周期
	end
	endtask

	task MC_READ_ADDR;		// 读地址段
	input [ADDR_WIDTH-1:0] 	t_addr;
	input [1:0]				trans;
	input [2:0]				burst;					// 突发模式
	begin
		MC_REQ <= 1'b1;								// 读请求
		MC_ADDR <= t_addr;
		MC_TRANS <= trans;							// 单拍传输模式
		MC_BURST <= burst;							// burst类型
		MC_SIZE <= `BYTE_4;							// 宽度为32bit
		MC_W_R <= 1'b0;
		#1 wait(MC_ACK == 1);
		@(posedge clk);								// 插入等待周期
		MC_TRANS <= `IDLE;							// 单拍传输模式
		MC_REQ <= 1'b0;								// 读请求结束
	end
	endtask

	task MC_READ_DATA;		// 读数据段
	input [ADDR_WIDTH-1:0] 	t_addr;
	input [DATA_WIDTH-1:0] 	w_data;
	reg [DATA_WIDTH-1:0] 	r_data;
	begin
		assign r_data = MC_RDATA;
		#1 wait(MC_ACK == 1);
		@(posedge clk);								// 插入等待周期
		if(r_data == w_data)						// 比较数据
			$display("MC_READ OK----addr: %h; rdata: %h; wdata: %h", t_addr, r_data, w_data);
		else
			$error("MC_READ ERR----addr: %h; rdata: %h; wdata: %h", t_addr, r_data, w_data);
	end
	endtask

    //-----------------------------------------------------------
    function [7:0] get_burst_len;
		input [2:0]				burst;				// 突发模式
    begin
        case (burst)
			`SINGLE: begin
				get_burst_len = 8'b00000000;		// 单拍数据
			end
			`INCR4, `WRAP4: begin
				get_burst_len = 8'b00000011;		// 4拍数据
			end
			`INCR8, `WRAP8: begin
				get_burst_len = 8'b00000111;		// 8拍数据
			end
			`INCR16, `WRAP16, `INCR: begin			// 16拍数据，无定义也为16拍数据
				get_burst_len = 8'b00001111;
			end
			default: get_burst_len = 8'b00000000;	// 单拍数据
		endcase
	end
    endfunction

endmodule