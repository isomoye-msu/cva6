CVA6_PATH="/tools/C/eegr-463/al.roberts/2025C3Sim/cva6"
vcs -full64 -sverilog +lint=TFIPC-L \
  +incdir+/tools/C/eegr-463/al.roberts/2025C3Sim/cva6/core/include \
  "${CVA6_PATH}/core/tb/ex_stage_packages.sv" \
  "${CVA6_PATH}/core/tb/ex_stage_stubs.sv" \
  "${CVA6_PATH}/core/ex_stage.sv" \
  "${CVA6_PATH}/core/tb/ex_stage_tb.sv" \
  -o ex_stage_sim \
  -l compile.log

./ex_stage_sim -l sim.log
