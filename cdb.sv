`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/12/2023 12:17:17 AM
// Design Name: 
// Module Name: cdb
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

`include "structs.sv"

//check timing to see if adding pipe stage is necessary!!!!
module cdb(
    input wire logic clk,
    
    input wire logic v,
    input wire logic [ROB_SIZE_CLOG-1:0] robid,
    input wire logic [DATA_LEN-1:0] data,
 
    output     logic v_cmt,
    output     logic [ROB_SIZE_CLOG-1:0] robid_cmt,
    output     logic [DATA_LEN-1:0] data_cmt
    );
    
    always_ff@(posedge clk) begin
        v_cmt     <= v;
        robid_cmt <= robid;
        data_cmt  <= data;
    end
    
endmodule
