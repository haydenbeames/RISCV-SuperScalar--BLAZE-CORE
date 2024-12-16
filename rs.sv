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
*   Distributed Reservation Station
*
****************************************************************************/

//include files
`include "rtl_constants.sv"
`include "decode_constants.sv"
`include "riscv_alu_constants.sv"
`include "macros.sv"
`include "structs.sv"

//Centralized Reservation Station for ALL Instruction types
module rs(
	input  wire logic clk_free_master,
	input  wire logic global_rst, 
	

	//inputs from CDB 
	input  cdb_t [CPU_NUM_LANES-1:0] cdb_cmt,
	
  //inputs from rob
  input  wire logic rob_full,

  //inputs from regfile
  input  wire logic [NUM_RF_R_PORTS-1:0][DATA_LEN-1:0] rf_r_port_data,
  
  //inputs from f-rat
  input  wire logic        [ISSUE_WIDTH_MAX-1:0][OPCODE_LEN-1:0] opcode_ar,
  input  wire logic        [ISSUE_WIDTH_MAX-1:0][SRC_LEN-1:0] rd_ar,
  input  wire logic        [ISSUE_WIDTH_MAX-1:0][NUM_SRCS-1:0][RAT_RENAME_DATA_WIDTH-1:0] src_rdy_2_issue_ar,
  input  wire logic        [ISSUE_WIDTH_MAX-1:0][NUM_SRCS-1:0]                  src_data_type_rdy_2_issue_ar, // 1: PRF, 0: ROB 
  input  wire logic        [ISSUE_WIDTH_MAX-1:0] instr_val_ar,
  input  wire instr_info_t [ISSUE_WIDTH_MAX-1:0] instr_info_ar,
  input  wire logic        [ISSUE_WIDTH_MAX-1:0][CPU_NUM_LANES-1:0] rs_binding_ar, //tells us which RS instruction is going to //FIXME! logic not supported yet

  //inputs from functional units
  input  wire logic [CPU_NUM_LANES-1:0] fu_free, fu_free_1c, //fu_free_1c means fu free in 1 cycle
    
  //rs OUTPUTS TO EXECUTION UNITS
  output int_alu_lane_t [NUM_INT_ALU_LN+INT_ALU_LN_OFFSET-1:INT_ALU_LN_OFFSET] int_alu_ln_info_ex1,
  output int_mul_lane_t [NUM_INT_MUL_LN+INT_MUL_LN_OFFSET-1:INT_MUL_LN_OFFSET] int_mul_ln_info_ex1,

  output wire logic [CPU_NUM_LANES-1:0] rs_full,
  output wire logic [CPU_NUM_LANES-1:0][RS_NUM_ENTRIES_CLOG :0] rs_count
);

  rs_t [CPU_NUM_LANES-1:0][RS_NUM_ENTRIES-1:0] rs;
  rs_t [CPU_NUM_LANES-1:0][RS_NUM_ENTRIES-1:0] rs_next;
  
  logic [ISSUE_WIDTH_MAX-1:0][CPU_NUM_LANES-1:0]                     fu_dest_qual_ar;
  logic [ISSUE_WIDTH_MAX-1:0][CPU_NUM_LANES-1:0][RS_NUM_ENTRIES-1:0] issue_free_rs_ety; 

  logic [CPU_NUM_LANES-1:0][RS_NUM_ENTRIES-1:0]        inbuff_rs_valid_lsb;
  logic [CPU_NUM_LANES-1:0][RS_NUM_ENTRIES-1:0]        inbuff_rs_valid_msb;
  logic [CPU_NUM_LANES-1:0][RS_NUM_ENTRIES-1:0]        outbuff_rs_free_ety_lsb;
  logic [CPU_NUM_LANES-1:0][RS_NUM_ENTRIES-1:0]        outbuff_rs_free_ety_msb;
  logic [CPU_NUM_LANES-1:0][RS_NUM_ENTRIES-1:0]        inbuff_rs_free_ety_enc;
  logic [CPU_NUM_LANES-1:0][RS_NUM_ENTRIES_CLOG-1:0]   outbuff_rs_free_ety_enc;

  //initialize RS in simulation
  initial begin
    for (int ln = 0; ln < CPU_NUM_LANES; ln++) begin
      for (int ety = 0; ety < RS_NUM_ENTRIES; ety++) begin
        rs[ln][ety] = '{default:0};
      end
    end
  end


//------------------------------------------------------------------------------------------------------------------------------------------//
// RESERVATION STATION ALLOCATION
//------------------------------------------------------------------------------------------------------------------------------------------//

//  always_comb begin
//      inbuff_rs_valid_lsb = '{default:'x};
//	    inbuff_rs_valid_msb = '{default:'x};
//			for (int ln = 0; ln < CPU_NUM_LANES; ln++) begin
//        for (int ety = 0; ety < RS_NUM_ENTRIES; ety++) begin
//          inbuff_rs_valid_lsb[ln][ety] = rs[ln][ety].valid;
//		      inbuff_rs_valid_msb[ln][ety] = rs[ln][ety].valid;
//        end
//        for (int i = 0; i < (ISSUE_WIDTH_MAX/2); i++) begin
//         `ZERO_1ST_LSB(outbuff_rs_free_ety_lsb[ln], inbuff_rs_valid_lsb[ln]);
//          issue_free_rs_ety[i][ln]  = outbuff_rs_free_ety_lsb[ln];
//          inbuff_rs_valid_lsb[ln]  |= issue_free_rs_ety[i][ln];
//        end
//        for (int i = ISSUE_WIDTH_MAX-1; i >= (ISSUE_WIDTH_MAX/2); i--) begin
//         `ZERO_1ST_MSB(outbuff_rs_free_ety_msb[ln], inbuff_rs_valid_msb[ln])
//		      issue_free_rs_ety[i][ln]  = outbuff_rs_free_ety_msb[ln];
//		      inbuff_rs_valid_msb[ln]  |= issue_free_rs_ety[i][ln];
//        end
//			end
//	  // DONT THINK NEEDED for (int i = 0; i < ISSUE_WIDTH_MAX; i++) begin 
//	  // DONT THINK NEEDED 	inbuff_rs_free_ety_enc = issue_free_rs_ety[i];
//	  // DONT THINK NEEDED 	`ONE_HOT_ENCODE(outbuff_rs_free_ety_enc, inbuff_rs_free_ety_enc)
//	  // DONT THINK NEEDED 	issue_free_rs_ety[i] = outbuff_rs_free_ety_enc;
//	  // DONT THINK NEEDED end
//  end

  always_comb begin
    rs_count = '0;
		for (int ln = 0; ln < CPU_NUM_LANES; ln++) begin
      for (int ety = 0; ety < RS_NUM_ENTRIES; ety++) begin
        rs_count[ln] += rs[ln][ety].valid;
      end 
			rs_full[ln] = rs_count[ln] > (RS_NUM_ENTRIES - ISSUE_WIDTH_MAX); //TODO make this more optimized to reduce stalls (Backing QUEUE?)
		end
  end

  localparam RS_ALLOCATION_WIDTH = 2; //FIXME -> Put in param file

	logic [CPU_NUM_LANES-1:0][RS_ALLOCATION_WIDTH-1:0][RS_NUM_ENTRIES-1:0] find_free_rs_ety_ar;
	logic [CPU_NUM_LANES-1:0][RS_ALLOCATION_WIDTH-1:0][RS_NUM_ENTRIES-1:0]  sel_free_rs_ety_ar;
	logic [CPU_NUM_LANES-1:0][ISSUE_WIDTH_MAX-1:0]                          rs_binding_val_4_sel_ety_ar;
	logic [CPU_NUM_LANES-1:0][$clog2(ISSUE_WIDTH_MAX):0]                    alloc_2_lane_count_ar; //can have at max ISSUE_WIDTH_MAX uops push to a single RS lane. However, the # of allocs is set by RS_ALLOCATION_WIDTH

  //currently, previous find feeds into the next find.
	//Could optimize the gate depth better later
	always_comb begin
    for (int ln = 0; ln < CPU_NUM_LANES; ln++) begin
		 `ZERO_1ST_LSB(find_free_rs_ety_ar[ln][0], rs[ln][ety].valid) //scan RS_NUM_ENTRIES width
			for (int f = 1; f < RS_ALLOCATION_WIDTH; f++) begin
       `ZERO_1ST_LSB(find_free_rs_ety_ar[ln][f], find_free_rs_ety_ar[ln][f-1])
			end
		end
	end

  //count # ops pushing to RS lane
	always_comb begin
		alloc_2_lane_count_ar = '{default:0};
    for (ln = 0; ln < CPU_NUM_LANES; ln++) begin
			for (int i = 0; i < ISSUE_WIDTH_MAX; i++) begin
        rs_binding_val_4_sel_ety_ar[ln][i] = rs_binding_ar[i][ln];

				alloc_2_lane_count_ar[ln] += rs_binding_val_4_sel_ety_ar[ln][i];
			end
		end
	end

  // assign which free entry issuing instruction gets
	always_comb begin
    for (int ln = 0; ln < CPU_NUM_LANES; ln++) begin
		 `ZERO_1ST_LSB(sel_free_rs_ety_ar[ln][0], rs_binding_val_4_sel_ety_ar[ln][0]) //scan ISSUE_WIDTH_MAX width
			for (int f = 1; f < RS_ALLOCATION_WIDTH; f++) begin
       `ZERO_1ST_LSB(sel_free_rs_ety_ar[ln][f], rs_binding_val_4_sel_ety_ar[ln][f-1])
			end
		end
	end

  //FINAL assign the free entry pick to the RS lane
  // alloc_2_lane_count_ar is not necessary but may be if code is further optimized
  always_comb begin
		for (int ln = 0; ln < CPU_NUM_LANES; ln++) begin
      for (int f = 0; f < RS_ALLOCATION_WIDTH; f++) begin
        issue_free_rs_ety[ln][RS_NUM_ENTRIES-1:0] = sel_free_rs_ety_ar[ln][f] ? find_free_rs_ety_ar[ln][f][RS_NUM_ENTRIES-1:0] : '0;

			//issue_free_rs_ety[ln] = sel_free_rs_ety_ar[ln][f] & (alloc_2_lane_count_ar[ln] >= (f+1)) ? find_free_rs_ety_ar[ln][f]; //keep for optimized version
			end
		end
	end


