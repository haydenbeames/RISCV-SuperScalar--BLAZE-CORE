`ifndef STRUCTS
`define STRUCTS

`timescale 1ns / 1ps

    //ctrl signal struct
    typedef struct packed { 
        logic memRead;
        logic memWrite;
        logic rfWrite;
        logic [ALU_CTRL_WIDTH-1:0] alu_ctrl;
		logic alu_src;
        logic [FUNC3_WIDTH-1:0] func3;
        logic [CPU_NUM_LANES-1:0] fu_dest;
        
    } ctrl_sig_t;
    
    //instruction info packet
	typedef struct packed { 
		logic [ROB_SIZE_CLOG-1:0] robid;
		logic [DATA_LEN-1:0] imm; //immediate
		logic [DATA_LEN-1:0] pc;
		ctrl_sig_t ctrl_sig;

    } instr_info_t;

    //reservation station 
    typedef struct packed {
		logic [5:0] op; 	//instruction opcode
		logic [ROB_SIZE_CLOG:0] robid;
		logic [RAT_RENAME_DATA_WIDTH-1:0][NUM_SRCS-1:0] Q; //data location as specified from RAT //if zero, data already allocated
		logic [31:0][NUM_SRCS-1:0] V; 	//value of src operands needed
        logic [SRC_LEN-1:0] rd;
        logic [CPU_NUM_LANES-1:0] fu_dest;
        logic [FUNC3_WIDTH-1:0] func3;
        logic [DATA_LEN-1:0] imm;
		logic busy; 	//indicated specified rs and functional unit is occupied
		logic valid; 	//info in rs is valid

	} rs_t;

`endif //STRUCTS
