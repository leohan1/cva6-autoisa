// SPDX-License-Identifier: Apache-2.0
`timescale 1ns / 1ps

module tb_autoisa_ci_request_queue;
  import autoisa_ci_types_pkg::*;

  localparam int unsigned DEPTH = 4;
  localparam int unsigned OCC_WIDTH = $clog2(DEPTH + 1);

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic flush;
  logic in_valid, in_ready;
  autoisa_ci_req_t in_req;
  logic out_valid, out_ready;
  autoisa_ci_req_t out_req;
  logic [OCC_WIDTH-1:0] occupancy, high_watermark;
  logic [31:0] enqueue_count, dequeue_count, full_stall_count;
  integer wrap_i;
  logic d1_in_valid, d1_in_ready, d1_out_valid, d1_out_ready;
  autoisa_ci_req_t d1_in_req, d1_out_req;
  logic d1_occupancy;

  always #5 clk = ~clk;

  autoisa_ci_request_queue #(
      .DEPTH(DEPTH)
  ) dut (
      .clk_i(clk),
      .rst_ni(rst_n),
      .flush_i(flush),
      .in_valid_i(in_valid),
      .in_ready_o(in_ready),
      .in_req_i(in_req),
      .identity_query_valid_i(1'b0),
      .identity_query_tag_i('0),
      .identity_query_epoch_i('0),
      .identity_query_match_o(),
      .out_valid_o(out_valid),
      .out_ready_i(out_ready),
      .out_req_o(out_req),
      .occupancy_o(occupancy),
      .high_watermark_o(high_watermark),
      .enqueue_count_o(enqueue_count),
      .dequeue_count_o(dequeue_count),
      .full_stall_count_o(full_stall_count)
  );

  // Elaboration sentinels for every required queue depth.
  autoisa_ci_request_queue #(
      .DEPTH(1)
  ) i_depth_1 (
      .clk_i(clk),
      .rst_ni(rst_n),
      .flush_i(flush),
      .in_valid_i(d1_in_valid),
      .in_ready_o(d1_in_ready),
      .in_req_i(d1_in_req),
      .identity_query_valid_i(1'b0),
      .identity_query_tag_i('0),
      .identity_query_epoch_i('0),
      .identity_query_match_o(),
      .out_valid_o(d1_out_valid),
      .out_ready_i(d1_out_ready),
      .out_req_o(d1_out_req),
      .occupancy_o(d1_occupancy),
      .high_watermark_o(),
      .enqueue_count_o(),
      .dequeue_count_o(),
      .full_stall_count_o()
  );
  autoisa_ci_request_queue #(
      .DEPTH(2)
  ) i_depth_2 (
      .clk_i(clk),
      .rst_ni(rst_n),
      .flush_i(flush),
      .in_valid_i(1'b0),
      .in_ready_o(),
      .in_req_i('0),
      .identity_query_valid_i(1'b0),
      .identity_query_tag_i('0),
      .identity_query_epoch_i('0),
      .identity_query_match_o(),
      .out_valid_o(),
      .out_ready_i(1'b0),
      .out_req_o(),
      .occupancy_o(),
      .high_watermark_o(),
      .enqueue_count_o(),
      .dequeue_count_o(),
      .full_stall_count_o()
  );
  autoisa_ci_request_queue #(
      .DEPTH(8)
  ) i_depth_8 (
      .clk_i(clk),
      .rst_ni(rst_n),
      .flush_i(flush),
      .in_valid_i(1'b0),
      .in_ready_o(),
      .in_req_i('0),
      .identity_query_valid_i(1'b0),
      .identity_query_tag_i('0),
      .identity_query_epoch_i('0),
      .identity_query_match_o(),
      .out_valid_o(),
      .out_ready_i(1'b0),
      .out_req_o(),
      .occupancy_o(),
      .high_watermark_o(),
      .enqueue_count_o(),
      .dequeue_count_o(),
      .full_stall_count_o()
  );

  task automatic push(input logic [3:0] tag);
    begin
      @(negedge clk);
      in_req = '0;
      in_req.tag = tag;
      in_req.ci_id = {4'd0, tag};
      in_valid = 1'b1;
      #1;
      if (!in_ready) $fatal(1, "push tag %0d was unexpectedly blocked", tag);
      @(posedge clk);
      @(negedge clk);
      in_valid = 1'b0;
    end
  endtask

  task automatic pop_expect(input logic [3:0] tag);
    begin
      @(negedge clk);
      out_ready = 1'b1;
      #1;
      if (!out_valid || (out_req.tag != tag))
        $fatal(1, "pop mismatch: expected %0d got %0d", tag, out_req.tag);
      @(posedge clk);
      @(negedge clk);
      out_ready = 1'b0;
    end
  endtask

  initial begin
    flush = 1'b0;
    in_valid = 1'b0;
    in_req = '0;
    out_ready = 1'b0;
    d1_in_valid = 1'b0;
    d1_in_req = '0;
    d1_out_ready = 1'b0;

    repeat (3) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    // Q00: depth-1 storage performs a basic enqueue/dequeue without loss.
    d1_in_req = '0;
    d1_in_req.tag = 4'd13;
    d1_in_valid = 1'b1;
    #1;
    if (!d1_in_ready) $fatal(1, "depth-1 queue rejected basic enqueue");
    @(posedge clk);
    @(negedge clk);
    d1_in_valid = 1'b0;
    if (!d1_out_valid || !d1_occupancy || (d1_out_req.tag != 4'd13))
      $fatal(1, "depth-1 queue lost stored request");
    d1_out_ready = 1'b1;
    @(posedge clk);
    @(negedge clk);
    d1_out_ready = 1'b0;
    if (d1_out_valid || d1_occupancy) $fatal(1, "depth-1 queue did not dequeue");

    // Fill the queue and establish its high-watermark.
    push(4'd1);
    push(4'd2);
    push(4'd3);
    push(4'd4);
    if ((occupancy != 4) || (high_watermark != 4) || in_ready) $fatal(1, "full-state check failed");

    // Q01: REQ_DEPTH+2 continuous attempts reach full and backpressure both
    // excess requests.
    in_req = '0;
    in_req.tag = 4'd9;
    in_valid = 1'b1;
    @(posedge clk);
    @(negedge clk);
    in_req.tag = 4'd10;
    @(posedge clk);
    @(negedge clk);
    in_valid = 1'b0;
    if (full_stall_count != 2) $fatal(1, "full stalls were not counted");

    // Full queue replacement: pop tag 1 and push tag 5 in the same cycle.
    in_req = '0;
    in_req.tag = 4'd5;
    in_valid = 1'b1;
    out_ready = 1'b1;
    #1;
    if (!in_ready || !out_valid || (out_req.tag != 4'd1))
      $fatal(1, "simultaneous full pop/push failed");
    @(posedge clk);
    @(negedge clk);
    in_valid  = 1'b0;
    out_ready = 1'b0;
    if (occupancy != 4) $fatal(1, "occupancy changed on replacement");

    pop_expect(4'd2);
    pop_expect(4'd3);
    pop_expect(4'd4);
    pop_expect(4'd5);
    if (occupancy != 0) $fatal(1, "queue did not drain");

    // Empty queue bypass must not consume a storage slot.
    @(negedge clk);
    in_req = '0;
    in_req.tag = 4'd6;
    in_valid = 1'b1;
    out_ready = 1'b1;
    #1;
    if (!out_valid || !in_ready || (out_req.tag != 4'd6)) $fatal(1, "empty bypass failed");
    @(posedge clk);
    @(negedge clk);
    in_valid  = 1'b0;
    out_ready = 1'b0;
    if (occupancy != 0) $fatal(1, "bypass changed occupancy");

    // Q07: force the depth-4 read/write pointers to wrap more than 100 times.
    for (wrap_i = 0; wrap_i < 512; wrap_i = wrap_i + 1) begin
      push(wrap_i[3:0]);
      pop_expect(wrap_i[3:0]);
    end
    if (occupancy != 0) $fatal(1, "queue did not drain after pointer wrap test");

    // Flush clears structural state but preserves lifetime traffic counters.
    push(4'd7);
    @(negedge clk);
    flush = 1'b1;
    @(posedge clk);
    @(negedge clk);
    flush = 1'b0;
    if ((occupancy != 0) || (high_watermark != 0) || out_valid) $fatal(1, "flush failed");
    if ((enqueue_count != 519) || (dequeue_count != 518) || (full_stall_count != 2))
      $fatal(
          1,
          "counter mismatch enq=%0d deq=%0d stall=%0d",
          enqueue_count,
          dequeue_count,
          full_stall_count
      );

    $display("PASS: autoisa_ci_request_queue");
    $finish;
  end

  initial begin
    #30000;
    $fatal(1, "timeout");
  end
endmodule
