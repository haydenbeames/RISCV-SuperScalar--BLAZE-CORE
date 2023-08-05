`ifndef MACROS
`define MACROS

`timescale 1ns / 1ps

//outputs location of first LSB 0 ex. 8'b11011011 -> 8'b00000100
`define ZERO_1ST_LSB(OUT, IN) \
    begin \
        logic [$bits(IN)-1:0] in_invert, in_p1; \
        in_invert = ~IN; \
        in_p1     =  IN + 1; \
        OUT       = in_invert & in_p1; \
        //$display("First Zero LSB: %0b", OUT); \
    end

`define ZERO_1ST_MSB(OUT,IN) \
    begin \
        logic [$bits(IN)-1:0] in_invert, in_p1, in_flip, logic_out; \
        for (int i = 0; i < $bits(IN); i++) begin \
            in_flip[($bits(IN)-1)-i] = IN[i]; \
        end \
        in_invert = ~in_flip; \
        in_p1     =  in_flip + 1; \
        logic_out = in_invert & in_p1; \
        for (int i = 0; i < $bits(IN); i++) begin \
            OUT[($bits(IN)-1)-i] = logic_out[i]; \
        end \
        //$display("First One MSB: %0b", OUT); \
    end
    
//outputs location of first LSB 1 ex. 8'b10111000 -> 8'b00001000
`define ONE_1ST_LSB(OUT,IN) \
    begin \
        logic [$bits(IN)-1:0] in_invert_p1; \
        in_invert_p1 = ~IN + 1; \
        OUT = IN & in_invert_p1; \
        //$display("First One LSB: %0b", OUT); \
    end
    
//outputs location of first msb 1 ex. 8'b10111000 -> 8'b10000000
`define ONE_1ST_MSB(OUT,IN) \
    begin \
        logic [$bits(IN)-1:0] in_invert_p1, in_flip, logic_out; \
        for (int i = 0; i < $bits(IN); i++) begin \
            in_flip[($bits(IN)-1)-i] = IN[i]; \
        end \
        in_invert_p1 = ~in_flip + 1; \
        logic_out = in_flip & in_invert_p1; \
        for (int i = 0; i < $bits(IN); i++) begin \
            OUT[($bits(IN)-1)-i] = logic_out[i]; \
        end \
        //$display("First One MSB: %0b", OUT); \
    end

// NOTE!!!! RTL analysis shows this as a chain of muxes -> will need to implement as LUT likely
`define ONE_HOT_ENCODE(OUT,IN) \
    begin \
        logic [$clog2($bits(IN))-1:0] out; \
        out = 0; \
        for (int i = 0; i < $bits(IN); i++) begin \
            //$display("i: %0d  IN[%0d]: %0d\n", i, i, IN[i]); \
            if (IN[i] & 1'b1) \
                out = i; \
        end \
        OUT = out; \
    end
    
`endif // MACROS
