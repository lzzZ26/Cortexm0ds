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
//     This block implements a Generic 4-entry AXI CoreSight ROM Table
//-----------------------------------------------------------------------------
//
// This example block occupies an 4kB space on the AXI bus at the address
// specified by the BASE[31:0] parameter.
//
//  BASE[31:0] + 0x1000 +--------------------------------------+
//                      | CID: CoreSight ROM Table             |
//                      |--------------------------------------|
//                      | PID: Manufacturer and Partnumber     |
//                      |--------------------------------------|
//                      .                                      .
//                      .                                      .
//                      .                                      .
//                      |--------------------------------------|
//                      | Fourth Entry                         |
//  BASE[31:0] + 0xC    |--------------------------------------|
//                      | Third Entry                          |
//  BASE[31:0] + 0x8    |--------------------------------------|
//                      | Second Entry                         |
//  BASE[31:0] + 0x4    |--------------------------------------|
//                      | First Entry                          |
//  BASE[31:0]          +--------------------------------------+
//
//
// The ROM table allows debug tools to identify the CoreSight components in
// a SoC or subsystem, and to identify the manufacturer and part and revision
// information for the SoC or subsystem.
// The PID fields include the manufacturer's JEDEC JEP106 identity code and
// manufacturer-defined partnumber and revision values.
//
// Considerations:
//
// To allow debug tools to discover the ROM table, it must be pointed to by
// another ROM table in the system, or by the BASEADDR pointer in the DAP.
//
// The ROM table contents must contain correct ID values. To allow for late
// changes (e.g. metal fixes) to be identified from the ID values, the
// ECOREVNUM bus should be easily identifiable and modifiable.
//-----------------------------------------------------------------------------

