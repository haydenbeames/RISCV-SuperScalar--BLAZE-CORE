`timescale 1ns / 1ps

/***************************************************************************
* Module 	RSV
* Filename: RSV.sv
*
* Author: Hayden Beames
* Date: 12/31/2022
*
* Description: 
****************************************************************************/

//include files
`include "rtl_constants.sv"

//Reservation Station for non MUL/DIV/SW/LW instructions
module RSV (
	input wire logic clk, rst, 
	
	//issue inputs
	input wire logic [ISSUE_WIDTH_MAX-1:0] 		  instr_val_id,
	input wire logic [ISSUE_WIDTH_MAX-1:0][31:0] instruction_id,
	
	//new instruction into RSV
	input wire logic [CPU_NUM_LANES-1:0][5:0] 	  opcode_ar1,
	input wire logic [CPU_NUM_LANES-1:0][5:0] 	  rd_ar1, //only for alu instr (figure out what to do for sw/lw operands)
	input wire logic [CPU_NUM_LANES-1:0][31:0] 	  rs1_ar1, rs2_ar2,
	input wire logic [ROB_SIZE_CLOG-1:0] rob_issue_ptr,
	
	//inputs from CDB
	input wire logic [CPU_NUM_LANES-1:0][ROB_SIZE_CLOG-1:0] ROB_id_cdb,
	input wire logic [CPU_NUM_LANES-1:0][5:0]  op_cdb,
	input wire logic [CPU_NUM_LANES-1:0][4:0]  rd_tag_cdb,
	input wire logic [CPU_NUM_LANES-1:0] 	   commit_instr_cdb,
	input wire logic [CPU_NUM_LANES-1:0][31:0] result_data_cdb,
	
	//inputs from RAT
	input wire logic read_RAT_rs1,
	
	//RSV OUTPUTS TO EXECUTION UNITS
	output logic [CPU_NUM_LANES-1:0] 	   fullRSV,
	output logic [CPU_NUM_LANES-1:0][31:0] rs1_rsv, rs2_rsv

);

	/////////////////////////////////////////////////////
	// **DESIGN QUESTIONS TO CONSIDER**
	//  
	// -> should CDB send out more than one result? 
	//	  if so, should it be same length as issue?
	//
	// 
	
	/////////////////////////////////////////////////////
	// PIPELINE
	// 
	//   IF* | ID | IS | RSV | EX* | COM | RET
	//
	// AR1: Rename and dispatch to ROB and IQ,
	// COM: (commit) result from ex finished and sent to CDB and ROB
	//
	// EX varies based on lane, i.e. DIV & MUL take more cycles. 
	// ALU Instruc take 1 cycle

    // Only forwarding is from CDB

	
	////////////////////////////////////////
	//
	// AR1 PIPE STAGE
	//
	// write to RAT and ROB
	//
	// -check RAT for source operands
	// -find spot to put issued instr into RSV
	// -find source ops and dependencies in arr
	//
	////////////////////////////////////////
	
	typedef struct packed {
		logic [5:0] op; 	//instruction opcode
		logic [ROB_SIZE_CLOG:0] dst_tag;
		logic [RAT_RENAME_DATA_WIDTH-1:0][NUM_SRCS-1:0] Q; //data location as specified from RAT //if zero, data already allocated
		logic [31:0][NUM_SRCS-1:0] V; 	//value of src operands needed
		logic busy; 	//indicated specified RSV and functional unit is occupied
		logic valid; 	//info in RSV is valid
      	//logic [$clog(MAX_MEM_ADDR)-1:0] A; //Used to hold information for the memory address calculation for a load
		//or store. Initially, the immediate field of the instruction is stored here; after
		//the address calculation, the effective address is stored here.
	} RSV_t;
	RSV_t [CPU_NUM_LANES-1:0][RSV_NUM_ENTRIES-1:0] entries;

	//Declare output signals
	logic [CPU_NUM_LANES-1:0][RSV_NUM_ENTRIES-1:0][NUM_SRCS-1:0] match_src_dep;  //find src dependency match
	logic [CPU_NUM_LANES-1:0][RSV_NUM_ENTRIES-1:0] ready_out;
	logic [CPU_NUM_LANES-1:0][RSV_NUM_ENTRIES-1:0] rsv_ety_to_dispatch;
	logic [CPU_NUM_LANES-1:0][RSV_NUM_ENTRIES-1:0] rsv_ety_rdy_to_dispatch;
	
	//match src dependencies
	always_comb begin
		//on bdcst, check to see if source needed is bdcst dest. Also, if Qj or Qk = 0, src not neededs
		match_src_dep = '{default:0};
		for (int ln = 0; ln < CPU_NUM_LANES; ln++) begin
			for (int ety = 0; ety < RSV_NUM_ENTRIES; ety++) begin
				for (int cdb = 0; cdb < CDB_NUM_LANES; cdb++) begin
				    for (int src = 0; src < NUM_SRCS; src++) begin
					   match_src_dep[ln][ety][src] = (entries[ln][ety].valid & ((ROB_id_cdb[cdb] & commit_instr_cdb[cdb])== entries[ln][ety].Qj) & (entries[ln][ety].Q[src] != 0));
					end
				end
			end
		end
	end
	
	
	////////////////////////////////////////////////////////////////////////////////
	////// 
	//////   GENERATE F-RAT (Front-End Register Alias Table)
	//////  
	////////////////////////////////////////////////////////////////////////////////
	
	logic [ISSUE_WIDTH_MAX-1:0][NUM_SRCS-1:0][RAT_RENAME_DATA_WIDTH-1-1:0] src_renamed_is;
	logic [ISSUE_WIDTH_MAX-1:0][NUM_SRCS-1:0]                            src_data_type_rat_is;
	logic [ISSUE_WIDTH_MAX-1:0][ROB_SIZE_CLOG-1:0]                ROB_id_is;
	
	f_RAT f_rat(.clk(clk), 
	            .rst(rst),
	            .instr_val_id(instr_val_id),
	            .opcode_id(instruction_id[6:0]),
	            .rd_id(    instruction_id[11:7]),
	            .rs1_id(   instruction_id[19:15]),
	            .rs2_id(   instruction_id[24:20]),
	            .rob_issue_ptr(rob_issue_ptr),
	            .src_renamed_is(src_renamed_is),
	            .src_data_type_rat_is(src_data_type_rat_is),
	            .ROB_id_is(ROB_id_is)
	            );
	            
	////////////////////////////////////////////////////////////////////////////////
	////// 
	//////   GENERATE ROB (Re-Order Buffer)
	//////  
	////////////////////////////////////////////////////////////////////////////////
	/*
	//RSV update on CDB   //FIXME
	always_ff @(posedge clk) begin
		for (int ln = 0; ln < CPU_NUM_LANES; ln++) begin
			for (int ety = 0; ety < RSV_NUM_ENTRIES; ety++) begin
				if (rst) begin
					entries[ln][ety].op 	     <= opcode_ar1;
					entries[ln][ety].dst_tag     <= ROB_id_ar1;
					entries[ln][ety][RS_1].Q 	 <= '0;
					entries[ln][ety][RS_2].Q 	 <= '0;
					entries[ln][ety][RS_1].V 	 <= '0;
					entries[ln][ety][RS_2].V 	 <= '0;
					entries[ln][ety].busy 	     <=  0;
					entries[ln][ety].valid 	     <=  0; 
				end else if (alloc_instr_rsv[ln][ety]) begin //lane determined by RSV availabilites, more likely to issue to more free RSV
		            
		            
					entries[ln][ety][RS_2].Q <= low_1st_free_is[ln][ety] ? (loadInstruc || storeInstruc || ALUImmInstrucNoFuncS || ALUImmInstrucFuncS || LUI_ex) ?
					                                                        immGenOut_is : src_data_type_rat_is ? 
					entries[ln][ety][src].V <= low_1st_free_is[ln][ety] ? 
					
	                
	                entries[ln][ety].op 	 <= low_1st_free_is[ln][ety] ? opcode_ar1		: entries[ln][ety].op;
					entries[ln][ety].dst_tag <= low_1st_free_ar1[ln][ety] ? ROB_id_ar1		: entries[ln][ety].dst_tag;
	                entries[ln][ety].busy 	 <= low_1st_free_ar1[ln][ety] ? ;
					entries[ln][ety].valid 	 <= low_1st_free_ar1[ln][ety] ? ;
					
					//if current ety, increase age, otherwise, if writing to RSV then set as youngest ety
					entries[ln][ety].age 	 <= entries[ln][ety].valid    ? entries[ln][ety].age + 1'b1 : 
												low_1st_free_ar1[ln][ety] ? 1'b1 : entries[ln][ety].age;
				end else begin
		        //update RSV from CDB based on match_src_dep
				    for (int ety = 0; ety < RSV_NUM_ENTRIES; ety++) begin 
				        for (int src = 0; src < NUM_SRCS; src++) begin
					           //updating rsv src dep on bdcst matches
					           entries[ln][ety][src].Q <= match_src_dep[ln][ety][RS_1] ? 0 		 	  : entries[ln][ety][src].Q;
					           entries[ln][ety][src].V <= match_src_dep[ln][ety][RS_1] ? result_data_cdb : entries[ln][ety][src].V;
					   end
					entries[ln][ety].dst_tag <= rob_issue_ptr_is;
					//clear RSV on dispatch
				end
			end
		end
	end
	
	//find RSV ETY to write to on ISSUE next cycle
	///*FIRST ZERO ALGORITHM* -> finds first INVALID RSV
	/// INPUT:   1101
	/// Invert:  0010
	/// INPUT+1: 1110
	/// (INPUT+1)&(INVERT): 0010  **FAST FIRST ZERO DETECT**
	
	//logic [CPU_NUM_LANES-1:0] top_1st_free_is;
	//logic [CPU_NUM_LANES-1:0] top_2nd_free_is;
	logic [CPU_NUM_LANES-1:0] low_1st_free_is;
	//logic [CPU_NUM_LANES-1:0] low_2nd_free_is;
	
	//could one hot to reduce power on ff
	always_comb begin
		//start from beginning to end
		low_1st_free_is = '0;
		for (int ln = 0; ln < CPU_NUM_LANES; ln++) begin
			low_1st_free_is[ln] = (RSV[ln].valid + 1'b1) & ~(RSV[ln].valid);
		end
		//start from end to beginning
		//for (int ln = CPU_NUM_LANES-1; ln >= 0; ln--) begin
			
		//end
	end

	//CHOOSE RSV ENTRY TO DISPATCH
	//if 2 ready, dispatch oldest ety
	always_comb begin
		rsv_ety_dispatch = '0;
		for (int ln = 0; ln < CPU_NUM_LANES; ln++) begin
			for (int ety = 0; ety < RSV_NUM_ENTRIES; ety++) begin
				rsv_ety_rdy_to_dispatch[ety] = (entries[ety].Qj == 0) & (entries[ety].Qk == 0) ? 1 : 0;
			
			end
		end
	end
	
	//full RSV?
	always_comb begin
		fullRSV = 0;
		for (int ln = 0; ln < CPU_NUM_LANES; ln++) begin
			for (int i = 0; i < RSV_NUM_ENTRIES; i++) begin
				fullRSV[ln] |= entries[ln][i].busy;	
			end 
		end
	end
	*/
endmodule 
