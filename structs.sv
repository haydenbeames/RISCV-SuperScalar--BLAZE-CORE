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
    
    //alu laneinfo packet
	typedef struct packed { 
		logic [ROB_SIZE_CLOG-1:0] robid;
		logic [NUM_SRCS-1:0][DATA_LEN-1:0] src;
		logic [ALU_CTRL_WIDTH-1:0] alu_ctrl;

    } alu_lane_t;
    
    //int mul laneinfo packet
	typedef struct packed { 
		logic [ROB_SIZE_CLOG-1:0] robid;
		logic [NUM_SRCS-1:0][DATA_LEN-1:0] src;
		logic [FUNC3_SIZE-1:0] func3;

    } int_mul_lane_t;

    //reservation station 
    typedef struct packed {
		logic [OPCODE_LEN-1:0] op; 	//instruction opcode
		logic [ROB_SIZE_CLOG:0] robid;
		logic [NUM_SRCS-1:0][RAT_RENAME_DATA_WIDTH-1:0] Q; //data location as specified from RAT //if zero, data already allocated
		logic [NUM_SRCS-1:0][31:0] V; 	//value of src operands needed
        logic [SRC_LEN-1:0] rd;
        logic [DATA_LEN-1:0] imm;
		logic valid; 	//info in rs is valid
		
		ctrl_sig_t ctrl_sig;

	} rs_t;
	
	//re-order buffer
	typedef struct packed { 
        logic [SRC_LEN-1:0]  rd;
        logic [DATA_LEN-1:0] pc;
        logic [DATA_LEN-1:0] data; //branch should just use data to take of pc
        logic        v;
        logic        done;
        logic        rfWrite;
        logic        memWrite;
        
    } rob_t;
	
	typedef struct packed {
	   logic [CPU_NUM_LANES-1:0] alu;
	   logic [CPU_NUM_LANES-1:0] beu;
	   
	} fu_dest_t;
	
	typedef struct packed {
	   logic [CPU_NUM_LANES_CLOG:0] alu;
	   logic [CPU_NUM_LANES_CLOG:0] beu;
	   
	} lane_cnt_t;
	
`endif //STRUCTS
