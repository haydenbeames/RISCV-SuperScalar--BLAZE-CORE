//-----------------------------------------------------------------------------
// Copyright 2021 Andrea Miele
// 
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// 
//     http://www.apache.org/licenses/LICENSE-2.0
// 
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//-----------------------------------------------------------------------------

// Radix4SRTDivider.sv
// Radix-4 generic integer SRT divider
// remainder is in rxqReg[N + 2 : N] and it is kept in [-2/3 y, 2/3 y]

module Radix4SRTDivider
#(
    parameter N = 32
)
(
    input logic rst,
    input logic clk,
    input logic start,
    input logic signedInput,
    input logic [N - 1 : 0] x,
    input logic [N - 1 : 0] y,
    output logic [N - 1 : 0] q,
    output logic [N - 1 : 0] r,
    output logic done,
    output logic divByZeroEx
);

typedef enum {RESET, START, RUN, DONE} State;
State state;
logic doneReg;
logic divByZeroExReg;
logic [N - 1 : 0] qnReg;
logic [N - 1 : 0] yReg;
logic [2 * N + 2 : 0] rxqReg;
logic [$size(N) - 1 : 0] counter;
logic ySign;
logic [$size(N) : 0] shiftY;
logic [$size(N) : 0] shiftYReg;
logic [N - 1 : 0] yAbs;
logic [N + 2 : 0] cReg;
logic [N + 2 : 0] ca, sa, cs, ss, ca2, sa2, cs2, ss2;
logic [N + 2 : 0] ca1, sa1, cs1, ss1; // to handle odd N
logic [5 : 0] r6;
logic [7 : 0] r8;
logic [2 * N + 2 : 0] rxVar;
logic [N + 2 : 0] sum;
logic q0, q1, qSign;

// outputs
assign q = rxqReg[N - 1 : 0];
assign r = rxqReg[2 * N - 1 : N];
assign done = doneReg;
assign divByZeroEx = divByZeroExReg;

assign sum = rxqReg[2 * N + 2 : N] + {cReg[N + 2 : 0]};
assign r8 = rxqReg[2 * N : 2 * N - 7] + cReg[N : N - 7]; // need to sum 8 bits of carry-save registers with carry ripple to select q
assign r6 = r8[7 : 2]; // last bit is sign
assign yAbs = (y[N - 1] & signedInput) ? -y : y;

zeroMSBCounter #(N) zmsb(.x(yAbs), .out(shiftY));
// For odd N, last iteration shift by 1 only
csAddSubGen #(N + 3) csadd1(.sub(1'b0), .cin({cReg[N + 1 : 0], 1'b0}), .x({rxqReg[2 * N + 1 : N - 1]}), .y({3'b000, yReg}), 
.s(sa1), .c(ca1));
csAddSubGen #(N + 3) cssub1(.sub(1'b1), .cin({cReg[N + 1 : 0], 1'b0}), .x({rxqReg[2 * N + 1 : N - 1]}), .y({3'b000, yReg}), 
.s(ss1), .c(cs1));

csAddSubGen #(N + 3) csadd(.sub(1'b0), .cin({cReg[N : 0], 2'b00}), .x(rxqReg[2 * N : N - 2]), .y({3'b000, yReg}), 
.s(sa), .c(ca));
csAddSubGen #(N + 3) cssub(.sub(1'b1), .cin({cReg[N : 0], 2'b00}), .x(rxqReg[2 * N : N - 2]), .y({3'b000, yReg}), 
.s(ss), .c(cs));
csAddSubGen #(N + 3) csadd2(.sub(1'b0), .cin({cReg[N : 0], 2'b00}), .x(rxqReg[2 * N : N - 2]), .y({2'b0, yReg, 1'b0}), 
.s(sa2), .c(ca2));
csAddSubGen #(N + 3) cssub2(.sub(1'b1), .cin({cReg[N : 0], 2'b00}), .x(rxqReg[2 * N : N - 2]), .y({2'b0, yReg, 1'b0}), 
.s(ss2), .c(cs2));

