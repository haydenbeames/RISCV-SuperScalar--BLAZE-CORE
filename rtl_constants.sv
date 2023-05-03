`ifndef RTL_CONSTANTS_SV
`define RTL_CONSTANTS_SV

`timescale 1ns / 1ps

//CPU CONSTANTS
parameter CPU_NUM_LANES = 2; //number of execution lanes, i.e. ld/st, ALU's mult, div
parameter DATA_LEN = 32;
parameter SRC_LEN = 5;
parameter OPCODE_LEN = 7;
parameter BEU_LANE_MASK = 4'b0000;
parameter MEU_LANE_MASK = 4'b0000;
parameter ALU_LANE_MASK = 4'b0001;
parameter ALU_CTRL_WIDTH = 4;
parameter FUNC3_SIZE = 3;
parameter FUNC7_SIZE = 7;
localparam SR_FUNC3   = 3'b101;
localparam SR_I_FUNC3 = 3'b101;
parameter FUNC3_WIDTH = 3;
parameter NUM_SRCS = 2;
parameter RS_1	   = 0;
parameter RS_2 	   = 1;

//ISSUE CONSTANTS
parameter NUM_ISSUE_MAX = 1;
parameter ISSUE_WIDTH_MAX = 4;
parameter ISSUE_WIDTH_MAX_CLOG = $clog2(ISSUE_WIDTH_MAX);

//RS CONSTANTS
parameter RS_NUM_ENTRIES = 16;
parameter RS_NUM_ENTRIES_CLOG = $clog2(RS_NUM_ENTRIES);

//ROB CONSTANTS
parameter ROB_SIZE = 32;
parameter ROB_SIZE_CLOG = $clog2(ROB_SIZE);
parameter ROB_MAX_RETIRE  = 4; //change later
parameter RETIRE_WIDTH_MAX = ROB_MAX_RETIRE;
parameter RETIRE_WIDTH_MAX_CLOG = $clog2(RETIRE_WIDTH_MAX);
parameter ROB_MAX_RETIRE_CLOG = $clog2(ROB_MAX_RETIRE);

//REGFILE CONSTANTS
parameter RF_SIZE = 32;
parameter NUM_RF_R_PORTS = ISSUE_WIDTH_MAX*NUM_SRCS;
parameter NUM_RF_W_PORTS = RETIRE_WIDTH_MAX;

//RAT CONSTANTS
parameter RAT_RENAME_DATA_WIDTH  = $clog2(ROB_SIZE); //should change to whatever is greater: regfile or rob
parameter RAT_SIZE	 	  = RF_SIZE;
parameter RAT_TABLE_MAX_INDEX = $clog2(RAT_SIZE); 
parameter BRATCR_NUM_ETY = 3;
parameter BRATCR_NUM_ETY_CLOG = $clog2(BRATCR_NUM_ETY);
parameter RF_DATA_TYPE = 1;
parameter ROB_DATA_TYPE = 0;

//COMMIT CONSTANTS
parameter MAX_COMMIT_WIDTH  = 1; //change later
parameter CDB_NUM_LANES = CPU_NUM_LANES;



`endif //RTL_CONSTANTS
