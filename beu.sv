`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/04/2023 09:03:53 PM
// Design Name: 
// Module Name: beu
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
//////////////////////////////////////////////////////////////////////////////////

//include files
`include "rtl_constants.sv"
`include "decode_constants.sv"
`include "riscv_alu_constants.sv"
`include "macros.sv"
`include "structs.sv"

//Branch Execution Unit
module beu(
    input  logic clk_free_master,
    input  logic global_rst,
    
    input  logic [DATA_LEN-1:0] rs1_ex1,
    input  logic [DATA_LEN-1:0] rs2_ex1,
    input  logic [DATA_LEN-1:0] imm_ex1,

    
    output logic [DATA_LEN-1:0] jmp_target_ex1
    );
    
    assign jmp_target_ex1[DATA_LEN-1:0] = rs1_ex1[DATA_LEN-1:0]
                                        + rs2_ex1[DATA_LEN-1:0]
                                        + imm_ex1[DATA_LEN-1:0]; //NOT CORRECT - Temporary
    
endmodule