module cmsdk_axi_sysrom_table
  #(
    // ------------------------------------------------------------
    // ROM Table BASE Address
    // ------------------------------------------------------------
    parameter [31:0]   BASE = 32'h00000000,

    // ------------------------------------------------------------
    // ROM Table Manufacturer, Part Number and Revision
    // ------------------------------------------------------------
    parameter [6:0]    JEPID           = 7'b0000000,// JEP106 identity code
    parameter [3:0]    JEPCONTINUATION = 4'h0,      // number of JEP106
                                                    // continuation codes
    parameter [11:0]   PARTNUMBER      = 12'h000,   // part number
    parameter [3:0]    REVISION        = 4'h0,      // part revision

    // ------------------------------------------------------------
    // ROM Table entries: (Base Address | Present)
    // ------------------------------------------------------------
    parameter [31:0]   ENTRY0BASEADDR = 32'h00000000,
    parameter          ENTRY0PRESENT  = 1'b0,

    parameter [31:0]   ENTRY1BASEADDR = 32'h00000000,
    parameter          ENTRY1PRESENT  = 1'b0,

    parameter [31:0]   ENTRY2BASEADDR = 32'h00000000,
    parameter          ENTRY2PRESENT  = 1'b0,

    parameter [31:0]   ENTRY3BASEADDR = 32'h00000000,
    parameter          ENTRY3PRESENT  = 1'b0
    )
  (
    input  wire                 ACLK,               // Clock
    input  wire                 ARESETn,            // Reset

    //----------------- AXI - Read ------------------
    input  wire                 AR_SEL,             // SEL
    input wire                  AR_VALID,           // Read request valid
    output wire                 AR_READY,           // Read request ready
    input wire   [2:0]          AR_SIZE,            // Read data size
    input wire   [1:0]          AR_BURST,           // Read burst type
    input wire   [7:0]          AR_LEN,             // Read burst length
    input wire   [31:0]         AR_ADDR,            // Read address

    output wire                 R_VALID,            // Read data valid
    input wire                  R_READY,            // Read data ready
    output wire                 R_LAST,             // Read data last
    output wire  [31:0]         R_DATA,             // Read data
    output wire  [1:0]          R_RESP,             // Read response

    input wire [3:0]            ECOREVNUM           // ECOREVNUM
    ); 

	//---------------------<局部变量定义>-------------------------------------
	localparam AW		    = 'd10;			        // 地址宽度

    wire                    RF_RAREQ;               // Address phase read valid
    wire                    RF_RREQ;                // Data phase read enable
    wire                    RF_RACK;                // Data phase read ack
    reg  [AW-1:0]	    	RF_RADDR;               // Read address
    wire [31:0]	    	    RF_RDATA;               // Read data

	//---------------------<状态机参数>-------------------------------------
	localparam STR_IDLE		= 4'b0001;			    // 读操作空闲
	localparam STR_REQ		= 4'b0010;			    // 读操作请求
	localparam STR_DATA		= 4'b0100;			    // 读操作数据
	localparam STR_BURST	= 4'b1000;			    // BURST读等待
	reg [3:0]               str_cur;
	reg [3:0]               str_next;

	//---------------------<局部变量定义>-------------------------------------
	reg [7:0]               r_beatCNT;			    // BUSRT读操作拍数计数器



	//############################# 读操作 #################################
    // ------------------------------------------------------------
    // AXI Interface
    // ------------------------------------------------------------
	reg						RF_RACK_D1;

	always @(posedge ACLK or negedge ARESETn) begin
		if(!ARESETn) begin
			RF_RACK_D1 <= 1'b0;
		end
		else begin
			RF_RACK_D1 <= RF_RACK;                  // 延迟一拍
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
			STR_IDLE: begin						    // 读空闲
				if(AR_SEL & AR_VALID)               // 读请求
					str_next = STR_REQ;
			end
			STR_REQ: begin						    // 读请求通道
				str_next = STR_DATA;
			end
			STR_DATA: begin						    // 读数据通道
                if(RF_RACK_D1)begin
                    if(r_beatCNT < AR_LEN)		    // BURST读
                        str_next = STR_BURST;
					else if(AR_SEL & AR_VALID)	    // 单拍流水
						str_next = STR_REQ;
					else		                    // 单拍或者BURST最后一拍
						str_next = STR_IDLE;
                end
			end
			STR_BURST: begin					    // BURST读
				str_next = STR_DATA;
			end
			default: str_next = STR_IDLE;
		endcase
	end

	// BUSRT读操作拍数计数
	always @(posedge ACLK or negedge ARESETn) begin
		if(!ARESETn) begin
			r_beatCNT <= 'h0; 
		end
 		else if(str_next == STR_REQ) begin
			r_beatCNT <= 'h0;                       // 重置
		end
 		else if(str_next == STR_BURST) begin
			r_beatCNT <= r_beatCNT + 1;		        // 完成一拍
		end
	end

	//----------------------------------------------------------------------
	//--   状态机第3段（状态对输出的影响）
	//----------------------------------------------------------------------
	// AXI信号产生
	assign AR_READY = (str_next == STR_REQ) ? 1'b1 : 1'b0; 	// 读请求准备好

	assign R_VALID = RF_RACK;                       // 读数据有效 
	assign R_LAST = R_VALID & R_READY & (r_beatCNT == AR_LEN);	// 最后一拍数据
	assign R_DATA = RF_RDATA;                       // 输出读数据
	assign R_RESP = 2'b00;                          // 输出读响应信息：OKAY

	// RF信号产生
    // BURST读操作计算下一拍地址
    always @(posedge ACLK or negedge ARESETn)
	//always @(*)
    begin
		if(!ARESETn) begin
			RF_RADDR <= {AW{1'b0}};					// 区域地址
		end
		else if(str_next == STR_REQ)begin
			RF_RADDR <= {AR_ADDR[AW-1:2], 2'b00};	// 采样读首地址，必须4字节对齐！！！
		end
		else if(str_next == STR_BURST)begin
			RF_RADDR <= get_next_addr(RF_RADDR, 3'b010, AR_BURST);	// 下一拍地址，必须4字节对齐
		end
	end

    // Generate read control (address phase)
    assign RF_RAREQ = AR_SEL & AR_VALID & AR_READY;
 
    // Generate read enable (data and respone phase)
    assign RF_RREQ  = R_READY;
	assign RF_RACK = RF_RREQ;

	//############################# 基本函数 #################################
    function [AW-1:0]   get_next_addr;              // 获取下一拍地址
        input [AW-1:0]  addr ;                      // 当前地址
        input [ 2:0]    size ;                      // 读数据宽度
        input [ 1:0]    burst;                      // burst type
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


	//############################# ROM Table ############################
    // ------------------------------------------------------------
    // ROM Tables
    // ------------------------------------------------------------

    //
    // ROM Table Entry Calculation:
    //
    // Ref: ARM IHI0029B CoreSight Architecture Specification
    //
    // ROM table entry format:
    // [31:12] Address Offset. Base address of highest 4KB block relative to ROM
    //         table address.
    // [11: 2] RESERVED, RAZ
    //     [1] Format. 1=32-bit format
    //     [0] Entry Present.
    //
    // ComponentAddress = ROMAddress + (AddressOffset SHL 12)
    //

    // Calculate address offset values
    localparam [19:0] ENTRY0OFFSET = ENTRY0BASEADDR[31:12] - BASE[31:12];
    localparam [19:0] ENTRY1OFFSET = ENTRY1BASEADDR[31:12] - BASE[31:12];
    localparam [19:0] ENTRY2OFFSET = ENTRY2BASEADDR[31:12] - BASE[31:12];
    localparam [19:0] ENTRY3OFFSET = ENTRY3BASEADDR[31:12] - BASE[31:12];

    // Construct entries
    localparam [31:0] ENTRY0 = { ENTRY0OFFSET, 10'b0, 1'b1, ENTRY0PRESENT!=0 };
    localparam [31:0] ENTRY1 = { ENTRY1OFFSET, 10'b0, 1'b1, ENTRY1PRESENT!=0 };
    localparam [31:0] ENTRY2 = { ENTRY2OFFSET, 10'b0, 1'b1, ENTRY2PRESENT!=0 };
    localparam [31:0] ENTRY3 = { ENTRY3OFFSET, 10'b0, 1'b1, ENTRY3PRESENT!=0 };

    // ------------------------------------------------------------
    wire [11:0] word_addr = RF_RADDR;               // 必须4字节对齐

    // ------------------------------------------------------------
    // ROM Table Content
    // ------------------------------------------------------------

    wire       cid3_en         = (word_addr[11:0] == 12'hFFC);
    wire       cid2_en         = (word_addr[11:0] == 12'hFF8);
    wire       cid1_en         = (word_addr[11:0] == 12'hFF4);
    wire       cid0_en         = (word_addr[11:0] == 12'hFF0);

    wire       pid7_en         = (word_addr[11:0] == 12'hFDC);
    wire       pid6_en         = (word_addr[11:0] == 12'hFD8);
    wire       pid5_en         = (word_addr[11:0] == 12'hFD4);
    wire       pid4_en         = (word_addr[11:0] == 12'hFD0);
    wire       pid3_en         = (word_addr[11:0] == 12'hFEC);
    wire       pid2_en         = (word_addr[11:0] == 12'hFE8);
    wire       pid1_en         = (word_addr[11:0] == 12'hFE4);
    wire       pid0_en         = (word_addr[11:0] == 12'hFE0);

    wire       systemaccess_en = (word_addr[11:0] == 12'hFCC);

    wire       entry0_en       = (word_addr[11:0] == 12'h000);
    wire       entry1_en       = (word_addr[11:0] == 12'h004);
    wire       entry2_en       = (word_addr[11:0] == 12'h008);
    wire       entry3_en       = (word_addr[11:0] == 12'h00C);

    wire [7:0] ids =
              ( ( {8{cid3_en}} & 8'hB1 ) | // CID3 : Rom Table
                ( {8{cid2_en}} & 8'h05 ) | // CID2 : Rom Table
                ( {8{cid1_en}} & 8'h10 ) | // CID1 : Rom Table
                ( {8{cid0_en}} & 8'h0D ) | // CID0 : Rom Table

                ( {8{pid7_en}} & 8'h00 ) | // PID7 : RESERVED
                ( {8{pid6_en}} & 8'h00 ) | // PID6 : RESERVED
                ( {8{pid5_en}} & 8'h00 ) | // PID5 : RESERVED
                ( {8{pid4_en}} & { {4{1'b0}}, JEPCONTINUATION[3:0] } ) |
                ( {8{pid3_en}} & { ECOREVNUM[3:0], {4{1'b0}} } ) |
                ( {8{pid2_en}} & { REVISION[3:0], 1'b1, JEPID[6:4] } ) |
                ( {8{pid1_en}} & { JEPID[3:0], PARTNUMBER[11:8] } ) |
                ( {8{pid0_en}} &   PARTNUMBER[7:0] )
                );

    //
    // Assign Read Data. Default value of 32'h00000000
    // corresponds to the End Of Table marker.
    //
    assign RF_RDATA[31:0] =
              ( ( {{24{1'b0}}, ids[7:0] } )              |
                ( {32{systemaccess_en}} & 32'h00000001 ) |
                // Pointers to CoreSight Components
                ( {32{entry0_en}} & ENTRY0[31:0] )       |
                ( {32{entry1_en}} & ENTRY1[31:0] )       |
                ( {32{entry2_en}} & ENTRY2[31:0] )       |
                ( {32{entry3_en}} & ENTRY3[31:0] )
                );

    // -------------------------------------------------------------------------

endmodule
