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
    input wire logic clk, rst,
    input wire logic [15:0] instr_id_input,
       
    output [ROB_SIZE_CLOG-1:0] robid_out
    
    );
    
    cdb_in [CPU_NUM_LANES-1:0] cdb_in_t;
    
    //////////////////////////////////////////////////////////////////
    ///
    /// Fetch RAT Instance
    ///
    /// includes decode as well
    
    logic  [ISSUE_WIDTH_MAX-1:0] instr_val_id; //valid instr id
    logic  [ISSUE_WIDTH_MAX-1:0][DATA_LEN-1:0] instr_id;

    //inputs from rob
    logic  [ISSUE_WIDTH_MAX-1:0][ROB_SIZE_CLOG-1:0] rob_is_ptr;
    logic   rob_full;
    //rob retire bus
    logic  [ROB_MAX_RETIRE-1:0][SRC_LEN-1:0]          rd_ret;
    logic  [ROB_MAX_RETIRE-1:0]                      val_ret;
    logic  [ROB_MAX_RETIRE-1:0]                  rfWrite_ret;
    logic  [ROB_MAX_RETIRE-1:0][DATA_LEN-1:0]    wb_data_ret;
    logic  [ROB_MAX_RETIRE-1:0][ROB_SIZE_CLOG-1:0] robid_ret;
    
    //outputs of f-rat
    logic [ISSUE_WIDTH_MAX-1:0][OPCODE_LEN-1:0] opcode_ar;
    logic [ISSUE_WIDTH_MAX-1:0][SRC_LEN-1:0]        rd_ar;
    logic [ISSUE_WIDTH_MAX-1:0][NUM_SRCS-1:0][RAT_RENAME_DATA_WIDTH-1:0] src_rdy_2_issue_ar;
    logic [ISSUE_WIDTH_MAX-1:0][NUM_SRCS-1:0]                  src_data_type_rdy_2_issue_ar; // 1: PRF, 0: ROB 
    logic [ISSUE_WIDTH_MAX-1:0]      		instr_val_ar;

    instr_info_t [ISSUE_WIDTH_MAX-1:0]     instr_info_ar; //important instr. info passed down pipeline
    //inputs from functional units
	logic [CPU_NUM_LANES-1:0] fu_free, fu_free_1c; //fu_free_1c means fu free in 1 cycle
    
	//rs OUTPUTS TO EXECUTION UNITS
	int_alu_lane_t [NUM_INT_ALU_LN+INT_ALU_LN_OFFSET-1:INT_ALU_LN_OFFSET] int_alu_ln_info_ex1;
	int_mul_lane_t [NUM_INT_MUL_LN+INT_MUL_LN_OFFSET-1:INT_MUL_LN_OFFSET] int_mul_ln_info_ex1;
	logic rs_full;
    //*****strictly testing signals*****
    logic [ISSUE_WIDTH_MAX-1:0][OPCODE_LEN-1:0] opcode_id;
    logic [ISSUE_WIDTH_MAX-1:0][FUNC3_WIDTH-1:0] func3_id;
    logic [ISSUE_WIDTH_MAX-1:0][SRC_LEN-1   :0] rd_id;
    logic [ISSUE_WIDTH_MAX-1:0][SRC_LEN-1   :0] rs1_id;
    logic [ISSUE_WIDTH_MAX-1:0][SRC_LEN-1   :0] rs2_id;
    //logic [ISSUE_WIDTH_MAX-1:0][DATA_LEN-1:0] instr_id;
    
    always_comb begin
      instr_id = '{default:0};
          instr_id[0][6:0]   = instr_id_input[6:0];
          instr_id[0][11:7]  = instr_id_input[11:7];
          instr_id[0][19:15] = instr_id_input[19-5:15-5];
          instr_id[0][24:20] = instr_id_input[24-10:20-10];
          instr_id[0][14:12] = instr_id_input[14:12];
      for (int i = 1; i < ISSUE_WIDTH_MAX; i++) begin
          instr_id[i][6:0] = opcode_id[i];
          instr_id[i][11:7] = rd_id[i];
          instr_id[i][19:15] = rs1_id[i];
          instr_id[i][24:20] = rs2_id[i];
          instr_id[i][14:12] = func3_id[i];
      end
    end
    
   // f_rat f_rat_t(.*);
    
    ///////////////////////////////////////////////////
    //
    // Multiported Regfile Instance 
    //
    
    //only output for now -> may want to add a valid signal
    logic [NUM_RF_R_PORTS-1:0][DATA_LEN-1:0] rf_r_port_data;
    
    //regfile regfile_t(.*);
    
    ///////////////////////////////////////////////////
    //
    // Reservation Station Instance 
    //
    
    //inputs from CDB
	logic [CPU_NUM_LANES-1:0][ROB_SIZE_CLOG-1:0] robid_cdb;
	logic [CPU_NUM_LANES-1:0][5:0]  op_cdb;
	logic [CPU_NUM_LANES-1:0][4:0]  rd_tag_cdb;
	logic [CPU_NUM_LANES-1:0] 	   commit_instr_cdb;
	logic [CPU_NUM_LANES-1:0][31:0] result_data_cdb;

	//inputs from functional units
	logic [CPU_NUM_LANES-1:0] fu_free, fu_free_1c; //fu_free_1c means fu free in 1 cycle
    
	assign robid_out = alu_lane_info_ex1[0].robid;
    
    //rs rs_t(.*);
      
    // END FRAT INSTANCE
    /////////////////////////////////////////////////////////////////////
    
    
    ////////////////////////////////////
    // Integer Multipliers 

    genvar g_i, g_ln;
    
    generate
        for (g_i = 0; g_i < NUM_INT_MUL_LN; g_i++) begin
            int_mul int_mul_t(.clk(clk),
                              .mul_val(int_mul_ln_info_ex1[g_i].val),
                              .op1(int_mul_ln_info_ex1[g_i].src[RS_1]),
                              .op2(int_mul_ln_info_ex1[g_i].src[RS_2]),
                              .func3(int_mul_ln_info_ex1[g_i].func3),
                              .robid(int_mul_ln_info_ex1[g_i].robid),
                              .mul_val(   cdb_in[g_i+INT_MUL_LN_OFFSET].v),
                              .robid_ex1( cdb_in[g_i+INT_MUL_LN_OFFSET].robid),
                              .mul_result(cdb_in[g_i+INT_MUL_LN_OFFSET].data)
                              );                              
        end
    endgenerate
    
    
    //////////////////////////////////////////
    // Integer ALUs  
    
    generate
        for (g_ln = INT_ALU_LN_OFFSET; g_ln < INT_ALU_LN_OFFSET+NUM_INT_ALU_LN; g_ln++) begin
            int_alu in_alu_t(.alu_val_ex1(int_alu_ln_info_ex1[g_ln].v),
                             .op1_ex1(int_alu_ln_info_ex1[g_ln].src[RS_1]),
                             .op2_ex1(int_alu_ln_info_ex1[g_ln].src[RS_2]),
                             .alu_ctrl_ex1(int_alu_ln_info_ex1[g_ln].alu_ctrl),
                             .robid_ex1(int_alu_ln_info_ex1[g_ln].robid),
                             .alu_val(cdb_in[g_ln].v),
                             .robid(cdb_in[g_ln].robid),
                             .result_alu(cdb_in[g_ln].data)
                             );
        end      
    endgenerate
    
    ///////////////////////////////////
    // Common Data Bus (CDB)
    
    generate
        for (g_ln = 0; g_ln < CPU_NUM_LANES; g_ln++) begin
            cdb cdb_t(.v(cdb_in[g_ln].v),
                      .robid(cdb_in[g_ln].robid),
                      .data(cdb_in[g_ln].data)
                      );
        end
    endgenerate
    
    ///////////////////////////////////
    // Re-Order Buffer (ROB)
    
    rob rob_t(.*);
    
    
endmodule
