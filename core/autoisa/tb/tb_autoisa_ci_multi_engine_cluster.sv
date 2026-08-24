// SPDX-License-Identifier: Apache-2.0
`timescale 1ns / 1ps

module tb_autoisa_ci_multi_engine_cluster;
  import autoisa_ci_types_pkg::*;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic req_valid, req_ready, req_supported;
  logic flush;
  logic kill_valid, kill_pending_hit, kill_running_hit;
  logic [3:0] kill_tag;
  logic [1:0] kill_epoch;
  autoisa_ci_req_t req;
  logic rsp_valid, rsp_ready;
  autoisa_ci_rsp_t rsp;
  logic [2:0] pending_occupancy, pending_high_watermark;
  logic engine0_busy, engine1_busy;
  logic engine0_running, engine1_running;
  logic [31:0] accepted_count, engine0_dispatch_count;
  logic [31:0] engine1_dispatch_count, completion_count;
  logic [31:0] unsupported_stall_count;
  logic [31:0] pending_kill_drop_count, pending_flush_drop_count;
  integer parallel_busy_cycles;

  always #5 clk = ~clk;

  autoisa_ci_multi_engine_cluster #(
      .PENDING_DEPTH(4)
  ) dut (
      .clk_i(clk),
      .rst_ni(rst_n),
      .flush_i(flush),
      .req_valid_i(req_valid),
      .req_ready_o(req_ready),
      .req_i(req),
      .req_supported_o(req_supported),
      .kill_valid_i(kill_valid),
      .kill_tag_i(kill_tag),
      .kill_epoch_i(kill_epoch),
      .kill_pending_hit_o(kill_pending_hit),
      .kill_running_hit_o(kill_running_hit),
      .rsp_valid_o(rsp_valid),
      .rsp_ready_i(rsp_ready),
      .rsp_o(rsp),
      .pending_occupancy_o(pending_occupancy),
      .pending_high_watermark_o(pending_high_watermark),
      .engine0_busy_o(engine0_busy),
      .engine1_busy_o(engine1_busy),
      .engine0_running_o(engine0_running),
      .engine1_running_o(engine1_running),
      .accepted_count_o(accepted_count),
      .engine0_dispatch_count_o(engine0_dispatch_count),
      .engine1_dispatch_count_o(engine1_dispatch_count),
      .completion_count_o(completion_count),
      .unsupported_stall_count_o(unsupported_stall_count),
      .pending_kill_drop_count_o(pending_kill_drop_count),
      .pending_flush_drop_count_o(pending_flush_drop_count)
  );

  always @(posedge clk)
    if (rst_n && engine0_busy && engine1_busy)
      parallel_busy_cycles = parallel_busy_cycles + 1;

  task automatic submit(input logic [3:0] tag, input logic [7:0] ci_id, input logic [31:0] operand0,
                        input logic [31:0] operand1);
    begin
      @(negedge clk);
      req = '0;
      req.tag = tag;
      req.epoch = 2'd0;
      req.ci_id = ci_id;
      req.operand_valid = 6'b00_0011;
      req.operands[0] = operand0;
      req.operands[1] = operand1;
      req_valid = 1'b1;
      while (!req_ready) @(negedge clk);
      if (!req_supported) $fatal(1, "supported D%0d rejected", ci_id);
      @(posedge clk);
      @(negedge clk);
      req_valid = 1'b0;
    end
  endtask

  task automatic consume_expect(input logic [3:0] tag, input logic [31:0] value);
    begin
      while (!rsp_valid) @(negedge clk);
      if ((rsp.tag != tag) || (rsp.epoch != 0) ||
          (rsp.status != AUTOISA_STATUS_OK) ||
          (rsp.result_valid != 2'b01) || (rsp.results[0] != value))
        $fatal(
            1,
            "response mismatch tag=%0d got_tag=%0d got=%h expected=%h",
            tag,
            rsp.tag,
            rsp.results[0],
            value
        );
      rsp_ready = 1'b1;
      @(posedge clk);
      @(negedge clk);
      rsp_ready = 1'b0;
    end
  endtask

  initial begin
    req_valid = 1'b0;
    flush = 1'b0;
    kill_valid = 1'b0;
    kill_tag = '0;
    kill_epoch = '0;
    req = '0;
    rsp_ready = 1'b0;
    parallel_busy_cycles = 0;

    repeat (4) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    // D9 occupies engine 1. The older second D9 must wait, while the younger
    // D0 bypasses it and starts on idle engine 0.
    submit(4'd1, 8'd9, 32'hffff_0000, 32'h0f0f_0f0f);
    submit(4'd2, 8'd9, 32'haaaa_5555, 32'h1234_5678);
    submit(4'd3, 8'd0, 32'd7, 32'd35);

    // D0 completes first. Hold merged output stalled for three cycles and
    // rely on the RTL stability assertion to check its complete payload.
    while (!rsp_valid) @(negedge clk);
    if (rsp.tag != 4'd3) $fatal(1, "oldest-ready bypass failed, first tag=%0d", rsp.tag);
    repeat (3) begin
      if (!rsp_valid || (rsp.tag != 4'd3) || (rsp.results[0] != 32'd42))
        $fatal(1, "stalled engine-0 response changed");
      @(negedge clk);
    end
    consume_expect(4'd3, 32'd42);
    consume_expect(4'd1, 32'hf0f0_0f0f);
    consume_expect(4'd2, 32'hb89e_032d);

    // Cross-engine arbiter lock: engine 1 finishes D8 first and is stalled;
    // engine 0 completes D4 during that stall, but must not replace tag 6.
    submit(4'd5, 8'd4, 32'd2, 32'd3);
    submit(4'd6, 8'd8, 32'd8, 32'd9);
    while (!rsp_valid) @(negedge clk);
    if ((rsp.tag != 4'd6) || (rsp.results[0] != 32'd17))
      $fatal(1, "engine-1 response was not first in cross-stall case");
    repeat (6) begin
      if (!rsp_valid || (rsp.tag != 4'd6) || (rsp.results[0] != 32'd17))
        $fatal(1, "response arbiter changed grant while stalled");
      @(negedge clk);
    end
    consume_expect(4'd6, 32'd17);
    while (!rsp_valid) @(negedge clk);
    if ((rsp.tag != 4'd5) || (rsp.result_valid != 2'b11) ||
        (rsp.results[0] != 0) || (rsp.results[1] != 0))
      $fatal(1, "delayed engine-0 D4 response mismatch");
    rsp_ready = 1'b1;
    @(posedge clk);
    @(negedge clk);
    rsp_ready = 1'b0;

    if (parallel_busy_cycles == 0)
      $fatal(1, "the two physical engines were never busy concurrently");
    if ((accepted_count != 5) || (engine0_dispatch_count != 2) ||
        (engine1_dispatch_count != 3) || (completion_count != 5))
      $fatal(
          1,
          "counter mismatch accepted=%0d e0=%0d e1=%0d completed=%0d",
          accepted_count,
          engine0_dispatch_count,
          engine1_dispatch_count,
          completion_count
      );

    // Unsupported CI IDs are explicitly reported and never accepted.
    @(negedge clk);
    req = '0;
    req.tag = 4'd4;
    req.ci_id = 8'd12;
    req_valid = 1'b1;
    #1;
    if (req_supported || req_ready) $fatal(1, "unsupported CI ID was accepted");
    @(posedge clk);
    @(negedge clk);
    req_valid = 1'b0;

    if ((unsupported_stall_count != 1) || (pending_occupancy != 0))
      $fatal(1, "unsupported/pending accounting mismatch");

    $display(
        "DATA: accepted=%0d engine0_dispatch=%0d engine1_dispatch=%0d completed=%0d parallel_busy_cycles=%0d pending_hwm=%0d unsupported_stall=%0d order=3,1,2",
        accepted_count, engine0_dispatch_count, engine1_dispatch_count, completion_count,
        parallel_busy_cycles, pending_high_watermark, unsupported_stall_count);
    $display("PASS: autoisa_ci_multi_engine_cluster");
    $finish;
  end
endmodule
