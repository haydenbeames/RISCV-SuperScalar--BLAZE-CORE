# RISC-V SuperScalar (BLAZE CORE)

### parameterize CPU according to needs (power, performance, area, # execution units etc.) simply by tweaking rtl_constants.sv !!
### capable of handling all dependencies between any # of issue widths!


**WIP: 1st Version Anticipated Completion/Functionality by 2/31/2024 *

![alt text](https://github.com/haydenbeames/RISCV-SuperScalar--BLAZE-CORE/blob/main/architecture_diagrams/Architecture-high-level_v1.png)


Current items under progress: (priority 1 > 2 > 3 > 4)
- 1: L/S units
- 1: common data bus - DONE
- 1: Fowarding Hardware
- 2: area and latency efficient adder tree for integer multiplication - DONE
- 2: Tournament Branch Predictor, (created perceptron predictor -> not efficient enough, 3 way tournament hybrid??)
- 3: Division unit - DONE
- 3: RRAT for branch mispredictions - DONE
- 4: Fetch Instruction Queue (might not implement in V1)
- 4: Implementation hardware -> clock trees, MMCM, Memory Setup, AXI, etc.
 
2nd Version:
- Add Support for Matrix Multiply Accumulate (MAC) for AI acceleration
- - Will be concurrently researching TPU architecture since I may eventually want this CPU be a master for TPU (tensor processing unit) submodules
- Adding FRAT checkpoints
- faster and more area efficient macro logic
- improved division algorithm
- reduce partial products on multiplication

3rd Version:
- Add Floating point unit
- floating point MUL & DIV is speculative to be completed in this version at this point

4th Version:
- Add a LRU cache (Least Recently Used) or other form of caching to improve locality (currently just R/W directly to memory)

5th Version:
- Extensive low power work i.e. clock gating, data gating, temporarily shutting down units

6th Version:
- may add a vector graphics unit potentially as a slave unit to the core

**SIDE NOTE:
-  Currently Github is not up to date, using windows Vivado 2021.1 IDE so not connected to github
-  Usually I will update github every 2 weeks to 1 month
## Pipe stages

IF*| ID | AR | RS | FWD | EX* | CMT | RET* 

Instruction Fetch* | Instruction Decode/Rename | Allocate/Rename | Reservation Station | Forward | Execution* | Commit | Retire*

*: stage may take multiple cycles

## ID STAGE (also doing renaming)

- Note: Decode and Renaming included in frat.sv

  Since source operands RS1 and RS2 are in fixed locations, the RAT can be read before the instruction is decoded!


- rd will first update the FRAT
- false dependencies between renamed instructions heading to RS will be corrected
- false dependencies due to retiring instructions updating the RAT after read from renaming will also be corrected
- instruction will be assigned to an open Reservation Station Entry



  At the moment, support for the following instructions:
-   Arithmetic Instructions: add, sub, slt
-   Arithmetic Immediate: addi, slti
-   Logical: and, or, xor
-   Logical Immediate: andi, ori, xori
-   Immediate Instruction: LUI
-   Branch Instructions: 	beq BNE, BLT, BGE
-   Shift instructions: SLLI, SRLI, SRAI, SLL, SRL, SRA
-   Jump Instructions: JAL, JALR,
-   Memory: lw, sw
-   Multiplication: MUL, MULH, MULHSU, MULHU, 
  
### Instructions to be added in future:
-   DIV, DIVU

- See https://riscv.org/wp-content/uploads/2017/05/riscv-spec-v2.2.pdf pg 104 (pg 116 in pdf view)  for ISA

## RS (Reservation Station) STAGE 
- Centralized Reservation Station to reduce stalls
- have not yet parameterized completely # entries to issue into RS
  - can currently do 1-4 instructions per cycle (although very quick fix to expand this)
## FWD (Forward) STAGE:
    1 Cycle Lane:      AR | RS | FWD | EX1 | CMT
    Long Latency Lane: AR | RS | FWD | EX1 | EX2 | CMT
    
    FWD MUX: select data out of EX1, EX2, or CMT 

# MISSPECULATING BRANCHES

## 2 RAT System

CPU uses 2 Register Alias Tables (RAT): 1 Fetch RAT (FRAT) and 1 Retire RAT (RRAT)



# FRAT

priority renaming to instruction srcs rs1 and rs2 is given to retiring instructions. This is to prevent false data dependencies on retired ROB entries. In order for this to work, the retirement data must be forwarded to the source operands

# RRAT - Implemented as Regfile

the RRAT is updated whenever a committed instruction is retired from the Re-Order Buffer (ROB). 

In the case of the 4th mispredicted branch, the following occurs:
- Branch Predictor is updated
- all instructions after misspeculated branch will be marked as stale and be removed from pipeline
- misspeculated entries in ROB marked as invalid
- Pipeline will wait until all valid entries in ROB have retired and updated RRAT
- Finally, RRAT gets copied to FRAT and CPU resumes execution!

# Checkpoint

A checkpointing system will eventually be implemented to complement the 2 RAT system to reduce the IPC impact of misspeculated branches and reduce # of data busses from retirement

# Retirement
- Completely parameterizable Re-Order Buffer (ROB) width.
- Instruction result data stored inside ROB
- Also can retire any # of instructions (obviously there is a trade off between more complex hardware/timing and more instructions retired)
- User would want to retire at least 1 more instruction than ISSUE_WDITH_MAX (*I personally recommend at least 2 more* -> UPDATE RETIRE_WIDTH_MAX to do this)



# Execution Units

## Radix-4 SRT Division
- 18 cycle output

## Radix-4 Multiplier
- 2 cycle output
- uses 4:2 compressors for fast adder tree addition
- low level instantiation for fast addition

# BEU (Branch Execution Unit)

# MAC (Multiply Accumulate)
- Implementing soon with other matrix operations to allow for Machine Learning Acceleration
- May potentialy incorporate many of these modules for a vector unit with a singular MAC including in Floating Point unit
