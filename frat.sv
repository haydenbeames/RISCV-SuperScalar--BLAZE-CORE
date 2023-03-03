`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01/28/2023 12:36:13 PM
// Design Name: 
// Module Name: rat
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

module f_rat(
    input logic   clk, rst,
    input logic  [ISSUE_WIDTH_MAX-1:0] instr_val_id, //valid instr id
    input logic  [ISSUE_WIDTH_MAX-1:0][OPCODE_LEN-1:0] opcode_id,
    input logic  [ISSUE_WIDTH_MAX-1:0][SRC_LEN-1   :0] rd_id,
    input logic  [ISSUE_WIDTH_MAX-1:0][SRC_LEN-1   :0] rs1_id,
    input logic  [ISSUE_WIDTH_MAX-1:0][SRC_LEN-1   :0] rs2_id,

    //inputs from rob
    input logic  [ROB_SIZE_CLOG-1:0] rob_is_ptr,
    input logic  [ROB_SIZE_CLOG-1:0] mispredict_tag_id,
    input logic   branch_clear_id,
    input logic   rob_full,
    //rob retire bus
    input logic  [ROB_MAX_RETIRE-1:0][SRC_LEN-1:0] rd_ret,
    input logic  [ROB_MAX_RETIRE-1:0]              val_ret,
    input logic  [ROB_MAX_RETIRE-1:0]           branch_ret,
    
    //outputs of f-rat
    output logic [ISSUE_WIDTH_MAX-1:0][NUM_SRCS-1:0][RAT_RENAME_DATA_WIDTH-1:0] src_renamed_ar,
    output logic [ISSUE_WIDTH_MAX-1:0][NUM_SRCS-1:0]                      src_data_type_rat_ar, // 1: PRF, 0: ROB
    output logic [ISSUE_WIDTH_MAX-1:0][ROB_SIZE_CLOG-1:0]                             robid_is
    );
    
    /////////////////////////////////////////////////
    ///// Front-End Register Alias Table (FRAT)
    /////////////////////////////////////////////////
    
    typedef struct packed { 
        logic dataType; //if 1, data points to ROB, else points to regfile 
        logic [RAT_RENAME_DATA_WIDTH-1:0] table_data; //points to addr data dependency will come from
    } rat_t;
    rat_t [RAT_SIZE-1:0] rat;
    
    initial begin
        for (int i = 0; i < RAT_SIZE; i++) begin
            rat[i].table_data = i;
            rat[i].rf   = 0; 
        end
    end
    
    logic [ISSUE_WIDTH_MAX-1:0] storeInstruc_id, branchInstruc_id;
    always_comb begin
        for (int i = 0; i < ISSUE_WIDTH_MAX; i++) begin
            storeInstruc_id[i]  = (opcode_id[i] == S_TYPE);
            branchInstruc_id[i] = (opcode_id[i] == SB_TYPE);
        end
    end
    
    //rename rs1 & rs2 before bypass from rob
    always_ff@(posedge clk) begin
        for (int i = 0; i < ISSUE_WIDTH_MAX; i++) begin
            if (instr_val_id[i]) begin
                src_renamed_ar[i][RS_1] <= rat[rs1_id[i]].table_data;
                src_renamed_ar[i][RS_2] <= rat[rs2_id[i]].table_data;
                
                src_data_type_rat_ar[i][RS_1] <= rat[rs1_id[i]].dataType;
                src_data_type_rat_ar[i][RS_2] <= rat[rs2_id[i]].dataType;
            end
        end
    end
    
    // Retirement Override
    always_comb begin
        
    end
    
    // update RAT  
    // need to also check for rd write conflicts and rd with rob write conflicts
    logic [ROB_MAX_RETIRE-1:0] rd_rob_w_conflict;
     
    // # RAT write ports = Retire Width
    always_ff@(posedge clk) begin
        rd_rob_w_conflict = '0;
        if (~(branchInstruc_id[0] || storeInstruc_id[0] ||
              branchInstruc_id[1] || storeInstruc_id[1])) begin
            for (int r = 0; r < ROB_MAX_RETIRE; r++) begin
                for (int i = 0; i < ISSUE_WIDTH_MAX; i++) begin
                    rd_rob_w_conflict[r] = instr_val_id[i] & ~branch_ret[r] & val_ret[r] ? 
                                          (rd_ret[r] == rd_id[i]): 0;
                end
            end
            
            //dual issue
            case (instr_val_id & ~{rob_full,rob_full})
                (2'b01): begin
                    rat[rd_id[0]].table_data <= rd_rob_w_conflict[0] ? rob_is_ptr : rd_ret;
                    robid_is[0]              <= rob_is_ptr;
                end
                (2'b10): begin
                    rat[rd_id[1]].table_data <= rob_is_ptr;
                    robid_is[1]              <= rob_is_ptr;
                end
                (2'b11): begin
                    if (rd_id[0] == rd_id[1]) begin  // cover rd conflict
                        rat[rd_id[1]].table_data <= rob_is_ptr + 1;
                    end else begin
                        rat[rd_id[0]].table_data <= rob_is_ptr;
                        robid_is[0]              <= rob_is_ptr;
                        rat[rd_id[1]].table_data <= rob_is_ptr + 1;
                        robid_is[1]              <= rob_is_ptr + 1;
                    end
                end
                default: begin end
            endcase
        end
        
        for (int r = 0; r < ROB_MAX_RETIRE; r++) begin
            
        end
    end
        
    ///////////////////////////////////////////////////////////////////////
    /////
    ///// BRATCR  (Branch RAT Copy Register)
    /////
    ///////////////////////////////////////////////////////////////////////
    
    logic [BRATCR_NUM_ETY_CLOG-1:0] bratcr_ety_ptr = 0;
    logic bratcr_full;
    
    typedef struct packed { 
        logic [RAT_SIZE-1:0][RAT_RENAME_DATA_WIDTH-1:0] rat_copy_data;
        logic [ROB_SIZE_CLOG-1:0]   robid;
        logic                       valid;
    } bratcr_t;
    
    bratcr_t [BRATCR_NUM_ETY-1:0] bratcr;
    logic [2:0]testCOND = '0;
    
    always_ff@(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < BRATCR_NUM_ETY; i++)
                bratcr[i].valid <= 0;
            bratcr_ety_ptr <= '0;
        end  
        else if (((branchInstruc_id[0] | storeInstruc_id[0]) ^ (branchInstruc_id[1] | storeInstruc_id[1])
                   | (bratcr_ety_ptr == (BRATCR_NUM_ETY-1))) & ~bratcr_full) begin //if only one instr is branch
            for (int i = 0; i < RAT_SIZE; i++) begin
                bratcr[bratcr_ety_ptr].rat_copy_data[i] <= rat[i].table_data;
            end
            bratcr[bratcr_ety_ptr].valid <= 1'b1;
            bratcr_ety_ptr               <= bratcr_ety_ptr + 1'b1;
            bratcr[bratcr_ety_ptr].robid <= branchInstruc_id[0] ? rob_is_ptr : rob_is_ptr + 1;
            testCOND <= 1;
            
        end else if (((branchInstruc_id[0] | storeInstruc_id[0]) & (branchInstruc_id[1] | storeInstruc_id[1])
                  & ~((bratcr_ety_ptr) == (BRATCR_NUM_ETY-1))) & ~bratcr_full) begin
            for (int i = 0; i < RAT_SIZE; i++) begin
                bratcr[bratcr_ety_ptr    ].rat_copy_data[i] <= rat[i].table_data; 
                bratcr[bratcr_ety_ptr + 1].rat_copy_data[i] <= rat[i].table_data; 
            end
            bratcr[bratcr_ety_ptr    ].valid <= 1'b1;
            bratcr[bratcr_ety_ptr + 1].valid <= 1'b1;
            bratcr_ety_ptr                   <= bratcr_ety_ptr + 2;
            bratcr[bratcr_ety_ptr    ].robid <= rob_is_ptr;
            bratcr[bratcr_ety_ptr + 1].robid <= rob_is_ptr + 1;
            testCOND <= 2;
        end
    end 
 
    always_comb begin
        bratcr_full = 1;
        for (int i = 0; i < BRATCR_NUM_ETY; i++)
            bratcr_full &= bratcr[i].valid;
    end
      
endmodule
