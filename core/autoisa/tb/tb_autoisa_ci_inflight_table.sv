// SPDX-License-Identifier: Apache-2.0
`timescale 1ns/1ps

module tb_autoisa_ci_inflight_table;
  import autoisa_ci_types_pkg::*;

  localparam int unsigned DEPTH = 4;
  localparam int unsigned OCC_WIDTH = $clog2(DEPTH + 1);

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic flush;
  logic alloc_valid, alloc_ready, alloc_duplicate;
  autoisa_ci_req_t alloc_req;
  logic dispatch_valid, dispatch_ready;
  autoisa_ci_req_t dispatch_req;
  logic complete_valid, complete_ready;
  autoisa_ci_rsp_t complete_rsp;
  logic commit_valid;
  logic [AUTOISA_TAG_WIDTH-1:0] commit_tag;
  logic [AUTOISA_EPOCH_WIDTH-1:0] commit_epoch;
  logic kill_valid, kill_hit;
  logic [AUTOISA_TAG_WIDTH-1:0] kill_tag;
  logic [AUTOISA_EPOCH_WIDTH-1:0] kill_epoch;
  logic retire_valid, retire_ready;
  autoisa_ci_rsp_t retire_rsp;
  logic [OCC_WIDTH-1:0] occupancy, high_watermark;
  logic [31:0] allocated_count, retired_count, killed_count;
  logic [31:0] orphan_completion_count;

  always #5 clk = ~clk;

  autoisa_ci_inflight_table #(.DEPTH(DEPTH)) dut (
      .clk_i(clk), .rst_ni(rst_n), .flush_i(flush),
      .alloc_valid_i(alloc_valid), .alloc_ready_o(alloc_ready),
      .alloc_req_i(alloc_req), .alloc_duplicate_o(alloc_duplicate),
      .dispatch_valid_o(dispatch_valid), .dispatch_ready_i(dispatch_ready),
      .dispatch_req_o(dispatch_req),
      .complete_valid_i(complete_valid), .complete_ready_o(complete_ready),
      .complete_rsp_i(complete_rsp),
      .commit_valid_i(commit_valid), .commit_tag_i(commit_tag),
      .commit_epoch_i(commit_epoch),
      .kill_valid_i(kill_valid), .kill_tag_i(kill_tag),
      .kill_epoch_i(kill_epoch), .kill_hit_o(kill_hit),
      .kill_dispatched_o(),
      .retire_valid_o(retire_valid), .retire_ready_i(retire_ready),
      .retire_rsp_o(retire_rsp),
      .occupancy_o(occupancy), .high_watermark_o(high_watermark),
      .allocated_count_o(allocated_count), .retired_count_o(retired_count),
      .killed_count_o(killed_count),
      .orphan_completion_count_o(orphan_completion_count)
  );

  task automatic allocate(input logic [3:0] tag, input logic [1:0] epoch);
    begin
      @(negedge clk);
      alloc_req = '0;
      alloc_req.tag = tag;
      alloc_req.epoch = epoch;
      alloc_req.ci_id = {4'd0, tag};
      alloc_valid = 1'b1;
      #1;
      if (!alloc_ready) $fatal(1, "allocation %0d/%0d blocked", tag, epoch);
      @(posedge clk);
      @(negedge clk);
      alloc_valid = 1'b0;
    end
  endtask

  task automatic dispatch_expect(input logic [3:0] tag);
    begin
      @(negedge clk);
      dispatch_ready = 1'b1;
      #1;
      if (!dispatch_valid || (dispatch_req.tag != tag))
        $fatal(1, "dispatch mismatch: expected tag %0d", tag);
      @(posedge clk);
      @(negedge clk);
      dispatch_ready = 1'b0;
    end
  endtask

  task automatic complete(input logic [3:0] tag, input logic [31:0] value);
    begin
      @(negedge clk);
      complete_rsp = '0;
      complete_rsp.tag = tag;
      complete_rsp.result_valid = 2'b01;
      complete_rsp.results[0] = value;
      complete_rsp.status = AUTOISA_STATUS_OK;
      complete_valid = 1'b1;
      #1;
      if (!complete_ready) $fatal(1, "completion unexpectedly blocked");
      @(posedge clk);
      @(negedge clk);
      complete_valid = 1'b0;
    end
  endtask

  task automatic commit(input logic [3:0] tag);
    begin
      @(negedge clk);
      commit_tag = tag;
      commit_epoch = '0;
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
      kill_epoch = '0;
      kill_valid = 1'b1;
      #1;
      if (!kill_hit) $fatal(1, "kill missed tag %0d", tag);
      @(posedge clk);
      @(negedge clk);
      kill_valid = 1'b0;
    end
  endtask

  task automatic retire_expect(input logic [3:0] tag, input logic [31:0] value);
    begin
      @(negedge clk);
      retire_ready = 1'b1;
      #1;
      if (!retire_valid || (retire_rsp.tag != tag) ||
          (retire_rsp.results[0] != value))
        $fatal(1, "retire mismatch: expected tag %0d value %h", tag, value);
      @(posedge clk);
      @(negedge clk);
      retire_ready = 1'b0;
    end
  endtask

  initial begin
    flush = 1'b0;
    alloc_valid = 1'b0;
    alloc_req = '0;
    dispatch_ready = 1'b0;
    complete_valid = 1'b0;
    complete_rsp = '0;
    commit_valid = 1'b0;
    commit_tag = '0;
    commit_epoch = '0;
    kill_valid = 1'b0;
    kill_tag = '0;
    kill_epoch = '0;
    retire_ready = 1'b0;

    repeat (3) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    // Four live transactions and full-table backpressure.
    allocate(4'd1, 2'd0);
    allocate(4'd2, 2'd0);
    allocate(4'd3, 2'd0);
    allocate(4'd4, 2'd0);
    if ((occupancy != 4) || (high_watermark != 4) || alloc_ready)
      $fatal(1, "four-entry occupancy check failed");

    // Duplicate identity is reported and never accepted.
    @(negedge clk);
    alloc_req = '0;
    alloc_req.tag = 4'd1;
    alloc_valid = 1'b1;
    #1;
    if (!alloc_duplicate || alloc_ready)
      $fatal(1, "duplicate tag/epoch was not rejected");
    @(negedge clk);
    alloc_valid = 1'b0;

    // Oldest-first dispatch; completions may arrive out of order.
    dispatch_expect(4'd1);
    dispatch_expect(4'd2);
    dispatch_expect(4'd3);
    dispatch_expect(4'd4);
    complete(4'd3, 32'h3333);
    commit(4'd3);

    // Lock tag 3 while stalled, even when older tag 1 becomes ready.
    @(negedge clk);
    if (!retire_valid || (retire_rsp.tag != 4'd3))
      $fatal(1, "tag 3 did not become retireable");
    @(posedge clk);
    complete(4'd1, 32'h1111);
    commit(4'd1);
    if (!retire_valid || (retire_rsp.tag != 4'd3) ||
        (retire_rsp.results[0] != 32'h3333))
      $fatal(1, "retire response changed while stalled");
    retire_expect(4'd3, 32'h3333);
    retire_expect(4'd1, 32'h1111);

    complete(4'd4, 32'h4444);
    commit(4'd4);
    complete(4'd2, 32'h2222);
    commit(4'd2);
    retire_expect(4'd4, 32'h4444);
    retire_expect(4'd2, 32'h2222);

    // Kill in queued, running and completed states.
    allocate(4'd5, 2'd0);
    kill(4'd5);

    allocate(4'd6, 2'd0);
    dispatch_expect(4'd6);
    kill(4'd6);
    complete(4'd6, 32'h6666); // late response is consumed as an orphan

    allocate(4'd7, 2'd0);
    dispatch_expect(4'd7);
    complete(4'd7, 32'h7777);
    kill(4'd7);

    if ((occupancy != 0) || (allocated_count != 7) ||
        (retired_count != 4) || (killed_count != 3) ||
        (orphan_completion_count != 1))
      $fatal(1, "terminal accounting mismatch occ=%0d alloc=%0d retire=%0d kill=%0d orphan=%0d",
             occupancy, allocated_count, retired_count, killed_count,
             orphan_completion_count);
    if ((retired_count + killed_count) != allocated_count)
      $fatal(1, "not every accepted request has exactly one terminal outcome");

    $display("PASS: autoisa_ci_inflight_table");
    $finish;
  end

  initial begin
    #10000;
    $fatal(1, "timeout");
  end
endmodule
