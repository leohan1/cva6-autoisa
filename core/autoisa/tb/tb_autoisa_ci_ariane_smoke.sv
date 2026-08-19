// SPDX-License-Identifier: Apache-2.0
// Minimal reset/clock smoke top for stock and AUTOISA_CI_CVXIF Ariane builds.
`timescale 1ns/1ps
module tb_autoisa_ci_ariane_smoke;
  function automatic config_pkg::cva6_cfg_t smoke_config();
    config_pkg::cva6_cfg_t cfg;
    cfg = build_config_pkg::build_config(cva6_config_pkg::cva6_cfg);
`ifndef AUTOISA_CI_CVXIF
`ifndef AUTOISA_STOCK_EXAMPLE
    // The stock control run checks CVA6 itself with no external coprocessor.
    // The untouched cv32a65x COPRO_EXAMPLE path is compiled separately; on
    // Vivado 2025.2 its compressed decoder triggers an xelab tool crash.
    cfg.CoproType = config_pkg::COPRO_NONE;
`endif
`endif
    return cfg;
  endfunction

  localparam config_pkg::cva6_cfg_t CVA6Cfg = smoke_config();

  logic clk_i = 1'b0;
  logic rst_ni = 1'b0;

  always #5ns clk_i = ~clk_i;

  ariane #(
    .CVA6Cfg (CVA6Cfg)
  ) dut (
    .clk_i         (clk_i),
    .rst_ni        (rst_ni),
    .boot_addr_i   ('0),
    .hart_id_i     ('0),
    .irq_i         ('0),
    .ipi_i         (1'b0),
    .time_irq_i    (1'b0),
    .debug_req_i   (1'b0),
    .rvfi_probes_o (),
    .noc_req_o     (),
    .noc_resp_i    ('0)
  );

  initial begin
    repeat (8) @(posedge clk_i);
    rst_ni = 1'b1;
    repeat (12) @(posedge clk_i);
    $display("PASS: cv32a65x Ariane reset smoke completed");
    $finish;
  end
endmodule
