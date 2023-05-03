`timescale 1ns / 1ps
/***************************************************************************
* Module: <regfile>
* Filename: regfile.sv
*
* Author: <Hayden Beames>
* Class: <ECEN 323 Section 002, Winter 2022>
* Date: 1/22/2022
*
* Description: <regfile circuit capable of reading from two addresses at once. 
****************************************************************************/


//regfile module ports
module regfile(
    input wire logic clk, rst, write,
    input wire logic [4:0] readReg1, readReg2, writeReg,
    input wire logic [DATA_LEN-1:0] writeData,
    
    // AR inputs 
    input wire logic [ISSUE_WIDTH_MAX-1:0]       instr_val_ar,
    input wire logic [ISSUE_WIDTH_MAX-1:0][NUM_SRCS-1:0][RAT_RENAME_DATA_WIDTH-1:0] src_rdy_2_issue_ar,
    input wire logic [ISSUE_WIDTH_MAX-1:0][NUM_SRCS-1:0]                  src_data_type_rdy_2_issue_ar, // 1: PRF, 0: ROB 
    input wire instr_info_t [ISSUE_WIDTH_MAX-1:0] instr_info_ar,
    //retire inputs
    input wire logic  [ROB_MAX_RETIRE-1:0][SRC_LEN-1:0]  rd_ret,
    input wire logic  [ROB_MAX_RETIRE-1:0]              val_ret,
    input wire logic  [ROB_MAX_RETIRE-1:0]              rfWrite_ret,
    input wire logic  [ROB_MAX_RETIRE-1:0][ROB_SIZE_CLOG-1:0] robid_ret,
    input wire logic  [ROB_MAX_RETIRE-1:0][DATA_LEN-1:0]    wb_data_ret,
    
    output logic [DATA_LEN-1:0] readData1, readData2
    );
    
    logic [RETIRE_WIDTH_MAX-1:0] rf_write_en;
    logic [NUM_RF_W_PORTS-1:0][DATA_LEN-1:0] rf_w_port_data;
    logic [NUM_RF_W_PORTS-1:0][SRC_LEN -1:0] rf_w_port_addr;
    logic [NUM_RF_W_PORTS-1:0][DATA_LEN-1:0] rf_r_port_data;
    logic [NUM_RF_W_PORTS-1:0][SRC_LEN -1:0] rf_r_port_addr;
    logic [RF_SIZE-1:0] register[RF_SIZE-1:0];
    
    // Initialize state
    initial begin
        for(int i = 0; i < DATA_LEN; i++)
            register[i] = i;
    end
    
    logic [ROB_MAX_RETIRE-1:0] w_val_ret;
    logic [RETIRE_WIDTH_MAX-1:0] rf_w_qual;
    logic [RETIRE_WIDTH_MAX-1:0][RETIRE_WIDTH_MAX-1:0] rf_ret_rd_conflict_mtx;
    
    /////////////////////////////////////////
    // write conflict detector
    always_comb begin
        w_val_ret = val_ret & rfWrite_ret; //checking which retiring instr. are updating rf/regfile

        rf_ret_rd_conflict_mtx = '{default:0};
        for (int i = 0; i < RETIRE_WIDTH_MAX; i++) begin
            for (int j = 0; j < RETIRE_WIDTH_MAX; j++) begin
                if (j != i)
                    rf_ret_rd_conflict_mtx[i][j] = (rd_ret[i] == rd_ret[j]);
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
            rf_w_port_data[i] = wb_data_ret[i];
            rf_w_port_addr[i] = rd_ret[i];
        end
    end
    /////////////////////////////////////////

    ////////////////////////////////////////
    //Read Conflict Detector 

    logic [NUM_RF_R_PORTS-1:0] r_val_ar;
    logic [NUM_RF_R_PORTS-1:0] rf_r_qual;
    logic [NUM_RF_R_PORTS-1:0] rf_read_en;
    logic [NUM_RF_R_PORTS-1:0][NUM_RF_R_PORTS-1:0] rf_ar_read_conflict_mtx;

    always_comb begin
        for (int i = 0; i < ISSUE_WIDTH_MAX; i++) begin
            for (int s = 0; s < NUM_SRCS; s++)
                r_val_ar[i+s] = instr_val_ar[i] & src_data_type_rdy_2_issue_ar[i][s];
        end

        rf_ar_read_conflict_mtx = '{default:0};
        for (int i = 0; i < NUM_RF_R_PORTS; i++) begin
            for (int j = 0; j < NUM_RF_R_PORTS; j++) begin
                if (j != i)
                    rf_ar_read_conflict_mtx[i][j] = (src_rdy_2_issue_ar[i%NUM_SRCS][i%ISSUE_WIDTH_MAX] == src_rdy_2_issue_ar[j%NUM_SRCS][j%ISSUE_WIDTH_MAX]);
            end
        end  
        
        rf_r_qual = '{default:0};
        for (int i = 0; i < NUM_RF_R_PORTS; i++) begin
            for (int j = (i+1); j < NUM_RF_R_PORTS; j++) begin
                rf_r_qual[i] |= rf_ar_read_conflict_mtx[i][j];
            end
        end
    end

    // generate read enables rf
    always_comb begin
        for (int i = 0; i < NUM_RF_R_PORTS; i++) begin
            rf_write_en[i] = ~rf_r_qual[i] & r_val_ar[i];
        end
    end
    ///////////////////////////////////////////////////////////


    //multiported register file logic
    always_ff@(posedge clk) begin  
        //write ports
        for (int w = 0; w < NUM_RF_W_PORTS; w++) begin  //NUM_RF_W_PORTS = RETIRE_WIDH_MAX
            if (rf_write_en[w] && (rf_w_port_addr[w] != 0)) begin 
                register[rf_w_port_addr[w]] <= rf_w_port_data[w]; //no need to bypass write to a read in same clk
            end
        end

        //read ports
        for (int r = 0; r < NUM_RF_R_PORTS; r++) begin
            if(rf_read_en[r])
                rf_r_port_data[r] = register[rf_r_port_addr[r]];
        end  
    end
    
endmodule
