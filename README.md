# RISC-V-OOO-SuperScalar-
## Pipe stages

IF*| ID | ISSUE | REGFILE | EX1* | COMMIT | RETIRE 

## ID/RENAME STAGE

  Since source operands RS1 and RS2 are in fixed locations, the RAT can be read before the instruction is decoded!



# MISSPECULATING BRANCHES

## 2 RAT System

CPU uses 2 Register Alias Tables (RAT): 1 Fetch RAT (FRAT) and 1 Retire RAT (RRAT)

Additionally, when a branch is issued, a copy of FRAT data will be assigned to a branch for a maximum of 3 copies. If any of these 3 branches are mispredicted, FRAT can instantly update to these copies. However, if a 4th branch is mispredicted, use of the RRAT will become necessary

### RRAT

the RRAT is updated whenever a committed uop is retired from the Re-Order Buffer (ROB). 

In the case of the 4th mispredicted branch, the following occurs:
- Branch Predictor is updated
- all uops after misspeculated branch will be marked as stale and be removed from pipeline
