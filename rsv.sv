`timescale 1ns / 1ps

/***************************************************************************
* 
* Module:   rs
* Filename: rs.sv
*
* Author: Hayden Beames
* Date: 4/27/2023
*
* Description: 
*   Centralized Reservation chosen to reduce pipeline stalls.
*       * Data for instructions is held in the RS to reduce # of read 
*         ports to regfile 
*               - this also results in lower latency on dispatch since  
*                 retrieving rf data from dispatching instructions is not 
*                 necessary
*               - NOTE: this is less power efficient since will need
*                       not only more area for the RS but more data will need  
*                       to be written into RS  
*                                -> # RS memory cells extra vs dispatch method = DATA_LEN * RS_NUM_ENTRIES 
*                                    -prefer not to generate immediate data on dispatch since will need 
*                                     to decode again which requires more instruction information so will 
*                                     rs2 in reservation station
*                       -retrieving from regfile on dispatch will  
*                        not be explored further
*
****************************************************************************/

//include files
`include "rtl_constants.sv"
`include "decode_constants.sv"
`include "riscv_alu_constants.sv"
`include "macros.sv"
`include "structs.sv"

//Centralized Reservation Station for ALL Instruction types
module rs (
	input wire logic clk, rst, 
	

	//inputs from CDB
	input wire logic [CPU_NUM_LANES-1:0][ROB_SIZE_CLOG-1:0] robid_cdb,
	input wire logic [CPU_NUM_LANES-1:0][5:0]  op_cdb,
	input wire logic [CPU_NUM_LANES-1:0][4:0]  rd_tag_cdb,
	input wire logic [CPU_NUM_LANES-1:0] 	   commit_instr_cdb,
	input wire logic [CPU_NUM_LANES-1:0][31:0] result_data_cdb,
	
    //inputs from rob
    input wire logic   rob_full,
    
    //outputs of f-rat
    input wire logic [ISSUE_WIDTH_MAX-1:0][OPCODE_LEN-1:0] opcode_ar,
    input wire logic [ISSUE_WIDTH_MAX-1:0][SRC_LEN-1:0] rd_ar,
    input wire logic [ISSUE_WIDTH_MAX-1:0][NUM_SRCS-1:0][RAT_RENAME_DATA_WIDTH-1:0] src_rdy_2_issue_ar,
    input wire logic [ISSUE_WIDTH_MAX-1:0][NUM_SRCS-1:0]                  src_data_type_rdy_2_issue_ar, // 1: PRF, 0: ROB 
    input wire logic [ISSUE_WIDTH_MAX-1:0] instr_val_ar,
    input wire instr_info_t [ISSUE_WIDTH_MAX-1:0] instr_info_ar,
    
	//rs OUTPUTS TO EXECUTION UNITS
	output logic 	   rs_full
);
/*
	logic [ISSUE_WIDTH_MAX-1:0][RS_NUM_ENTRIES-1:0] free_rs_ety; 
	logic [ISSUE_WIDTH_MAX-1:0][RS_NUM_ENTRIES_CLOG-1:0] free_rs_ety_idx;   //index into free rs slots for issuing instrucitons 
    logic [RS_NUM_ENTRIES-1:0] inbuff_rs_valid_lsb, outbuff_rs_free_ety_lsb;
	logic [RS_NUM_ENTRIES-1:0] inbuff_rs_valid_msb, outbuff_rs_free_ety_msb;

    initial begin
        for (int ety = 0; ety < RS_NUM_ENTRIES; ety++) begin
            rs[ety].op 	    = '0;
			rs[ety].robid   = '0;
			rs[ety].Q[RS_1] = '0;
			rs[ety].Q[RS_2] = '0;
			rs[ety].V[RS_1] = '0;
			rs[ety].V[RS_2] = '0; 
            rs[ety].fu_dest = '0;
			rs[ety].busy 	=  0;
            rs[ety].valid   =  1;
        end
    end
    
    always_comb begin
        inbuff_rs_valid_lsb = 'X;
		inbuff_rs_valid_msb = 'X;
        for (int ety = 0; ety < RS_NUM_ENTRIES; ety++) begin
            inbuff_rs_valid_lsb[ety] = rs[ety].valid;
			inbuff_rs_valid_msb[ety] = rs[ety].valid;
        end
        for (int i = 0; i < (ISSUE_WIDTH_MAX/2); i++) begin
            `ZERO_1ST_LSB(outbuff_rs_free_ety_lsb, inbuff_rs_valid_lsb);
            free_rs_ety[i] = outbuff_rs_free_ety_lsb;
            inbuff_rs_valid_lsb |= free_rs_ety[i];
        end
        for (int i = ISSUE_WIDTH_MAX-1; i >= (ISSUE_WIDTH_MAX/2); i--) begin
            `ZERO_1ST_MSB(outbuff_rs_free_ety_msb, inbuff_rs_valid_msb)
			free_rs_ety[i] = outbuff_rs_free_ety_msb;
			inbuff_rs_valid_msb |= free_rs_ety[i];
        end
    end
    
    logic [RS_NUM_ENTRIES_CLOG :0] rs_occupancy;
    always_comb begin
        rs_occupancy = '0;
        for (int ety = 0; ety < RS_NUM_ENTRIES; ety++) begin
            rs_occupancy += rs[ety].valid;
        end
        rs_full = rs_occupancy > (RS_NUM_ENTRIES - ISSUE_WIDTH_MAX);
    end
    
    
    // ISSUE into RS flops 
    always_ff@(posedge clk) begin 
        for (int i = 0; i < ISSUE_WIDTH_MAX; i++) begin 
            if (instr_val_ar[i] & ~rs_full) begin
                rs[free_rs_ety[i]].op 	   <= opcode_ar[i];
				rs[free_rs_ety[i]].robid   <= instr_info_ar[i].robid;

            	rs[free_rs_ety[i]].fu_dest <= instr_info_ar[i].ctrl_sig.fu_dest;
				rs[free_rs_ety[i]].busy    <=  0; //could we use this to reduce forwarding logic ?? check which fu?
											      // and base on # of cycles to calculate? may be less expensive than comparisons
            	rs[free_rs_ety[i]].valid   <=  1;
				for (int s = 0; s < NUM_SRCS; s++) begin 
					rs[free_rs_ety[i]].Q[s] <= instr_info_ar[i].ctrl_sig.alu_src 			  ? '0 :
											   src_data_type_rdy_2_issue_ar[i][s] ? 'X/* rf */ /*: src_rdy_2_issue_ar[i][s];
					rs[free_rs_ety[i]].V[s] <= instr_info_ar[i].ctrl_sig.alu_src 			  ?  instr_info_ar[i].imm :
											   src_data_type_rdy_2_issue_ar[i][s] ? 32'hdeadbeef/* rf *//* : '0; //'0 since data from ROB not produced yet
					rs[free_rs_ety[i]].imm  <= instr_info_ar[i].imm
				end
            end
        end
    end
*/
	//functional unit binding SM

	
	/////////////////////////////////////////////////////
	// PIPELINE
	// 
	//   IF* | ID | IS | rs | EX* | COM | RET
	//
	// AR1: Rename and dispatch to ROB and IQ,
	// COM: (commit) result from ex finished and sent to CDB and ROB
	//
	// EX varies based on lane, i.e. DIV & MUL take more cycles. 
	// ALU Instruc take 1 cycle

    // Only forwarding is from CDB 
    
	rs_t [RS_NUM_ENTRIES-1:0] rs;
    /*
	//Declare output signals
	logic [CPU_NUM_LANES-1:0][RS_NUM_ENTRIES-1:0][NUM_SRCS-1:0] match_src_dep;  //find src dependency match
	logic [CPU_NUM_LANES-1:0][RS_NUM_ENTRIES-1:0] ready_out;
	logic [CPU_NUM_LANES-1:0][RS_NUM_ENTRIES-1:0] rs_ety_to_dispatch;
	logic [CPU_NUM_LANES-1:0][RS_NUM_ENTRIES-1:0] rs_ety_rdy_to_dispatch;
	
	//match src dependencies
	always_comb begin
		//on bdcst, check to see if source needed is bdcst dest. Also, if Qj or Qk = 0, src not neededs
		match_src_dep = '{default:0};
		for (int ln = 0; ln < CPU_NUM_LANES; ln++) begin
			for (int ety = 0; ety < RS_NUM_ENTRIES; ety++) begin
				for (int cdb = 0; cdb < CDB_NUM_LANES; cdb++) begin
				    for (int src = 0; src < NUM_SRCS; src++) begin
					   match_src_dep[ln][ety][src] = (rs[ln][ety].valid & ((ROB_id_cdb[cdb] & commit_instr_cdb[cdb])== rs[ln][ety].Q) & (rs[ln][ety].Q[src] != 0));
					end
				end
			end
		end
	end

	
	//rs update on CDB   //FIXME
	always_ff @(posedge clk) begin
		for (int ln = 0; ln < CPU_NUM_LANES; ln++) begin
			for (int ety = 0; ety < RS_NUM_ENTRIES; ety++) begin
				if (rst) begin
					entries[ln][ety].op 	     <= opcode_ar1;
					entries[ln][ety].robid     <= ROB_id_ar1;
					entries[ln][ety][RS_1].Q 	 <= '0;
					entries[ln][ety][RS_2].Q 	 <= '0;
					entries[ln][ety][RS_1].V 	 <= '0;
					entries[ln][ety][RS_2].V 	 <= '0;
					entries[ln][ety].busy 	     <=  0;
					entries[ln][ety].valid 	     <=  0; 
				end else if (alloc_instr_rs[ln][ety]) begin //lane determined by rs availabilites, more likely to issue to more free rs
		            
		            
					entries[ln][ety][RS_2].Q <= low_1st_free_is[ln][ety] ? (loadInstruc || storeInstruc || ALUImmInstrucNoFuncS || ALUImmInstrucFuncS || LUI_ex) ?
					                                                        immGenOut_is : src_data_type_rat_is ? 
					entries[ln][ety][src].V <= low_1st_free_is[ln][ety] ? 
					
	                
	                entries[ln][ety].op 	 <= low_1st_free_is[ln][ety] ? opcode_ar1		: entries[ln][ety].op;
					entries[ln][ety].robid <= low_1st_free_ar1[ln][ety] ? ROB_id_ar1		: entries[ln][ety].robid;
	                entries[ln][ety].busy 	 <= low_1st_free_ar1[ln][ety] ? ;
					entries[ln][ety].valid 	 <= low_1st_free_ar1[ln][ety] ? ;
					
					//if current ety, increase age, otherwise, if writing to rs then set as youngest ety
					entries[ln][ety].age 	 <= entries[ln][ety].valid    ? entries[ln][ety].age + 1'b1 : 
												low_1st_free_ar1[ln][ety] ? 1'b1 : entries[ln][ety].age;
				end else begin
		        //update rs from CDB based on match_src_dep
				    for (int ety = 0; ety < RS_NUM_ENTRIES; ety++) begin 
				        for (int src = 0; src < NUM_SRCS; src++) begin
					           //updating rs src dep on bdcst matches
					           entries[ln][ety][src].Q <= match_src_dep[ln][ety][RS_1] ? 0 		 	  : entries[ln][ety][src].Q;
					           entries[ln][ety][src].V <= match_src_dep[ln][ety][RS_1] ? result_data_cdb : entries[ln][ety][src].V;
					   end
					entries[ln][ety].robid <= rob_issue_ptr_is;
					//clear rs on dispatch
				end
			end
		end
	end
	*/
	
endmodule 
