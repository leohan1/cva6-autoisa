// SPDX-License-Identifier: Apache-2.0
`timescale 1ns/1ps

module tb_autoisa_ci_concurrent_shell;
  import autoisa_ci_types_pkg::*;

  localparam int unsigned REQUEST_DEPTH = 4;
  localparam int unsigned INFLIGHT_DEPTH = 4;
  localparam int unsigned RESULT_DEPTH = 2;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic flush;
  logic req_valid, req_ready, req_duplicate;
  autoisa_ci_req_t req;
  logic commit_valid;
  logic [AUTOISA_TAG_WIDTH-1:0] commit_tag;
  logic [AUTOISA_EPOCH_WIDTH-1:0] commit_epoch;
  logic kill_valid, kill_hit;
  logic [AUTOISA_TAG_WIDTH-1:0] kill_tag;
  logic [AUTOISA_EPOCH_WIDTH-1:0] kill_epoch;
  logic result_valid, result_ready;
  autoisa_ci_rsp_t result;
  logic [$clog2(REQUEST_DEPTH+1)-1:0] request_occupancy;
  logic [$clog2(REQUEST_DEPTH+1)-1:0] request_high_watermark;
  logic [$clog2(INFLIGHT_DEPTH+1)-1:0] inflight_occupancy;
  logic [$clog2(INFLIGHT_DEPTH+1)-1:0] inflight_high_watermark;
  logic [$clog2(RESULT_DEPTH+1)-1:0] result_occupancy;
  logic [$clog2(RESULT_DEPTH+1)-1:0] result_high_watermark;
  logic [$clog2(RESULT_DEPTH+1)-1:0] reserved_result_credits;
  logic [$clog2(RESULT_DEPTH+1)-1:0] credit_high_watermark;
  logic [31:0] accepted_count, dispatched_count, completion_count;
  logic [31:0] engine_started_count;
  logic [31:0] retired_count, killed_count, orphan_completion_count;
  logic [31:0] tombstone_drop_count;
  logic [31:0] credit_stall_count, result_full_stall_count;
  logic [31:0] result_flush_drop_count;
  logic engine_skid_occupancy, engine_skid_high_watermark;
  logic [31:0] skid_killed_drop_count, skid_flush_drop_count;
  logic [$clog2(REQUEST_DEPTH+1)-1:0] observed_request_hwm;
  logic [$clog2(INFLIGHT_DEPTH+1)-1:0] observed_inflight_hwm;
  logic [$clog2(RESULT_DEPTH+1)-1:0] observed_result_hwm;
  logic [$clog2(RESULT_DEPTH+1)-1:0] observed_credit_hwm;

  always #5 clk = ~clk;

  autoisa_ci_concurrent_shell #(
      .REQUEST_DEPTH(REQUEST_DEPTH),
      .INFLIGHT_DEPTH(INFLIGHT_DEPTH),
      .RESULT_DEPTH(RESULT_DEPTH)
  ) dut (
      .clk_i(clk), .rst_ni(rst_n), .flush_i(flush),
      .req_valid_i(req_valid), .req_ready_o(req_ready), .req_i(req),
      .req_duplicate_o(req_duplicate),
      .commit_valid_i(commit_valid), .commit_tag_i(commit_tag),
      .commit_epoch_i(commit_epoch),
      .kill_valid_i(kill_valid), .kill_tag_i(kill_tag),
      .kill_epoch_i(kill_epoch), .kill_hit_o(kill_hit),
      .result_valid_o(result_valid), .result_ready_i(result_ready),
      .result_o(result),
      .request_occupancy_o(request_occupancy),
      .request_high_watermark_o(request_high_watermark),
      .inflight_occupancy_o(inflight_occupancy),
      .inflight_high_watermark_o(inflight_high_watermark),
      .result_occupancy_o(result_occupancy),
      .result_high_watermark_o(result_high_watermark),
      .reserved_result_credits_o(reserved_result_credits),
      .credit_high_watermark_o(credit_high_watermark),
      .engine_skid_occupancy_o(engine_skid_occupancy),
      .engine_skid_high_watermark_o(engine_skid_high_watermark),
      .accepted_count_o(accepted_count),
      .dispatched_count_o(dispatched_count),
      .engine_started_count_o(engine_started_count),
      .completion_count_o(completion_count),
      .retired_count_o(retired_count), .killed_count_o(killed_count),
      .orphan_completion_count_o(orphan_completion_count),
      .tombstone_drop_count_o(tombstone_drop_count),
      .credit_stall_count_o(credit_stall_count),
      .result_full_stall_count_o(result_full_stall_count),
      .result_flush_drop_count_o(result_flush_drop_count),
      .skid_killed_drop_count_o(skid_killed_drop_count),
      .skid_flush_drop_count_o(skid_flush_drop_count)
  );

  task automatic submit(
      input logic [3:0] tag,
      input logic [7:0] ci_id,
      input logic [31:0] operand0,
      input logic [31:0] operand1
  );
    begin
      @(negedge clk);
      req = '0;
      req.tag = tag;
      req.epoch = 2'd0;
      req.ci_id = ci_id;
      req.operand_valid = 6'b000011;
      req.operands[0] = operand0;
      req.operands[1] = operand1;
      req_valid = 1'b1;
      #1;
      if (!req_ready || req_duplicate)
        $fatal(1, "request %0d was not accepted", tag);
      @(posedge clk);
      @(negedge clk);
      req_valid = 1'b0;
    end
  endtask

  task automatic commit(input logic [3:0] tag);
    begin
      @(negedge clk);
      commit_tag = tag;
      commit_epoch = 2'd0;
      commit_valid = 1'b1;
      @(posedge clk);
      @(negedge clk);
      commit_valid = 1'b0;
    end
  endtask

  task automatic kill(input logic [3:0] tag);
    begin
      @(negedge clk);
      kill_tag = tag;
      kill_epoch = 2'd0;
      kill_valid = 1'b1;
      #1;
      if (!kill_hit) $fatal(1, "kill missed tag %0d", tag);
      @(posedge clk);
      @(negedge clk);
      kill_valid = 1'b0;
    end
  endtask

  task automatic retire_expect(
      input logic [3:0] tag,
      input logic [31:0] expected
  );
    begin
      @(negedge clk);
      result_ready = 1'b1;
      #1;
      if (!result_valid || (result.tag != tag) ||
          (result.result_valid != 2'b01) ||
          (result.results[0] != expected) ||
          (result.status != AUTOISA_STATUS_OK))
        $fatal(1, "result mismatch for tag %0d", tag);
      @(posedge clk);
      @(negedge clk);
      result_ready = 1'b0;
    end
  endtask

  initial begin
    flush = 1'b0;
    req_valid = 1'b0;
    req = '0;
    commit_valid = 1'b0;
    commit_tag = '0;
    commit_epoch = '0;
    kill_valid = 1'b0;
    kill_tag = '0;
    kill_epoch = '0;
    result_ready = 1'b0;

    repeat (3) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    // D9 occupies the engine for 16 cycles while three younger requests fill
    // the queue and all four identities remain allocated in the table.
    submit(4'd1, 8'd9, 32'h55aa_55aa, 32'h0f0f_0f0f);
    submit(4'd2, 8'd0, 32'd2, 32'd20);
    submit(4'd3, 8'd0, 32'd3, 32'd30);
    submit(4'd4, 8'd0, 32'd4, 32'd40);

    if ((inflight_occupancy != 4) || (inflight_high_watermark != 4))
      $fatal(1, "did not reach four simultaneous inflight requests");
    if (request_high_watermark <= 1)
      $fatal(1, "request queue occupancy never exceeded one");
    observed_request_hwm = request_high_watermark;
    observed_inflight_hwm = inflight_high_watermark;

    // A duplicate still in the queue must be rejected at shell ingress.
    @(negedge clk);
    req = '0;
    req.tag = 4'd3;
    req.epoch = 2'd0;
    req.ci_id = 8'd0;
    req_valid = 1'b1;
    #1;
    if (!req_duplicate || req_ready)
      $fatal(1, "queued duplicate identity was not rejected");
    @(posedge clk);
    @(negedge clk);
    req_valid = 1'b0;

    commit(4'd3);
    commit(4'd4);

    // Tag 2 is held in the skid; tag 1 is executing. Both terminate as killed,
    // but only tag 1 is allowed to reach the engine.
    kill(4'd2);
    kill(4'd1);

    // The late D9 result is drained as an orphan. Tags 3 and 4 then execute.
    wait (orphan_completion_count == 1);
    wait (result_valid);
    if ((result.tag != 4'd3) || (result.results[0] != 32'd33))
      $fatal(1, "unexpected first visible result");

    // Hold the result channel stalled while tag 4 completes behind tag 3.
    repeat (3) begin
      @(posedge clk);
      if (!result_valid || (result.tag != 4'd3) ||
          (result.results[0] != 32'd33))
        $fatal(1, "result changed under backpressure");
    end

    // With RESULT_DEPTH=2 and Host backpressure, tags 3 and 4 fill the result
    // queue. Two new committed requests must remain queued without credits.
    wait (result_occupancy == 2);
    submit(4'd5, 8'd0, 32'd5, 32'd50);
    submit(4'd6, 8'd0, 32'd6, 32'd60);
    commit(4'd5);
    commit(4'd6);
    repeat (3) begin
      @(posedge clk);
      if ((dispatched_count != 4) || (engine_started_count != 3) ||
          (request_occupancy != 2) ||
          (reserved_result_credits != 0))
        $fatal(1, "dispatch was not stopped by exhausted result credits");
    end
    if (credit_stall_count == 0)
      $fatal(1, "credit stall was not observed");

    // Each Host dequeue frees exactly one slot/credit for one younger request.
    retire_expect(4'd3, 32'd33);
    wait ((completion_count == 4) && (result_occupancy == 2));
    retire_expect(4'd4, 32'd44);
    wait ((completion_count == 5) && (result_occupancy == 2));
    retire_expect(4'd5, 32'd55);
    retire_expect(4'd6, 32'd66);

    repeat (2) @(posedge clk);
    @(negedge clk);
    if ((accepted_count != 6) || (dispatched_count != 6) ||
        (engine_started_count != 5) ||
        (completion_count != 5) || (retired_count != 4) ||
        (killed_count != 2) || (orphan_completion_count != 1) ||
        (tombstone_drop_count != 0) || (skid_killed_drop_count != 1) ||
        !engine_skid_high_watermark || engine_skid_occupancy ||
        (request_occupancy != 0) ||
        (inflight_occupancy != 0) || (result_occupancy != 0) ||
        (reserved_result_credits != 0) || (result_high_watermark != 2) ||
        (credit_high_watermark == 0) || (result_full_stall_count != 0))
      $fatal(1, "shell accounting mismatch acc=%0d disp=%0d comp=%0d ret=%0d kill=%0d orphan=%0d tomb=%0d rq=%0d inf=%0d",
             accepted_count, dispatched_count, completion_count,
             retired_count, killed_count, orphan_completion_count,
             tombstone_drop_count, request_occupancy, inflight_occupancy);
    if ((retired_count + killed_count) != accepted_count)
      $fatal(1, "accepted requests did not have one terminal outcome");
    observed_result_hwm = result_high_watermark;
    observed_credit_hwm = credit_high_watermark;

    // Flush one executing and one queued request. Both live table entries are
    // terminally killed; the executing engine response is drained afterward.
    submit(4'd8, 8'd9, 32'h1234_5678, 32'hffff_0000);
    submit(4'd9, 8'd0, 32'd9, 32'd90);
    if (inflight_occupancy != 2)
      $fatal(1, "flush setup did not create two live requests");
    @(negedge clk);
    flush = 1'b1;
    @(posedge clk);
    @(negedge clk);
    flush = 1'b0;
    if ((request_occupancy != 0) || (inflight_occupancy != 0) ||
        (request_high_watermark != 0) || (inflight_high_watermark != 0))
      $fatal(1, "flush did not clear structural state");
    wait (orphan_completion_count == 2);
    if ((accepted_count != 8) || (dispatched_count != 8) ||
        (engine_started_count != 6) ||
        (completion_count != 6) || (retired_count != 4) ||
        (killed_count != 4) || (orphan_completion_count != 2) ||
        (skid_killed_drop_count != 1) || (skid_flush_drop_count != 1) ||
        (reserved_result_credits != 0) ||
        (request_occupancy != 0) || (inflight_occupancy != 0))
      $fatal(1, "post-flush accounting mismatch");
    if ((retired_count + killed_count) != accepted_count)
      $fatal(1, "post-flush terminal accounting failed");

    $display("DATA: accepted=%0d dispatched=%0d engine_started=%0d completed=%0d retired=%0d killed=%0d orphan=%0d skid_kill=%0d skid_flush=%0d request_hwm=%0d inflight_hwm=%0d result_hwm=%0d credit_hwm=%0d credit_stall=%0d",
             accepted_count, dispatched_count, engine_started_count,
             completion_count,
             retired_count, killed_count, orphan_completion_count,
             skid_killed_drop_count, skid_flush_drop_count,
             observed_request_hwm, observed_inflight_hwm,
             observed_result_hwm, observed_credit_hwm,
             credit_stall_count);
    $display("PASS: autoisa_ci_concurrent_shell");
    $finish;
  end

  initial begin
    #10000;
    $fatal(1, "timeout");
  end
endmodule
