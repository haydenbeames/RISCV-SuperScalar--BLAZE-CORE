`ifndef RISCV_ALU_CONSTANTS
`define RISCV_ALU_CONSTANTS

`timescale 1ns / 1ps
/***************************************************************************
*
* Filename: riscv_alu_constants.sv
*
* Author: <Hayden Beames>
* Class: <ECEn 323, Section 2, Winter Semester>
* Date: <1/2/2022>
*
* Description: <constants for operand>
*
****************************************************************************/

localparam[3:0] AND_OP = 4'b0000;
localparam[3:0] OR_OP = 4'b0001;
localparam[3:0] ADD_OP = 4'b0010;
localparam[3:0] SUB_OP = 4'b0110;
localparam[3:0] LESS_THAN_OP = 4'b0111;
localparam[3:0] SHIFT_R_LOGICAL_OP = 4'b1000;
localparam[3:0] SHIFT_L_LOGICAL_OP = 4'b1001;
localparam[3:0] SHIFT_R_ARITH_OP = 4'b1010;
localparam[3:0] XOR_OP = 4'b1101;
localparam[3:0] DEFAULT_OP = ADD_OP;



`endif // RISCV_ALU_CONSTANTS
