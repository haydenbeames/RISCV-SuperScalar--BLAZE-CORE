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

module f_rat(
    input logic   clk, rst,
    input logic  [ISSUE_WIDTH_MAX-1:0] instr_val_id, //valid instr id
    input logic  [ISSUE_WIDTH_MAX-1:0][DATA_LEN-1:0] instr_id,

    //inputs from rob
    input logic  [ISSUE_WIDTH_MAX-1:0][ROB_SIZE_CLOG-1:0] rob_is_ptr,
    input logic   rob_full,
    //rob retire bus
    input logic  [ROB_MAX_RETIRE-1:0][SRC_LEN-1:0]          rd_ret,
    input logic  [ROB_MAX_RETIRE-1:0]                      val_ret,
    input logic  [ROB_MAX_RETIRE-1:0]                   branch_ret,  //sw also doesnt write !!!!! need signal -> generalize??? 
    input logic  [ROB_MAX_RETIRE-1:0][ROB_SIZE_CLOG-1:0] robid_ret,
    
    //outputs of f-rat
    output logic [ISSUE_WIDTH_MAX-1:0][OPCODE_LEN-1:0] opcode_ar,
    output logic [ISSUE_WIDTH_MAX-1:0][SRC_LEN-1:0]        rd_ar,
    output logic [ISSUE_WIDTH_MAX-1:0][NUM_SRCS-1:0][RAT_RENAME_DATA_WIDTH-1:0] src_rdy_2_issue_ar,
    output logic [ISSUE_WIDTH_MAX-1:0][NUM_SRCS-1:0]                  src_data_type_rdy_2_issue_ar, // 1: PRF, 0: ROB 
    output logic [ISSUE_WIDTH_MAX-1:0]      		instr_val_ar,
    output instr_info_t [ISSUE_WIDTH_MAX-1:0] instr_info_ar
    );

    logic [ISSUE_WIDTH_MAX-1:0][OPCODE_LEN-1:0] opcode_id;
    logic [ISSUE_WIDTH_MAX-1:0][SRC_LEN-1   :0] rd_id;
    logic [ISSUE_WIDTH_MAX-1:0][SRC_LEN-1   :0] rs1_id;
    logic [ISSUE_WIDTH_MAX-1:0][SRC_LEN-1   :0] rs2_id;
    logic [ISSUE_WIDTH_MAX-1:0][FUNC3_SIZE-1:0] func3_id;
    logic [ISSUE_WIDTH_MAX-1:0][FUNC7_SIZE-1:0] func7_id;
    
    logic [RETIRE_WIDTH_MAX-1:0]                                        rat_write_id;
    logic [RETIRE_WIDTH_MAX-1:0][ROB_SIZE_CLOG-1:0]                     rat_port_data_id;
    logic [RETIRE_WIDTH_MAX-1:0][SRC_LEN      -1:0]                     rat_port_addr_id;
    
    logic [RETIRE_WIDTH_MAX-1:0] ret_val_ar;
    

    logic [ISSUE_WIDTH_MAX-1:0][NUM_SRCS-1:0][RAT_RENAME_DATA_WIDTH-1:0] src_renamed_ar;
    logic [ISSUE_WIDTH_MAX-1:0][NUM_SRCS-1:0]                          src_data_type_ar; // 1: PRF, 0: ROB 
    
    always_comb begin
        for (int i = 0; i < ISSUE_WIDTH_MAX; i++) begin
            instr_info_id[i].robid = rob_is_ptr[i];
        end
    end

    /////////////////////////////////////////////////
    //
    // Decode/Immediate Gen Logic
    //
    /////////////////////////////////////////////////
    
    instr_info_t [ISSUE_WIDTH_MAX-1:0] instr_info_id;    

    always_comb begin
        for (int i = 0; i < ISSUE_WIDTH_MAX; i++) begin
            opcode_id[i] = instr_id[i][6:0];
            rd_id[i]     = instr_id[i][11:7];
            rs1_id[i]    = instr_id[i][19:15];
            rs2_id[i]    = instr_id[i][24:20];
			func3_id[i]  = instr_id[i][14:12];
			func7_id[i]  = instr_id[i][31:25];

			instr_info_id[i].ctrl_sig.func3 = func3_id[i];
        end
    end

    //immediate generation
    always_comb begin
        for (int i = 0; i < ISSUE_WIDTH_MAX; i++) begin
            case(opcode_id[i])
                I_TYPE1:
                    instr_info_id[i].imm = {{20{instr_id[i][31]}}, instr_id[i][31:20]};
                I_TYPE2: 
                    instr_info_id[i].imm = {{20{instr_id[i][31]}}, instr_id[i][31:20]};
                I_TYPE3:
                    instr_info_id[i].imm = {{20{instr_id[i][31]}}, instr_id[i][31:20]};
                S_TYPE:
                    instr_info_id[i].imm = {{20{instr_id[i][31]}}, instr_id[i][31:25], instr_id[i][11:7]};
                SB_TYPE: 
                    instr_info_id[i].imm = {{19{instr_id[i][31]}}, instr_id[i][31], instr_id[i][7],
                     instr_id[i][30:25], instr_id[i][12:8]};
                U_TYPE1:
                    instr_info_id[i].imm = {instr_id[i][31:12],12'b0};
                U_TYPE2:
                    instr_info_id[i].imm = {{12{instr_id[i][31]}}, instr_id[i][31:12]};
                J_TYPE:
                    instr_info_id[i].imm = {{12{instr_id[i][20]}}, instr_id[i][20], instr_id[i][10:1],
                     instr_id[i][11], instr_id[i][19:12]};
                default:
                    instr_info_id[i].imm = DEFAULT_IMMEDIATE;
            endcase
        end
    end
    
	
    always_comb begin
        for (int i = 0; i < ISSUE_WIDTH_MAX; i++) begin
            case(opcode_id[i])
                I_TYPE1: begin //JALR
                            instr_info_id[i].ctrl_sig.alu_src  = 1;
                            instr_info_id[i].ctrl_sig.fu_dest  = BEU_LANE_MASK;
                            instr_info_id[i].ctrl_sig.alu_ctrl = ADD_OP;
							instr_info_id[i].ctrl_sig.memRead  = 0;
							instr_info_id[i].ctrl_sig.memWrite = 0;
							instr_info_id[i].ctrl_sig.rfWrite  = 1;
                         end
                I_TYPE2: begin //lw
                            instr_info_id[i].ctrl_sig.alu_src  = 1;
                            instr_info_id[i].ctrl_sig.fu_dest  = MEU_LANE_MASK;
                            instr_info_id[i].ctrl_sig.alu_ctrl = ADD_OP;
							instr_info_id[i].ctrl_sig.memRead  = 1;
							instr_info_id[i].ctrl_sig.memWrite = 0;
							instr_info_id[i].ctrl_sig.rfWrite  = 1;
                         end
                I_TYPE3: begin//ALU imm
                    		instr_info_id[i].ctrl_sig.alu_src  = 1;
                    		instr_info_id[i].ctrl_sig.fu_dest  = ALU_LANE_MASK;
							instr_info_id[i].ctrl_sig.memRead  = 0;
							instr_info_id[i].ctrl_sig.memWrite = 0;
							instr_info_id[i].ctrl_sig.rfWrite  = 1;
                    		case (func3_id[i])
                    		    ADDI_FUNC3: //addi
                    		        instr_info_id[i].ctrl_sig.alu_ctrl = ADD_OP;
                    		    SLTI_FUNC3: //slti
                    		        instr_info_id[i].ctrl_sig.alu_ctrl = LESS_THAN_OP;
                    		    SLTIU_FUNC3: //sltiu
                    		        instr_info_id[i].ctrl_sig.alu_ctrl = LESS_THAN_OP;
                    		    XORI_FUNC3: //xori
                    		        instr_info_id[i].ctrl_sig.alu_ctrl = XOR_OP;
                    		    ORI_FUNC3: //ori
                    		        instr_info_id[i].ctrl_sig.alu_ctrl = OR_OP;
                    		    ANDI_FUNC3: //andi
                    		        instr_info_id[i].ctrl_sig.alu_ctrl = AND_OP;
                    		    SR_I_FUNC3:     //just added : 101  for SRAI and SRLI
                    		        instr_info_id[i].ctrl_sig.alu_ctrl = (func7_id[i] == 7'b0100000) ? SHIFT_R_ARITH_OP : SHIFT_R_LOGICAL_OP; //other case is 7'b0000000 
                    		    SLLI_FUNC3: //slli
                    		        instr_info_id[i].ctrl_sig.alu_ctrl = SHIFT_L_LOGICAL_OP;
                    		    default:
                    		        instr_info_id[i].ctrl_sig.alu_ctrl = 'X;
                    		endcase
                		end
                U_TYPE1: begin	//LUI  //ALU op1 == 0;  just use immediate in op2 and store in rd
                    		instr_info_id[i].ctrl_sig.alu_src  = 1;
							instr_info_id[i].ctrl_sig.fu_dest  = ALU_LANE_MASK; //no ALU logic needed
							instr_info_id[i].ctrl_sig.memRead  = 0;
							instr_info_id[i].ctrl_sig.memWrite = 0;
							instr_info_id[i].ctrl_sig.rfWrite  = 1;
                    		//no functional unit destination, just put immediate in RF //DO I NEED CTRL SIGNAL??????
						end
                U_TYPE2: begin //AUIPC
							   //add a 20-bit unsigned immediate value to the 20 most significant bits of the program counter (PC) and store the result in a register
							   //op 1 PC, op2 immediate
                    		instr_info_id[i].ctrl_sig.alu_src  = 1;
                    		instr_info_id[i].ctrl_sig.fu_dest  = ALU_LANE_MASK; //no ALU logic needed
							instr_info_id[i].ctrl_sig.memRead  = 0;
							instr_info_id[i].ctrl_sig.memWrite = 0;
							instr_info_id[i].ctrl_sig.rfWrite  = 1;
                    	end
                J_TYPE: begin
							//JAL WILL!!! write back since stores PC+4 into return address register but also jumps with immediate
                    		instr_info_id[i].ctrl_sig.alu_src  = 1;
                    		instr_info_id[i].ctrl_sig.fu_dest  = BEU_LANE_MASK;
							instr_info_id[i].ctrl_sig.alu_ctrl = ADD_OP;
							instr_info_id[i].ctrl_sig.memRead  = 0;
							instr_info_id[i].ctrl_sig.memWrite = 0;
							instr_info_id[i].ctrl_sig.rfWrite  = 1;
                    	end
                S_TYPE: begin//sw //in OOO add is handled by L/S Unit
                            instr_info_id[i].ctrl_sig.alu_src  = 1;
                            instr_info_id[i].ctrl_sig.fu_dest  = MEU_LANE_MASK;
                            instr_info_id[i].ctrl_sig.alu_ctrl = ADD_OP;
							instr_info_id[i].ctrl_sig.memRead  = 0;
							instr_info_id[i].ctrl_sig.memWrite = 1;
							instr_info_id[i].ctrl_sig.rfWrite  = 0;
                        end
                SB_TYPE: begin //branches  //need func3 to determine other operations in JEU //use func3 in RS
							// rs1, rs2, and an additional immediate -> this complicates RS
                            instr_info_id[i].ctrl_sig.alu_src  = 0;
                            instr_info_id[i].ctrl_sig.fu_dest  = MEU_LANE_MASK;
                            instr_info_id[i].ctrl_sig.alu_ctrl = SUB_OP;
							instr_info_id[i].ctrl_sig.memRead  = 0;
							instr_info_id[i].ctrl_sig.memWrite = 0;
							instr_info_id[i].ctrl_sig.rfWrite  = 0;
                         end
                R_TYPE: begin // register ALU instruc
							instr_info_id[i].ctrl_sig.alu_src  = 0;
                    		instr_info_id[i].ctrl_sig.fu_dest  = ALU_LANE_MASK;
							instr_info_id[i].ctrl_sig.memRead  = 0;
							instr_info_id[i].ctrl_sig.memWrite = 0;
							instr_info_id[i].ctrl_sig.rfWrite  = 1;
                    		case(func3_id[i])
                    		    3'b000:   //add & SUB//***NOTE DID NOT CREATE CONSTANT -- CONSTANT SHOULD BE ZERO***
                    		        instr_info_id[i].ctrl_sig.alu_ctrl = (func7_id[i] == 7'b0100000) ? SUB_OP : ADD_OP; //other case 7'b0000000
                    		    SLL_FUNC3: //sll
                    		        instr_info_id[i].ctrl_sig.alu_ctrl = SHIFT_L_LOGICAL_OP;
                    		    SLT_FUNC3: //slt
                    		        instr_info_id[i].ctrl_sig.alu_ctrl = LESS_THAN_OP;
                    		    SLTU_FUNC3: //sltu
                    		        instr_info_id[i].ctrl_sig.alu_ctrl = LESS_THAN_OP;
                    		    XOR_FUNC3: //xor
                    		        instr_info_id[i].ctrl_sig.alu_ctrl = XOR_OP;
                    		    SR_FUNC3: //sra
                    		        instr_info_id[i].ctrl_sig.alu_ctrl = (func7_id[i] == 7'b0100000) ? SHIFT_R_ARITH_OP : SHIFT_R_LOGICAL_OP;
                    		    OR_FUNC3: //or
                    		        instr_info_id[i].ctrl_sig.alu_ctrl = OR_OP;
                    		    AND_FUNC3: //and
                    		        instr_info_id[i].ctrl_sig.alu_ctrl = AND_OP;
                    		    default:
                    		        instr_info_id[i].ctrl_sig.alu_ctrl = 'X;
                    		endcase
                end

                default: begin
                            instr_info_id[i].ctrl_sig.alu_src  = 'X;
                            instr_info_id[i].ctrl_sig.fu_dest  = 'X;
                            instr_info_id[i].ctrl_sig.alu_ctrl = 'X;
							instr_info_id[i].ctrl_sig.memRead  = 'X;
							instr_info_id[i].ctrl_sig.memWrite = 'X;
							instr_info_id[i].ctrl_sig.rfWrite  = 'X;
                         end

            endcase
        end
    end

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
    end

    logic [ISSUE_WIDTH_MAX-1:0] storeInstruc_id, branchInstruc_id;

    always_comb begin
        for (int i = 0; i < ISSUE_WIDTH_MAX; i++) begin
            storeInstruc_id[i]  = (opcode_id[i] == S_TYPE);
            branchInstruc_id[i] = (opcode_id[i] == SB_TYPE);
        end
    end
    
    //rename rs1 & rs2 before bypass from rob
    // FIXME : change to renamed from one of the read ports, will need 4 + 4 readports?

    always_ff@(posedge clk) begin
        for (int i = 0; i < ISSUE_WIDTH_MAX; i++) begin
            if (instr_val_id[i]) begin
                src_renamed_ar[i][RS_1] <= rat[rs1_id[i]].table_data;
                src_renamed_ar[i][RS_2] <= rat[rs2_id[i]].table_data;
                
                src_data_type_ar[i][RS_1] <= rat[rs1_id[i]].rf;
                src_data_type_ar[i][RS_2] <= rat[rs2_id[i]].rf;
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
        ret_w_val_id = val_ret & ~branch_ret; //checking which retiring instr. are updating rat/regfile

        rat_ret_rd_conflict_mtx_id = '{default:0};
        for (int i = 0; i < ISSUE_WIDTH_MAX; i++) begin
            for (int j = 0; j < ISSUE_WIDTH_MAX; j++) begin
                if (j != i)
                    rat_ret_rd_conflict_mtx_id[i][j] = ~(storeInstruc_id[i] | branchInstruc_id[i]) & instr_val_id[i] & (rd_id[i] == rd_id[j]);
            end
            
            for (int j = ISSUE_WIDTH_MAX; j < RETIRE_WIDTH_MAX+ISSUE_WIDTH_MAX; j++) begin
                for (int k = 0; k < RETIRE_WIDTH_MAX; k++) begin
                     rat_ret_rd_conflict_mtx_id[i][j] |= ret_w_val_id[k] & (rd_id[i] == rd_ret[k]);
                end
            end
        end  
        
        //may want to put this logic in retirement
        for (int i = ISSUE_WIDTH_MAX; i < RETIRE_WIDTH_MAX+ISSUE_WIDTH_MAX; i++) begin  //write port in question
            for (int j = ISSUE_WIDTH_MAX; j < RETIRE_WIDTH_MAX+ISSUE_WIDTH_MAX; j++) begin //comparison to other write ports
                if (j != i)
                    rat_ret_rd_conflict_mtx_id[i][j] = ret_w_val_id[i-ISSUE_WIDTH_MAX] & (rd_ret[i-ISSUE_WIDTH_MAX] == rd_ret[j-ISSUE_WIDTH_MAX]);
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
                rat_w_qual_id[i] |= (rat[rd_ret[i]].table_data == robid_ret[i]) & ~rat[rd_ret[i]].rf; // should adjust to read ports
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
        //rat_port_data_id[0] = instr_val_id[0] ? rob_is_ptr[0] : rd_ret[0];
        //rat_port_data_id[1] = instr_val_id[1] ? (instr_val_id[0] ? rob_is_ptr[1] : rob_is_ptr[0]) : rd_ret[1];
        
        for (int i = 0; i < ISSUE_WIDTH_MAX; i++) begin
            rat_port_addr_id[i] = instr_val_id[i] & ~(storeInstruc_id[i] | branchInstruc_id[i]) ? rd_id[i] : rd_ret[i];
            rat_port_data_id[i] = instr_val_id[i] & ~(storeInstruc_id[i] | branchInstruc_id[i]) ? rob_is_ptr[i] : rd_ret[i];
        end

        for (int i = ISSUE_WIDTH_MAX; i < RETIRE_WIDTH_MAX; i++) begin
            rat_port_data_id[i] = rd_ret[i]; //MAY BE LESS CDYN BY JUST RESETTING rat.rf
            rat_port_addr_id[i] = rd_ret[i];
        end
    end

    // write ports to FRAT
    always_ff@(posedge clk) begin
        for (int i = 0; i < RETIRE_WIDTH_MAX; i++) begin
            if (rat_write_id[i]) begin
                rat[rat_port_addr_id[i]].table_data <= rat_port_data_id[i];
                rat[rat_port_addr_id[i]].rf         <= val_ret[i] ? 1 : 0; //change to constants  //FIX ME * WRONG PRIORITY*
            end
        end
    end

    //////////////////////////////////////////
    //
    //  ID/AR 
    //
    //////////////////////////////////////////
    
    logic [RETIRE_WIDTH_MAX-1:0][ROB_SIZE_CLOG-1:0] robid_ret_ar;
    logic [RETIRE_WIDTH_MAX-1:0][SRC_LEN-1:0] rd_ret_ar;
    logic [ISSUE_WIDTH_MAX-1:0][NUM_SRCS-1:0][SRC_LEN-1:0] src_original_ar;
    
    always_ff@(posedge clk) begin
        if (rst) begin
            instr_info_ar   <= '0;
            ret_val_ar   	<= '0;
            robid_ret_ar 	<= '{default:0};
            instr_val_ar 	<= '0;
            rd_ret_ar    	<= '0;
            src_original_ar <= '0;
            opcode_ar    	<= '0;
            rd_ar        	<= '0;
        end else begin
            instr_info_ar <= instr_info_id;
            ret_val_ar    <= ret_w_val_id;
            robid_ret_ar  <= robid_ret;
            instr_val_ar  <= instr_val_id;
            rd_ret_ar     <= rd_ret;
            opcode_ar     <= opcode_id;
            rd_ar         <= rd_id;
            for (int i = 0; i < ISSUE_WIDTH_MAX; i++) begin
                src_original_ar[i][RS_1] <= rs1_id[i];
                src_original_ar[i][RS_2] <= rs2_id[i];
            end
        end
    end
    
    logic [ISSUE_WIDTH_MAX-1:0][NUM_SRCS-1:0][RETIRE_WIDTH_MAX-1:0]      ret_ovrd_dep_mtx_ar;
    logic [ISSUE_WIDTH_MAX-1:0][NUM_SRCS-1:0][RETIRE_WIDTH_MAX-1:0]      ret_ovrd_dep_mtx_id;
    logic [ISSUE_WIDTH_MAX-1:0][NUM_SRCS-1:0][RETIRE_WIDTH_MAX_CLOG-1:0] ret_ovrd_dep_mtx_onehot_ar;
    logic [ISSUE_WIDTH_MAX-1:0][NUM_SRCS-1:0][RETIRE_WIDTH_MAX_CLOG-1:0] ret_ovrd_dep_mtx_onehot_id;
    logic [RETIRE_WIDTH_MAX_CLOG-1:0] inbuff_ret_ovrd_dep_ar_onehot, outbuff_ret_ovrd_dep_ar_onehot;
    logic [RETIRE_WIDTH_MAX_CLOG-1:0] inbuff_ret_ovrd_dep_id_onehot, outbuff_ret_ovrd_dep_id_onehot;

    
    //retirement override dependency matrix
    always_comb begin
        for (int i = 0; i < ISSUE_WIDTH_MAX; i++) begin
            ret_ovrd_dep_mtx_ar[i] = '{default:0};
            ret_ovrd_dep_mtx_id[i] = '{default:0};
            for (int s = 0; s < NUM_SRCS; s++) begin
                for (int r = 0; r < RETIRE_WIDTH_MAX; r++) begin
                    //check instructions that retired in last cycle that could not check before
                    ret_ovrd_dep_mtx_ar[i][s][r] = (src_renamed_ar[i][s] == robid_ret_ar[r]) & (instr_val_ar[i] & ret_val_ar[r]) & ~src_data_type_ar[i][s];
                    
                    //also need to check instructions currently retiring
                    ret_ovrd_dep_mtx_id[i][s][r] = (src_renamed_ar[i][s] ==    robid_ret[r]) & (instr_val_ar[i] &    val_ret[r]) & ~src_data_type_ar[i][s]; 
                end
            end
        end
    end
    
    logic [ISSUE_WIDTH_MAX-1:1][NUM_SRCS-1:0][ISSUE_WIDTH_MAX-2:0] src_dep_ovrd_mtx_ar; //ISSUE SRC dependedent on which previous ISSUE checker
    logic [ISSUE_WIDTH_MAX-1:1][NUM_SRCS-1:0][ISSUE_WIDTH_MAX-2:0] src_dep_ovrd_mtx_qual_1st_ar;
    logic [ISSUE_WIDTH_MAX-1:1][NUM_SRCS-1:0][ISSUE_WIDTH_MAX_CLOG-1:0] src_dep_ovrd_mtx_one_hot_ar;
    logic [ISSUE_WIDTH_MAX-2:0] inbuff_src_dep_mtx, outbuff_src_dep_mtx;  //weird thing with macros where I have to buffer signal
    logic [ISSUE_WIDTH_MAX_CLOG-1:0] inbuff_src_dep_onehot, outbuff_src_dep_onehot;
    
    always_comb begin
        for (int i = 1; i < ISSUE_WIDTH_MAX; i++) begin //instr 0 will not have any dependencies
            src_dep_ovrd_mtx_ar[i] = '{default:0};
            for (int s = 0; s < NUM_SRCS; s++) begin
                for (int j = 0; j < (ISSUE_WIDTH_MAX-1); j++) begin //cannot compare last instr to itself                
                    src_dep_ovrd_mtx_ar[i][s][j] = (src_original_ar[i][s] == rd_ar[j]) & (instr_val_ar[i] & instr_val_ar[j]);
                end
            end
        end
    end
    
    //macro qualifiers and encodings for src dependency tracker
    always_comb begin
        for (int i = 1; i < ISSUE_WIDTH_MAX; i++) begin //instr 0 will not have any dependencies
            src_dep_ovrd_mtx_qual_1st_ar[i] = '{default:0};
            src_dep_ovrd_mtx_one_hot_ar[i]  = '{default:0};
            for (int s = 0; s < NUM_SRCS; s++) begin
                inbuff_src_dep_mtx = src_dep_ovrd_mtx_ar[i][s];
                `ONE_1ST_MSB(outbuff_src_dep_mtx, inbuff_src_dep_mtx);
                src_dep_ovrd_mtx_qual_1st_ar[i][s] = outbuff_src_dep_mtx;
                
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

    //generate final src renamed with false dependencies removed
    always_comb begin
        src_rdy_2_issue_ar = '{default:0};
        src_data_type_rdy_2_issue_ar = '{default:0};
        for (int i = 1; i < ISSUE_WIDTH_MAX; i++) begin
            for (int s = 0; s < NUM_SRCS; s++) begin
                src_rdy_2_issue_ar[i][s] =           |src_dep_ovrd_mtx_qual_1st_ar[i][s] ? instr_info_ar[src_dep_ovrd_mtx_one_hot_ar[i][s]].robid :
                                                     |ret_ovrd_dep_mtx_id[i][s]          ? rd_ret[        ret_ovrd_dep_mtx_onehot_id[i][s]] :
                                                     |ret_ovrd_dep_mtx_ar[i][s]          ? rd_ret_ar[     ret_ovrd_dep_mtx_onehot_ar[i][s]] :
                                                           src_renamed_ar[i][s];
                                                
                src_data_type_rdy_2_issue_ar[i][s] = |src_dep_ovrd_mtx_qual_1st_ar[i][s] ? ROB_DATA_TYPE :
                                                    (|ret_ovrd_dep_mtx_id[i][s] | 
                                                     |ret_ovrd_dep_mtx_ar[i][s])         ? RF_DATA_TYPE : 
                                                         src_data_type_ar[i][s];                
            end
        end
        for (int s = 0; s < NUM_SRCS; s++) begin 
            src_rdy_2_issue_ar[0][s] =            |ret_ovrd_dep_mtx_id[0][s]   ? rd_ret[   ret_ovrd_dep_mtx_onehot_id[0][s]] :
                                                  |ret_ovrd_dep_mtx_ar[0][s]   ? rd_ret_ar[ret_ovrd_dep_mtx_onehot_ar[0][s]] :
                                                        src_renamed_ar[0][s];
            src_data_type_rdy_2_issue_ar[0][s] = (|ret_ovrd_dep_mtx_id[0][s]  |
                                                  |ret_ovrd_dep_mtx_ar[0][s]) ? RF_DATA_TYPE : 
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
