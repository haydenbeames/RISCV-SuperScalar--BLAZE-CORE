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
    input cdb_t [CDB_NUM_LANES-1:0] cdb_cmt,
       
    //outputs for retire to f-rat r-rat (regfile) & Store unit
    output info_ret_t [ROB_MAX_RETIRE-1:0] info_ret,
    output logic [ROB_SIZE_CLOG-1:0] ret_ptr,
    output logic rob_full,
    output logic [ISSUE_WIDTH_MAX-1:0][ROB_SIZE_CLOG-1:0] rob_is_ptr
    );
    
    logic [ROB_SIZE_CLOG  :0] rob_occupancy;
    logic [ISSUE_WIDTH_MAX_CLOG:0] num_val_instr_id;
    
    logic [ROB_MAX_RETIRE_CLOG:0] num_instr_2_ret;
    logic [ROB_MAX_RETIRE-1:0]       num_ret_qual;
    
    rob_t [ROB_SIZE-1:0] rob;
    
    initial begin
        for (int i = 0; i < ROB_SIZE; i++) begin
            rob[i]     = '{default:0};
            rob_is_ptr = '{default:0};
            
        end
    end
    
    always_comb begin
        num_val_instr_id = '0;
        for (int i = 0; i < ISSUE_WIDTH_MAX; i++) begin
            num_val_instr_id += instr_val_id[i];
        end
    end
    
    /*
    // new instr to rob
    always_ff@(posedge clk) begin
        case (instr_val_id & ~{rob_full,rob_full}) // & ~rob_full
            (2'b01): begin
                rob[rob_is_ptr[0]].op   <= op_id[0];
                rob[rob_is_ptr[0]].rd   <= rd_id[0];
                rob[rob_is_ptr[0]].pc   <= pc_id[0];
                rob[rob_is_ptr[0]].v    <= 1;
                rob[rob_is_ptr[0]].done <= 0;

                rob_is_ptr[0] <= rob_is_ptr[0] + 1;
            end
            (2'b10): begin
                rob[rob_is_ptr[0]].op   <= op_id[1];
                rob[rob_is_ptr[0]].rd   <= rd_id[1];
                rob[rob_is_ptr[0]].pc   <= pc_id[1];
                rob[rob_is_ptr[0]].v    <= 1;
                rob[rob_is_ptr[0]].done <= 0;  

                rob_is_ptr[0] <= rob_is_ptr[0] + 1;      
            end
            (2'b11): begin
                rob[rob_is_ptr[0]].op   <= op_id[0];
                rob[rob_is_ptr[0]].rd   <= rd_id[0];
                rob[rob_is_ptr[0]].pc   <= pc_id[0];
                rob[rob_is_ptr[0]].v    <= 1;
                rob[rob_is_ptr[0]].done <= 0;
                
                rob[rob_is_ptr[1]].op   <= op_id[1];
                rob[rob_is_ptr[1]].rd   <= rd_id[1];
                rob[rob_is_ptr[1]].pc   <= pc_id[1];
                rob[rob_is_ptr[1]].v    <= 1;
                rob[rob_is_ptr[1]].done <= 0;
                
                rob_is_ptr[0] <= rob_is_ptr[0] + 2;
            end
            default: begin end
        endcase
    end
    */
    
    //new rob issue with varied issue width  
    always_ff@(posedge clk) begin 
        for (int i = 0; i < ISSUE_WIDTH_MAX; i++) begin 
            if (instr_val_id[i]) begin
                rob[rob_is_ptr[i]].rd   <= rd_id[i];
                rob[rob_is_ptr[i]].pc   <= instr_info_id[i].pc;
                rob[rob_is_ptr[i]].v    <= 1;
                rob[rob_is_ptr[i]].done <= 0;
                rob[rob_is_ptr[i]].rfWrite  <= instr_info_id[i].ctrl_sig.rfWrite;
                rob[rob_is_ptr[i]].memWrite <= instr_info_id[i].ctrl_sig.memWrite;
            end
        end
    end
    //assign rob_is_ptr[1] = rob_is_ptr + 1;

    always_comb begin
        for (int i = 1; i < ISSUE_WIDTH_MAX; i++) begin
            rob_is_ptr[i] = rob_is_ptr[0] + i;
        end
    end
    
    always_ff@(posedge clk) begin
        if (|instr_val_id) 
            rob_is_ptr[0] <= rob_is_ptr[0] + num_val_instr_id;
    end
    
    //commit instr to rob 
    always_ff@(posedge clk) begin
        for (int i = 0; i < CDB_NUM_LANES; i++) begin
            if (cdb_cmt[i].v) begin
                rob[cdb_cmt[i].robid].data <= cdb_cmt[i].data;
                rob[cdb_cmt[i].robid].done <= 1;
            end
        end
    end
    
    //retire from rob
    //will retire 4 unless it is wrapping around -> saves a lot of complexity and almost no perf. impact
    always_ff@(posedge clk) begin
        for (int i = 0; i < ROB_MAX_RETIRE; i++) begin
            if (rst)
                info_ret <= '{default:0};
            else if ((num_instr_2_ret >= (i+1)) && ((ret_ptr+i) <= ROB_SIZE)) begin
                info_ret[i].data         <= rob[ret_ptr+i].data;
                info_ret[i].rd           <= rob[ret_ptr+i].rd;
                info_ret[i].pc           <= rob[ret_ptr+i].pc;
                info_ret[i].v            <= rob[ret_ptr+i].v;
                info_ret[i].rfWrite      <= rob[ret_ptr+i].rfWrite;
                info_ret[i].memWrite     <= rob[ret_ptr+i].memWrite;
                info_ret[i].robid        <= ret_ptr + i;
                
                rob[ret_ptr+i].v    <= 0;
                rob[ret_ptr+i].done <= 0;
            end else begin
                info_ret[i].v  <= 0;
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
        num_ret_qual[0] = rob[ret_ptr].done;
        num_instr_2_ret = num_ret_qual[0];
        for (int i = 1; i < ROB_MAX_RETIRE; i++) begin
            num_ret_qual[i] = rob[ret_ptr].done;
            for (int j = i-1; j >= 0; j--) begin
                num_ret_qual[i] &= rob[ret_ptr+i].done & rob[ret_ptr+j].done;
            end
            num_instr_2_ret += num_ret_qual[i];
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
