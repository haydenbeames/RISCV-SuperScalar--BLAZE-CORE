//-----------------------------------------------------------------------------
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

// csAddSubGen.sv
// generic carry-save adder

module csAddSubGen
#(parameter N = 32)

(
input logic sub,
input logic [N - 1 : 0] x,
input logic [N - 1 : 0] y,
input logic [N - 1 : 0] cin,
output logic [N - 1: 0] s,
output logic [N - 1 : 0] c
);

logic [N - 1 : 0] ys;

assign ys = y ^ {N{sub}};
assign c[0] = 1'b0;
assign s[0] = x[0] ^ ys[0] ^ sub;
assign c[1] = x[0] & ys[0] | x[0] & sub | ys[0] & sub;
assign s[N - 1 : 1] = x[N - 1 : 1] ^ ys[N - 1 : 1] ^ cin[N - 1 : 1];
assign c[N - 1 : 2] = x[N - 2 : 1] & ys[N - 2 : 1] | x[N - 2 : 1] & cin[N - 2 : 1] |
 ys[N - 2 : 1] & cin[N - 2 : 1];

// ignore last carry

endmodule
