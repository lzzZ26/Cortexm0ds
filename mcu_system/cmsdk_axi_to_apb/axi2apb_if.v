//---------------------------------------------------------------
// 请求（REQ）-应答（ACK）协议，信息：控制信息、地址信息、数据信息、响应信息
//             __    __    __    __    __    __    __    __
// CLK      __|  |__|  |__|  |__|  |__|  |__|  |__|  |__|  |__
//             _________________
// BC_REQ   __|                 |_____________________________
//                         _____
// BC_ACK   ______________|     |_____________________________
//            __________________
// BC_ADDR  XX______________A___XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
//            __________________
// BC_WDATA XX______________DW__XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
//                         _____
// BC_RDATA XXXXXXXXXXXXXXX_DR__XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
//                         _____
// BC_RESP  XXXXXXXXXXXXXXX_RR__XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
// 
//---------------------------------------------------------------
`timescale 1ns/1ns

module axi2apb_if
     #(parameter ADDR_WIDTH  = 32,        			// address width
                 DATA_WIDTH  = 32         			// data width
      )
    (
    input  wire                     ACLK,			// AXI时钟
    input  wire                     ARESETn,		// AXI复位

    input  wire                     AW_SEL,      	// AXI2APB Device select
    input  wire                     AW_VALID,		// 写请求有效
    output wire                     AW_READY,		// 写请求准备好
    input  wire [ 2:0]              AW_SIZE,		// 写数据宽度
    input  wire [ 1:0]              AW_BURST,		// 写传输类型
    input  wire [ 7:0]              AW_LEN,			// 写数据长度
    input  wire [ADDR_WIDTH-1:0]  	AW_ADDR,		// 写地址

    input  wire                     W_VALID,		// 写数据有效
    output wire                     W_READY,		// 写数据准备好
    input  wire                     W_LAST,			// 写数据最后一条
    input  wire [DATA_WIDTH-1:0]  	W_DATA,			// 写数据有效
    output wire                     B_VALID,		// 写响应有效
    input  wire                     B_READY,		// 写响应准备好
    output wire [ 1:0]              B_RESP,			// 写响应信息

    input  wire                     AR_SEL,      	// AXI2APB Device select
    input  wire                     AR_VALID,		// 读请求有效
    output wire                     AR_READY,		// 读请求准备好
    input  wire [ 2:0]              AR_SIZE,		// 读数据宽度
    input  wire [ 1:0]              AR_BURST,		// 读传输类型
    input  wire [ 7:0]              AR_LEN,			// 读数据长度
    input  wire [ADDR_WIDTH-1:0]  	AR_ADDR,		// 读地址

    output wire                     R_VALID,		// 读数据有效
    input  wire                     R_READY,		// 读数据准备好
    output wire                     R_LAST,			// 读数据最后一条
    output wire [DATA_WIDTH-1:0]  	R_DATA,			// 读数据
    output wire [ 1:0]              R_RESP,			// 读响应

    //-----------------------------------------------------------
	output wire  APBACTIVE,  // APB bus is active, for clock gating of APB bus

    input  wire                     PCLK,			// APB时钟
    input  wire                     PRESETn,		// APB复位
    output wire                     PSEL,			// APB bus select
    output wire                     PENABLE,		// APB bus enable
    output wire                     PWRITE,			// APB bus write
    output wire [3:0]               PSTRB,			// APB bus byte lane strobe
    output wire [ADDR_WIDTH-1:0] 	PADDR,			// APB bus address
    output wire [DATA_WIDTH-1:0] 	PWDATA,			// APB bus write data
    input  wire                     PREADY,			// APB bus ready
    input  wire [DATA_WIDTH-1:0] 	PRDATA,			// APB bus read data
    input  wire                     PSLVERR			// APB bus error
    );

    // 内部信号
    //-----------------------------------------------------------
    // BC Interface
    wire							BC_WREQ;		// Write request
    wire 							BC_WACK;		// Write acknowledge
    wire [ADDR_WIDTH-1:0]	    	BC_WADDR;		// Write address
    wire [DATA_WIDTH-1:0]	    	BC_WDATA;		// Write data
    wire 							BC_WRESP;		// Write response
    wire							BC_RREQ;		// Read request
    wire 							BC_RACK;		// Read acknowledge
    wire [ADDR_WIDTH-1:0]	    	BC_RADDR;		// Read address
    wire [DATA_WIDTH-1:0]	    	BC_RDATA;		// Read data
    wire 							BC_RRESP;		// Read response

	reg  [3:0]						pstrb_reg;   	// Byte lane strobe register
	wire [3:0]						pstrb_nxt;   	// Byte lane strobe next state
	wire							apb_select;   	// APB bridge is selected

	//####################################################################
	// Byte strobe generation
	// - Only enable for write operations
	// - For word write transfers (AW_SIZE[1]=1), all byte strobes are 1
	// - For hword write transfers (AW_SIZE[0]=1), check AW_ADDR[1]
	// - For byte write transfers, check AW_ADDR[1:0]
	assign pstrb_nxt[0] = ((AW_SIZE[1])|((AW_SIZE[0])&(~AW_ADDR[1]))|(AW_ADDR[1:0]==2'b00));
	assign pstrb_nxt[1] = ((AW_SIZE[1])|((AW_SIZE[0])&(~AW_ADDR[1]))|(AW_ADDR[1:0]==2'b01));
	assign pstrb_nxt[2] = ((AW_SIZE[1])|((AW_SIZE[0])&( AW_ADDR[1]))|(AW_ADDR[1:0]==2'b10));
	assign pstrb_nxt[3] = ((AW_SIZE[1])|((AW_SIZE[0])&( AW_ADDR[1]))|(AW_ADDR[1:0]==2'b11));

	// Sample control signals
	assign apb_select = AW_SEL & AW_VALID & AW_READY;
	always @(posedge PCLK or negedge PRESETn)
	begin
		if(!PRESETn)
		begin
			pstrb_reg <= {4{1'b0}};
		end
		else if (apb_select) // Capture transfer information at the end of AHB address phase
		begin
			pstrb_reg <= pstrb_nxt;
		end
	end

	assign PSTRB = pstrb_reg[3:0];

	//####################################################################
    //-----------------------------------------------------------
	axi2apb_axi	
		#(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH))
		u_axi2apb_axi(
			.ACLK		(ACLK),		
			.ARESETn	(ARESETn),		
		
			.AW_SEL		(AW_SEL),
			.AW_VALID	(AW_VALID),
			.AW_READY	(AW_READY),
			.AW_SIZE	(AW_SIZE),
			.AW_BURST	(AW_BURST),
			.AW_LEN		(AW_LEN),
			.AW_ADDR	(AW_ADDR),	
			
			.W_VALID	(W_VALID),
			.W_READY	(W_READY),
			.W_LAST		(W_LAST),
			.W_DATA		(W_DATA),
			.B_VALID	(B_VALID),
			.B_READY	(B_READY),
			.B_RESP		(B_RESP),
			
			.AR_SEL		(AR_SEL),
			.AR_VALID	(AR_VALID),
			.AR_READY	(AR_READY),
			.AR_SIZE	(AR_SIZE),
			.AR_BURST	(AR_BURST),
			.AR_LEN		(AR_LEN),
			.AR_ADDR	(AR_ADDR),
			
			.R_VALID	(R_VALID),
			.R_READY	(R_READY),
			.R_LAST		(R_LAST),
			.R_DATA		(R_DATA),
			.R_RESP		(R_RESP),

			.APBACTIVE	(APBACTIVE),

			.BC_WREQ	(BC_WREQ),
			.BC_WACK	(BC_WACK),
			.BC_WADDR	(BC_WADDR),
			.BC_WDATA	(BC_WDATA),
			.BC_WRESP	(BC_WRESP),
			.BC_RREQ	(BC_RREQ),
			.BC_RACK	(BC_RACK),
			.BC_RADDR	(BC_RADDR),
			.BC_RDATA	(BC_RDATA),
			.BC_RRESP	(BC_RRESP)
		);

	axi2apb_apb	
		#(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH))
		u_axi2apb_apb(
			.PCLK		(PCLK),		
			.PRESETn	(PRESETn),		
			.PSEL		(PSEL),
			.PENABLE	(PENABLE),
			.PWRITE		(PWRITE),
			.PADDR		(PADDR),
			.PWDATA		(PWDATA),
			.PREADY		(PREADY),
			.PRDATA		(PRDATA),
			.PSLVERR	(PSLVERR),

			.BC_WREQ	(BC_WREQ),
			.BC_WACK	(BC_WACK),
			.BC_WADDR	(BC_WADDR),
			.BC_WDATA	(BC_WDATA),
			.BC_WRESP	(BC_WRESP),
			.BC_RREQ	(BC_RREQ),
			.BC_RACK	(BC_RACK),
			.BC_RADDR	(BC_RADDR),
			.BC_RDATA	(BC_RDATA),
			.BC_RRESP	(BC_RRESP)
		);

endmodule
