`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Hayden Beames
// 
// Create Date: 08/04/2023 08:59:16 PM
// Design Name: 
// Module Name: fwd
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

//include files
`include "rtl_constants.sv"
`include "decode_constants.sv"
`include "riscv_alu_constants.sv"
`include "macros.sv"
`include "structs.sv"

//fwd unit  
module fwd(
    input  wire logic clk,
    input  info_instr_inflight_t [CPU_NUM_LANES-1:0] info_instr_fwd,
    input                  cdb_t [CDB_NUM_LANES-1:0] cdb_cmt,   
    input  wire logic [NUM_PRF_R_PORTS-1:0][DATA_LEN-1:0] prf_r_port_data,
    
    output info_instr_inflight_t [CPU_NUM_LANES-1:0] info_instr_ex1
    );
    
    /*
    1 Cycle Lane:      AR | RS | FWD | EX1 | CMT
    Long Latency Lane: AR | RS | FWD | EX1 | EX2 | CMT
    
    FWD MUX: select data out of EX1, EX2, or CMT 
    
    Scheduling determined in RS to time FWD select muxes
    */
    
    logic [CPU_NUM_LANES-1:0][NUM_SRCS-1:0][CPU_NUM_LANES-1:0]             sel_cdb_ln_fwd;
    logic [CPU_NUM_LANES-1:0][NUM_SRCS-1:0][CPU_NUM_LANES_CLOG-1:0]    sel_cdb_ln_idx_fwd; //index encoding
    logic                                  [CPU_NUM_LANES-1:0]       in_onhot_sel_cdb_fwd;
    logic                                  [CPU_NUM_LANES_CLOG-1:0] out_onhot_sel_cdb_fwd;
    
    // match src dependency coming out of CDB
    always_comb begin
        sel_cdb_ln_fwd = '{default:'0};
        for (int i = 0; i < CPU_NUM_LANES; i++) begin
			for (int s = 0; s < NUM_SRCS; s++) begin
            	for (int j = 0; j < CPU_NUM_LANES; j++) begin
            	    sel_cdb_ln_fwd[i][s][j] = info_instr_fwd[i].v & (info_instr_fwd[i].src[s] == cdb_cmt[j].robid) & ~info_instr_fwd[i].src_prf[s];
	
            	    in_onhot_sel_cdb_fwd = sel_cdb_ln_fwd[i][s];
            	   `ONE_HOT_ENCODE(out_onhot_sel_cdb_fwd, in_onhot_sel_cdb_fwd);
            	    sel_cdb_ln_idx_fwd[i][s] = out_onhot_sel_cdb_fwd;
            	end
			end
        end
    end

    //for now just selecting prf data
    logic [CPU_NUM_LANES-1:0][NUM_SRCS-1:0][NUM_FWD_SEL_CLOG-1:0] sel_data_fwd;
    logic [CPU_NUM_LANES-1:0][NUM_SRCS-1:0][DATA_LEN-1:0]         src_data_fwd;

	always_comb begin
        for (int ln = 0; ln < CPU_NUM_LANES; ln++) begin
            for (int s = 0; s < NUM_SRCS; s++) begin
				sel_data_fwd[ln][s] = ~info_instr_fwd[i].src_prf[s] ; //need to extend bits for src_prf. Also add in other forward selects when fwd_mtx is finished
			end 
		end
	end 
    // forwarding mux
    always_comb begin
        for (int ln = 0; ln < CPU_NUM_LANES; ln++) begin
            for (int s = 0; s < NUM_SRCS; s++) begin
                unique case (sel_data_fwd)
                    PRF_DATA_READ: // 0 default case
                        src_data_fwd[ln][s] = prf_r_port_data[ln*NUM_SRCS+s];
                    PRF_FWD:
                        src_data_fwd[ln][s] = cdb_cmt[sel_cdb_ln_idx_fwd[ln]];
                endcase
            end
        end
    end

    
    /////////////////////////////////////////////////////
    ///
    ///  Assign instructions to execution units
    ///
   
   
   	always_ff@(posedge clk) begin 
	   for (int ln = 0; ln < CPU_NUM_LANES; ln++) begin 
            // ALU Lanes
			if (INT_ALU_LANE_MASK[ln]) begin
                info_instr_ex1[ln].v         <= info_instr_fwd[ln].v;       
				info_instr_ex1[ln].src[RS_1] <=   src_data_fwd[ln][RS_1];
				info_instr_ex1[ln].src[RS_2] <=   src_data_fwd[ln][RS_2];
				info_instr_ex1[ln].robid 	 <= info_instr_fwd[ln].robid;	 
				info_instr_ex1[ln].alu_ctrl  <= info_instr_fwd[ln].alu_ctrl; 
			end
            // MUL Lanes
			if (INT_MUL_LANE_MASK[ln]) begin
                info_instr_ex1[ln].v         <= info_instr_fwd[ln].v;       
				info_instr_ex1[ln].src[RS_1] <=   src_data_fwd[ln][RS_1];
				info_instr_ex1[ln].src[RS_2] <=   src_data_fwd[ln][RS_2];
				info_instr_ex1[ln].robid 	 <= info_instr_fwd[ln].robid;	 
				info_instr_ex1[ln].func3     <= info_instr_fwd[ln].func3;   
		    end 
	   	end	
	end	 
    
endmodule
