// SPDX-License-Identifier: Apache-2.0
`timescale 1ns/1ps

module tb_autoisa_ci_result_queue;
  import autoisa_ci_types_pkg::*;

  localparam int unsigned DEPTH = 4;
  localparam int unsigned OCC_WIDTH = $clog2(DEPTH + 1);

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic flush;
  logic in_valid, in_ready;
  autoisa_ci_rsp_t in_rsp;
  logic out_valid, out_ready;
  autoisa_ci_rsp_t out_rsp;
  logic [OCC_WIDTH-1:0] occupancy, high_watermark;
  logic [31:0] enqueue_count, dequeue_count, full_stall_count;
  logic [31:0] flush_drop_count;

  always #5 clk = ~clk;

  autoisa_ci_result_queue #(.DEPTH(DEPTH)) dut (
      .clk_i(clk), .rst_ni(rst_n), .flush_i(flush),
      .in_valid_i(in_valid), .in_ready_o(in_ready), .in_rsp_i(in_rsp),
      .out_valid_o(out_valid), .out_ready_i(out_ready), .out_rsp_o(out_rsp),
      .occupancy_o(occupancy), .high_watermark_o(high_watermark),
      .enqueue_count_o(enqueue_count), .dequeue_count_o(dequeue_count),
      .full_stall_count_o(full_stall_count),
      .flush_drop_count_o(flush_drop_count)
  );

  autoisa_ci_result_queue #(.DEPTH(1)) i_depth_1 (
      .clk_i(clk), .rst_ni(rst_n), .flush_i(flush),
      .in_valid_i(1'b0), .in_ready_o(), .in_rsp_i('0),
      .out_valid_o(), .out_ready_i(1'b0), .out_rsp_o(),
      .occupancy_o(), .high_watermark_o(), .enqueue_count_o(),
      .dequeue_count_o(), .full_stall_count_o(), .flush_drop_count_o()
  );
  autoisa_ci_result_queue #(.DEPTH(2)) i_depth_2 (
      .clk_i(clk), .rst_ni(rst_n), .flush_i(flush),
      .in_valid_i(1'b0), .in_ready_o(), .in_rsp_i('0),
      .out_valid_o(), .out_ready_i(1'b0), .out_rsp_o(),
      .occupancy_o(), .high_watermark_o(), .enqueue_count_o(),
      .dequeue_count_o(), .full_stall_count_o(), .flush_drop_count_o()
  );
  autoisa_ci_result_queue #(.DEPTH(8)) i_depth_8 (
      .clk_i(clk), .rst_ni(rst_n), .flush_i(flush),
      .in_valid_i(1'b0), .in_ready_o(), .in_rsp_i('0),
      .out_valid_o(), .out_ready_i(1'b0), .out_rsp_o(),
      .occupancy_o(), .high_watermark_o(), .enqueue_count_o(),
      .dequeue_count_o(), .full_stall_count_o(), .flush_drop_count_o()
  );

  task automatic push(
      input logic [3:0] tag,
      input logic [1:0] mask,
      input logic [31:0] value0,
      input logic [31:0] value1
  );
    begin
      @(negedge clk);
      in_rsp = '0;
      in_rsp.tag = tag;
      in_rsp.result_valid = mask;
      in_rsp.results[0] = value0;
      in_rsp.results[1] = value1;
      in_rsp.status = AUTOISA_STATUS_OK;
      in_valid = 1'b1;
      #1;
      if (!in_ready) $fatal(1, "push tag %0d blocked", tag);
      @(posedge clk);
      @(negedge clk);
      in_valid = 1'b0;
    end
  endtask

  task automatic pop_expect(
      input logic [3:0] tag,
      input logic [1:0] mask,
      input logic [31:0] value0,
      input logic [31:0] value1
  );
    begin
      @(negedge clk);
      out_ready = 1'b1;
      #1;
      if (!out_valid || (out_rsp.tag != tag) ||
          (out_rsp.result_valid != mask) ||
          (out_rsp.results[0] != value0) ||
          (out_rsp.results[1] != value1))
        $fatal(1, "pop mismatch for tag %0d", tag);
      @(posedge clk);
      @(negedge clk);
      out_ready = 1'b0;
    end
  endtask

  initial begin
    flush = 1'b0;
    in_valid = 1'b0;
    in_rsp = '0;
    out_ready = 1'b0;

    repeat (3) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    push(4'd1, 2'b01, 32'h11, 32'h0);
    push(4'd2, 2'b11, 32'h22, 32'h2a);
    push(4'd3, 2'b01, 32'h33, 32'h0);
    push(4'd4, 2'b01, 32'h44, 32'h0);
    if ((occupancy != 4) || (high_watermark != 4) || in_ready)
      $fatal(1, "result queue full-state check failed");

    // Count a producer stalled against full storage.
    in_rsp = '0;
    in_rsp.tag = 4'd9;
    in_valid = 1'b1;
    @(posedge clk);
    @(negedge clk);
    in_valid = 1'b0;
    if (full_stall_count != 1) $fatal(1, "result full stall not counted");

    // Full pop/push replacement preserves occupancy and complete pair data.
    in_rsp = '0;
    in_rsp.tag = 4'd5;
    in_rsp.result_valid = 2'b11;
    in_rsp.results[0] = 32'h55;
    in_rsp.results[1] = 32'h5a;
    in_valid = 1'b1;
    out_ready = 1'b1;
    #1;
    if (!in_ready || !out_valid || (out_rsp.tag != 4'd1))
      $fatal(1, "result full replacement failed");
    @(posedge clk);
    @(negedge clk);
    in_valid = 1'b0;
    out_ready = 1'b0;

    pop_expect(4'd2, 2'b11, 32'h22, 32'h2a);
    pop_expect(4'd3, 2'b01, 32'h33, 32'h0);
    pop_expect(4'd4, 2'b01, 32'h44, 32'h0);
    pop_expect(4'd5, 2'b11, 32'h55, 32'h5a);

    // Empty fall-through bypass consumes no storage entry.
    @(negedge clk);
    in_rsp = '0;
    in_rsp.tag = 4'd6;
    in_rsp.result_valid = 2'b01;
    in_rsp.results[0] = 32'h66;
    in_valid = 1'b1;
    out_ready = 1'b1;
    #1;
    if (!out_valid || !in_ready || (out_rsp.tag != 4'd6))
      $fatal(1, "result empty bypass failed");
    @(posedge clk);
    @(negedge clk);
    in_valid = 1'b0;
    out_ready = 1'b0;
    if (occupancy != 0) $fatal(1, "result bypass changed occupancy");

    // Flush drops complete entries and reports how many were discarded.
    push(4'd7, 2'b01, 32'h77, 32'h0);
    push(4'd8, 2'b11, 32'h88, 32'h8a);
    @(negedge clk);
    flush = 1'b1;
    @(posedge clk);
    @(negedge clk);
    flush = 1'b0;
    if ((occupancy != 0) || (high_watermark != 0) || out_valid ||
        (flush_drop_count != 2))
      $fatal(1, "result flush failed");

    $display("DATA: enqueued=%0d dequeued=%0d full_stall=%0d flush_drop=%0d",
             enqueue_count, dequeue_count, full_stall_count, flush_drop_count);
    $display("PASS: autoisa_ci_result_queue");
    $finish;
  end

  initial begin
    #5000;
    $fatal(1, "timeout");
  end
endmodule
