`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/04/2023 08:59:16 PM
// Design Name: 
// Module Name: fwd
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

//fwd unit  
module fwd(
    input wire logic clk,
        
    );
    
    /*
    1 Cycle Lane:      AR | RS | FWD | EX1 | CMT
    Long Latency Lane: AR | RS | FWD | EX1 | EX2 | CMT
    
    FWD MUX: select data out of EX1, EX2, or CMT 
    
    Scheduling determined in RS to time FWD select muxes
    
    
    */
    
endmodule