// simplified, non-negative, quotient selection LUT/PLA 
// use 1's complement absolute value
qSelPLAPos qSelect(r6[5] ? ~r6[4 : 0]: r6[4 : 0], yReg[N - 1 : N - 4], {q1, q0});
assign qSign = r6[5] & (!({q1, q0} == 2'b00)); // Takes care of sign-magnitude 000, 100 zeros

// signed shift
always_comb
begin: signedShift
    rxVar = x <<< shiftY;
end


always_ff @(posedge clk)
begin: FSM
    integer i;
    if(rst)
    begin
        state <= RESET;
        doneReg <= 1'b0; 
    end
    else 
    begin
        case (state)
            RESET:
            begin
                counter <= '0;
                rxqReg <= '0;
                yReg <= '0;
                qnReg <= '0;
                cReg <= '0;
                doneReg <= 1'b0;
                divByZeroExReg <= 1'b0;
                if(start)
                    state <= START;
                else 
                    state <= RESET;  
            end
            START:
            begin
                shiftYReg <= shiftY;
                yReg      <= yAbs << shiftY;
                ySign <= y[N - 1];
                rxqReg  <=   rxVar;
                if (y == {N{1'b0}})
                begin
                    doneReg <= 1'b1;
                    divByZeroExReg <= 1'b1;
                    state <= DONE;  
                end
                else
                    state <= RUN;
            end
            DONE:
            begin
                state <= DONE;
            end
            RUN:
            begin
                if (counter == N / 2 + N % 2)
                begin
                    if(sum[N + 2])
                    begin
                        rxqReg[2 * N - 1 : N] <= N'((sum + yReg) >> shiftYReg);
                    end
                    else
                    begin
                        rxqReg[2 * N - 1 : N] <= N'(sum >> shiftYReg); 
                    end  
                    if(signedInput & ySign)
                        rxqReg[N - 1 : 0] <= -(rxqReg[N - 1 : 0] - sum[N]);   
                    else            
                        rxqReg[N - 1 : 0] <= rxqReg[N - 1 : 0] - sum[N];   
                    doneReg <= 1'b1;
                    counter <= 0;    
                    state <= DONE;
                end
                else
                if (counter == N / 2 && (N % 2) 
                || (counter == 0 && (y == 1 && x[N - 1] && !(signedInput)))) 
                // handle odd N (last iteration: shift by just 1) or 
                // first remainder > 2/3 y (first iteration: shift by just 1)
                begin
                    case ({qSign, q1, q0})
                        3'b000:
                        begin

                            rxqReg <= {rxqReg[2 * N + 1 : 0], 1'b0};  
                            cReg <= {cReg[N + 1 : 0], 1'b0};                     
                            qnReg <= {qnReg[N - 2 : 0], 1'b1};
                        end
                        3'b001:
                        begin

                            rxqReg <= {ss1, rxqReg[N - 2 : 0], 1'b1};  
                            cReg <=  cs1;                     
                            qnReg <= {rxqReg[N - 2 : 0], 1'b0};
                        end

                        3'b010:
                        begin

                            rxqReg <= {ss1, rxqReg[N - 2 : 0], 1'b1};  
                            cReg <=  cs1;                     
                            qnReg <= {rxqReg[N - 2 : 0], 1'b0};
                        end

                        3'b101:
                        begin

                            rxqReg <= {sa1, qnReg[N - 2 : 0], 1'b1};  
                            cReg <=  ca1;                     
                            qnReg <= {qnReg[N - 2 : 0], 1'b0};
                        end

                        3'b110:
                        begin

                            rxqReg <= {sa1, qnReg[N - 2 : 0], 1'b1};  
                            cReg <=  ca1;                     
                            qnReg <= {qnReg[N - 2 : 0], 1'b0};
                        end
                    endcase

                    state <= RUN;
                    counter <= counter + 1;                
                end
                else
                begin

                    case ({qSign, q1, q0})
                        3'b000:
                        begin

                            rxqReg <= {rxqReg[2 * N : 0], 2'b00};  
                            cReg <= {cReg[N : 0], 2'b00};                     
                            qnReg <= {qnReg[N - 3 : 0], 2'b11};
                        end
                        3'b001:
                        begin

                            rxqReg <= {ss, rxqReg[N - 3 : 0], 2'b01};  
                            cReg <=  cs;                     
                            qnReg <= {rxqReg[N - 3 : 0], 2'b00};
                        end

                        3'b010:
                        begin

                            rxqReg <= {ss2, rxqReg[N - 3 : 0], 2'b10};  
                            cReg <=  cs2;                     
                            qnReg <= {rxqReg[N - 3 : 0], 2'b01};
                        end

                        3'b101:
                        begin

                            rxqReg <= {sa, qnReg[N - 3 : 0], 2'b11};  
                            cReg <=  ca;                     
                            qnReg <= {qnReg[N - 3 : 0], 2'b10};
                        end

                        3'b110:
                        begin

                            rxqReg <= {sa2, qnReg[N - 3 : 0], 2'b10};  
                            cReg <=  ca2;                     
                            qnReg <= {qnReg[N - 3 : 0], 2'b01};
                        end
                    endcase

                    state <= RUN;
                    counter <= counter + 1;                
                end
            end   
        endcase
    end
end // end FSM
endmodule
