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

// encoder.sv
// one-hot to binary encoded

module encoder
#(parameter N = 32)
(
    input logic [N - 1 : 0] x,
    output logic [$size(N) : 0] out
);

always_comb
begin
    out = {$clog2(N) + 1{1'b0}};
    for (int unsigned i = 0; i < N; i++)
    begin
        if (x[i])
            out |= $clog2(N)'(i);
    end
end
endmodule
