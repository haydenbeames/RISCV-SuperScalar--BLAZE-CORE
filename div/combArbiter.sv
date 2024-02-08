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

// combArbiter.sv
// returns one-hot position of most significant bit
// repeated cell   out[0] = x[0] & 1, out[1] = x[1] & ~x[0] & 1, out[2] = x[2] & ~x[1] & ~x[0] & 1

module combArbiter
#(parameter N = 32)
(  
    input logic [N - 1 : 0] x,
    output logic [N - 1 : 0] out
);
logic [N - 1 : 0] notFoundYet;

genvar i;
assign notFoundYet[0] = 1'b1;

generate
for(i = 1; i < N; i++)
begin: arbiterFor
    assign notFoundYet[i] = (~x[i - 1]) & notFoundYet[i - 1];
end
endgenerate
assign out = x & notFoundYet;
endmodule
