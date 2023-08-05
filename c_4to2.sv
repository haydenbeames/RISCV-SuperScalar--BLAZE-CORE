`timescale 1ns / 1ps


module c_4to2(
    input wire logic in1, in2, in3, in4, cin,
    output logic s, c, cout
    );

  
  //Gate-level implemtation instead of FA
  //based to reduce critical path to 3 XORs.
  //REF: http://www.ece.ucdavis.edu/~vojin/CLASSES/EEC180A/W2005/lectures/Lect-Multiplier.pdf
  logic cin_in1, i2_i3_i4,mux1, mux0;
  
  assign cin_in1 = cin ^ in1;
  assign i2_i3_i4 = ~(in2 ^ in3 ^ in4);
  assign s = ~(cin_in1 ^ i2_i3_i4); 
  
  assign mux1 = ~(cin & in1);
  assign mux0 = ~(cin | in1);
  assign c = (i2_i3_i4)?~mux1:~mux0; 
  assign cout = ~((~(in2 & in3)) & (~(in2 & in4)) & (~(in3 & in4)));  
  
endmodule
