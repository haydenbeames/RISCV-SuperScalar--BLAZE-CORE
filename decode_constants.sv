`ifndef DECODE_CONSTANTS
`define DECODE_CONSTANTS

`timescale 1ns / 1ps
/***************************************************************************
*
* Filename: riscv_datapath_constants.sv
*
* Author: <Hayden Beames>
* Class: <ECEn 323, Section 2, Winter Semester>
* Date: <2/20/2022>
*
* Description: <constants for operand>
*
****************************************************************************/

//operand constants
localparam[6:0] I_TYPE1 = 7'b1100111;
localparam[6:0] I_TYPE2 = 7'b0000011;
localparam[6:0] I_TYPE3 = 7'b0010011;
localparam[6:0] S_TYPE = 7'b0100011;
localparam[6:0] SB_TYPE = 7'b1100011;
localparam[6:0] U_TYPE1 = 7'b0110111;
localparam[6:0] U_TYPE2 = 7'b0010111;
localparam[6:0] J_TYPE = 7'b1101111;
localparam[6:0] R_TYPE = 7'b0110011;

 //func3 & func7 parameters
localparam FUNC_SEVEN_DIFF = 7'b0100000;
localparam SLLI_FUNC3 = 3'b001;
localparam SRLI_FUNC3 = 3'b101;
localparam SRAI_FUNC3 = 3'b101;
localparam SLL_FUNC3 = 3'b001;
localparam SLT_FUNC3 = 3'b010;
localparam SLTU_FUNC3 = 3'b011;
localparam XOR_FUNC3 = 3'b100;
localparam SRL_FUNC3 = 3'b101;
localparam SRA_FUNC3 = 3'b101;
localparam OR_FUNC3 = 3'b110;
localparam AND_FUNC3 = 3'b111;
localparam ADDI_FUNC3 = 3'b000;
localparam SLTI_FUNC3 = 3'b010;
localparam SLTIU_FUNC3 = 3'b011;
localparam XORI_FUNC3 = 3'b100;
localparam ORI_FUNC3 = 3'b110;
localparam ANDI_FUNC3 = 3'b111;
localparam BEQ_FUNC3 = 3'b000;
localparam BLT_FUNC3 = 3'b100;
localparam BGE_FUNC3 = 3'b101;
localparam BNE_FUNC3 = 3'b001;

localparam MUL_FUNC3    = 3'b000;
localparam MULH_FUNC3   = 3'b001;
localparam MULHSU_FUNC3 = 3'b010;
localparam MULHU_FUNC3  =  3'b011;
 
localparam DEFAULT_OFFSET = 4'h4; //default increment for PC
localparam DEFAULT_IMMEDIATE = 32'hdeadbeef;
    
`endif //DECODE_CONSTANTS
