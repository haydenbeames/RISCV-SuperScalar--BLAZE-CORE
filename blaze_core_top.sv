`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/24/2023 03:32:15 PM
// Design Name: 
// Module Name: blaze_core_top
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
`include "structs.sv"

module blaze_core_top(
  input wire logic clk_free_master,
  input wire logic global_rst,
  input wire logic [ISSUE_WIDTH_MAX-1:0]           instr_val_id,
  input wire logic [ISSUE_WIDTH_MAX-1:0][DATA_LEN-1:0] instr_id,
     
  output [ROB_SIZE_CLOG-1:0] robid_out
  
  );
  
  //general signals from ID input ////
  logic [ISSUE_WIDTH_MAX-1:0][SRC_LEN-1:0]    rd_id;
  logic [ISSUE_WIDTH_MAX-1:0][OPCODE_LEN-1:0] opcode_id;
  logic [ISSUE_WIDTH_MAX-1:0][SRC_LEN-1   :0] rs1_id;
  logic [ISSUE_WIDTH_MAX-1:0][SRC_LEN-1   :0] rs2_id;
  logic [ISSUE_WIDTH_MAX-1:0][FUNC3_SIZE-1:0] func3_id;
  logic [ISSUE_WIDTH_MAX-1:0][FUNC7_SIZE-1:0] func7_id;
  
  always_comb begin
    for (int i = 0; i < ISSUE_WIDTH_MAX; i++) begin
      opcode_id[i] = instr_id[i][6:0];
      rd_id[i]     = instr_id[i][11:7];
      rs1_id[i]    = instr_id[i][19:15];
      rs2_id[i]    = instr_id[i][24:20];
		  func3_id[i]  = instr_id[i][14:12];
		  func7_id[i]  = instr_id[i][31:25];
    end
  end    
  
  //////////////////////
  // CDB (Common Data Bus) signals
  cdb_t [CPU_NUM_LANES-1:0] cdb_in;
  cdb_t [CPU_NUM_LANES-1:0] cdb_cmt;
  
  ////////////////////////
  /// ROB output  
  info_ret_t [ROB_MAX_RETIRE-1:0]                     info_ret;
  logic      [ROB_SIZE_CLOG-1:0]                      ret_ptr;
  logic                                               rob_full;
  logic      [ISSUE_WIDTH_MAX-1:0][ROB_SIZE_CLOG-1:0] rob_is_ptr;
  ////////////////////////
  
  //outputs of f-rat
  logic        [ISSUE_WIDTH_MAX-1:0][OPCODE_LEN-1:0]                  opcode_ar;
  logic        [ISSUE_WIDTH_MAX-1:0][PRF_SIZE_CLOG-1:0]               rd_ar; //to ROB
  logic        [ISSUE_WIDTH_MAX-1:0][NUM_SRCS-1:0]                    src_valid_ar;
  logic        [ISSUE_WIDTH_MAX-1:0][NUM_SRCS-1:0][PRF_SIZE_CLOG-1:0] src_rdy_2_issue_ar; //this is the actual pdst
  logic        [ISSUE_WIDTH_MAX-1:0][NUM_SRCS-1:0]                    src_data_type_rdy_2_issue_ar; // 1: PRF, 0: ROB 
  logic        [ISSUE_WIDTH_MAX-1:0]                                  instr_val_ar;
  instr_info_t [ISSUE_WIDTH_MAX-1:0]                                  instr_info_id; //to reorder buffer
  instr_info_t [ISSUE_WIDTH_MAX-1:0]                                  instr_info_ar;
  logic        [ISSUE_WIDTH_MAX-1:0][CPU_NUM_LANES-1:0]               rs_binding_ar;
  //////////////////////////////
  
  ////////////////////////
  
  rat rat_t(.*);
  
  ///////////////////////////////////////////////////
  //
  // Multiported Regfile Instance 
  //
  
  //only output for now -> may want to add a valid signal
  logic [NUM_RF_R_PORTS-1:0][DATA_LEN-1:0] rf_r_port_data;
  
