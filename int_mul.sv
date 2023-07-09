`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/14/2023 10:29:41 AM
// Design Name: 
// Module Name: 4to2_tree
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

`include "rtl_constants.sv"
`include "decode_constants.sv"

module signed_mul_4to2_tree_32bit(
    input wire logic clk,
    input wire logic mul_val,
    input wire logic [DATA_LEN-1:0] op1, op2,
    input wire logic [FUNC3_WIDTH-1:0] func3,
    input wire logic [ROB_SIZE_CLOG-1:0] robid,
    output logic [DATA_LEN*2-1:0] mul_result
    );
    
    logic signed_op1_ex1, signed_op2_ex1;

    //determine if signed multiplication
    always_comb begin
        case(func3)
            MUL_FUNC3: begin
                signed_op1_ex1 = TRUE;
                signed_op2_ex1 = TRUE;
                end
			MULH_FUNC3: begin
                signed_op1_ex1 = TRUE;
                signed_op2_ex1 = TRUE;
                end
			MULHSU_FUNC3: begin
                signed_op1_ex1 = TRUE;
                signed_op2_ex1 = FALSE;
                end
			MULHU_FUNC3: begin
                signed_op1_ex1 = FALSE;
                signed_op2_ex1 = FALSE; 
                end
		    default: begin
                signed_op1_ex1 = TRUE;
                signed_op2_ex1 = TRUE;
                end
		endcase
    end
    
    logic [DATA_LEN-1:0][DATA_LEN*2-1:0] pp_nontri, pp;
    logic [DATA_LEN-1:0][DATA_LEN-1:0] multiplicand_qual;
    
    
    //generate partial products
    always_comb begin
        for (int i = 0; i < DATA_LEN-1; i++) begin
            multiplicand_qual[i] = op1 & {DATA_LEN{op2[i]}};
        end
        
        if (signed_op2_ex1)
            multiplicand_qual[DATA_LEN-1] = {DATA_LEN{op2[DATA_LEN-1]}} & (~op1 + 1'b1); //twos complement last partial product
        else
            multiplicand_qual[DATA_LEN-1] = {DATA_LEN{op2[DATA_LEN-1]}} & op1;
            
        for (int i = 0; i < DATA_LEN-1; i++) begin
            for (int j = 0; j < DATA_LEN*2; j++) begin
                if (j < i)
                    pp_nontri[i][j] = 1'bX;
                else if (j < DATA_LEN + i)
                    pp_nontri[i][j] = multiplicand_qual[i][j-i];
                else
                    pp_nontri[i][j] = signed_op1_ex1 & op2[i] & op1[DATA_LEN-1];
            end
        end
        
        //iterate over last partial product sign extension and placement
        for (int j = 0; j < DATA_LEN*2-1; j++) begin
            if (j < (DATA_LEN-1)) 
                pp_nontri[DATA_LEN-1][j] = 1'b0;
            else if (j < DATA_LEN + (DATA_LEN-1))
                pp_nontri[DATA_LEN-1][j] = multiplicand_qual[DATA_LEN-1][j-(DATA_LEN-1)];
            else
                pp_nontri[DATA_LEN-1][j] = signed_op1_ex1 & op2[DATA_LEN-1] & op1[DATA_LEN-1];
        end
    
        //sign extension cases on last pp
        pp_nontri[DATA_LEN-1][DATA_LEN*2-1] = ((signed_op1_ex1 & op1[DATA_LEN-1]) ^ (signed_op2_ex1 & op2[DATA_LEN-1])) & op2[DATA_LEN-1] & multiplicand_qual[DATA_LEN-1][DATA_LEN-1]; 

        /* Dont need to put lower partial products to upper to create triangle in signed multiplication
        for (int i = 0; i < DATA_LEN; i++) begin
            for (int j = DATA_LEN; j < DATA_LEN*2; j++) begin           
                pp[(DATA_LEN-1)-i][j] = pp_nontri[i][j];
            end
        end
        */
        for (int i = 0; i < DATA_LEN; i++) begin  
            for (int j = 0; j < DATA_LEN*2; j++) begin //adjust from DATA_LEN to DATA_LEN*2 for Signed MUL
                pp[i][j] = pp_nontri[i][j];
            end
        end
    end

    //generate first stage of tree
    logic [DATA_LEN/2 -1:0][DATA_LEN*2-1:0] cout_stg1;
    logic [DATA_LEN/4 -1:0][DATA_LEN*2-1:0] cout_stg2;
    logic [DATA_LEN/8 -1:0][DATA_LEN*2-1:0] cout_stg3;
    logic [DATA_LEN/16-1:0][DATA_LEN*2-1:0] cout_stg4;
    
    logic [DATA_LEN/2 -1:0][DATA_LEN*2-1:0] in_stg2 = '{default:'0};
    logic [DATA_LEN/4 -1:0][DATA_LEN*2-1:0] in_stg3 = '{default:'0};
    logic [DATA_LEN/8 -1:0][DATA_LEN*2-1:0] in_stg4 = '{default:'0};
    logic [DATA_LEN/16-1:0][DATA_LEN*2-1:0] in_stg5 = '{default:'0};
    
    genvar g_i,g_j;
    
    //stage 1 adder tree
    generate
        
        ha ha_stg1_16_0(.a(pp[0][16]), .b(pp[1][16]), .s(in_stg2[0][16]), .c(in_stg2[1][17]));
        
        assign cout_stg1[0][16] = 1'b0;
        
        for (g_i = 17; g_i < DATA_LEN*2; g_i++) begin: c_4to2_stg1_0
            c_4to2 c_4to2_stg1_0(.in1(pp[0][g_i]),
                                 .in2(pp[1][g_i]),
                                 .in3(pp[2][g_i]),
                                 .in4(pp[3][g_i]), //0 for 2nd 4:2 compressor
                                 .cin( cout_stg1[0][g_i-1]),
                                 .s(     in_stg2[0][g_i]),
                                 .c(     in_stg2[1][g_i+1]),
                                 .cout(cout_stg1[0][g_i])
                                 );       
        end
        
        ha ha_stg1_18_2(.a(pp[4][18]), .b(pp[5][18]), .s(in_stg2[2][18]), .c(in_stg2[3][19]));
        
        assign cout_stg1[1][18] = 1'b0;
        
        for (g_i = 19; g_i < DATA_LEN*2; g_i++) begin: c_4to2_stg1_1
            c_4to2 c_4to2_stg1_1(.in1(pp[4][g_i]),
                                 .in2(pp[5][g_i]),
                                 .in3(pp[6][g_i]),
                                 .in4(pp[7][g_i]),
                                 .cin( cout_stg1[1][g_i-1]),
                                 .s(     in_stg2[2][g_i]),
                                 .c(     in_stg2[3][g_i+1]),
                                 .cout(cout_stg1[1][g_i])
                                 );       
        end
        
        ha ha_stg1_20_4(.a(pp[8][20]), .b(pp[9][20]), .s(in_stg2[4][20]), .c(in_stg2[5][21]));
        
        assign cout_stg1[2][20] = 1'b0;
        
        for (g_i = 21; g_i < DATA_LEN*2; g_i++) begin: c_4to2_stg1_2
            c_4to2 c_4to2_stg1_1(.in1(pp[8][g_i]),
                                 .in2(pp[9][g_i]),
                                 .in3(pp[10][g_i]),
                                 .in4(pp[11][g_i]),
                                 .cin( cout_stg1[2][g_i-1]),
                                 .s(     in_stg2[4][g_i]),
                                 .c(     in_stg2[5][g_i+1]),
                                 .cout(cout_stg1[2][g_i])
                                 );       
        end  
        
        ha ha_stg1_22_6(.a(pp[12][22]), .b(pp[13][22]), .s(in_stg2[6][22]), .c(in_stg2[7][23]));   
        
        assign cout_stg1[3][22] = 1'b0;
        
        for (g_i = 23; g_i < DATA_LEN*2; g_i++) begin: c_4to2_stg1_3
            c_4to2 c_4to2_stg1_1(.in1(pp[12][g_i]),
                                 .in2(pp[13][g_i]),
                                 .in3(pp[14][g_i]),
                                 .in4(pp[15][g_i]),
                                 .cin( cout_stg1[3][g_i-1]),
                                 .s(     in_stg2[6][g_i]),
                                 .c(     in_stg2[7][g_i+1]),
                                 .cout(cout_stg1[3][g_i])
                                 );       
        end    
        
        ha ha_stg1_24_8(.a(pp[16][24]), .b(pp[17][24]), .s(in_stg2[8][24]), .c(in_stg2[9][25]));   
        
        assign cout_stg1[4][24] = 1'b0;
        
        for (g_i = 25; g_i < DATA_LEN*2; g_i++) begin: c_4to2_stg1_4
            c_4to2 c_4to2_stg1_1(.in1(pp[16][g_i]),
                                 .in2(pp[17][g_i]),
                                 .in3(pp[18][g_i]),
                                 .in4(pp[19][g_i]),
                                 .cin( cout_stg1[4][g_i-1]),
                                 .s(     in_stg2[8][g_i]),
                                 .c(     in_stg2[9][g_i+1]),
                                 .cout(cout_stg1[4][g_i])
                                 );       
        end 
        
        ha ha_stg1_26_10(.a(pp[20][26]), .b(pp[21][26]), .s(in_stg2[10][26]), .c(in_stg2[11][27]));   
        
        assign cout_stg1[5][26] = 1'b0;
                                
        for (g_i = 27; g_i < DATA_LEN*2; g_i++) begin: c_4to2_stg1_5
            c_4to2 c_4to2_stg1_1(.in1(pp[20][g_i]),
                                 .in2(pp[21][g_i]),
                                 .in3(pp[22][g_i]),
                                 .in4(pp[23][g_i]),
                                 .cin( cout_stg1[5][g_i-1]),
                                 .s(     in_stg2[10][g_i]),
                                 .c(     in_stg2[11][g_i+1]),
                                 .cout(cout_stg1[5][g_i])
                                 );       
        end 
        
        ha ha_stg1_28_12(.a(pp[24][28]), .b(pp[25][28]), .s(in_stg2[12][28]), .c(in_stg2[13][29]));   
        
        assign cout_stg1[6][28] = 1'b0;
        
        for (g_i = 29; g_i < DATA_LEN*2; g_i++) begin: c_4to2_stg1_6
            c_4to2 c_4to2_stg1_1(.in1(pp[24][g_i]),
                                 .in2(pp[25][g_i]),
                                 .in3(pp[26][g_i]),
                                 .in4(pp[27][g_i]),
                                 .cin( cout_stg1[6][g_i-1]),
                                 .s(     in_stg2[12][g_i]),
                                 .c(     in_stg2[13][g_i+1]),
                                 .cout(cout_stg1[6][g_i])
                                 );       
        end
        
        ha ha_stg1_30_14(.a(pp[28][30]), .b(pp[29][30]), .s(in_stg2[14][30]), .c(in_stg2[15][31]));   
        
        assign cout_stg1[7][30] = 1'b0;
        
        for (g_i = 31; g_i < DATA_LEN*2; g_i++) begin: c_4to2_stg1_7
            c_4to2 c_4to2_stg1_1(.in1(pp[28][g_i]),
                                 .in2(pp[29][g_i]),
                                 .in3(pp[30][g_i]),
                                 .in4(pp[31][g_i]),
                                 .cin( cout_stg1[7][g_i-1]),
                                 .s(     in_stg2[14][g_i]),
                                 .c(     in_stg2[15][g_i+1]),
                                 .cout(cout_stg1[7][g_i])
                                 );       
        end
        
    endgenerate
    
    //create in_stg2 default inputs (just original partial products)
    always_comb begin          
        for (int j = 0; j <= 15; j++)
            for (int i = j; i >= 0; i--)
                in_stg2[i][j] = pp[i][j];  
        
        for (int j = 16; j <= 30; j++)
            for (int i = (j - 15); i <= 15; i++)
                in_stg2[i][j] = pp[i + (j-15)][j];

    end
    
    //stage 2 adder tree 
    generate
    
        ha ha_stg2_8_0(.a(in_stg2[0][8]), .b(in_stg2[1][8]), .s(in_stg3[0][8]), .c(in_stg3[1][9]));
        
        assign cout_stg2[0][8] = 1'b0;
        
        for (g_i = 9; g_i < DATA_LEN*2; g_i++) begin: c_4to2_stg2_0
            c_4to2 c_4to2_stg2_0(.in1(in_stg2[0][g_i]),
                                 .in2(in_stg2[1][g_i]),
                                 .in3(in_stg2[2][g_i]),
                                 .in4(in_stg2[3][g_i]), 
                                 .cin( cout_stg2[0][g_i-1]),
                                 .s(     in_stg3[0][g_i]),
                                 .c(     in_stg3[1][g_i+1]),
                                 .cout(cout_stg2[0][g_i])
                                 );                   
        end
        
        ha ha_stg2_10_2(.a(in_stg2[4][10]), .b(in_stg2[5][10]), .s(in_stg3[2][10]), .c(in_stg3[3][11]));
        
        assign cout_stg2[1][10] = 1'b0;
        
        for (g_i = 11; g_i < DATA_LEN*2; g_i++) begin: c_4to2_stg2_1
            c_4to2 c_4to2_stg2_0(.in1(in_stg2[4][g_i]),
                                 .in2(in_stg2[5][g_i]),
                                 .in3(in_stg2[6][g_i]),
                                 .in4(in_stg2[7][g_i]), 
                                 .cin( cout_stg2[1][g_i-1]),
                                 .s(     in_stg3[2][g_i]),
                                 .c(     in_stg3[3][g_i+1]),
                                 .cout(cout_stg2[1][g_i])
                                 );                   
        end
        
        ha ha_stg2_12_4(.a(in_stg2[8][12]), .b(in_stg2[9][12]), .s(in_stg3[4][12]), .c(in_stg3[5][13]));
        
        assign cout_stg2[2][12] = 1'b0;
        
        for (g_i = 13; g_i < DATA_LEN*2; g_i++) begin: c_4to2_stg2_2
            c_4to2 c_4to2_stg2_0(.in1(in_stg2[8][g_i]),
                                 .in2(in_stg2[9][g_i]),
                                 .in3(in_stg2[10][g_i]),
                                 .in4(in_stg2[11][g_i]), 
                                 .cin( cout_stg2[2][g_i-1]),
                                 .s(     in_stg3[4][g_i]),
                                 .c(     in_stg3[5][g_i+1]),
                                 .cout(cout_stg2[2][g_i])
                                 );                   
        end
        
        ha ha_stg2_14_6(.a(in_stg2[12][14]), .b(in_stg2[13][14]), .s(in_stg3[6][14]), .c(in_stg3[7][15]));
        
        assign cout_stg2[3][14] = 1'b0;
        
        for (g_i = 15; g_i < DATA_LEN*2; g_i++) begin: c_4to2_stg2_3
            c_4to2 c_4to2_stg2_0(.in1(in_stg2[12][g_i]),
                                 .in2(in_stg2[13][g_i]),
                                 .in3(in_stg2[14][g_i]),
                                 .in4(in_stg2[15][g_i]), 
                                 .cin( cout_stg2[3][g_i-1]),
                                 .s(     in_stg3[6][g_i]),
                                 .c(     in_stg3[7][g_i+1]),
                                 .cout(cout_stg2[3][g_i])
                                 );                   
        end
        
    endgenerate
    
    //create stage 3 default inputs (just unused from stage 2)
    always_comb begin
        for (int j = 0; j <= 7; j++)
            for (int i = j; i >= 0; i--)
                in_stg3[i][j] = in_stg2[i][j];  
        
        for (int j = 8; j <= 14; j++)
            for (int i = (j - 7); i <= 7; i++)
                in_stg3[i][j] = in_stg2[i + (j-7)][j];
                
    end
    
    //stage 3 adder tree 
    generate

        ha ha_stg3_4_0(.a(in_stg3[0][4]), .b(in_stg3[1][4]), .s(in_stg4[0][4]), .c(in_stg4[1][5]));
        
        assign cout_stg3[0][4] = 1'b0;
        
        for (g_i = 5; g_i < DATA_LEN*2; g_i++) begin: c_4to2_stg3_0
            c_4to2 c_4to2_stg3_0(.in1(in_stg3[0][g_i]),
                                 .in2(in_stg3[1][g_i]),
                                 .in3(in_stg3[2][g_i]),
                                 .in4(in_stg3[3][g_i]), 
                                 .cin( cout_stg3[0][g_i-1]),
                                 .s(     in_stg4[0][g_i]),
                                 .c(     in_stg4[1][g_i+1]),
                                 .cout(cout_stg3[0][g_i])
                                 );                   
        end 
        
        ha ha_stg3_6_2(.a(in_stg3[4][6]), .b(in_stg3[5][6]), .s(in_stg4[2][6]), .c(in_stg4[3][7]));
        
        assign cout_stg3[1][6] = 1'b0;
        
        for (g_i = 7; g_i < DATA_LEN*2; g_i++) begin: c_4to2_stg3_1
            c_4to2 c_4to2_stg3_0(.in1(in_stg3[4][g_i]),
                                 .in2(in_stg3[5][g_i]),
                                 .in3(in_stg3[6][g_i]),
                                 .in4(in_stg3[7][g_i]), 
                                 .cin( cout_stg3[1][g_i-1]),
                                 .s(     in_stg4[2][g_i]),
                                 .c(     in_stg4[3][g_i+1]),
                                 .cout(cout_stg3[1][g_i])
                                 );                   
        end 
          
    endgenerate
    
    //create stage 4 default inputs (just unused from stage 3)
    always_comb begin
        for (int j = 0; j <= 3; j++)
            for (int i = j; i >= 0; i--)
                in_stg4[i][j] = in_stg3[i][j];  
        
        for (int j = 4; j <= 6; j++)
            for (int i = (j - 3); i <= 3; i++)
                in_stg4[i][j] = in_stg3[i + (j-3)][j];
    end
    
    //stage 4 adder tree
    generate
        
        ha ha_stg4_2_0(.a(in_stg4[0][2]), .b(in_stg4[1][2]), .s(in_stg5[0][2]), .c(in_stg5[1][3]));
        
        assign cout_stg4[0][2] = 1'b0;
        
        for (g_i = 3; g_i < DATA_LEN*2; g_i++) begin: c_4to2_stg4_0
            c_4to2 c_4to2_stg3_0(.in1(in_stg4[0][g_i]),
                                 .in2(in_stg4[1][g_i]),
                                 .in3(in_stg4[2][g_i]),
                                 .in4(in_stg4[3][g_i]), 
                                 .cin( cout_stg4[0][g_i-1]),
                                 .s(     in_stg5[0][g_i]),
                                 .c(     in_stg5[1][g_i+1]),
                                 .cout(cout_stg4[0][g_i])
                                 );                   
        end
    endgenerate
    
    //create stage 4 default inputs (just unused from stage 3)
    always_comb begin
        for (int j = 0; j <= 1; j++)
            for (int i = j; i >= 0; i--)
                in_stg5[i][j] = in_stg4[i][j];  
        
        for (int j = 2; j <= 2; j++)
            for (int i = (j - 1); i <= 1; i++)
                in_stg5[i][j] = in_stg4[i + (j-1)][j];
    end
    
    logic [DATA_LEN*2-1:0] sum_4to2_tree, cout_4to2_tree;
    
    //stage 3 (add sum and carries for final product)
    always_comb begin
        sum_4to2_tree  = '0;
        cout_4to2_tree = '0;
        for (int i = 1; i < (DATA_LEN*2); i++) begin
            sum_4to2_tree[i]  = in_stg5[0][i];
            cout_4to2_tree[i] = in_stg5[1][i];
        end
        sum_4to2_tree[0] = in_stg3[0][0];
        
    end
    
    assign mul_result = sum_4to2_tree + cout_4to2_tree;

endmodule
