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

module idecode(
    input  logic        [ISSUE_WIDTH_MAX-1:0][DATA_LEN-1:0]      instr_id,
    //inputs from rob
    input  logic        [ISSUE_WIDTH_MAX-1:0][ROB_SIZE_CLOG-1:0] rob_is_ptr,

    output instr_info_t [ISSUE_WIDTH_MAX-1:0]                    instr_info_id, //to reorder buffer
    output logic        [ISSUE_WIDTH_MAX-1:0][OPCODE_LEN-1:0]    opcode_id,
    output logic        [ISSUE_WIDTH_MAX-1:0][PRF_SIZE_CLOG-1:0] rd_id,
    output logic        [ISSUE_WIDTH_MAX-1:0][PRF_SIZE_CLOG-1:0] rs1_id,
    output logic        [ISSUE_WIDTH_MAX-1:0][PRF_SIZE_CLOG-1:0] rs2_id
    );
    logic [ISSUE_WIDTH_MAX-1:0][FUNC3_SIZE-1:0] func3_id;
    logic [ISSUE_WIDTH_MAX-1:0][FUNC7_SIZE-1:0] func7_id;
    
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
                            instr_info_id[i].ctrl_sig.fu_dest  = BEU_LANE;
                            instr_info_id[i].ctrl_sig.alu_ctrl = ADD_OP;
							instr_info_id[i].ctrl_sig.memRead  = 0;
							instr_info_id[i].ctrl_sig.memWrite = 0;
							instr_info_id[i].ctrl_sig.rfWrite  = 1;
                         end
                I_TYPE2: begin //lw
                            instr_info_id[i].ctrl_sig.alu_src  = 1;
                            instr_info_id[i].ctrl_sig.fu_dest  = MEU_LANE;
                            instr_info_id[i].ctrl_sig.alu_ctrl = ADD_OP;
							instr_info_id[i].ctrl_sig.memRead  = 1;
							instr_info_id[i].ctrl_sig.memWrite = 0;
							instr_info_id[i].ctrl_sig.rfWrite  = 1;
                         end
                I_TYPE3: begin//ALU imm
                    		instr_info_id[i].ctrl_sig.alu_src  = 1;
                    		instr_info_id[i].ctrl_sig.fu_dest  = INT_ALU_LANE;
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
                    		instr_info_id[i].ctrl_sig.alu_ctrl = DEFAULT_OP;
							instr_info_id[i].ctrl_sig.fu_dest  = INT_ALU_LANE; //no ALU logic needed
							instr_info_id[i].ctrl_sig.memRead  = 0;
							instr_info_id[i].ctrl_sig.memWrite = 0;
							instr_info_id[i].ctrl_sig.rfWrite  = 1;
                    		//no functional unit destination, just put immediate in RF //DO I NEED CTRL SIGNAL??????
						end
                U_TYPE2: begin //AUIPC
							   //add a 20-bit unsigned immediate value to the 20 most significant bits of the program counter (PC) and store the result in a register
							   //op 1 PC, op2 immediate
                    		instr_info_id[i].ctrl_sig.alu_src  = 1;
                    		instr_info_id[i].ctrl_sig.alu_ctrl = DEFAULT_OP;
                    		instr_info_id[i].ctrl_sig.fu_dest  = INT_ALU_LANE; //no ALU logic needed
							instr_info_id[i].ctrl_sig.memRead  = 0;
							instr_info_id[i].ctrl_sig.memWrite = 0;
							instr_info_id[i].ctrl_sig.rfWrite  = 1;
                    	end
                J_TYPE: begin
							//JAL WILL!!! write back since stores PC+4 into return address register but also jumps with immediate
                    		instr_info_id[i].ctrl_sig.alu_src  = 1;
                    		instr_info_id[i].ctrl_sig.fu_dest  = BEU_LANE;
							instr_info_id[i].ctrl_sig.alu_ctrl = ADD_OP;
							instr_info_id[i].ctrl_sig.memRead  = 0;
							instr_info_id[i].ctrl_sig.memWrite = 0;
							instr_info_id[i].ctrl_sig.rfWrite  = 1;
                    	end
                S_TYPE: begin//sw //in OOO add is handled by L/S Unit
                            instr_info_id[i].ctrl_sig.alu_src  = 1;
                            instr_info_id[i].ctrl_sig.fu_dest  = MEU_LANE;
                            instr_info_id[i].ctrl_sig.alu_ctrl = ADD_OP;
							instr_info_id[i].ctrl_sig.memRead  = 0;
							instr_info_id[i].ctrl_sig.memWrite = 1;
							instr_info_id[i].ctrl_sig.rfWrite  = 0;
                        end
                SB_TYPE: begin //branches  //need func3 to determine other operations in JEU //use func3 in RS
							// rs1, rs2, and an additional immediate -> this complicates RS
                            instr_info_id[i].ctrl_sig.alu_src  = 0;
                            instr_info_id[i].ctrl_sig.fu_dest  = MEU_LANE;
                            instr_info_id[i].ctrl_sig.alu_ctrl = SUB_OP;
							instr_info_id[i].ctrl_sig.memRead  = 0;
							instr_info_id[i].ctrl_sig.memWrite = 0;
							instr_info_id[i].ctrl_sig.rfWrite  = 0;
                         end
                R_TYPE: begin // register ALU instruc
                            if (func7_id[i] == M_FUNC7) begin
                                instr_info_id[i].ctrl_sig.alu_src   = 0;
                    		    instr_info_id[i].ctrl_sig.fu_dest   = INT_MUL_LANE;
                                 instr_info_id[i].ctrl_sig.alu_ctrl = 0;
							    instr_info_id[i].ctrl_sig.memRead   = 0;
							    instr_info_id[i].ctrl_sig.memWrite  = 0;
							    instr_info_id[i].ctrl_sig.rfWrite   = 1;                               
                            end else begin
							    instr_info_id[i].ctrl_sig.alu_src  = 0;
                    		    instr_info_id[i].ctrl_sig.fu_dest  = INT_ALU_LANE;
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

endmodule
