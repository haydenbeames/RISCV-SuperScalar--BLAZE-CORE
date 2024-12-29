`timescale 1ns / 1ps
/***************************************************************************
* Module:   regfile
* Filename: regfile.sv
*
* Author: Hayden Beames
* Date: 4/17/2022
*
* Description: Variable width register file capable of perforing multiple R/W
*              Included is logic for write port conflicts from retirement
****************************************************************************/

//include files
`include "rtl_constants.sv"
`include "structs.sv"

//regfile module ports
module regfile(
    input wire logic clk,
    
    // AR inputs 
    input wire logic [ISSUE_WIDTH_MAX-1:0][NUM_SRCS-1:0][PRF_SIZE_CLOG-1:0] src_rdy_2_issue_ar,
    
    //retire inputs
    input info_ret_t [ROB_MAX_RETIRE-1:0] info_ret,
    
    output logic [NUM_RF_R_PORTS-1:0][DATA_LEN-1:0] rf_r_port_data
    );
    
    logic [RETIRE_WIDTH_MAX-1:0] rf_write_en;
    logic [NUM_RF_W_PORTS-1:0][DATA_LEN-1:0] rf_w_port_data;
    logic [NUM_RF_W_PORTS-1:0][SRC_LEN -1:0] rf_w_port_addr;
    
    logic [NUM_RF_R_PORTS-1:0][SRC_LEN -1:0] rf_r_port_addr;
    logic [RF_SIZE-1:0] register[RF_SIZE-1:0];
    
    // Initialize state
    initial begin
        for(int i = 0; i < DATA_LEN; i++)
            register[i] = 0;
    end
    
    logic [ROB_MAX_RETIRE-1:0] w_val_ret;
    logic [RETIRE_WIDTH_MAX-1:0] rf_w_qual;
    logic [RETIRE_WIDTH_MAX-1:0][RETIRE_WIDTH_MAX-1:0] rf_ret_rd_conflict_mtx;
    
    /////////////////////////////////////////
    // write conflict detector
    always_comb begin
        for (int r = 0; r < RETIRE_WIDTH_MAX; r++) begin
           w_val_ret[r] = info_ret[r].v & info_ret[r].rfWrite; //checking which retiring instr. are updating rat/regfile
        end
        rf_ret_rd_conflict_mtx = '{default:0};
        for (int i = 0; i < RETIRE_WIDTH_MAX; i++) begin
            for (int j = 0; j < RETIRE_WIDTH_MAX; j++) begin
                if (j != i)
                    rf_ret_rd_conflict_mtx[i][j] = (info_ret[i].rd == info_ret[j].rd);
            end
        end  
        
        rf_w_qual = '{default:0};
        for (int i = 0; i < RETIRE_WIDTH_MAX; i++) begin
            for (int j = (i+1); j < RETIRE_WIDTH_MAX; j++) begin
                rf_w_qual[i] |= rf_ret_rd_conflict_mtx[i][j];
            end
        end
    end

    // generate write enables rf
    always_comb begin
        for (int i = 0; i < RETIRE_WIDTH_MAX; i++) begin
            rf_write_en[i] = ~rf_w_qual[i] & w_val_ret[i];
        end
    end

    always_comb begin
        for (int i = 0; i < RETIRE_WIDTH_MAX; i++) begin
            rf_w_port_data[i] = info_ret[i].data;
            rf_w_port_addr[i] = info_ret[i].rd;
        end
    end
    /////////////////////////////////////////

    /////////////////////////////////////////

    always_comb begin  
        for (int i = 0; i < ISSUE_WIDTH_MAX; i++) begin
            for (int s = 0; s < NUM_SRCS; s++)
                rf_r_port_addr[i*NUM_SRCS+s] = src_rdy_2_issue_ar[i][s][SRC_LEN-1:0];
        end        
    end
    
    ////////////////////////////////////////

    //multiported register file
    always_ff@(posedge clk) begin  
        //write ports
        for (int w = 0; w < NUM_RF_W_PORTS; w++) begin  //NUM_RF_W_PORTS = RETIRE_WIDH_MAX
            if (rf_write_en[w] && (rf_w_port_addr[w] != 0)) begin 
                register[rf_w_port_addr[w]] <= rf_w_port_data[w]; //no need to bypass write to a read in same clk
            end
        end

        //read ports
        for (int r = 0; r < NUM_RF_R_PORTS; r++) begin 
            rf_r_port_data[r] = register[rf_r_port_addr[r]];
        end  
    end
    
endmodule
