`timescale 1ns/1ns

module axi2apb_apb
     #(parameter ADDR_WIDTH  = 32,        			// APB address width
                 DATA_WIDTH  = 32         			// APB data width
    )
    (
    input  wire                     PCLK,			// APB clock	
    input  wire                     PRESETn,		// APB reset

	// APB Master Interface
    output reg                      PSEL,			// APB select
    output reg                      PENABLE,		// APB enable
    output reg                      PWRITE,			// APB write
    output reg [ADDR_WIDTH-1:0]     PADDR,			// APB address
    output reg [DATA_WIDTH-1:0]     PWDATA,			// APB write data
    input  wire                     PREADY,			// APB ready
    input  wire [DATA_WIDTH-1:0]    PRDATA,			// APB read data
    input  wire                     PSLVERR,		// APB error

	// BC Interface
	input wire						BC_WREQ,		// Write request
	output wire   					BC_WACK,		// Write acknowledge
	input wire [ADDR_WIDTH-1:0]		BC_WADDR,		// Write address
	input wire [DATA_WIDTH-1:0]		BC_WDATA,		// Write data
	output wire						BC_WRESP,		// Write response
	input wire						BC_RREQ,		// Read request
	output wire   					BC_RACK,		// Read acknowledge
	input wire [ADDR_WIDTH-1:0]		BC_RADDR,		// Read address
	output wire [DATA_WIDTH-1:0]	BC_RDATA,		// Read data
	output wire						BC_RRESP		// Read response
    );


	//---------------------<状态机参数>-------------------------------------
	localparam ST_IDLE		= 3'b001;				// 空闲
	localparam ST_SETUP		= 3'b010;				// APB SETUP
	localparam ST_ACCESS	= 3'b100;				// APB ACCESS
	//---------------------<状态定义>---------------------------------------
	reg [2:0]               st_cur;
	reg [2:0]               st_next;

	//----------------------------------------------------------------------
	//--   状态机第1段（状态迁移）
	//----------------------------------------------------------------------
	always @(posedge PCLK or negedge PRESETn)begin
		if(!PRESETn) begin
			st_cur <= ST_IDLE;
		end
		else begin
			st_cur <= st_next;
		end
	end

	//----------------------------------------------------------------------
	//--   状态机第2段（输入对状态的影响）
	//----------------------------------------------------------------------
	always @(*) begin
		st_next = st_cur;			// 下面有不完全赋值，这样可以避免LATCH
		case(st_cur)
			ST_IDLE: begin
				if(BC_WREQ | BC_RREQ)				// 事务启动
					st_next = ST_SETUP;
			end
			ST_SETUP: begin							// APB SETUP
				st_next = ST_ACCESS;
			end
			ST_ACCESS: begin						// APB ACCESS
				if(PREADY)
					st_next = ST_IDLE;
			end
			default: st_next = ST_IDLE;				// 防御性编程
		endcase
	end

	//----------------------------------------------------------------------
	//--   状态机第3段（状态对输出的影响）
	//----------------------------------------------------------------------
	// APB信号产生（寄存输出）
	always @(posedge PCLK or negedge PRESETn)begin
		if(!PRESETn)begin
			PSEL <= 1'b0;
			PENABLE <= 1'b0;
			PWRITE <= 1'b0;
			PADDR <= 'h0;
			PWDATA <= 'h0;
		end
		else begin
			case(st_next)
				ST_IDLE:begin
					PSEL <= 1'b0;
					PENABLE <= 1'b0;
				end
				ST_SETUP:begin
					PSEL <= 1'b1;
					PENABLE <= 1'b0;
					if(BC_WREQ) begin				// 写
						PWRITE <= 1'b1;
						PADDR <= BC_WADDR;			// 写地址
						PWDATA <= BC_WDATA;			// 锁存写数据
					end
					else if(BC_RREQ)begin			// 读
						PWRITE <= 1'b0;
						PADDR <= BC_RADDR;			// 读地址
					end
				end
				ST_ACCESS:begin
					PSEL <= 1'b1;
					PENABLE <= 1'b1;
				end
				default:begin						// 防御性编程
					PSEL <= 1'b0;
					PENABLE <= 1'b0;
				end
			endcase
		end
	end

	// BC信号产生
	assign BC_WACK  = BC_WREQ & (st_cur == ST_ACCESS) & PREADY;// 准备好
	assign BC_WRESP = PSLVERR;						// 出错
	assign BC_RACK  = BC_RREQ & (st_cur == ST_ACCESS) & PREADY;// 准备好
	assign BC_RDATA = PRDATA;						// 采样数据
	assign BC_RRESP = PSLVERR;						// 出错

endmodule
