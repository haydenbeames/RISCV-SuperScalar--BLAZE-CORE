`timescale 1ns / 1ps
/***************************************************************************
*Module: <alu>
*Filename: alu.sv
*
* Author: <Hayden Beames>
* Class: <ECEn 323, Section 2, Winter Semester>
* Date: <12/29/2021>
*
* Description: <ALU with 9 operands>
*
****************************************************************************/
`include "riscv_alu_constants.sv"
`include "rtl_constants.sv"

//`default_nettype none
module int_alu(
        input  logic alu_val_ex1,
        input  logic [DATA_LEN-1:0]       rs1_ex1,
        input  logic [DATA_LEN-1:0]       rs2_ex1,
        input  logic [ALU_CTRL_WIDTH-1:0] alu_ctrl_ex1,
        input  logic [ROB_SIZE_CLOG-1:0] robid_ex1,
        //output logic zero, //only needed for BEU
        output logic                     alu_result_val_ex1,
        output logic [ROB_SIZE_CLOG-1:0] robid_result_ex1,
        output logic [DATA_LEN-1:0]      result_alu_ex1
    );
    
    //alu operands in always comb
    always_comb begin
        case(alu_ctrl_ex1)
            AND_OP:             result_alu_ex1 = rs1_ex1[DATA_LEN-1:0] & rs2_ex1[DATA_LEN-1:0];
            OR_OP:              result_alu_ex1 = rs1_ex1[DATA_LEN-1:0] | rs2_ex1[DATA_LEN-1:0];
            ADD_OP:             result_alu_ex1 = rs1_ex1[DATA_LEN-1:0] + rs2_ex1[DATA_LEN-1:0];
            SUB_OP:             result_alu_ex1 = rs1_ex1[DATA_LEN-1:0] - rs2_ex1[DATA_LEN-1:0];
            LESS_THAN_OP:       result_alu_ex1 =  ($signed(rs1_ex1[DATA_LEN-1:0]) < $signed(rs2_ex1[DATA_LEN-1:0])) ? 32'b1 : 32'b0;
            SHIFT_R_LOGICAL_OP: result_alu_ex1 = rs1_ex1[DATA_LEN-1:0] >> rs2_ex1[4:0];
            SHIFT_L_LOGICAL_OP: result_alu_ex1 = rs1_ex1[DATA_LEN-1:0] << rs2_ex1[4:0];
            SHIFT_R_ARITH_OP:   result_alu_ex1 = $unsigned($signed(rs1_ex1[DATA_LEN-1:0]) >>> rs2_ex1[4:0]);
            XOR_OP:             result_alu_ex1 = rs1_ex1[DATA_LEN-1:0] ^ rs2_ex1[DATA_LEN-1:0];
            default:            result_alu_ex1 = rs1_ex1 + rs2_ex1;
        endcase
    end
    
    assign alu_result_val_ex1 = alu_val_ex1;
    assign   robid_result_ex1 =   robid_ex1;
        /*
        //zero_ex1 output logic
        if(result_alu == 0)
            zero_ex1 = 1;
        else
            zero_ex1 = 0;
        end
        */
     
endmodule
