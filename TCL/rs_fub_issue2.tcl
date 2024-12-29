restart

# Run circuit with no input stimulus settings
run 20ns

# Set the clock to oscillate with a period of 10 ns
add_force clk_free_master {0} {1 5} -repeat_every 10
# Run the circuit for a bit
run 120 ns

#resets
add_force global_rst 1
add_force instr_val_ar 00
add_force instr_id[0] -radix hex 00000000
add_force instr_id[1] -radix hex 00000000
add_force rs_binding_ar[0] 01
add_force rs_binding_ar[1] 10
run 55ns
add_force global_rst 0
run 100ns

add_force instr_val_ar 11


# addi x1, x0, 1
# add x1, x1, x1
add_force instr_id[0] -radix hex 00100093
add_force instr_id[1] -radix hex 001080b3
run 10ns
add_force instr_val_ar 00
# add x1, x1, x1
# add x1, x1, x1
add_force instr_id[0] -radix hex 001080b3
add_force instr_id[1] -radix hex 001080b3
run 10ns
 add_force instr_val_ar 11
# mul    x1, x1, x1
# mulh   x1, x1, x1
add_force instr_id[0] -radix hex 021080b3
add_force instr_id[1] -radix hex 021090b3
run 10ns
add_force instr_val_ar 00

run 10ns
