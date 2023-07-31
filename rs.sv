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
    input wire logic rob_full,

    //inputs from regfile
    input wire logic [NUM_RF_R_PORTS-1:0][DATA_LEN-1:0] rf_r_port_data,
    
    //inputs from f-rat
    input wire logic [ISSUE_WIDTH_MAX-1:0][OPCODE_LEN-1:0] opcode_ar,
    input wire logic [ISSUE_WIDTH_MAX-1:0][SRC_LEN-1:0] rd_ar,
    input wire logic [ISSUE_WIDTH_MAX-1:0][NUM_SRCS-1:0][RAT_RENAME_DATA_WIDTH-1:0] src_rdy_2_issue_ar,
    input wire logic [ISSUE_WIDTH_MAX-1:0][NUM_SRCS-1:0]                  src_data_type_rdy_2_issue_ar, // 1: PRF, 0: ROB 
    input wire logic [ISSUE_WIDTH_MAX-1:0] instr_val_ar,
    input wire instr_info_t [ISSUE_WIDTH_MAX-1:0] instr_info_ar,

	//inputs from functional units
	input wire logic [CPU_NUM_LANES-1:0] fu_free, fu_free_1c, //fu_free_1c means fu free in 1 cycle
    
	//rs OUTPUTS TO EXECUTION UNITS
	output alu_lane_t [NUM_ALU_LANES-1:0] alu_lane_info_ex1,
	output logic 	   rs_full
);

    rs_t [RS_NUM_ENTRIES-1:0] rs;
    
    logic [ISSUE_WIDTH_MAX-1:0][CPU_NUM_LANES-1:0] fu_dest_qual_ar;
    
	logic [ISSUE_WIDTH_MAX-1:0][RS_NUM_ENTRIES-1:0] free_rs_ety_onehot; 
	logic [ISSUE_WIDTH_MAX-1:0][RS_NUM_ENTRIES_CLOG-1:0] free_rs_ety;   //index into free rs slots for issuing instrucitons 
    logic [RS_NUM_ENTRIES-1:0] inbuff_rs_valid_lsb, outbuff_rs_free_ety_lsb;
	logic [RS_NUM_ENTRIES-1:0] inbuff_rs_valid_msb, outbuff_rs_free_ety_msb;
	logic [RS_NUM_ENTRIES-1:0] inbuff_rs_free_ety_enc;
	logic [RS_NUM_ENTRIES_CLOG-1:0] outbuff_rs_free_ety_enc;

    initial begin
        for (int ety = 0; ety < RS_NUM_ENTRIES; ety++) begin
            rs[ety] = '{default:0};
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
            free_rs_ety_onehot[i] = outbuff_rs_free_ety_lsb;
            inbuff_rs_valid_lsb |= free_rs_ety_onehot[i];
        end
        for (int i = ISSUE_WIDTH_MAX-1; i >= (ISSUE_WIDTH_MAX/2); i--) begin
            `ZERO_1ST_MSB(outbuff_rs_free_ety_msb, inbuff_rs_valid_msb)
			free_rs_ety_onehot[i] = outbuff_rs_free_ety_msb;
			inbuff_rs_valid_msb |= free_rs_ety_onehot[i];
        end

		for (int i = 0; i < ISSUE_WIDTH_MAX; i++) begin 
			inbuff_rs_free_ety_enc = free_rs_ety_onehot[i];
			`ONE_HOT_ENCODE(outbuff_rs_free_ety_enc, inbuff_rs_free_ety_enc)
			free_rs_ety[i] = outbuff_rs_free_ety_enc;
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
				rs[free_rs_ety[i]].rd      <= rd_ar[i];
            	rs[free_rs_ety[i]].valid   <=  1;
                rs[free_rs_ety[i]].ctrl_sig.alu_ctrl <= instr_info_ar[  i].ctrl_sig.alu_ctrl;
                rs[free_rs_ety[i]].ctrl_sig.fu_dest  <= fu_dest_qual_ar[i];
            	rs[free_rs_ety[i]].ctrl_sig.func3    <= instr_info_ar[  i].ctrl_sig.func3;
				for (int s = 0; s < NUM_SRCS; s++) begin 
					rs[free_rs_ety[i]].Q[s] <= src_data_type_rdy_2_issue_ar[i][s] ? 0 : instr_info_ar[i].robid;
					rs[free_rs_ety[i]].V[s] <= src_data_type_rdy_2_issue_ar[i][s] ? rf_r_port_data[i*NUM_SRCS+s] : 0;
					rs[free_rs_ety[i]].imm  <= instr_info_ar[i].ctrl_sig.alu_src  ? instr_info_ar[i].imm : 0;
				end
            end
        end
    end
    
    fu_dest_t  [ISSUE_WIDTH_MAX-1:0] fu_dest_cs = '{default:0}; //current state
    fu_dest_t  [ISSUE_WIDTH_MAX-1:0] fu_dest_ns = '{default:0}; //next state
    lane_cnt_t [ISSUE_WIDTH_MAX-1:0] lane_count = '{default:0};
    
    logic [ISSUE_WIDTH_MAX-1:0] fu_1_state_TEST;
    logic [CPU_NUM_LANES-1:0] inbuff_1_1st_fu_dest_ar, outbuff_1_1st_fu_dest_ar;
    
    always_ff@(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < ISSUE_WIDTH_MAX; i++) begin
                //fu_dest_cs[i].alu <= ALU_LANE_MASK;
                //fu_dest_ns[i].alu <= ALU_LANE_MASK;
            end
        end else begin
            fu_dest_cs <= fu_dest_ns;
        end
    end
    
	//functional unit binding SM
	//add more units later
	always_comb begin
        fu_dest_qual_ar = '0;
        fu_1_state_TEST = '0;
        lane_count = '{default:0};
        for (int i = 0; i < ISSUE_WIDTH_MAX; i++) begin
            fu_dest_ns[i].alu = ALU_LANE_MASK;
	    	case (instr_info_ar[i].ctrl_sig.fu_dest)
	    	    ALU_LANE_MASK: begin 
	    	        for (int ln = 0; ln < CPU_NUM_LANES ; ln++)
	    	            lane_count[i].alu += fu_dest_cs[i].alu[ln];
	    	            
	    	        if ($unsigned(lane_count[i].alu) > 1) begin
	    	             inbuff_1_1st_fu_dest_ar = fu_dest_cs[i].alu;
	    	            `ONE_1ST_LSB(outbuff_1_1st_fu_dest_ar, inbuff_1_1st_fu_dest_ar);
	    	            fu_dest_qual_ar[i] = outbuff_1_1st_fu_dest_ar;
	    	            fu_dest_ns[i].alu &= ~fu_dest_qual_ar[i];
	    	        end else begin
	    	            fu_dest_qual_ar[i] = fu_dest_cs[i].alu;
	    	            fu_dest_ns[i].alu = ALU_LANE_MASK;
	    	            fu_1_state_TEST[i] = 1;
	    	        end
	    	    end
	    	endcase
		end
	end
	
	
	////////////////////////////////////////////
	////
	//// DISPATCH LOGIC
	////
	////////////////////////////////////////////
	
	logic [CPU_NUM_LANES-1:0][RS_NUM_ENTRIES-1:0] rdy_2_disp_rs;
	
	//ety ready to dispatch logic
	always_comb begin
		rdy_2_disp_rs = '{default:0};
		for (int ln = 0; ln < CPU_NUM_LANES; ln++) begin
	   		for (int ety = 0; ety < RS_NUM_ENTRIES; ety++) begin
	   		    rdy_2_disp_rs[ln][ety] = rs[ety].valid & (rs[ety].Q[RS_1] == 0) & (rs[ety].Q[RS_2] == 0) & rs[ety].ctrl_sig.fu_dest[ln];
	   		end
		end
	end

	logic [CPU_NUM_LANES-1:0][RS_NUM_ENTRIES-1:0] rdy_2_disp_fu_qual_rs;
    logic [CPU_NUM_LANES-1:0] any_rdy_2_disp_qual_rs;
	//qualify with fu ready status
	always_comb begin
		rdy_2_disp_fu_qual_rs = '{default:0};
		any_rdy_2_disp_qual_rs = '0;
		for (int ln = 0; ln < CPU_NUM_LANES; ln++) begin
	   		for (int ety = 0; ety < RS_NUM_ENTRIES; ety++) begin
				rdy_2_disp_fu_qual_rs[ ln][ety] = rdy_2_disp_rs[ln][ety] & (fu_free[ln] | fu_free_1c[ln]); //if fu free | fu free in 1 cycle
			    any_rdy_2_disp_qual_rs[ln]     |= rdy_2_disp_fu_qual_rs[ln][ety];
			end 
		end
	end

	logic [CPU_NUM_LANES-1:0][RS_NUM_ENTRIES-1:0] disp_fu_1st_1_rs;

	//if there is more than one instruction in rs ready to dispatch to same fu as another instruction, grab first one
	//this implementation does not use instruction age in order to reduce area and logic complexity
	//may be some slight performance degredation on certain cases
	always_comb begin 
		disp_fu_1st_1_rs = '{default:0};
		for (int ln = 0; ln < CPU_NUM_LANES; ln++) begin
	   		for (int ety = 0; ety < RS_NUM_ENTRIES; ety++) begin	   		     
				`ONE_1ST_LSB(disp_fu_1st_1_rs[ln], rdy_2_disp_fu_qual_rs[ln]);
			end 
		end
	end
	
	logic [CPU_NUM_LANES-1:0][RS_NUM_ENTRIES-1:0] instruc_2_disp_fu_rs;

	always_comb begin
		for (int ln = 0; ln < CPU_NUM_LANES; ln++) begin
	   		for (int ety = 0; ety < RS_NUM_ENTRIES; ety++) begin 
				instruc_2_disp_fu_rs[ln][ety] = disp_fu_1st_1_rs[ln][ety];
			end 
		end
	end
	


	logic [CPU_NUM_LANES-1:0][RS_NUM_ENTRIES_CLOG-1:0] fu_disp_enc_rs; //final encoding 

	//one hot encoding to give index of isntruction in rs to dispatch to corresponding fu
	always_comb begin 
		for (int ln = 0; ln < CPU_NUM_LANES; ln++) begin
			`ONE_HOT_ENCODE(fu_disp_enc_rs[ln], instruc_2_disp_fu_rs[ln]);
		end 
	end
	
	
	/////////////////////////////////////////////////
	///
	/// ASSIGN RDY_2_DISP INSTRUCTION IN RS TO FU
	///
	/////////////////////////////////////////////////
	
	
	
	logic [CPU_NUM_LANES-1:0] testALU_MASK;
	
	always_ff@(posedge clk) begin 
	   testALU_MASK = '0;
	   for (int ln = 0; ln < CPU_NUM_LANES; ln++) begin 
			if (ALU_LANE_MASK[ln]) begin
			     testALU_MASK[ln] = 1;
				if (any_rdy_2_disp_qual_rs[ln]) begin 
					alu_lane_info_ex1[ln-ALU_LN_OFFSET].src[RS_1] <= rs[fu_disp_enc_rs[ln]].V[RS_1];
					alu_lane_info_ex1[ln-ALU_LN_OFFSET].src[RS_2] <= rs[fu_disp_enc_rs[ln]].V[RS_2];
					alu_lane_info_ex1[ln-ALU_LN_OFFSET].op        <= rs[fu_disp_enc_rs[ln]].ctrl_sig.alu_src ? rs[fu_disp_enc_rs[ln]].imm : 
																									           rs[fu_disp_enc_rs[ln]].V[RS_2];
					alu_lane_info_ex1[ln-ALU_LN_OFFSET].robid 	  <= rs[fu_disp_enc_rs[ln]].robid;
					alu_lane_info_ex1[ln-ALU_LN_OFFSET].alu_ctrl  <= rs[fu_disp_enc_rs[ln]].ctrl_sig.alu_ctrl;
				end 
			end 

	   	end	
	end

    

	/////////////////////////////////////////////////////
	// PIPELINE
	// 
	//   IF* | ID | AR | RS | EX* | COM | RET
	//
	// AR1: Rename and dispatch to ROB and IQ,
	// COM: (commit) result from ex finished and sent to CDB and ROB
	//
	// EX varies based on lane, i.e. DIV & MUL take more cycles. 
	// ALU Instruc take 1 cycle

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
    */
	
endmodule 
