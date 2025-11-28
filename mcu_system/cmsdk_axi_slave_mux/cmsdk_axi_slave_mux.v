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
// Abstract : Simple AXI slave multiplexer
//-----------------------------------------------------------------------------
// Each port can be disabled by parameter if not used.

module cmsdk_axi_slave_mux #(
	// Parameters to enable/disable ports
	// By default all ports are enabled
	parameter PORT0_ENABLE=1,
	parameter PORT1_ENABLE=1,
	parameter PORT2_ENABLE=1,
	parameter PORT3_ENABLE=1,
	parameter PORT4_ENABLE=1,
	parameter PORT5_ENABLE=1,
	parameter PORT6_ENABLE=1,
	parameter PORT7_ENABLE=1,
	parameter PORT8_ENABLE=1,
	parameter PORT9_ENABLE=1,
	// Data Bus Width
	parameter DW=32
)
(
	input  wire          		ACLK,         		// Clock
	input  wire          		ARESETn,      		// Reset
	input  wire          		AW_SEL0,      		// ASEL for AXI Slave #0
	input  wire          		AW_READY0,
	input  wire          		W_READY0,
	input  wire          		B_VALID0,
	input  wire [1:0]    		B_RESP0,
	input  wire          		AR_SEL0,      		// ASEL for AXI Slave #0
	input  wire          		AR_READY0,
	input  wire          		R_VALID0,
	input  wire          		R_LAST0,
	input  wire [DW-1:0] 		R_DATA0,
	input  wire [1:0]    		R_RESP0,
	input  wire          		AW_SEL1,      		// ASEL for AXI Slave #1
	input  wire          		AW_READY1,
	input  wire          		W_READY1,
	input  wire          		B_VALID1,
	input  wire [1:0]    		B_RESP1,
	input  wire          		AR_SEL1,      		// ASEL for AXI Slave #1
	input  wire          		AR_READY1,
	input  wire          		R_VALID1,
	input  wire          		R_LAST1,
	input  wire [DW-1:0] 		R_DATA1,
	input  wire [1:0]    		R_RESP1,
	input  wire          		AW_SEL2,      		// ASEL for AXI Slave #2
	input  wire          		AW_READY2,
	input  wire          		W_READY2,
	input  wire          		B_VALID2,
	input  wire [1:0]    		B_RESP2,
	input  wire          		AR_SEL2,      		// ASEL for AXI Slave #2
	input  wire          		AR_READY2,
	input  wire          		R_VALID2,
	input  wire          		R_LAST2,
	input  wire [DW-1:0] 		R_DATA2,
	input  wire [1:0]    		R_RESP2,
	input  wire          		AW_SEL3,      		// ASEL for AXI Slave #3
	input  wire          		AW_READY3,
	input  wire          		W_READY3,
	input  wire          		B_VALID3,
	input  wire [1:0]    		B_RESP3,
	input  wire          		AR_SEL3,      		// ASEL for AXI Slave #3
	input  wire          		AR_READY3,
	input  wire          		R_VALID3,
	input  wire          		R_LAST3,
	input  wire [DW-1:0] 		R_DATA3,
	input  wire [1:0]    		R_RESP3,
	input  wire          		AW_SEL4,      		// ASEL for AXI Slave #4
	input  wire          		AW_READY4,
	input  wire          		W_READY4,
	input  wire          		B_VALID4,
	input  wire [1:0]    		B_RESP4,
	input  wire          		AR_SEL4,      		// ASEL for AXI Slave #4
	input  wire          		AR_READY4,
	input  wire          		R_VALID4,
	input  wire          		R_LAST4,
	input  wire [DW-1:0] 		R_DATA4,
	input  wire [1:0]    		R_RESP4,
	input  wire          		AW_SEL5,      		// ASEL for AXI Slave #5
	input  wire          		AW_READY5,
	input  wire          		W_READY5,
	input  wire          		B_VALID5,
	input  wire [1:0]    		B_RESP5,
	input  wire          		AR_SEL5,      		// ASEL for AXI Slave #5
	input  wire          		AR_READY5,
	input  wire          		R_VALID5,
	input  wire          		R_LAST5,
	input  wire [DW-1:0] 		R_DATA5,
	input  wire [1:0]    		R_RESP5,
	input  wire          		AW_SEL6,      		// ASEL for AXI Slave #6
	input  wire          		AW_READY6,
	input  wire          		W_READY6,
	input  wire          		B_VALID6,
	input  wire [1:0]    		B_RESP6,
	input  wire          		AR_SEL6,      		// ASEL for AXI Slave #6
	input  wire          		AR_READY6,
	input  wire          		R_VALID6,
	input  wire          		R_LAST6,
	input  wire [DW-1:0] 		R_DATA6,
	input  wire [1:0]    		R_RESP6,
	input  wire          		AW_SEL7,      		// ASEL for AXI Slave #7
	input  wire          		AW_READY7,
	input  wire          		W_READY7,
	input  wire          		B_VALID7,
	input  wire [1:0]    		B_RESP7,
	input  wire          		AR_SEL7,      		// ASEL for AXI Slave #7
	input  wire          		AR_READY7,
	input  wire          		R_VALID7,
	input  wire          		R_LAST7,
	input  wire [DW-1:0] 		R_DATA7,
	input  wire [1:0]    		R_RESP7,
	input  wire          		AW_SEL8,      		// ASEL for AXI Slave #8
	input  wire          		AW_READY8,
	input  wire          		W_READY8,
	input  wire          		B_VALID8,
	input  wire [1:0]    		B_RESP8,
	input  wire          		AR_SEL8,      		// ASEL for AXI Slave #8
	input  wire          		AR_READY8,
	input  wire          		R_VALID8,
	input  wire          		R_LAST8,
	input  wire [DW-1:0] 		R_DATA8,
	input  wire [1:0]    		R_RESP8,
	input  wire          		AW_SEL9,      		// ASEL for AXI Slave #9
	input  wire          		AW_READY9,
	input  wire          		W_READY9,
	input  wire          		B_VALID9,
	input  wire [1:0]    		B_RESP9,
	input  wire          		AR_SEL9,      		// ASEL for AXI Slave #9
	input  wire          		AR_READY9,
	input  wire          		R_VALID9,
	input  wire          		R_LAST9,
	input  wire [DW-1:0] 		R_DATA9,
	input  wire [1:0]    		R_RESP9,
	input  wire          		AW_VALID,
	output wire          		AW_READY,
	output wire          		W_READY,
	output wire          		B_VALID,
	output wire [1:0]    		B_RESP,
	input  wire          		AR_VALID,
	output wire          		AR_READY,
	output wire          		R_VALID,
	output wire          		R_LAST,
	output wire [DW-1:0] 		R_DATA,
	output wire [1:0]    		R_RESP
);

	wire [9:0] 					awsel_mux;     		// Write selection control
	reg  [9:0] 					awsel_mux_reg; 		// next state for awsel_mux
	wire [9:0] 					arsel_mux;     		// Read selection control
	reg  [9:0] 					arsel_mux_reg; 		// next state for arsel_mux

	assign awsel_mux[0] = (PORT0_ENABLE!=0) & AW_SEL0;
	assign awsel_mux[1] = (PORT1_ENABLE!=0) & AW_SEL1;
	assign awsel_mux[2] = (PORT2_ENABLE!=0) & AW_SEL2;
	assign awsel_mux[3] = (PORT3_ENABLE!=0) & AW_SEL3;
	assign awsel_mux[4] = (PORT4_ENABLE!=0) & AW_SEL4;
	assign awsel_mux[5] = (PORT5_ENABLE!=0) & AW_SEL5;
	assign awsel_mux[6] = (PORT6_ENABLE!=0) & AW_SEL6;
	assign awsel_mux[7] = (PORT7_ENABLE!=0) & AW_SEL7;
	assign awsel_mux[8] = (PORT8_ENABLE!=0) & AW_SEL8;
	assign awsel_mux[9] = (PORT9_ENABLE!=0) & AW_SEL9;

	assign arsel_mux[0] = (PORT0_ENABLE!=0) & AR_SEL0;
	assign arsel_mux[1] = (PORT1_ENABLE!=0) & AR_SEL1;
	assign arsel_mux[2] = (PORT2_ENABLE!=0) & AR_SEL2;
	assign arsel_mux[3] = (PORT3_ENABLE!=0) & AR_SEL3;
	assign arsel_mux[4] = (PORT4_ENABLE!=0) & AR_SEL4;
	assign arsel_mux[5] = (PORT5_ENABLE!=0) & AR_SEL5;
	assign arsel_mux[6] = (PORT6_ENABLE!=0) & AR_SEL6;
	assign arsel_mux[7] = (PORT7_ENABLE!=0) & AR_SEL7;
	assign arsel_mux[8] = (PORT8_ENABLE!=0) & AR_SEL8;
	assign arsel_mux[9] = (PORT9_ENABLE!=0) & AR_SEL9;

	// Registering MuxCtrl
	always @(posedge ACLK or negedge ARESETn)
	begin
		if (~ARESETn)begin
			awsel_mux_reg <= {10{1'b0}};
			arsel_mux_reg <= {10{1'b0}};
		end
		else if (AW_VALID) // advance pipeline if AW_VALID is 1
			awsel_mux_reg <= awsel_mux;
		else if (AR_VALID) // advance pipeline if AR_VALID is 1
			arsel_mux_reg <= arsel_mux;
	end

	// 多路器
	assign AW_READY =								// 写请求就绪
           (awsel_mux[0] & AW_READY0) |
           (awsel_mux[1] & AW_READY1) |
           (awsel_mux[2] & AW_READY2) |
           (awsel_mux[3] & AW_READY3) |
           (awsel_mux[4] & AW_READY4) |
           (awsel_mux[5] & AW_READY5) |
           (awsel_mux[6] & AW_READY6) |
           (awsel_mux[7] & AW_READY7) |
           (awsel_mux[8] & AW_READY8) |
           (awsel_mux[9] & AW_READY9) ;

	assign W_READY =								// 写数据就绪
           (awsel_mux[0] & W_READY0) |
           (awsel_mux[1] & W_READY1) |
           (awsel_mux[2] & W_READY2) |
           (awsel_mux[3] & W_READY3) |
           (awsel_mux[4] & W_READY4) |
           (awsel_mux[5] & W_READY5) |
           (awsel_mux[6] & W_READY6) |
           (awsel_mux[7] & W_READY7) |
           (awsel_mux[8] & W_READY8) |
           (awsel_mux[9] & W_READY9) ;

	assign B_VALID =								// 写响应有效
           (awsel_mux_reg[0] & B_VALID0) |
           (awsel_mux_reg[1] & B_VALID1) |
           (awsel_mux_reg[2] & B_VALID2) |
           (awsel_mux_reg[3] & B_VALID3) |
           (awsel_mux_reg[4] & B_VALID4) |
           (awsel_mux_reg[5] & B_VALID5) |
           (awsel_mux_reg[6] & B_VALID6) |
           (awsel_mux_reg[7] & B_VALID7) |
           (awsel_mux_reg[8] & B_VALID8) |
           (awsel_mux_reg[9] & B_VALID9) ;

	assign B_RESP =									// 写响应信息
           ({2{(awsel_mux_reg[0])}} & B_RESP0) |
           ({2{(awsel_mux_reg[1])}} & B_RESP1) |
           ({2{(awsel_mux_reg[2])}} & B_RESP2) |
           ({2{(awsel_mux_reg[3])}} & B_RESP3) |
           ({2{(awsel_mux_reg[4])}} & B_RESP4) |
           ({2{(awsel_mux_reg[5])}} & B_RESP5) |
           ({2{(awsel_mux_reg[6])}} & B_RESP6) |
           ({2{(awsel_mux_reg[7])}} & B_RESP7) |
           ({2{(awsel_mux_reg[8])}} & B_RESP8) |
           ({2{(awsel_mux_reg[9])}} & B_RESP9) ;

	assign AR_READY =								// 读请求就绪
           (arsel_mux[0] & AR_READY0) |
           (arsel_mux[1] & AR_READY1) |
           (arsel_mux[2] & AR_READY2) |
           (arsel_mux[3] & AR_READY3) |
           (arsel_mux[4] & AR_READY4) |
           (arsel_mux[5] & AR_READY5) |
           (arsel_mux[6] & AR_READY6) |
           (arsel_mux[7] & AR_READY7) |
           (arsel_mux[8] & AR_READY8) |
           (arsel_mux[9] & AR_READY9) ;

	assign R_VALID =								// 读数据有效
           (arsel_mux_reg[0] & R_VALID0) |
           (arsel_mux_reg[1] & R_VALID1) |
           (arsel_mux_reg[2] & R_VALID2) |
           (arsel_mux_reg[3] & R_VALID3) |
           (arsel_mux_reg[4] & R_VALID4) |
           (arsel_mux_reg[5] & R_VALID5) |
           (arsel_mux_reg[6] & R_VALID6) |
           (arsel_mux_reg[7] & R_VALID7) |
           (arsel_mux_reg[8] & R_VALID8) |
           (arsel_mux_reg[9] & R_VALID9) ;

	assign R_LAST =									// 读数据最后一个
           (arsel_mux_reg[0] & R_LAST0) |
           (arsel_mux_reg[1] & R_LAST1) |
           (arsel_mux_reg[2] & R_LAST2) |
           (arsel_mux_reg[3] & R_LAST3) |
           (arsel_mux_reg[4] & R_LAST4) |
           (arsel_mux_reg[5] & R_LAST5) |
           (arsel_mux_reg[6] & R_LAST6) |
           (arsel_mux_reg[7] & R_LAST7) |
           (arsel_mux_reg[8] & R_LAST8) |
           (arsel_mux_reg[9] & R_LAST9) ;

	assign R_DATA =									// 读数据
           ({DW{(arsel_mux_reg[0])}} & R_DATA0) |
           ({DW{(arsel_mux_reg[1])}} & R_DATA1) |
           ({DW{(arsel_mux_reg[2])}} & R_DATA2) |
           ({DW{(arsel_mux_reg[3])}} & R_DATA3) |
           ({DW{(arsel_mux_reg[4])}} & R_DATA4) |
           ({DW{(arsel_mux_reg[5])}} & R_DATA5) |
           ({DW{(arsel_mux_reg[6])}} & R_DATA6) |
           ({DW{(arsel_mux_reg[7])}} & R_DATA7) |
           ({DW{(arsel_mux_reg[8])}} & R_DATA8) |
           ({DW{(arsel_mux_reg[9])}} & R_DATA9) ;

	assign R_RESP =									// 读响应信息
           ({2{(arsel_mux_reg[0])}} & R_RESP0) |
           ({2{(arsel_mux_reg[1])}} & R_RESP1) |
           ({2{(arsel_mux_reg[2])}} & R_RESP2) |
           ({2{(arsel_mux_reg[3])}} & R_RESP3) |
           ({2{(arsel_mux_reg[4])}} & R_RESP4) |
           ({2{(arsel_mux_reg[5])}} & R_RESP5) |
           ({2{(arsel_mux_reg[6])}} & R_RESP6) |
           ({2{(arsel_mux_reg[7])}} & R_RESP7) |
           ({2{(arsel_mux_reg[8])}} & R_RESP8) |
           ({2{(arsel_mux_reg[9])}} & R_RESP9) ;

endmodule