//  regfile regfile_t(.*);
  
  ///////////////////////////////////////////////////
  // RS Outputs 
  //int_alu_lane_t [NUM_INT_ALU_LN+INT_ALU_LN_OFFSET-1:INT_ALU_LN_OFFSET] int_alu_ln_info_ex1;
  //int_mul_lane_t [NUM_INT_MUL_LN+INT_MUL_LN_OFFSET-1:INT_MUL_LN_OFFSET] int_mul_ln_info_ex1;
  ///////////////////////////////////////////////////
  
  
	//assign robid_out = alu_lane_info_ex1[0].robid;
  int_lane_info_t [CPU_NUM_LANES-1:0] int_lane_info_ex1;
  logic           [CPU_NUM_LANES-1:0]                                 rs_full;
  logic           [CPU_NUM_LANES-1:0][RS_NUM_ENTRIES_CLOG:0]          rs_count;
  
  rs rs_t(.*);
    
  // END FRAT INSTANCE
  /////////////////////////////////////////////////////////////////////
  
  
  ////////////////////////////////////
  // Integer Multipliers 
  genvar g_i, g_ln;

  //////////////////////////////////////////
  // Integer ALUs  
  
//  generate
//      for (g_ln = INT_ALU_LN_OFFSET; g_ln < INT_ALU_LN_OFFSET+NUM_INT_ALU_LN; g_ln++) begin
//          int_alu in_alu_t(.alu_val_ex1        (int_alu_ln_info_ex1[g_ln].v        ),
//                           .op1_ex1            (int_alu_ln_info_ex1[g_ln].src[RS_1]),
//                           .op2_ex1            (int_alu_ln_info_ex1[g_ln].src[RS_2]),
//                           .alu_ctrl_ex1       (int_alu_ln_info_ex1[g_ln].alu_ctrl ),
//                           .robid_ex1          (int_alu_ln_info_ex1[g_ln].robid    ),
//                           .alu_result_val_ex1 (cdb_in[g_ln].v                     ),
//                           .robid_result_ex1   (cdb_in[g_ln].robid                 ),
//                           .result_alu_ex1     (cdb_in[g_ln].data                  )
//                           );
//      end      
//  endgenerate  
//  
//  generate
//      for (g_i = INT_MUL_LN_OFFSET; g_i < NUM_INT_MUL_LN+INT_MUL_LN_OFFSET; g_i++) begin
//          int_mul int_mul_t(.clk           (clk                                ),
//                            .mul_val_ex1   (int_mul_ln_info_ex1[g_i].v         ),
//                            .op1_ex1       (int_mul_ln_info_ex1[g_i].src[RS_1] ),
//                            .op2_ex1       (int_mul_ln_info_ex1[g_i].src[RS_2] ),
//                            .func3_ex1     (int_mul_ln_info_ex1[g_i].func3     ),
//                            .robid_ex1     (int_mul_ln_info_ex1[g_i].robid     ),
//                            .mul_val_ex2   (cdb_in[g_i].v                      ),
//                            .robid_ex2     (cdb_in[g_i].robid                  ),
//                            .mul_result_ex2(cdb_in[g_i].data                   )
//                            );                   
//      end
//  endgenerate  
//  
//  
//  ///////////////////////////////////
//  // Common Data Bus (CDB)
//  
//  generate
//      for (g_ln = 0; g_ln < CPU_NUM_LANES; g_ln++) begin
//          cdb cdb_t(.clk       (clk                ),
//                    .v         (cdb_in[g_ln].v     ),
//                    .robid     (cdb_in[g_ln].robid ),
//                    .data      (cdb_in[g_ln].data  ),
//                    .v_cmt     (cdb_cmt[g_ln].v    ),
//                    .robid_cmt (cdb_cmt[g_ln].robid),
//                    .data_cmt  (cdb_cmt[g_ln].data )                    
//                   );
//      end
//  endgenerate
//  
//  ///////////////////////////////////
//  // Re-Order Buffer (ROB)
//  
//  rob rob_t(.*);
    
    
endmodule
