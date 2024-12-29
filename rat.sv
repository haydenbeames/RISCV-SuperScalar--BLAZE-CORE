`timescale 1ns / 1ps
/***************************************************************************
* 
* Module:   f_rat
* Filename: f_rat.sv
*
* Author: Hayden Beames
* Date: 4/24/2023
*
* Description: 
* This module includes the decoding of RISC-V Instructions along
* with generation of the Fetch Register Alias Table.
* Instructions are renamed in ID (Instruction Decode) Stage and passing into the
* AR (Allocate Rename) stage for false dependency/rename correction.
* These corrections in the AR stage include:
* 1) dependencies on currently retiring instructions (ID stage)
* 2) dependencies on retiring instructions at the time of decode (flopped into AR and handled there [1 cycle delay])
* 3) rs1/rs2 dependencies on instructions issuing in the same cycle (writes to RAT do not happen until after RAT
*    read so false reads need to be corrected)
* 
* corrections 1 & 2 are handled by the ret_ovrd_dep_mtx_id and ret_ovrd_dep_mtx_ar respectively 
* correction  3 is handled by src_dep_ovrd_mtx_ar
*
* Decode:
*   including in the decode is immediate generation, Functional Unit Control signals (ALU Ctrl), and
*   Functional Unit Destinations. Since it is likely that there is more than 1 possible Functional 
*   Unit Destination (i.e. ALU, MUL, DIV, L/S Units), this will be qualified upon instruction dispatch
*   selection from the RS (Reservation Station)
*
*NOTE *** recently fetched instructions must be sequentially valid from instruction 0 and forward in each respective cycle
*Example:  isntr_val_id: 1110   NOT OKAY: since LSB is 0 and MSB bits are 1 
*           instr_val_id: 0111   OKAY  
*           instr_val_id: 1101   NOT OKAY: valid must be sequential   
* **Do not have to worry about it, LSB instructions will not be killed, only precursing instructions following a branch
****************************************************************************/

//include files
`include "rtl_constants.sv"
`include "decode_constants.sv"
`include "riscv_alu_constants.sv"
`include "macros.sv"
`include "structs.sv"

