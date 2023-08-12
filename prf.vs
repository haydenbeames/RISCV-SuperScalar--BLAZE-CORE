`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Hayden Beames
// 
// Create Date: 08/12/2023 11:32:51 AM
// Design Name: 
// Module Name: prf
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
/////////////////////////////////////////////////////////////////////////////////

//include files
`include "rtl_constants.sv"
`include "structs.sv"

//physical register file (speculative)
//entries directly correspond with ROB entries
module prf(
    input wire logic clk,
    
    // AR inputs 
    input info_instr_2_disp_rs [CPU_NUM_LANES-1:0],

    //cdb inputs for commit
    input cdb_t [CDB_NUM_LANES-1:0] cdb_cmt,  

    output logic [NUM_PRF_R_PORTS-1:0][DATA_LEN-1:0] prf_r_port_data
    );
    
    logic [COMMIT_WIDTH_MAX-1:0] prf_write_en;
    logic [NUM_PRF_W_PORTS-1:0][DATA_LEN-1:0] prf_w_port_data;
    logic [NUM_PRF_W_PORTS-1:0][ROB_SIZE_CLOG -1:0] prf_w_port_addr;
    
    logic [NUM_PRF_R_PORTS-1:0][ROB_SIZE_CLOG -1:0] prf_r_port_addr;

    logic [PRF_SIZE-1:0] prf[PRF_SIZE-1:0];
    logic [PRF_SIZE-1:0] prfv; //valid, marked 0 on init and when misspeculated write
    
    // Initialize state
    initial begin
        for(int i = 0; i < DATA_LEN; i++)
            prf[i]  = '0;
            prfv[i] =  0;
    end
    
    logic [ROB_MAX_RETIRE-1:0] w_val_ret;
    logic [COMMIT_WIDTH_MAX-1:0] prf_w_qual;
    logic [COMMIT_WIDTH_MAX-1:0][COMMIT_WIDTH_MAX-1:0] prf_ret_rd_conflict_mtx;
    
    /////////////////////////////////////////
    // write conflict detector
    always_comb begin
        for (int r = 0; r < COMMIT_WIDTH_MAX; r++) begin
           w_val_ret[r] = cdb_cmt[r].v & cdb_cmt[r].prfWrite; //checking which committing instr. are updating rat/regfile
        end
        prf_ret_rd_conflict_mtx = '{default:0};
        for (int i = 0; i < COMMIT_WIDTH_MAX; i++) begin
            for (int j = 0; j < COMMIT_WIDTH_MAX; j++) begin
                if (j != i)
                    prf_ret_rd_conflict_mtx[i][j] = (cdb_cmt[i].robid == cdb_cmt[j].robid);
            end
        end  
        
        prf_w_qual = '{default:0};
        for (int i = 0; i < COMMIT_WIDTH_MAX; i++) begin
            for (int j = (i+1); j < COMMIT_WIDTH_MAX; j++) begin
                prf_w_qual[i] |= prf_ret_rd_conflict_mtx[i][j];
            end
        end
    end

    // generate write enables prf
    always_comb begin
        for (int i = 0; i < COMMIT_WIDTH_MAX; i++) begin
            prf_write_en[i] = ~prf_w_qual[i] & w_val_ret[i];
        end
    end

    always_comb begin
        for (int i = 0; i < COMMIT_WIDTH_MAX; i++) begin
            prf_w_port_data[i] = cdb_cmt[i].data;
            prf_w_port_addr[i] = cdb_cmt[i].robid;
        end
    end
    /////////////////////////////////////////

    /////////////////////////////////////////

    always_comb begin  
        for (int ln = 0; ln < CPU_NUM_LANES; ln++) begin
            for (int s = 0; s < NUM_SRCS; s++)
                prf_r_port_addr[i*NUM_SRCS+s] = info_instr_2_disp_rs[ln].src[s];
        end        
    end
    
    ////////////////////////////////////////

    //multiported register file
    always_ff@(posedge clk) begin  
        //write ports
        for (int w = 0; w < NUM_RRF_W_PORTS; w++) begin  //NUM_PRF_W_PORTS = CPU_NUM_LANES
            if (prf_write_en[w]) begin 
                prf[prf_w_port_addr[w]] <= prf_w_port_data[w]; //no need to bypass write to a read in same clk
            end
        end

        //read ports 
        for (int r = 0; r < NUM_PRF_R_PORTS; r++) begin // NUM_PRF_R_PORTS = CPU_NUM_LANES*NUM_SRCS
            prf_r_port_data[r] = prf[prf_r_port_addr[r]];
        end  
    end
    
endmodule
