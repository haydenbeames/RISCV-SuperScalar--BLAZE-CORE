`timescale 1ns / 1ps

//include files
`include "rtl_constants.sv"

module rob_hb(
    input wire logic clk, rst,
    
    //inputs from id stage
    input wire logic [ISSUE_WIDTH_MAX-1:0]               instr_val_id,
    input wire logic [ISSUE_WIDTH_MAX-1:0][DATA_LEN-1:0]        pc_id,
    input wire logic [ISSUE_WIDTH_MAX-1:0][SRC_LEN-1:0]         rd_id,
    input wire logic [ISSUE_WIDTH_MAX-1:0][OPCODE_LEN-1:0]      op_id,
    
    //cdb inputs for commit
    input wire logic [CDB_NUM_LANES-1:0][ROB_SIZE_CLOG-1:0]  robid_cdb,
    input wire logic [CDB_NUM_LANES-1:0][31:0]              result_cdb,
    input wire logic [CDB_NUM_LANES-1:0]                       val_cdb,
    
    //outputs for retire to r-rat & prf
    output logic [ROB_MAX_RETIRE-1:0][DATA_LEN-1:0]  data_ret,
    output logic [ROB_MAX_RETIRE-1:0][SRC_LEN-1:0]     rd_ret,
    output logic [ROB_MAX_RETIRE-1:0][DATA_LEN-1:0]    pc_ret,
    output logic [ROB_MAX_RETIRE-1:0]                 val_ret,
    output logic [ROB_MAX_RETIRE-1:0]              branch_ret,  //fill in later     
    output logic [ROB_SIZE_CLOG-1:0] ret_ptr, //to R-RAT
    
    //output to F_RAT
    output logic [ROB_SIZE_CLOG-1:0] is_ptr //d1 -> delayed one cycle
    
    );
    
    logic rob_full;
    logic [ROB_SIZE_CLOG  :0] rob_occupancy;
    logic [ROB_SIZE_CLOG-1:0] is_ptr_p1;
    
    logic [ROB_MAX_RETIRE_CLOG:0] num_instr_2_ret;
    logic                         num_ret_qual;
    
    typedef struct packed { 
        logic [6:0]  op;
        logic [4:0]  rd;
        logic [31:0] pc;
        logic [31:0] data; //branch should just use data to take of pc
        logic        v;
        logic        done;
        logic        PCSrc;
        
    } rob_t;
    rob_t [ROB_SIZE-1:0] rob;
    
    initial begin
        for (int i = 0; i < ROB_SIZE; i++) begin
            rob[i].op   = '0;
            rob[i].rd   = '0;
            rob[i].pc   = '0;
            rob[i].data = '0;
            rob[i].v    =  0;
            rob[i].done =  0; 
            is_ptr = '0;
        end
    end
    
    // new instr to rob
    always_ff@(posedge clk) begin
        case (instr_val_id & ~{rob_full,rob_full}) // & ~rob_full
            (2'b01): begin
                rob[is_ptr].op   <= op_id[0];
                rob[is_ptr].rd   <= rd_id[0];
                rob[is_ptr].pc   <= pc_id[0];
                rob[is_ptr].v    <= 1;
                rob[is_ptr].done <= 0;

                is_ptr <= is_ptr + 1;
            end
            (2'b10): begin
                rob[is_ptr].op   <= op_id[1];
                rob[is_ptr].rd   <= rd_id[1];
                rob[is_ptr].pc   <= pc_id[1];
                rob[is_ptr].v    <= 1;
                rob[is_ptr].done <= 0;  

                is_ptr <= is_ptr + 1;      
            end
            (2'b11): begin
                rob[is_ptr   ].op   <= op_id[0];
                rob[is_ptr   ].rd   <= rd_id[0];
                rob[is_ptr   ].pc   <= pc_id[0];
                rob[is_ptr   ].v    <= 1;
                rob[is_ptr   ].done <= 0;
                
                rob[is_ptr_p1].op   <= op_id[1];
                rob[is_ptr_p1].rd   <= rd_id[1];
                rob[is_ptr_p1].pc   <= pc_id[1];
                rob[is_ptr_p1].v    <= 1;
                rob[is_ptr_p1].done <= 0;

                is_ptr <= is_ptr + 2;
            end
            default: begin end
        endcase
    end
    
    assign is_ptr_p1 = is_ptr + 1;
    
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
                pc_ret[i]   <= branch_ret[i] ? rob[ret_ptr+i].pc : '0;
                val_ret[i]  <= 1;
                
                rob[ret_ptr+i].v    <= 0;
                rob[ret_ptr+i].done <= 0;
                //add in branch_ret
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
        rob_full = (rob_occupancy > (ROB_SIZE - 2));
    end
    
endmodule