//------------------------------------------------------------------------------------------------------------------------------------------//
// RESERVATION STATION STUCTURE
//------------------------------------------------------------------------------------------------------------------------------------------//

  // ISSUE into RS
  always_comb begin
    for (int i = 0; i < ISSUE_WIDTH_MAX; i++) begin
			for (int ln = 0; ln < CPU_NUM_LANES; ln++) begin
			  for (int ety = 0; ety < RS_NUM_ENTRIES; ety++) begin
            rs_next[ln][ety].opcode            = issue_free_rs_ety[ln][ety] & rs_binding_ar[i][ln] ? opcode_ar[i]           : '0;
			  	  rs_next[ln][ety].pdst              = issue_free_rs_ety[ln][ety] & rs_binding_ar[i][ln] ? rd_ar[i]               : '0; //FIXME -> turn rd_ar into pdst
			  	  rs_next[ln][ety].opcode            = issue_free_rs_ety[ln][ety] & rs_binding_ar[i][ln] ? instr_info_ar[i].robid : '0;
			  	  rs_next[ln][ety].fu_dest           = issue_free_rs_ety[ln][ety] & rs_binding_ar[i][ln] ? fu_dest_qual_ar[i]     : '0;

			  	  rs_next[ln][ety].ctrl_sig.memRead  = issue_free_rs_ety[ln][ety] & rs_binding_ar[i][ln] ? instr_info_ar[i].ctrl_sig.memRead  : '0;
			  	  rs_next[ln][ety].ctrl_sig.memWrite = issue_free_rs_ety[ln][ety] & rs_binding_ar[i][ln] ? instr_info_ar[i].ctrl_sig.memWrite : '0;
			  	  rs_next[ln][ety].ctrl_sig.rfWrite  = issue_free_rs_ety[ln][ety] & rs_binding_ar[i][ln] ? instr_info_ar[i].ctrl_sig.rfWrite  : '0;
			  	  rs_next[ln][ety].ctrl_sig.alu_ctrl = issue_free_rs_ety[ln][ety] & rs_binding_ar[i][ln] ? instr_info_ar[i].ctrl_sig.alu_ctrl : '0;
			  	  rs_next[ln][ety].ctrl_sig.alu_src  = issue_free_rs_ety[ln][ety] & rs_binding_ar[i][ln] ? instr_info_ar[i].ctrl_sig.alu_src  : '0;
			  	  rs_next[ln][ety].ctrl_sig.func3	   = issue_free_rs_ety[ln][ety] & rs_binding_ar[i][ln] ? instr_info_ar[i].ctrl_sig.func3    : '0;

			  	  //rs_next[ln][ety].imm               = issue_free_rs_ety[ln][ety] & rs_binding_ar[i][ln] ? instr_info_ar[i].ctrl_sig.alu_src ? instr_info_ar[i].imm : '0;
			  	  rs_next[ln][ety].imm               = issue_free_rs_ety[ln][ety] & rs_binding_ar[i][ln] ? instr_info_ar[i].imm : '0;
			  	for (int s = 0; s < NUM_SRCS; s++) begin
			  	  rs_next[ln][ety].Q[s]              = issue_free_rs_ety[ln][ety] & rs_binding_ar[i][ln] ? (src_data_type_rdy_2_issue_ar[i][s] ? '0 : src_rdy_2_issue_ar[i][s]   ) : '0; //this code isn't clear FIXME
            rs_next[ln][ety].Q_src_dep[s]      = issue_free_rs_ety[ln][ety] & rs_binding_ar[i][ln] ? (src_data_type_rdy_2_issue_ar[i][s] ? '0 : src_rdy_2_issue_ar[i][s]   ) : '0;
            rs_next[ln][ety].Q_src_dep[s]      = issue_free_rs_ety[ln][ety] & rs_binding_ar[i][ln] ? (src_data_type_rdy_2_issue_ar[i][s] ? '0 : 1                          ) : '0; //will be a case where not a source dep but is immediate but will still get written, should still work fine just unecessary toggling
            rs_next[ln][ety].V[s]              = issue_free_rs_ety[ln][ety] & rs_binding_ar[i][ln] ? (src_data_type_rdy_2_issue_ar[i][s] ? rf_r_port_data[i*NUM_SRCS+s] : 0) : '0;
			  	end
				end
			end
		end
	end

  logic [CPU_NUM_LANES-1:0][RS_NUM_ENTRIES-1:0] clk_allocate_rs_ar;
  
  // RESERVATION STATION
  generate
    for (genvar ln = 0; ln < CPU_NUM_LANES; ln++) begin
      for (genvar ety = 0; ety < RS_NUM_ENTRIES; ety++) begin
		   `FF(rs[ln][ety], rs_next[ln][ety], clk_allocate_rs_ar[ln][ety]) //functionally gated
		  end
		end
  endgenerate

  //always_ff@(posedge clk) begin 
  //    for (int i = 0; i < ISSUE_WIDTH_MAX; i++) begin 
  //        if (instr_val_ar[i] & ~rs_full) begin
  //            rs[issue_free_rs_ety[i]].op 	   <= opcode_ar[i];
	//		rs[issue_free_rs_ety[i]].robid   <= instr_info_ar[i].robid;
	//		rs[issue_free_rs_ety[i]].rd      <= rd_ar[i];
  //        	rs[issue_free_rs_ety[i]].valid   <=  1;
  //        	
  //        	rs[issue_free_rs_ety[i]].ctrl_sig.memRead  <= instr_info_ar[i].ctrl_sig.memRead;
  //        	rs[issue_free_rs_ety[i]].ctrl_sig.memWrite <= instr_info_ar[i].ctrl_sig.memWrite;
  //        	rs[issue_free_rs_ety[i]].ctrl_sig.rfWrite  <= instr_info_ar[i].ctrl_sig.rfWrite;
  //            rs[issue_free_rs_ety[i]].ctrl_sig.alu_ctrl <= instr_info_ar[i].ctrl_sig.alu_ctrl;
  //            rs[issue_free_rs_ety[i]].ctrl_sig.alu_src  <= instr_info_ar[i].ctrl_sig.alu_src;
  //        	rs[issue_free_rs_ety[i]].ctrl_sig.func3    <= instr_info_ar[i].ctrl_sig.func3;
  //        	rs[issue_free_rs_ety[i]].ctrl_sig.fu_dest  <= fu_dest_qual_ar[i];
	//		for (int s = 0; s < NUM_SRCS; s++) begin 
	//			rs[issue_free_rs_ety[i]].Q[s]         <= src_data_type_rdy_2_issue_ar[i][s] ? 0 : src_rdy_2_issue_ar[i][s];
	//			rs[issue_free_rs_ety[i]].Q_src_dep[s] <= src_data_type_rdy_2_issue_ar[i][s] ? 0 : 1; //will be a case where not a source dep but is immediate but will still get written, should still work fine just unecessary toggling
	//			rs[issue_free_rs_ety[i]].V[s]         <= src_data_type_rdy_2_issue_ar[i][s] ? rf_r_port_data[i*NUM_SRCS+s] : 0;
	//			rs[issue_free_rs_ety[i]].imm          <= instr_info_ar[i].ctrl_sig.alu_src  ? instr_info_ar[i].imm : 0;
	//		end
  //        end
  //    end
  //end
  
//------------------------------------------------------------------------------------------------------------------------------------------//
// EXECUTION UNIT LANE BINDING
//------------------------------------------------------------------------------------------------------------------------------------------//
    fu_dest_t  [ISSUE_WIDTH_MAX-1:0] fu_dest_cs = '{default:0}; //current state
    fu_dest_t  [ISSUE_WIDTH_MAX-1:0] fu_dest_ns = '{default:0}; //next state
    lane_cnt_t [ISSUE_WIDTH_MAX-1:0] lane_count = '{default:0};
    
    logic [ISSUE_WIDTH_MAX-1:0] fu_1_state_TEST;
    buff_1_1st_fu_dest_ar_t inbuff_1_1st_fu_dest_ar, outbuff_1_1st_fu_dest_ar;
    
    always_ff@(posedge clk) begin
      if (rst) begin
        for (int i = 0; i < ISSUE_WIDTH_MAX; i++) begin
          //fu_dest_cs[i].alu <= INT_ALU_LANE_MASK;
          //fu_dest_ns[i].alu <= INT_ALU_LANE_MASK;
        end
      end else begin
        fu_dest_cs <= fu_dest_ns;
      end
    end
    
	//functional unit binding State Machines
	//look into rewriting for more clarity
	//add more units later
	always_comb begin
        fu_dest_qual_ar = '0;
        fu_1_state_TEST = '0;
        lane_count = '{default:0};
        for (int i = 0; i < ISSUE_WIDTH_MAX; i++) begin
            fu_dest_ns[i].alu = INT_ALU_LANE_MASK;
            fu_dest_ns[i].mul = INT_MUL_LANE_MASK;
	    	case (instr_info_ar[i].ctrl_sig.fu_dest)
	    	    INT_ALU_LANE_MASK: begin 
	    	        for (int ln = 0; ln < CPU_NUM_LANES ; ln++)
	    	            lane_count[i].alu += fu_dest_cs[i].alu[ln];
	    	            
	    	        if ($unsigned(lane_count[i].alu) > 1) begin
	    	             inbuff_1_1st_fu_dest_ar.alu = fu_dest_cs[i].alu;
	    	            `ONE_1ST_LSB(outbuff_1_1st_fu_dest_ar.alu, inbuff_1_1st_fu_dest_ar.alu);
	    	            fu_dest_qual_ar[i] = outbuff_1_1st_fu_dest_ar.alu;
	    	            fu_dest_ns[i].alu &= ~fu_dest_qual_ar[i];
	    	        end else begin
	    	            fu_dest_qual_ar[i] = fu_dest_cs[i].alu;
	    	            fu_dest_ns[i].alu = INT_ALU_LANE_MASK;
	    	            fu_1_state_TEST[i] = 1;
	    	        end
	    	    end
	    	    
	    	    INT_MUL_LANE_MASK: begin 
	    	        for (int ln = 0; ln < CPU_NUM_LANES ; ln++)
	    	            lane_count[i].mul += fu_dest_cs[i].mul[ln];
	    	            
	    	        if ($unsigned(lane_count[i].mul) > 1) begin
	    	             inbuff_1_1st_fu_dest_ar.mul = fu_dest_cs[i].mul;
	    	            `ONE_1ST_LSB(outbuff_1_1st_fu_dest_ar.mul, inbuff_1_1st_fu_dest_ar.mul);
	    	            fu_dest_qual_ar[i] = outbuff_1_1st_fu_dest_ar.mul;
	    	            fu_dest_ns[i].mul &= ~fu_dest_qual_ar[i];
	    	        end else begin
	    	            fu_dest_qual_ar[i] = fu_dest_cs[i].mul;
	    	            fu_dest_ns[i].mul = INT_MUL_LANE_MASK;
	    	            fu_1_state_TEST[i] = 1;
	    	        end
	    	    end
	    	endcase
		end
	end	

	
//------------------------------------------------------------------------------------------------------------------------------------------//
// PDST BROADCASTING (Physical Destination)
//------------------------------------------------------------------------------------------------------------------------------------------//

logic [CPU_NUM_LANES-1:0][PDST_WIDTH-1:0] pdst_fwd;
logic [CPU_NUM_LANES-1:0][PDST_WIDTH-1:0] pdst_ex1;
logic [CPU_NUM_LANES-1:0][PDST_WIDTH-1:0] pdst_val_fwd;
logic [CPU_NUM_LANES-1:0][PDST_WIDTH-1:0] pdst_val_ex1;

logic [CPU_NUM_LANES-1:0][PDST_WIDTH-1:0] pdst_qd_latency_fwd;
logic [CPU_NUM_LANES-1:0][PDST_WIDTH-1:0] pdst_qd_latency_ex1;
logic [CPU_NUM_LANES-1:0][PDST_WIDTH-1:0] pdst_qd_latency_cdb;

logic [CPU_NUM_LANES-1:0]                 pdst_qd_latency_val_fwd;
logic [CPU_NUM_LANES-1:0]                 pdst_qd_latency_val_ex1;
logic [CPU_NUM_LANES-1:0]                 pdst_qd_latency_val_cdb;

// pdst to be matched against the rsv ety sources
// MUL takes 2 cycles so pdst is broadcasted a cycle late (EX1 instead of FWD),
// so that the dependent uop may issue a cycle late so it gets correct result
//
// MUL uop :  RSV | FWD | EX1 | EX2 |
// dep uop :            | RSV | FWD | EX1
//                               ^ dep uop gets correct value in FWD from EX2
always_comb begin
  for (int ln = 0; ln < CPU_NUM_LANES; ln++) begin
    pdst_qd_latency_fwd[ln]     = INT_ALU_LANE[ln] ? pdst_fwd     : '0
                                | INT_MUL_LANE[ln] ? pdst_ex1     : '0;
    pdst_qd_latency_val_fwd[ln] = INT_ALU_LANE[ln] ? pdst_val_fwd : '0
                                | INT_MUL_LANE[ln] ? pdst_val_ex1 : '0;
  end
end

//stage pdst (physical destination)
generate
  for (genvar ln = 0; ln < CPU_NUM_LANES; ln++) begin : pdst_val_staging
    `FF(pdst_ex1[ln],     pdst_fwd[ln],     clkfree)
    `FF(pdst_cdb[ln],     pdst_ex1[ln],     clkfree)
    `FF(pdst_val_ex1[ln], pdst_val_fwd[ln], clkfree)
    `FF(pdst_val_cdb[ln], pdst_val_ex1[ln], clkfree)

    `FF(pdst_qd_latency_ex1[ln],     pdst_qd_latency_fwd[ln],     clk_free)
    `FF(pdst_qd_latency_cdb[ln],     pdst_qd_latency_ex1[ln],     clk_free)
    `FF(pdst_qd_latency_val_ex1[ln], pdst_qd_latency_val_fwd[ln], clk_free)
    `FF(pdst_qd_latency_val_cdb[ln], pdst_qd_latency_val_ex1[ln], clk_free)
  end
endgenerate

//------------------------------------------------------------------------------------------------------------------------------------------//
// SOURCE DEPENDENCY TRACKING
//------------------------------------------------------------------------------------------------------------------------------------------//

logic [CPU_NUM_LANES-1:0][RS_NUM_ENTRIES-1:0][NUM_SRCS-1:0][CPU_NUM_LANES-1:0] match_fwd_src_dep_rsv;
logic [CPU_NUM_LANES-1:0][RS_NUM_ENTRIES-1:0][NUM_SRCS-1:0][CPU_NUM_LANES-1:0] match_ex1_src_dep_rsv;
logic [CPU_NUM_LANES-1:0][RS_NUM_ENTRIES-1:0][NUM_SRCS-1:0][CPU_NUM_LANES-1:0] match_cdb_src_dep_rsv;

logic [CPU_NUM_LANES-1:0][RS_NUM_ENTRIES-1:0][NUM_SRCS-1:0]                    match_any_src_dep_rsv;
logic [CPU_NUM_LANES-1:0][RS_NUM_ENTRIES-1:0][NUM_SRCS-1:0]                    src_rdy_next_rsv;
logic [CPU_NUM_LANES-1:0][RS_NUM_ENTRIES-1:0][NUM_SRCS-1:0]                    src_rdy_rsv;

// Source Dependency Tracking
always_comb begin
  match_fwd_src_dep_rsv = '0;
  match_ex1_src_dep_rsv = '0;
  match_cdb_src_dep_rsv = '0;
  match_any_src_dep_rsv = '0;

  // in flight dependency cam hits
	//match each RS entry source to other dependent execution lanes (ln_d)
	for (int ln = 0; ln < CPU_NUM_LANES; ln++) begin
    for (int ety = 0; ety < RS_NUM_ENTRIES; ety++) begin
      for (int s = 0; s < NUM_SRCS; s++) begin
        for (int ln = 0; ln < CPU_NUM_LANES; ln++) begin
          match_fwd_src_dep_rsv[ln][ety][src][[ln_d]  = (rs[ety].src[s] == pdst_qd_latency_fwd[ln_d]);
          match_ex1_src_dep_rsv[ln][ety][src][[ln_d]  = (rs[ety].src[s] == pdst_qd_latency_ex1[ln_d]);
          match_cdb_src_dep_rsv[ln][ety][src][[ln_d]  = (rs[ety].src[s] == pdst_qd_latency_cdb[ln_d]);

          //make sure match is valid
          match_fwd_src_dep_rsv[ln][ety][src][[ln_d] &= rs[ety].v & pdst_qd_latency_val_fwd[ln_d];
          match_ex1_src_dep_rsv[ln][ety][src][[ln_d] &= rs[ety].v & pdst_qd_latency_val_ex1[ln_d];
          match_cdb_src_dep_rsv[ln][ety][src][[ln_d] &= rs[ety].v & pdst_qd_latency_val_cdb[ln_d];  //CHANGE THIS TO WB1 (Write Back 1) instead of CDB (Common Data Bus) WIll allow for variable stages which may be great for future improvements
        end
      end
    end
	

    // final overall source dependency matching
    for (int ety = 0; ety < RS_NUM_ENTRIES; ety++) begin
      match_any_src_dep_rsv[ln][ety][src] = |(match_fwd_src_dep_rsv[ln][ety][src])
                                          | |(match_ex1_src_dep_rsv[ln][ety][src])
                                          | |(match_cdb_src_dep_rsv[ln][ety][src]);
    end
	end
end

// marking which sources have values ready
always_comb begin
	for (int ln = 0; ln < CPU_NUM_LANES; ln++) begin
    for (int ety = 0; ety < RS_NUM_ENTRIES; ety++) begin
      for (int s = 0; s < NUM_SRCS; s++) begin
        src_rdy_next_rsv[ln][ety][s] = src_rdy_rsv[ln][ety][s]
                                     | match_any_src_dep_rsv[ln][ety][s];
      end
    end
	end
end

generate
	for (int ln = 0; ln < CPU_NUM_LANES; ln++) begin : src_rdy_ln
    for (int ety = 0; ety < RS_NUM_ENTRIES; ety++) begin : src_rdy_ety
      for (int s = 0; s < NUM_SRCS; s++) begin : src_rdy_s
       `FF(src_rdy_rsv[ln][ety][s], src_rdy_next_rs[ln][ety][s], clk_free)
      end
    end
	end
endgenerate

logic [RS_NUM_ENTRIES-1:0] instr_rdy_2_disp_rsv;
logic [RS_NUM_ENTRIES-1:0] disp_block_rsv;

always_comb begin
	for (ln = 0; ln < CPU_NUM_LANES; ln++) begin
    for (int ety = 0; ety < RS_NUM_ENTRIES; ety++) begin
      instr_rdy_2_disp_rsv[ln][ety]  = (src_rdy_next_rsv[ln][ety][RS1] & src_rdy_next_rsv[ln][ety][RS2]); 
	  	                               & ~disp_block_rsv[ln][ety];
    end
	end
end

//------------------------------------------------------------------------------------------------------------------------------------------//
// RESERVATION STATION DISPATCH PICK ALGORITHM
//------------------------------------------------------------------------------------------------------------------------------------------//

	logic [CPU_NUM_LANES-1:0][RS_NUM_ENTRIES-1:0]      disp_fu_1st_1_rs;
	logic [CPU_NUM_LANES-1:0][RS_NUM_ENTRIES-1:0]      instruc_2_disp_fu_rs;
	logic [CPU_NUM_LANES-1:0][RS_NUM_ENTRIES_CLOG-1:0] fu_disp_enc_rs; //final encoding 

	//if there is more than one instruction in rs ready to dispatch to same fu as another instruction, grab first one
	//this implementation does not use instruction age in order to reduce area and logic complexity
	//may be some slight performance degredation on certain cases
	always_comb begin //TODO change to find oldest entry
		disp_fu_1st_1_rs = '{default:0};
		for (int ln = 0; ln < CPU_NUM_LANES; ln++) begin
	   	for (int ety = 0; ety < RS_NUM_ENTRIES; ety++) begin	   		     
		 `ONE_1ST_LSB(disp_fu_1st_1_rs[ln], instr_rdy_2_disp_rsv[ln]);
			end 
		end
	end

	always_comb begin
		for (int ln = 0; ln < CPU_NUM_LANES; ln++) begin
	   	for (int ety = 0; ety < RS_NUM_ENTRIES; ety++) begin 
			instruc_2_disp_fu_rs[ln][ety] = disp_fu_1st_1_rs[ln][ety];
			end 
		end
	end
	
	//one hot encoding to give index of isntruction in rs to dispatch to corresponding fu
	always_comb begin 
		for (int ln = 0; ln < CPU_NUM_LANES; ln++) begin
		 `ONE_HOT_ENCODE(fu_disp_enc_rs[ln], instruc_2_disp_fu_rs[ln]);
		end 
	end
	
	
//------------------------------------------------------------------------------------------------------------------------------------------//
// LANE DISPATCH ASSIGNMENT
//------------------------------------------------------------------------------------------------------------------------------------------//
	
	//This code is fucking awful. Please Fix *cry face*
	always_ff@(posedge clk) begin 
	   for (int ln = 0; ln < CPU_NUM_LANES; ln++) begin 
			if (INT_ALU_LANE_MASK[ln]) begin
				if (any_rdy_2_disp_qual_rs[ln]) begin 
          int_alu_ln_info_ex1[ln].v         <= 1;
					int_alu_ln_info_ex1[ln].src[RS_1] <= rs[fu_disp_enc_rs[ln]].V[RS_1];
					int_alu_ln_info_ex1[ln].src[RS_2] <= rs[fu_disp_enc_rs[ln]].ctrl_sig.alu_src ? rs[fu_disp_enc_rs[ln]].imm : 
					                                                                               rs[fu_disp_enc_rs[ln]].V[RS_2];
					int_alu_ln_info_ex1[ln].robid 	  <= rs[fu_disp_enc_rs[ln]].robid;
					int_alu_ln_info_ex1[ln].alu_ctrl  <= rs[fu_disp_enc_rs[ln]].ctrl_sig.alu_ctrl;
					
				end else begin
				  int_alu_ln_info_ex1[ln-INT_ALU_LN_OFFSET].v <= 0;
				end
			end
			if (INT_MUL_LANE_MASK[ln]) begin
			    if (any_rdy_2_disp_qual_rs[ln]) begin
                    int_mul_ln_info_ex1[ln].v         <= 1;
                    int_mul_ln_info_ex1[ln].src[RS_1] <= rs[fu_disp_enc_rs[ln]].V[RS_1];
                    int_mul_ln_info_ex1[ln].src[RS_2] <= rs[fu_disp_enc_rs[ln]].V[RS_1];
                    int_mul_ln_info_ex1[ln].robid     <= rs[fu_disp_enc_rs[ln]].robid;
                    int_mul_ln_info_ex1[ln].func3     <= rs[fu_disp_enc_rs[ln]].ctrl_sig.func3;

			    end else begin
			        int_mul_ln_info_ex1[ln].v         <= 0;
			    end
		    end 
	   	end	
	end
	

//------------------------------------------------------------------------------------------------------------------------------------------//
// RS HOUSEKEEPING
//------------------------------------------------------------------------------------------------------------------------------------------//


	///////////////////////////////////////////////
	// Invalidate Dispatched Instruction from RS
	always_ff@(posedge clk) begin
	   for (int ln = 0; ln < CPU_NUM_LANES; ln++) begin 
	       if (any_rdy_2_disp_qual_rs[ln]) begin
	           rs[fu_disp_enc_rs[ln]].valid <= 0;
	       end 
	   end
	end

	logic [RS_NUM_ENTRIES-1:0][NUM_SRCS-1:0][CPU_NUM_LANES-1:0]      match_src_dep_rs;         //find src dependency match -> which src of the rs entry has a match with the data on the producing common data bus lane 
  logic                                   [CPU_NUM_LANES-1:0]      inbuff_match_src_dep_rs;
  logic                                   [CPU_NUM_LANES_CLOG-1:0] outbuff_match_src_dep_rs; 
  logic [RS_NUM_ENTRIES-1:0][NUM_SRCS-1:0][CPU_NUM_LANES_CLOG-1:0] match_src_dep_idx_rs;     //index of which CDB lane data is dependent on
    
	always_comb begin
	  match_src_dep_rs = '{default:0};
	  for (int ety = 0; ety < RS_NUM_ENTRIES; ety++) begin
	    for (int src = 0; src < NUM_SRCS; src++) begin
	      for (int ln = 0; ln < CPU_NUM_LANES; ln++) begin
	          match_src_dep_rs[ety][src][ln] = (cdb_cmt[ln].robid == rs[ety].Q[src]) & rs[ety].valid & cdb_cmt[ln].v & rs[ety].Q_src_dep[src];	               
	      end
	      inbuff_match_src_dep_rs = match_src_dep_rs[ety][src];
	     `ONE_HOT_ENCODE(outbuff_match_src_dep_rs, inbuff_match_src_dep_rs)
	      match_src_dep_idx_rs[ety][src] = outbuff_match_src_dep_rs;
	    end
	  end
	end
	
	always_ff@(posedge clk) begin
	  for (int ety = 0; ety < RS_NUM_ENTRIES; ety++) begin
	    for (int src = 0; src < NUM_SRCS; src++) begin
	      if (|match_src_dep_rs[ety][src]) begin
	        rs[ety].Q_src_dep[src] <= 0;
	        rs[ety].V[src]         <= cdb_cmt[match_src_dep_idx_rs[ety][src]].data;
	      end
	    end 
	  end
	end

	
endmodule 