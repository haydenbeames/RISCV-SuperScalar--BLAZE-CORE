

`timescale 1ns / 1ps

//include files
`include "rtl_constants.sv"
`include "structs.sv"

module rob(
    input wire logic clk, rst,
    
    //inputs from id stage
    input wire logic [ISSUE_WIDTH_MAX-1:0]               instr_val_id,
    input wire logic [ISSUE_WIDTH_MAX-1:0][SRC_LEN-1:0]         rd_id,
    input instr_info_t [ISSUE_WIDTH_MAX-1:0] instr_info_id,
    
    //cdb inputs for commit
    input wire logic [CDB_NUM_LANES-1:0][ROB_SIZE_CLOG-1:0]  robid_cdb,
    input wire logic [CDB_NUM_LANES-1:0][31:0]              result_cdb,
    input wire logic [CDB_NUM_LANES-1:0]                       val_cdb,
    
    
    //outputs for retire to r-rat & prf
    output logic [ROB_MAX_RETIRE-1:0][DATA_LEN-1:0]  data_ret,
    output logic [ROB_MAX_RETIRE-1:0][SRC_LEN-1:0]     rd_ret,
    output logic [ROB_MAX_RETIRE-1:0][DATA_LEN-1:0]    pc_ret,
    output logic [ROB_MAX_RETIRE-1:0]                 val_ret,
    output logic [ROB_MAX_RETIRE-1:0]             rfWrite_ret,
    output logic [ROB_MAX_RETIRE-1:0]            memWrite_ret,  //maybe put info in a struct
    output logic [ROB_MAX_RETIRE-1:0][ROB_SIZE_CLOG-1:0] robid_ret,
    output logic [ROB_SIZE_CLOG-1:0] ret_ptr, //to R-RAT
    
    output logic rob_full,
    
    //output to F_RAT
    output logic [ISSUE_WIDTH_MAX-1:0][ROB_SIZE_CLOG-1:0] is_ptr //all issue ptrs to rob
    );
    
    logic [ROB_SIZE_CLOG  :0] rob_occupancy;
    
    logic [ROB_MAX_RETIRE_CLOG:0] num_instr_2_ret;
    logic                         num_ret_qual;
    
    rob_t [ROB_SIZE-1:0] rob;
    
    initial begin
        for (int i = 0; i < ROB_SIZE; i++) begin
            rob[i] = '{default:0};
            is_ptr = '0;
        end
    end
    
    /*
    // new instr to rob
    always_ff@(posedge clk) begin
        case (instr_val_id & ~{rob_full,rob_full}) // & ~rob_full
            (2'b01): begin
                rob[is_ptr[0]].op   <= op_id[0];
                rob[is_ptr[0]].rd   <= rd_id[0];
                rob[is_ptr[0]].pc   <= pc_id[0];
                rob[is_ptr[0]].v    <= 1;
                rob[is_ptr[0]].done <= 0;

                is_ptr[0] <= is_ptr[0] + 1;
            end
            (2'b10): begin
                rob[is_ptr[0]].op   <= op_id[1];
                rob[is_ptr[0]].rd   <= rd_id[1];
                rob[is_ptr[0]].pc   <= pc_id[1];
                rob[is_ptr[0]].v    <= 1;
                rob[is_ptr[0]].done <= 0;  

                is_ptr[0] <= is_ptr[0] + 1;      
            end
            (2'b11): begin
                rob[is_ptr[0]].op   <= op_id[0];
                rob[is_ptr[0]].rd   <= rd_id[0];
                rob[is_ptr[0]].pc   <= pc_id[0];
                rob[is_ptr[0]].v    <= 1;
                rob[is_ptr[0]].done <= 0;
                
                rob[is_ptr[1]].op   <= op_id[1];
                rob[is_ptr[1]].rd   <= rd_id[1];
                rob[is_ptr[1]].pc   <= pc_id[1];
                rob[is_ptr[1]].v    <= 1;
                rob[is_ptr[1]].done <= 0;
                
                is_ptr[0] <= is_ptr[0] + 2;
            end
            default: begin end
        endcase
    end
    */
    
    //new rob issue with varied issue width  
    always_ff@(posedge clk) begin 
        for (int i = 0; i < ISSUE_WIDTH_MAX; i++) begin 
            if (instr_val_id[i]) begin
                rob[is_ptr[i]].rd   <= rd_id[i];
                rob[is_ptr[i]].pc   <= instr_info_id[i].pc;
                rob[is_ptr[i]].v    <= 1;
                rob[is_ptr[i]].done <= 0;
                rob[is_ptr[i]].rfWrite  <= instr_info_id[i].ctrl_sig.rfWrite;
                rob[is_ptr[i]].memWrite <= instr_info_id[i].ctrl_sig.memWrite;
            end
        end
    end
    //assign is_ptr[1] = is_ptr + 1;

    always_comb begin
        for (int i = 1; i < ISSUE_WIDTH_MAX; i++) begin
            is_ptr[i] = is_ptr[0] + i;
        end
    end
    
    //commit instr to rob 
    always_ff@(posedge clk) begin
        for (int i = 0; i < CDB_NUM_LANES; i++) begin
            if (val_cdb[i]) begin
                rob[robid_cdb[i]].data <= result_cdb[i];
                rob[robid_cdb[i]].done <= 1;
            end
        end
    end
    
    //retire from rob
    //will retire 4 unless it is wrapping around -> saves a lot of complexity and almost no perf. impact
    always_ff@(posedge clk) begin
        for (int i = 0; i < ROB_MAX_RETIRE; i++) begin
            if ((num_instr_2_ret >= (i+1)) && ((ret_ptr+i) <= ROB_SIZE)) begin
                data_ret[i] <= rob[ret_ptr+i].data;
                rd_ret[i]   <= rob[ret_ptr+i].rd;
                pc_ret[i]   <= rob[ret_ptr+i].pc;
                val_ret[i]  <= 1;
                
                rob[ret_ptr+i].v    <= 0;
                rob[ret_ptr+i].done <= 0;

            end else begin
                val_ret[i]  <= 0;
            end
        end        
    end
    
    //update ret_ptr
    always_ff@(posedge clk) begin
        if (rst) begin
            ret_ptr <= '0;
        end else begin
            ret_ptr <= ret_ptr + num_instr_2_ret;
        end
    end
    
    //grab # instr 2 retire
    always_comb begin
        num_instr_2_ret = 0;
        for (int i = 0; i < ROB_MAX_RETIRE; i++) begin
            num_ret_qual = rob[ret_ptr];
            for (int j = i-1; j >= 0; j--) begin
                num_ret_qual &= rob[ret_ptr+i].done & rob[ret_ptr+j].done;
            end
            num_instr_2_ret += num_ret_qual;
        end
    end
           
    always_comb begin
        rob_full      =  0;
        rob_occupancy = '0;
        for (int i = 0; i < ROB_SIZE; i++)
            rob_occupancy += rob[i].v;
        rob_full = rob_occupancy > (ROB_SIZE - ISSUE_WIDTH_MAX);   //RE-CHECK THIS!!  **************
    end
    
endmodule
