restart

# Run circuit with no input stimulus settings
run 20ns

# Set the clock to oscillate with a period of 10 ns
add_force clk {0} {1 5} -repeat_every 10
# Run the circuit for a bit
run 10 ns

#resets
add_force rst 1
add_force instr_val_id 0000
add_force instr_id[0] -radix hex 00000000
add_force instr_id[1] -radix hex 00000000
add_force instr_id[2] -radix hex 00000000
add_force instr_id[3] -radix hex 00000000
run 10ns
add_force rst 0
run 15ns

add_force instr_val_id 1111
# addi x1, x0, 1
# add x1, x1, x1
# add x1, x1, x1
# add x1, x1, x1
add_force instr_id[0] -radix hex 00100093
add_force instr_id[1] -radix hex 001080b3
add_force instr_id[2] -radix hex 001080b3
add_force instr_id[3] -radix hex 001080b3
run 10ns

# add x1, x1, x1
# add x1, x1, x1
# add x1, x1, x1
# add x1, x1, x1
add_force instr_id[0] -radix hex 001080b3
add_force instr_id[1] -radix hex 001080b3
add_force instr_id[2] -radix hex 001080b3
add_force instr_id[3] -radix hex 001080b3
run 10ns
# mul    x1, x1, x1
# mulh   x1, x1, x1
# mulhsu x1, x1, x1
# mulhu  x1, x1, x1
add_force instr_id[0] -radix hex 021080b3
add_force instr_id[1] -radix hex 021090b3
add_force instr_id[2] -radix hex 0210a0b3
add_force instr_id[3] -radix hex 0210b0b3
run 10ns
add_force instr_val_id 0000


run 10ns
