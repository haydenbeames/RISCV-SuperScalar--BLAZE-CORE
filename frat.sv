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
    input logic  [ROB_SIZE_CLOG-1:0] rob_is_ptr_p1,
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
        logic rf; // 1: PRF, 0: ROB
        logic [RAT_RENAME_DATA_WIDTH-1:0] table_data; //points to addr data dependency will come from
    } rat_t;
    rat_t [RAT_SIZE-1:0] rat;
    
    initial begin
        for (int i = 0; i < RAT_SIZE; i++) begin
            rat[i].table_data = i;
            rat[i].rf   = 1; 
        end

    logic [ISSUE_WIDTH_MAX-1:0] storeInstruc_id, branchInstruc_id;
    always_comb begin
        for (int i = 0; i < ISSUE_WIDTH_MAX; i++) begin
            storeInstruc_id[i]  = (opcode_id[i] == S_TYPE);
            branchInstruc_id[i] = (opcode_id[i] == SB_TYPE);
        end
    end
    
    always_ff@(posedge clk) begin
        for (int i = 0; i < RETIRE_WIDTH_MAX; i++) begin
            if (rat_write_id[i]) begin
                rat[rat_port_addr_id[i]].table_data <= rat_port_data_id[i];
                rat[rat_port_addr_id[i]].rf         <= ret_val[i] ? 1 : 0; //change to constants
            end
        end
    end
    
    //rename rs1 & rs2 before bypass from rob
    always_ff@(posedge clk) begin
        for (int i = 0; i < ISSUE_WIDTH_MAX; i++) begin
            if (instr_val_id[i]) begin
                src_renamed_ar[i][RS_1] <= rat[rs1_id[i]].table_data;
                src_renamed_ar[i][RS_2] <= rat[rs2_id[i]].table_data;
                
                src_data_type_rat_ar[i][RS_1] <= rat[rs1_id[i]].rf;
                src_data_type_rat_ar[i][RS_2] <= rat[rs2_id[i]].rf;
            end
        end
    end
    
    // Retirement Override
    always_comb begin
        
    end
    
    // update RAT  
    // need to also check for rd write conflicts and rd with rob write conflicts
    logic [ROB_MAX_RETIRE-1:0] ret_w_val_id;
    logic [ROB_MAX_RETIRE+ISSUE_WIDTH_MAX-1:0] rat_w_qual_id;
    logic [ROB_MAX_RETIRE+ISSUE_WIDTH_MAX-1:0][ROB_MAX_RETIRE+ISSUE_WIDTH_MAX-1:0] rat_ret_rd_conflict_mtx_id;

    // write conflict handling
    always_comb begin
        ret_w_val_id = val_ret & ~branch_ret; //checking which retiring instr. are updating rat/regfile

        rat_ret_rd_conflict_mtx_id = '{default:0};
        for (int i = 0; i < ISSUE_WIDTH_MAX; i++) begin
            for (int j = 0; j < ISSUE_WIDTH_MAX; j++) begin
                if (j != i)
                    //this mtx shows conflicts in respect to its own write port
                    rat_ret_rd_conflict_mtx_id[i][j] = ~(storeInstruc_id[i] | branchInstruc_id[i]) & instr_val_id[i] & (rd_id[i] == rd_id[j]);
            end
            
            for (int j = ISSUE_WIDTH_MAX; j < RETIRE_WIDTH_MAX+ISSUE_WIDTH_MAX; j++) begin
                for (int k = 0; k < RETIRE_WIDTH_MAX; k++) begin
                     rat_ret_rd_conflict_mtx_id[i][j] |= ret_w_val_id[k] & (rd_id[i] == rd_ret[k]);
                end
            end
        end
        
        
        for (int i = ISSUE_WIDTH_MAX; i < RETIRE_WIDTH_MAX+ISSUE_WIDTH_MAX; i++) begin  //write port in question
            for (int j = ISSUE_WIDTH_MAX; j < RETIRE_WIDTH_MAX+ISSUE_WIDTH_MAX; j++) begin //comparison to other write ports
                if (j != i)
                    //this mtx shows conflicts in respect to its own write port
                    rat_ret_rd_conflict_mtx_id[i][j] = ret_w_val_id[i-ISSUE_WIDTH_MAX] & (rd_ret[i-ISSUE_WIDTH_MAX] == rd_ret[j-ISSUE_WIDTH_MAX]);
            end
        end
        
        rat_w_qual_id = '{default:0};
        for (int i = 0; i < RETIRE_WIDTH_MAX+ISSUE_WIDTH_MAX; i++) begin 
            for (int j = (i+1); j < RETIRE_WIDTH_MAX+ISSUE_WIDTH_MAX; j++) begin
                rat_w_qual_id[i] |= ~rat_ret_rd_conflict_mtx_id[i][j];
            end
        end
    end
    
    logic [RETIRE_WIDTH_MAX-1:0]                    rat_write_id;
    logic [RETIRE_WIDTH_MAX-1:0][ROB_SIZE_CLOG-1:0] rat_port_data_id;
    logic [RETIRE_WIDTH_MAX-1:0][ROB_SIZE_CLOG-1:0] rat_instr_rd_data_id;
    logic [RETIRE_WIDTH_MAX-1:0][SRC_LEN      -1:0] rat_port_addr_id;

    // generate write enables rat
    always_comb begin
        for (int i = 0; i < ISSUE_WIDTH_MAX; i++) begin
            rat_write_id[i] = (rat_w_qual_id[i] | rat_w_qual_id[i+ISSUE_WIDTH_MAX]) & ~rob_full; //test with valid signals, valid is included above but simulate to be sure
        end
        for (int i = ISSUE_WIDTH_MAX; i < RETIRE_WIDTH_MAX; i++) begin
            rat_write_id[i] = rat_w_qual_id[i+ISSUE_WIDTH_MAX] & ~rob_full;
        end
    end

    always_comb begin
        rat_port_data_id[0] = ret_val[0] ? rd_ret[0] : is_ptr;
        rat_port_data_id[1] = ret_val[1] ? rd_ret[1] : (instr_val_id[0] ? rob_is_ptr_p1 : rob_is_ptr);

        rat_port_addr_id[0] = ret_val[0] ? rd_ret[0] : rd_id[0];
        rat_port_addr_id[1] = ret_val[1] ? rd_ret[1] : rd_id[1];

        for (int i = ISSUE_WIDTH_MAX; i < RETIRE_WIDTH_MAX; i++) begin
            rat_port_data_id[i] = ret_val[i];
            rat_port_addr_id[i] =  rd_ret[i];
        end
    end

    // write ports to FRAT
    always_ff@(posedge clk) begin
        for (int i = 0; i < RETIRE_WIDTH_MAX; i++) begin
            if (rat_write_id[i]) begin
                rat[rat_port_addr_id[i]].table_data <= rat_port_data_id[i];
                rat[rat_port_addr_id[i]].rf         <= ret_val[i] ? 1 : 0; //change to constants
            end
        end
    end
    
    /*
    // RAT write ports connected to issuing instructions and retiring instructions
    // priority is givien to retiring instructions
    always_ff@(posedge clk) begin
        if (~(branchInstruc_id[0] || storeInstruc_id[0] ||
              branchInstruc_id[1] || storeInstruc_id[1])) begin
            
            //dual issue
            case (instr_val_id & ~{rob_full,rob_full})
                (2'b01): begin
                    if (~rat_w_qual_id[0]) begin
                        rat[rd_id[0]].table_data <= ~rat_w_qual_id[0] ? rob_is_ptr : ;
                        robid_is[0]              <= rob_is_ptr;
                    end begin
                        
                    end
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
    end
    */

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
