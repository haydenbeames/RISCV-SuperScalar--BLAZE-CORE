# RISC-V SuperScalar

### parameterize CPU needs (power, performance, area, etc.) using rtl_constants.sv


**WIP: 1st Version Anticipated Completion/Functionality by 6/26**

2nd Version:
- Adding 2 RAT system
- Adding RAT checkpoints
- updated/faster macro logic
- improved division algorithm
- reduce partial products on multiplication

3rd Version:
- Add Floating point unit
- floating point MUL & DIV is speculative to be completed in this version at this point

4th Version:
- Add a LRU cache (Least Recently Used) or other form of caching to improve locality (currently just R/W directly to memory)

5th Version:
- potential to add a vector graphics unit

**SIDE NOTE:
-  Currently Github is not up to date, using windows Vivado 2021.1 IDE so not connected to github
-  Usually I will update github every 2 weeks to 1 month
## Pipe stages

IF*| ID | AR | RS | EX* | CMT | RET 

Instruction Fetch | Instruction Decode/Rename | Allocate/Rename | Issue | Reservation Station | Execution | Commit | Retire

*: stage may take multiple cycles

## ID STAGE (also doing renaming)

  Since source operands RS1 and RS2 are in fixed locations, the RAT can be read before the instruction is decoded!
  
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
  
### Instructions to be added in future:
-   MUL, MULH, MULHSU, MULHU, 
-   DIV, DIVU

## AR STAGE (Allocate/Rename)

-rd will first update the FRAT
-false dependencies will be corrected
-instruction will be assigned to an open Reservation Station Entry

## RS (Reservation Station) STAGE 
Centralized Reservation Station to reduce stalls

# MISSPECULATING BRANCHES

## 2 RAT System

CPU uses 2 Register Alias Tables (RAT): 1 Fetch RAT (FRAT) and 1 Retire RAT (RRAT)

Additionally, when a branch is issued, a copy of FRAT data will be assigned to a branch, recommended 3 copies maximum. If any of these 3 branches are mispredicted, FRAT can instantly update to these copies. However, if a 4th branch is mispredicted, use of the RRAT will become necessary

# FRAT

priority renaming to instruction srcs rs1 and rs2 is given to retiring instructions. This is to prevent false data dependencies on retired ROB entries. In order for this to work, the retirement data must be forwarded to the source operands

# RRAT

the RRAT is updated whenever a committed instruction is retired from the Re-Order Buffer (ROB). 

In the case of the 4th mispredicted branch, the following occurs:
- Branch Predictor is updated
- all uops after misspeculated branch will be marked as stale and be removed from pipeline
- misspeculated entries in ROB marked as invalid
- Pipeline will wait until all valid entries in ROB have retired and updated RRAT
- Finally, RRAT gets copied to FRAT and CPU resumes execution!

# Retirement
- Completely parameterizable Re-Order Buffer (ROB) width. 
- Also can retire any # of instructions (obviously there is a trade off between more complex hardware/timing and more instructions retired)
- User would want to retire at least 1 more instruction than ISSUE_WDITH_MAX (*I personally recommend at least 2 more* -> UPDATE RETIRE_WIDTH_MAX to do this)

