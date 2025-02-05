CVA6_PATH="/tools/C/eegr-463/al.roberts/2025C3Sim/cva6"
# 1) Compile the design and testbench
vcs -full64 -sverilog \
    ${CVA6_PATH}/core/tb/ex_stage_packages.sv \
    ${CVA6_PATH}/core/tb/ex_stage_stubs.sv \
    ${CVA6_PATH}/core/ex_stage.sv \
    ${CVA6_PATH}/core/tb/ex_stage_tb.sv \
    -o ex_stage_sim

# 2) Run the generated simulation executable
./ex_stage_sim
