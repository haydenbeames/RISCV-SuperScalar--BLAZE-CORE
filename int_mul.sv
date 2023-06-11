`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/03/2023 11:03:11 PM
// Design Name: 
// Module Name: int_mul
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
`include "riscv_alu_constants.sv"
`include "macros.sv"
`include "structs.sv"

module int_mul(
    input wire logic clk, rst,
    input int_mul_lane_t int_mul_lane_info_ex1,
    
    output logic [DATA_LEN-1:0] mul_rslt_ex2
    );
    
    logic [DATA_LEN-1:0][DATA_LEN*2-1:0] partial_product_ex1;
    logic [DATA_LEN-1:0][DATA_LEN-1:0]   multiplicand_qual_ex1;
    logic is_signed_ex1;
    //determine if signed multiplication
    always_comb begin
        case(int_mul_lane_info_ex1.func3)
            MUL_FUNC3:
                is_signed_ex1 = TRUE;
			MULH_FUNC3:
				is_signed_ex1 = FALSE;
			MULHSU_FUNC3:
				is_signed_ex1 = FALSE;
			MULHU_FUNC3:
				is_signed_ex1 = FALSE;
		    default:
		        is_signed_ex1 = FALSE;
		endcase
    end
    //generate partial products
    logic [DATA_LEN-1:0][DATA_LEN-1:0] TEST_RS2_EXTEND;
    always_comb begin
        for (int i = 0; i < DATA_LEN; i++) begin 
            multiplicand_qual_ex1[i] = int_mul_lane_info_ex1.src[RS_1] & {DATA_LEN{int_mul_lane_info_ex1.src[RS_2][i]}};
            TEST_RS2_EXTEND[i] = {DATA_LEN{int_mul_lane_info_ex1.src[RS_2][i]}};
            partial_product_ex1[i] = multiplicand_qual_ex1[i] << i;
        end
    end
    
    //generate CSA adder tree (adds partial products) 
    logic [DATA_LEN_CLOG-1:0][DATA_LEN*2-1:0][DATA_LEN/2-1:0] A, B, Cin, Y, Cout;
    assign A = '{default:0};
    assign B = '{default:0};
    assign Cin = '{default:0};
    assign Y = '{default:0};
    assign Cout = '{default:0};
    genvar x, i, j;
    
    /*
    generate
        for (i = 0; i < DATA_LEN*2; i++) begin 
            for (j = 0; j < DATA_LEN/2; j++) begin
                assign A[0][i][j] = partial_product_ex1[j*2][i];
                assign B[0][i][j] = partial_product_ex1[j*2+1][i];   
                assign Cin[0][i][j] = 0;
                csa csa_t(A[0][i][j], B[0][i][j], Cin[0][i][j], Y[0][i][j], Cout[0][i][j]);
            end
        end

        for (x = 1; x < DATA_LEN_CLOG; x++) begin
            //int val = (DATA_LEN/(2**x))/2;
            //$display("NUM CSR: %d", val);
            for (i = 0; i < DATA_LEN*2; i++) begin 
                assign A[x][i][0] = Y[x-1][i][0*2];
                assign B[x][i][0] = Y[x-1][i][0*2+1];
                assign Cin[x][i][0] = 0;  
                csa csa_t(A[x][i][0], B[x][i][0], Cin[x][i][0], Y[x][i][0], Cout[x][i][0]);
                for (j = 1; j < (DATA_LEN/(2**x))/2; j++) begin
                    assign A[x][i][j] = Y[x-1][i][j*2];
                    assign B[x][i][j] = Y[x-1][i][j*2+1];
                    assign Cin[x][i][j] = Cout[x-1][i][j];   
                    csa csa_t(A[x][i][j], B[x][i][j], Cin[x][i][j], Y[x][i][j], Cout[x][i][j]);           
                end 
            end 
        end 
    endgenerate
    
    logic [DATA_LEN*2-1:0][DATA_LEN_CLOG:0] partial_product_sum;
    always_comb begin
        partial_product_sum = '{default:0};
        for (int i = 0; i < DATA_LEN*2; i++) begin 
            for (int j = 0; j < DATA_LEN; j++) begin 
                partial_product_sum[i] += partial_product_ex1[j][i];
             end
        end
    end
    
    
    
    logic [DATA_LEN*2-1:0] csa_rslt_ex1, csa_rslt_ex2;
    logic [DATA_LEN*2-1:0] csa_cout_ex1, csa_cout_ex2;
    
    always_comb begin
        csa_cout_ex1 = '0;
        csa_rslt_ex1 = '0;
        for (int i = 0; i < DATA_LEN*2; i++) begin
            csa_rslt_ex1[i] = partial_product_sum[i][0];//Y[   DATA_LEN_CLOG-1][i][0];
            for (int j = 1; j < (DATA_LEN_CLOG+1); j++) begin
                csa_cout_ex1[i] |= partial_product_sum[i][j];//Cout[DATA_LEN_CLOG-1][i][0];
            end
        end
    end
    
    always_ff@(posedge clk) begin 
        csa_rslt_ex2 <= csa_rslt_ex1;
        csa_cout_ex2 <= csa_cout_ex1;
    end
    */
     //testing to see if synthesis can make an efficient tree
     //otherwise will need to innovate a parameterizable adder tree which combines
     // 3:2 CSA and 4:2 compressors
    logic [DATA_LEN*2-1:0] mul_rslt_ex2;
    always_comb begin
        mul_rslt_ex2 = '0;
        for (int i = 0; i < DATA_LEN; i++) begin
            mul_rslt_ex2 += partial_product_ex1[i];
        end
    end   
    
endmodule
