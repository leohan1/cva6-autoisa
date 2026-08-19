# Standalone synthesis check for the initial two-engine AutoISA cluster.
read_verilog -sv [list \
  core/autoisa/autoisa_ci_types_pkg.sv \
  core/autoisa/autoisa_ci_engine_descriptor.sv \
  core/autoisa/autoisa_ci_dummy_engine.sv \
  core/autoisa/autoisa_ci_multi_engine_cluster.sv]

synth_design -top autoisa_ci_multi_engine_cluster -part xc7a35tcpg236-1
report_utilization -file ci/autoisa/logs/autoisa_ci_multi_engine_utilization.rpt
report_timing_summary -file ci/autoisa/logs/autoisa_ci_multi_engine_timing.rpt
