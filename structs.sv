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

	typedef struct packed { 
		logic [ROB_SIZE_CLOG-1:0]          robid;
		logic [NUM_SRCS-1:0][DATA_LEN-1:0] src;
		logic [ALU_CTRL_WIDTH-1:0]         alu_ctrl;
		logic                              v;

  } int_lane_info_t;
  
  //alu laneinfo packet
	typedef struct packed { 
		logic [ROB_SIZE_CLOG-1:0] robid;
		logic [NUM_SRCS-1:0][DATA_LEN-1:0] src;
		logic [ALU_CTRL_WIDTH-1:0] alu_ctrl;
		logic v; //valid

    } int_alu_lane_info_t;
    
  //int mul laneinfo packet
	typedef struct packed { 
		logic [ROB_SIZE_CLOG-1:0] robid;
		logic [NUM_SRCS-1:0][DATA_LEN-1:0] src;
		logic [FUNC3_SIZE-1:0] func3;
		logic v; //valid

    } int_mul_lane_t;

    //reservation station 
  typedef struct packed {
		logic [OPCODE_LEN-1:0]                  opcode; 	//instruction opcode
		logic [ROB_SIZE_CLOG:0]                 robid;
	  logic [NUM_SRCS-1:0][PRF_SIZE_CLOG-1:0] src;
	  logic [NUM_SRCS-1:0]                    src_valid;
    logic [PRF_SIZE_CLOG-1:0]               pdst;
    logic [DATA_LEN-1:0]                    imm;
		
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
	   logic [CPU_NUM_LANES-1:0] mul;
	   
	} fu_dest_t;
	
	typedef struct packed {
	   logic [CPU_NUM_LANES_CLOG:0] alu;
	   logic [CPU_NUM_LANES_CLOG:0] beu;
	   logic [CPU_NUM_LANES_CLOG:0] mul;
	   
	} lane_cnt_t;
	
	typedef struct packed {
	   logic [CPU_NUM_LANES-1:0] alu;
	   logic [CPU_NUM_LANES-1:0] beu;
	   logic [CPU_NUM_LANES-1:0] mul; 
	   
	} buff_1_1st_fu_dest_ar_t;
	
	typedef struct packed {
	   logic [ROB_SIZE_CLOG-1:0] robid;
	   logic [DATA_LEN-1:0]  data;
	   logic v;
	   logic prfWrite;
	   
	} cdb_t;
	
	typedef struct packed {
        logic [DATA_LEN-1:0]       data;
        logic [SRC_LEN-1:0]          rd;
        logic [DATA_LEN-1:0]         pc;
        logic                         v; //valid
        logic                   rfWrite;
        logic                  memWrite;
        logic [ROB_SIZE_CLOG-1:0] robid;
	} info_ret_t;
	
	// info which is not needed by an execution unit will be synthesized away
	typedef struct packed {
	   logic [ROB_SIZE_CLOG-1:0]                       robid;
	   logic [NUM_SRCS-1:0][PRF_SIZE_CLOG-1:0]         src;
	   logic [NUM_SRCS-1:0]                            src_prf; //1: grab prf, 0: inflight instruction
	   logic [NUM_SRCS-1:0]                            src_valid;
	   logic [DATA_LEN-1:0]                            imm;
	   logic [FUNC3_SIZE-1:0]                          func3;
	   logic [ALU_CTRL_WIDTH-1:0]                      alu_ctrl;
	   logic imm_valid;
	   logic prfWrite;
	   logic v;
	}
	info_instr_2_disp_rs;
	
`endif //STRUCTS