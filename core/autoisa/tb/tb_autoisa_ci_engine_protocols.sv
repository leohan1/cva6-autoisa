// SPDX-License-Identifier: Apache-2.0
`timescale 1ns/1ps

module tb_autoisa_ci_engine_protocols;
  import autoisa_ci_types_pkg::*;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic req_valid, req_ready;
  autoisa_ci_req_t req;
  logic rsp_valid, rsp_ready;
  autoisa_ci_rsp_t rsp;
  logic [31:0] cycle_count;

  always #5 clk = ~clk;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) cycle_count <= '0;
    else cycle_count <= cycle_count + 1'b1;
  end

  autoisa_ci_dummy_engine dut (
      .clk_i(clk), .rst_ni(rst_n),
      .req_valid_i(req_valid), .req_ready_o(req_ready), .req_i(req),
      .rsp_valid_o(rsp_valid), .rsp_ready_i(rsp_ready), .rsp_o(rsp)
  );

  task automatic run_and_expect(
      input logic [3:0] tag,
      input logic [7:0] ci_id,
      input logic [31:0] operand0,
      input logic [31:0] operand1,
      input logic [31:0] expected_value,
      input autoisa_ci_status_e expected_status,
      input logic [1:0] expected_mask,
      input integer expected_latency
  );
    integer accepted_cycle;
    integer observed_latency;
    begin
      @(negedge clk);
      req = '0;
      req.tag = tag;
      req.ci_id = ci_id;
      req.operand_valid = 6'b000011;
      req.operands[0] = operand0;
      req.operands[1] = operand1;
      req_valid = 1'b1;
      #1;
      if (!req_ready) $fatal(1, "engine request %0d blocked", tag);
      @(posedge clk);
      accepted_cycle = cycle_count;
      @(negedge clk);
      req_valid = 1'b0;
      while (!rsp_valid) @(negedge clk);
      observed_latency = cycle_count - accepted_cycle;
      if (observed_latency != expected_latency)
        $fatal(1, "latency mismatch ci=%0d expected=%0d got=%0d",
               ci_id, expected_latency, observed_latency);
      if ((rsp.tag != tag) || (rsp.status != expected_status) ||
          (rsp.result_valid != expected_mask) ||
          ((expected_mask != 0) && (rsp.results[0] != expected_value)))
        $fatal(1, "response mismatch ci=%0d tag=%0d", ci_id, tag);
      @(posedge clk);
      @(negedge clk);
    end
  endtask

  initial begin
    req_valid = 1'b0;
    req = '0;
    rsp_ready = 1'b1;

    repeat (3) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    // D8 latency is deterministic from operand0[2:0] + 1.
    run_and_expect(4'd1, 8'd8, 32'd0, 32'd10, 32'd10,
                   AUTOISA_STATUS_OK, 2'b01, 1);
    run_and_expect(4'd2, 8'd8, 32'd7, 32'd10, 32'd17,
                   AUTOISA_STATUS_OK, 2'b01, 8);

    // D10 produces a two-cycle sum and must hold it under output pressure.
    rsp_ready = 1'b0;
    @(negedge clk);
    req = '0;
    req.tag = 4'd3;
    req.ci_id = 8'd10;
    req.operand_valid = 6'b000011;
    req.operands[0] = 32'd12;
    req.operands[1] = 32'd30;
    req_valid = 1'b1;
    @(posedge clk);
    @(negedge clk);
    req_valid = 1'b0;
    wait (rsp_valid);
    repeat (3) begin
      @(posedge clk);
      if (!rsp_valid || (rsp.tag != 4'd3) ||
          (rsp.results[0] != 32'd42) ||
          (rsp.status != AUTOISA_STATUS_OK))
        $fatal(1, "D10 response changed under backpressure");
    end
    @(negedge clk);
    rsp_ready = 1'b1;
    @(posedge clk);
    @(negedge clk);

    // D11 is a deterministic test-only terminal engine fault.
    run_and_expect(4'd4, 8'd11, 32'd0, 32'd0, 32'd0,
                   AUTOISA_STATUS_ENGINE_FAULT, 2'b00, 1);

    $display("DATA: D8_latency_min=1 D8_latency_max=8 D10_stall_cycles=3 D11_status=%0d",
             AUTOISA_STATUS_ENGINE_FAULT);
    $display("PASS: autoisa_ci_engine_protocols");
    $finish;
  end

  initial begin
    #5000;
    $fatal(1, "timeout");
  end
endmodule