module rat(
    input logic                                                                clk_free_master, 
    input logic                                                                global_rst,
    input logic         [ISSUE_WIDTH_MAX-1:0]                                  instr_val_id, //valid instr id
    input logic         [ISSUE_WIDTH_MAX-1:0][DATA_LEN-1:0]                    instr_id,

    //inputs from rob
    input logic         [ISSUE_WIDTH_MAX-1:0][ROB_SIZE_CLOG-1:0]               rob_is_ptr,
    input logic                                                                rob_full,
    //rob retire bus
    input info_ret_t    [ROB_MAX_RETIRE-1:0]                                   info_ret,
    
    //outputs of f-rat
    output logic        [ISSUE_WIDTH_MAX-1:0][OPCODE_LEN-1:0]                  opcode_ar,
    output logic        [ISSUE_WIDTH_MAX-1:0][PRF_SIZE_CLOG-1:0]               rd_ar, //to ROB
    output logic        [ISSUE_WIDTH_MAX-1:0][NUM_SRCS-1:0]                    src_valid_ar,
    output logic        [ISSUE_WIDTH_MAX-1:0][NUM_SRCS-1:0][PRF_SIZE_CLOG-1:0] src_rdy_2_issue_ar, //this is the actual pdst
    output logic        [ISSUE_WIDTH_MAX-1:0][NUM_SRCS-1:0]                    src_data_type_rdy_2_issue_ar, // 1: PRF, 0: ROB 
    output logic        [ISSUE_WIDTH_MAX-1:0]                                  instr_val_ar,
    output instr_info_t [ISSUE_WIDTH_MAX-1:0]                                  instr_info_id, //to reorder buffer
    output instr_info_t [ISSUE_WIDTH_MAX-1:0]                                  instr_info_ar,
    output logic        [ISSUE_WIDTH_MAX-1:0][CPU_NUM_LANES-1:0]               rs_binding_ar             
    );

    
    logic [RETIRE_WIDTH_MAX-1:0]                                  rat_write_id;
    logic [RETIRE_WIDTH_MAX-1:0][ROB_SIZE_CLOG-1:0]               rat_port_data_id;
    logic [RETIRE_WIDTH_MAX-1:0][PRF_SIZE_CLOG-1:0]               rat_port_addr_id;
    
    logic [RETIRE_WIDTH_MAX-1:0] ret_val_ar;
    

    logic [ISSUE_WIDTH_MAX-1:0][NUM_SRCS-1:0][PRF_SIZE_CLOG-1:0]   src_renamed_ar;
    logic [ISSUE_WIDTH_MAX-1:0][NUM_SRCS-1:0]                      src_data_type_ar; // 1: PRF, 0: ROB 
    
		logic clk_free_rcb;
    logic clk_free_lcb;

	 `RCB(clk_free_rcb, 1'b1, clk_free_master)
   `LCB(clk_free_lcb, 1'b1, clk_free_rcb)


    /////////////////////////////////////////////////
    //
    // Decode/Immediate Gen Logic
    //
    /////////////////////////////////////////////////
    
    logic        [ISSUE_WIDTH_MAX-1:0][OPCODE_LEN-1:0]    opcode_id;
    logic        [ISSUE_WIDTH_MAX-1:0][PRF_SIZE_CLOG-1:0] rd_id;
    logic        [ISSUE_WIDTH_MAX-1:0][PRF_SIZE_CLOG-1:0] rs1_id;
    logic        [ISSUE_WIDTH_MAX-1:0][PRF_SIZE_CLOG-1:0] rs2_id;

		idecode idecode(
	  .instr_info_id(instr_info_id),
    .opcode_id    (opcode_id    ),       
    .rd_id        (rd_id        ),    
    .rs1_id       (rs1_id       ),       
    .rs2_id       (rs2_id       )        
		);


    /////////////////////////////////////////////////
    ///// Front-End Register Alias Table (FRAT)
    /////////////////////////////////////////////////
    
    typedef struct packed { 
        logic rf; // 1: PRF, 0: ROB
        logic [PRF_SIZE_CLOG-1:0] table_data; //points to addr data dependency will come from
    } rat_t;
    rat_t [RAT_SIZE-1:0] rat;
    
    initial begin
        for (int i = 0; i < RAT_SIZE; i++) begin
            rat[i].table_data = i;
            rat[i].rf   = 1; 
        end
    end

    logic [ISSUE_WIDTH_MAX-1:0] storeInstruc_id;
		logic [ISSUE_WIDTH_MAX-1:0] branchInstruc_id;

    always_comb begin
        for (int i = 0; i < ISSUE_WIDTH_MAX; i++) begin
            storeInstruc_id[i]  = (opcode_id[i] == S_TYPE);
            branchInstruc_id[i] = (opcode_id[i] == SB_TYPE);
        end
    end
    
    //rename rs1 & rs2 before bypass from rob
    // FIXME : change to renamed from one of the read ports, will need 4 + 4 readports?

    always_ff@(posedge clk_free_lcb) begin
        for (int i = 0; i < ISSUE_WIDTH_MAX; i++) begin
            if (instr_val_id[i]) begin
                src_renamed_ar[i][RS1] <= rat[rs1_id[i]].table_data;
                src_renamed_ar[i][RS2] <= rat[rs2_id[i]].table_data;
                
                src_data_type_ar[i][RS1] <= rat[rs1_id[i]].rf;
                src_data_type_ar[i][RS2] <= rat[rs2_id[i]].rf;
            end
        end
    end
    
    // update RAT  
    // need to also check for rd write conflicts and rd with rob write conflicts
    logic [ROB_MAX_RETIRE-1:0] ret_w_val_id;
    logic [ROB_MAX_RETIRE+ISSUE_WIDTH_MAX-1:0] rat_w_qual_id;
    logic [ROB_MAX_RETIRE+ISSUE_WIDTH_MAX-1:0][ROB_MAX_RETIRE+ISSUE_WIDTH_MAX-1:0] rat_ret_rd_conflict_mtx_id;

    // write conflict detector
    always_comb begin
        for (int r = 0; r < RETIRE_WIDTH_MAX; r++) begin
           ret_w_val_id[r] = info_ret[r].v & info_ret[r].rfWrite; //checking which retiring instr. are updating rat/regfile
        end

        rat_ret_rd_conflict_mtx_id = '{default:0};
        for (int i = 0; i < ISSUE_WIDTH_MAX; i++) begin
            for (int j = 0; j < ISSUE_WIDTH_MAX; j++) begin
                if (j != i)
                    rat_ret_rd_conflict_mtx_id[i][j] = ~(storeInstruc_id[i] | branchInstruc_id[i]) & instr_val_id[i] & (rd_id[i] == rd_id[j]);
            end
            
            for (int j = ISSUE_WIDTH_MAX; j < RETIRE_WIDTH_MAX+ISSUE_WIDTH_MAX; j++) begin
                for (int k = 0; k < RETIRE_WIDTH_MAX; k++) begin
                     rat_ret_rd_conflict_mtx_id[i][j] |= ret_w_val_id[k] & (rd_id[i] == info_ret[k].rd);
                end
            end
        end  
        
        //may want to put this logic in retirement
        for (int i = ISSUE_WIDTH_MAX; i < RETIRE_WIDTH_MAX+ISSUE_WIDTH_MAX; i++) begin  //write port in question
            for (int j = ISSUE_WIDTH_MAX; j < RETIRE_WIDTH_MAX+ISSUE_WIDTH_MAX; j++) begin //comparison to other write ports
                if (j != i)
                    rat_ret_rd_conflict_mtx_id[i][j] = ret_w_val_id[i-ISSUE_WIDTH_MAX] & (info_ret[i-ISSUE_WIDTH_MAX].rd == info_ret[j-ISSUE_WIDTH_MAX].rd);
            end
        end
        
        rat_w_qual_id = '{default:0};
        for (int i = 0; i < RETIRE_WIDTH_MAX+ISSUE_WIDTH_MAX; i++) begin
            for (int j = (i+1); j < RETIRE_WIDTH_MAX+ISSUE_WIDTH_MAX; j++) begin
                rat_w_qual_id[i] |= rat_ret_rd_conflict_mtx_id[i][j];
            end
        end
        
        //check if retirement data match in RAT
        for (int i = ISSUE_WIDTH_MAX; i < RETIRE_WIDTH_MAX; i++) begin
            if (~rat_w_qual_id[i]) begin
                rat_w_qual_id[i] |= (rat[info_ret[i].rd].table_data == info_ret[i].robid) & ~rat[info_ret[i].rd].rf; // should adjust to read ports
            end
        end
    end

    // generate write enables rat
    always_comb begin
        for (int i = 0; i < ISSUE_WIDTH_MAX; i++) begin
            rat_write_id[i] = (~rat_w_qual_id[i] | ~rat_w_qual_id[i+ISSUE_WIDTH_MAX]) & ~rob_full; //test with valid signals, valid is included above but simulate to be sure
        end
        for (int i = ISSUE_WIDTH_MAX; i < RETIRE_WIDTH_MAX; i++) begin
            rat_write_id[i] = ~rat_w_qual_id[i+ISSUE_WIDTH_MAX] & ret_w_val_id[i] & ~rob_full;
        end
    end
    
    always_comb begin
        //rat_port_data_id[0] = instr_val_id[0] ? rob_is_ptr[0] : info_ret[0].rd;
        //rat_port_data_id[1] = instr_val_id[1] ? (instr_val_id[0] ? rob_is_ptr[1] : rob_is_ptr[0]) : info_ret[1].rd;
        
        for (int i = 0; i < ISSUE_WIDTH_MAX; i++) begin
            rat_port_addr_id[i] = instr_val_id[i] & ~(storeInstruc_id[i] | branchInstruc_id[i]) ? rd_id[i]      : info_ret[i].rd;
            rat_port_data_id[i] = instr_val_id[i] & ~(storeInstruc_id[i] | branchInstruc_id[i]) ? rob_is_ptr[i] : info_ret[i].rd;
        end

        for (int i = ISSUE_WIDTH_MAX; i < RETIRE_WIDTH_MAX; i++) begin
            rat_port_data_id[i] = info_ret[i].rd; //MAY BE LESS CDYN BY JUST RESETTING rat.rf
            rat_port_addr_id[i] = info_ret[i].rd;
        end
    end

    // write ports to FRAT
    always_ff@(posedge clk_free_lcb) begin
        for (int i = 0; i < RETIRE_WIDTH_MAX; i++) begin
            if (rat_write_id[i] & (rat_port_addr_id[i] != 0)) begin
                rat[rat_port_addr_id[i]].table_data <= rat_port_data_id[i];
                rat[rat_port_addr_id[i]].rf         <= info_ret[i].v ? 1 : 0; //change to constants  //FIX ME * WRONG PRIORITY*
            end
        end
    end

    //////////////////////////////////////////
    //
    //  ID/AR 
    //
    //////////////////////////////////////////
    
    logic [RETIRE_WIDTH_MAX-1:0][ROB_SIZE_CLOG-1:0] robid_ret_ar;
    logic [RETIRE_WIDTH_MAX-1:0][PRF_SIZE_CLOG-1:0] rd_ret_from_id_ar;
    logic [ISSUE_WIDTH_MAX-1:0][NUM_SRCS-1:0][PRF_SIZE_CLOG-1:0] src_original_ar;
    
    always_ff@(posedge clk_free_lcb) begin
        if (global_rst) begin
            instr_info_ar   <= '0;
            ret_val_ar   	<= '0;
            robid_ret_ar 	<= '{default:0};
            instr_val_ar 	<= '0;
            rd_ret_from_id_ar    	<= '0;
            src_original_ar <= '0;
            opcode_ar    	<= '0;
            rd_ar        	<= '0;
        end else begin
            instr_info_ar <= instr_info_id;
            ret_val_ar    <= ret_w_val_id;
            instr_val_ar  <= instr_val_id;
            opcode_ar     <= opcode_id;
            rd_ar         <= rd_id;
            
            for (int i = 0; i < ISSUE_WIDTH_MAX; i++) begin
                src_original_ar[i][RS1] <= rs1_id[i];
                src_original_ar[i][RS2] <= rs2_id[i];
            end
            for (int r = 0; r < RETIRE_WIDTH_MAX; r++) begin
                rd_ret_from_id_ar[r]     <= info_ret[r].rd;
                robid_ret_ar[r]  <= info_ret[r].robid;
            end
        end
    end
    
    logic [ISSUE_WIDTH_MAX-1:0][NUM_SRCS-1:0][RETIRE_WIDTH_MAX-1:0]      ret_ovrd_dep_mtx_ar;
    logic [ISSUE_WIDTH_MAX-1:0][NUM_SRCS-1:0][RETIRE_WIDTH_MAX-1:0]      ret_ovrd_dep_mtx_id;
    logic [ISSUE_WIDTH_MAX-1:0][NUM_SRCS-1:0][RETIRE_WIDTH_MAX_CLOG-1:0] ret_ovrd_dep_mtx_onehot_ar;
    logic [ISSUE_WIDTH_MAX-1:0][NUM_SRCS-1:0][RETIRE_WIDTH_MAX_CLOG-1:0] ret_ovrd_dep_mtx_onehot_id;
    logic                                    [RETIRE_WIDTH_MAX_CLOG-1:0] inbuff_ret_ovrd_dep_ar_onehot;
		logic                                    [RETIRE_WIDTH_MAX_CLOG-1:0] outbuff_ret_ovrd_dep_ar_onehot;
    logic                                    [RETIRE_WIDTH_MAX_CLOG-1:0] inbuff_ret_ovrd_dep_id_onehot;
		logic                                    [RETIRE_WIDTH_MAX_CLOG-1:0] outbuff_ret_ovrd_dep_id_onehot;

    logic [ISSUE_WIDTH_MAX-1:0][NUM_SRCS-1:0][RETIRE_WIDTH_MAX-1:0]      ret_ovrd_dep_mtx_from_id_ar;
    logic [ISSUE_WIDTH_MAX-1:0][NUM_SRCS-1:0][RETIRE_WIDTH_MAX_CLOG-1:0] ret_ovrd_dep_mtx_onehot_from_id_ar;
    
    //retirement override dependency matrix
    always_comb begin
        for (int i = 0; i < ISSUE_WIDTH_MAX; i++) begin
            ret_ovrd_dep_mtx_ar[i] = '{default:0};
            ret_ovrd_dep_mtx_id[i] = '{default:0};
            for (int s = 0; s < NUM_SRCS; s++) begin
                for (int r = 0; r < RETIRE_WIDTH_MAX; r++) begin
                    //check instructions that retired in last cycle that could not check before
                    ret_ovrd_dep_mtx_ar[i][s][r] = (src_renamed_ar[i][s] == robid_ret_ar[r])   & (instr_val_ar[i] & ret_val_ar[r])   & ~src_data_type_ar[i][s];
                    
                    //also need to check instructions currently retiring
                    ret_ovrd_dep_mtx_id[i][s][r] = (src_renamed_ar[i][s] == info_ret[r].robid) & (instr_val_ar[i] &   info_ret[r].v) & ~src_data_type_ar[i][s]; 
                end
            end
        end
    end
    
    logic [ISSUE_WIDTH_MAX-1:1][NUM_SRCS-1:0][ISSUE_WIDTH_MAX-2:0] src_dep_ovrd_mtx_ar; //ISSUE SRC dependedent on which previous ISSUE checker
    logic [ISSUE_WIDTH_MAX-1:1][NUM_SRCS-1:0][ISSUE_WIDTH_MAX-2:0] src_dep_ovrd_mtx_qual_1st_ar;
    logic [ISSUE_WIDTH_MAX-1:1][NUM_SRCS-1:0][ISSUE_WIDTH_MAX_CLOG-1:0] src_dep_ovrd_mtx_one_hot_ar;
    logic [ISSUE_WIDTH_MAX-2:0] inbuff_src_dep_mtx;
    logic [ISSUE_WIDTH_MAX-2:0] outbuff_src_dep_mtx;  //weird thing with macros where I have to buffer signal 
    logic [ISSUE_WIDTH_MAX-2:0] inbuff_src_dep_onehot;
    logic [ISSUE_WIDTH_MAX_CLOG-1:0] outbuff_src_dep_onehot;
    
    always_comb begin
        for (int i = 1; i < ISSUE_WIDTH_MAX; i++) begin //instr 0 will not have any dependencies
            src_dep_ovrd_mtx_ar[i] = '{default:0};
            for (int s = 0; s < NUM_SRCS; s++) begin
                for (int j = i-1; j >= 0; j--) begin //cannot compare last instr to itself                
                    src_dep_ovrd_mtx_ar[i][s][j] = (src_original_ar[i][s] == rd_ar[j]) & (instr_val_ar[i] & instr_val_ar[j]);
                end
            end
        end
    end
    
    //macro qualifiers and encodings for src dependency tracker
    always_comb begin
        for (int i = 1; i < ISSUE_WIDTH_MAX; i++) begin //instr 0 will not have any dependencies
            src_dep_ovrd_mtx_qual_1st_ar[i] = '{default:0};

            for (int s = 0; s < NUM_SRCS; s++) begin
                inbuff_src_dep_mtx = src_dep_ovrd_mtx_ar[i][s];
                `ONE_1ST_MSB(outbuff_src_dep_mtx, inbuff_src_dep_mtx);
                src_dep_ovrd_mtx_qual_1st_ar[i][s] = outbuff_src_dep_mtx;
            end
        end
    end
    
    always_comb begin
        for (int i = 1; i < ISSUE_WIDTH_MAX; i++) begin //instr 0 will not have any dependencies
            src_dep_ovrd_mtx_one_hot_ar[i]  = '{default:0};
            for (int s = 0; s < NUM_SRCS; s++) begin
                 inbuff_src_dep_onehot = src_dep_ovrd_mtx_qual_1st_ar[i][s];
                `ONE_HOT_ENCODE(outbuff_src_dep_onehot, inbuff_src_dep_onehot);
                src_dep_ovrd_mtx_one_hot_ar[i][s] = outbuff_src_dep_onehot;
            end
        end
    end
    
	//encode into index
    always_comb begin
        for (int i = 0; i < ISSUE_WIDTH_MAX; i++) begin
            for (int s = 0; s < NUM_SRCS; s++) begin
                inbuff_ret_ovrd_dep_id_onehot = ret_ovrd_dep_mtx_id[i][s];
                `ONE_HOT_ENCODE(outbuff_ret_ovrd_dep_id_onehot, inbuff_ret_ovrd_dep_id_onehot);
                ret_ovrd_dep_mtx_onehot_id[i][s] = outbuff_ret_ovrd_dep_id_onehot;

                inbuff_ret_ovrd_dep_ar_onehot = ret_ovrd_dep_mtx_ar[i][s];
                `ONE_HOT_ENCODE(outbuff_ret_ovrd_dep_ar_onehot, inbuff_ret_ovrd_dep_ar_onehot);
                ret_ovrd_dep_mtx_onehot_ar[i][s] = outbuff_ret_ovrd_dep_ar_onehot;
            end  
        end
    end
    
    always_ff@(posedge clk_free_lcb) begin
        ret_ovrd_dep_mtx_onehot_from_id_ar <= ret_ovrd_dep_mtx_onehot_id;
        ret_ovrd_dep_mtx_from_id_ar        <= ret_ovrd_dep_mtx_id;
    end

    //generate final src renamed with false dependencies removed
    always_comb begin
        src_rdy_2_issue_ar = '{default:0};
        src_data_type_rdy_2_issue_ar = '{default:0};
        for (int i = 1; i < ISSUE_WIDTH_MAX; i++) begin
            for (int s = 0; s < NUM_SRCS; s++) begin
                src_rdy_2_issue_ar[i][s] =           |src_dep_ovrd_mtx_qual_1st_ar[i][s] ? instr_info_ar[  src_dep_ovrd_mtx_one_hot_ar[i][s]].robid :
                                                     |ret_ovrd_dep_mtx_from_id_ar[i][s]  ? info_ret[ret_ovrd_dep_mtx_onehot_from_id_ar[i][s]].rd    :
                                                     |ret_ovrd_dep_mtx_ar[i][s]          ? rd_ret_from_id_ar[ret_ovrd_dep_mtx_onehot_ar[i][s]]      :
                                                           src_renamed_ar[i][s];
                                                
                src_data_type_rdy_2_issue_ar[i][s] = |src_dep_ovrd_mtx_qual_1st_ar[i][s] ? ROB_DATA_TYPE :
                                                    (|ret_ovrd_dep_mtx_from_id_ar[i][s]  | 
                                                     |ret_ovrd_dep_mtx_ar[i][s])         ? PRF_DATA_TYPE : 
                                                         src_data_type_ar[i][s];
            end
        end
        
        for (int s = 0; s < NUM_SRCS; s++) begin 
            src_rdy_2_issue_ar[0][s] =            |ret_ovrd_dep_mtx_from_id_ar[0][s] ? info_ret[ ret_ovrd_dep_mtx_onehot_from_id_ar[0][s]].rd :
                                                  |ret_ovrd_dep_mtx_ar[0][s]         ? rd_ret_from_id_ar[ret_ovrd_dep_mtx_onehot_ar[0][s]]    :
                                                        src_renamed_ar[0][s];
            src_data_type_rdy_2_issue_ar[0][s] = (|ret_ovrd_dep_mtx_from_id_ar[0][s]  |
                                                  |ret_ovrd_dep_mtx_ar[0][s]) ? PRF_DATA_TYPE : 
                                                      src_data_type_ar[0][s];
        end
    end

    ///////////////////////////////////////////////////////////////////////
    /////
    ///// BRATCR  (Branch RAT Copy Register)
    /////
    ///////////////////////////////////////////////////////////////////////
    /*
    logic [BRATCR_NUM_ETY_CLOG-1:0] bratcr_ety_ptr = 0;
    logic bratcr_full;
    
    typedef struct packed { 
        logic [RAT_SIZE-1:0][PRF_SIZE_CLOG-1:0] rat_copy_data;
        logic [ROB_SIZE_CLOG-1:0]   robid;
        logic                       valid;
    } bratcr_t;
    
    bratcr_t [BRATCR_NUM_ETY-1:0] bratcr;
    logic [2:0]testCOND = '0;
    
    always_ff@(posedge clk_free_lcb) begin
        if (global_rst) begin
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
            bratcr[bratcr_ety_ptr].robid <= branchInstruc_id[0] ? rob_is_ptr[0] : rob_is_ptr[1];
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
            bratcr[bratcr_ety_ptr    ].robid <= rob_is_ptr[0];
            bratcr[bratcr_ety_ptr + 1].robid <= rob_is_ptr[1];
            testCOND <= 2;
        end
    end 
 
    always_comb begin
        bratcr_full = 1;
        for (int i = 0; i < BRATCR_NUM_ETY; i++)
            bratcr_full &= bratcr[i].valid;
    end
      */
endmodule
