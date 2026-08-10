// SPDX-License-Identifier: Apache-2.0
// Minimal concurrent AutoISA CI shell: atomic ingress, queued dispatch,
// inflight tracking, one reference engine, commit/kill and tagged retirement.
`timescale 1ns/1ps
`default_nettype none

module autoisa_ci_concurrent_shell #(
    parameter int unsigned REQUEST_DEPTH  = 4,
    parameter int unsigned INFLIGHT_DEPTH = 4,
    parameter int unsigned RESULT_DEPTH   = 4,
    parameter int unsigned COUNT_WIDTH    = 32,
    parameter int unsigned REQ_OCC_WIDTH  = $clog2(REQUEST_DEPTH + 1),
    parameter int unsigned INF_OCC_WIDTH  = $clog2(INFLIGHT_DEPTH + 1),
    parameter int unsigned RES_OCC_WIDTH  = $clog2(RESULT_DEPTH + 1)
) (
    input  wire clk_i,
    input  wire rst_ni,
    input  wire flush_i,

    input  wire req_valid_i,
    output logic req_ready_o,
    input  autoisa_ci_types_pkg::autoisa_ci_req_t req_i,
    output logic req_duplicate_o,

    input  wire commit_valid_i,
    input  wire [autoisa_ci_types_pkg::AUTOISA_TAG_WIDTH-1:0] commit_tag_i,
    input  wire [autoisa_ci_types_pkg::AUTOISA_EPOCH_WIDTH-1:0] commit_epoch_i,

    input  wire kill_valid_i,
    input  wire [autoisa_ci_types_pkg::AUTOISA_TAG_WIDTH-1:0] kill_tag_i,
    input  wire [autoisa_ci_types_pkg::AUTOISA_EPOCH_WIDTH-1:0] kill_epoch_i,
    output logic kill_hit_o,

    output logic result_valid_o,
    input  wire result_ready_i,
    output autoisa_ci_types_pkg::autoisa_ci_rsp_t result_o,

    output logic [REQ_OCC_WIDTH-1:0] request_occupancy_o,
    output logic [REQ_OCC_WIDTH-1:0] request_high_watermark_o,
    output logic [INF_OCC_WIDTH-1:0] inflight_occupancy_o,
    output logic [INF_OCC_WIDTH-1:0] inflight_high_watermark_o,
    output logic [RES_OCC_WIDTH-1:0] result_occupancy_o,
    output logic [RES_OCC_WIDTH-1:0] result_high_watermark_o,
    output logic [RES_OCC_WIDTH-1:0] reserved_result_credits_o,
    output logic [RES_OCC_WIDTH-1:0] credit_high_watermark_o,
    output logic engine_skid_occupancy_o,
    output logic engine_skid_high_watermark_o,
    output logic [COUNT_WIDTH-1:0] accepted_count_o,
    output logic [COUNT_WIDTH-1:0] dispatched_count_o,
    output logic [COUNT_WIDTH-1:0] engine_started_count_o,
    output logic [COUNT_WIDTH-1:0] completion_count_o,
    output logic [COUNT_WIDTH-1:0] retired_count_o,
    output logic [COUNT_WIDTH-1:0] killed_count_o,
    output logic [COUNT_WIDTH-1:0] orphan_completion_count_o,
    output logic [COUNT_WIDTH-1:0] tombstone_drop_count_o,
    output logic [COUNT_WIDTH-1:0] credit_stall_count_o,
    output logic [COUNT_WIDTH-1:0] result_full_stall_count_o,
    output logic [COUNT_WIDTH-1:0] result_flush_drop_count_o,
    output logic [COUNT_WIDTH-1:0] skid_killed_drop_count_o,
    output logic [COUNT_WIDTH-1:0] skid_flush_drop_count_o
);
  import autoisa_ci_types_pkg::*;

  logic queue_in_valid, queue_in_ready;
  logic queue_identity_match;
  logic queue_out_valid, queue_out_ready;
  autoisa_ci_req_t queue_out_req;
  logic [COUNT_WIDTH-1:0] queue_enqueue_count;
  logic [COUNT_WIDTH-1:0] queue_dequeue_count;
  logic [COUNT_WIDTH-1:0] queue_full_stall_count;

  logic table_alloc_valid, table_alloc_ready, table_alloc_duplicate;
  logic table_dispatch_valid, table_dispatch_ready;
  autoisa_ci_req_t table_dispatch_req;
  logic table_complete_valid, table_complete_ready;
  autoisa_ci_rsp_t table_complete_rsp;
  logic table_kill_dispatched;
  logic table_retire_valid, table_retire_ready;
  autoisa_ci_rsp_t table_retire_rsp;

  logic engine_req_valid, engine_req_ready;
  autoisa_ci_req_t engine_req;
  logic engine_rsp_valid, engine_rsp_ready;
  autoisa_ci_rsp_t engine_rsp;

  logic queue_has_stored_head;
  logic dispatch_identity_match;
  logic dispatch_fire;
  logic tombstone_drop;
  logic credit_available;
  logic result_enqueue;
  logic kill_credit_release;
  logic [RES_OCC_WIDTH-1:0] reserved_credits_q, reserved_credits_d;
  logic [RES_OCC_WIDTH:0] used_result_slots;
  logic [RES_OCC_WIDTH:0] credit_calc;
  logic [COUNT_WIDTH-1:0] result_enqueue_count;
  logic [COUNT_WIDTH-1:0] result_dequeue_count;
  logic skid_in_valid, skid_in_ready;
  logic skid_kill_hit;
  logic [COUNT_WIDTH-1:0] skid_accepted_count;

  // A request is accepted atomically by both structural stores. Queue lookup
  // also covers killed entries that are waiting to drain from the FIFO.
  assign req_duplicate_o = req_valid_i &&
                           (queue_identity_match || table_alloc_duplicate);
  assign req_ready_o = queue_in_ready && table_alloc_ready &&
                       !queue_identity_match;
  assign queue_in_valid = req_valid_i && table_alloc_ready &&
                          !queue_identity_match;
  assign table_alloc_valid = req_valid_i && queue_in_ready &&
                             !queue_identity_match;

  autoisa_ci_request_queue #(
      .DEPTH(REQUEST_DEPTH),
      .COUNT_WIDTH(COUNT_WIDTH)
  ) i_request_queue (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      .flush_i(flush_i),
      .in_valid_i(queue_in_valid),
      .in_ready_o(queue_in_ready),
      .in_req_i(req_i),
      .identity_query_valid_i(req_valid_i),
      .identity_query_tag_i(req_i.tag),
      .identity_query_epoch_i(req_i.epoch),
      .identity_query_match_o(queue_identity_match),
      .out_valid_o(queue_out_valid),
      .out_ready_i(queue_out_ready),
      .out_req_o(queue_out_req),
      .occupancy_o(request_occupancy_o),
      .high_watermark_o(request_high_watermark_o),
      .enqueue_count_o(queue_enqueue_count),
      .dequeue_count_o(queue_dequeue_count),
      .full_stall_count_o(queue_full_stall_count)
  );

  autoisa_ci_inflight_table #(
      .DEPTH(INFLIGHT_DEPTH),
      .COUNT_WIDTH(COUNT_WIDTH)
  ) i_inflight_table (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      .flush_i(flush_i),
      .alloc_valid_i(table_alloc_valid),
      .alloc_ready_o(table_alloc_ready),
      .alloc_req_i(req_i),
      .alloc_duplicate_o(table_alloc_duplicate),
      .dispatch_valid_o(table_dispatch_valid),
      .dispatch_ready_i(table_dispatch_ready),
      .dispatch_req_o(table_dispatch_req),
      .complete_valid_i(table_complete_valid),
      .complete_ready_o(table_complete_ready),
      .complete_rsp_i(table_complete_rsp),
      .commit_valid_i(commit_valid_i),
      .commit_tag_i(commit_tag_i),
      .commit_epoch_i(commit_epoch_i),
      .kill_valid_i(kill_valid_i),
      .kill_tag_i(kill_tag_i),
      .kill_epoch_i(kill_epoch_i),
      .kill_hit_o(kill_hit_o),
      .kill_dispatched_o(table_kill_dispatched),
      .retire_valid_o(table_retire_valid),
      .retire_ready_i(table_retire_ready),
      .retire_rsp_o(table_retire_rsp),
      .occupancy_o(inflight_occupancy_o),
      .high_watermark_o(inflight_high_watermark_o),
      .allocated_count_o(accepted_count_o),
      .retired_count_o(retired_count_o),
      .killed_count_o(killed_count_o),
      .orphan_completion_count_o(orphan_completion_count_o)
  );

  // The queue deliberately stores a newly accepted request for at least one
  // cycle. This avoids bypassing it before the table allocation is visible.
  assign queue_has_stored_head = (request_occupancy_o != '0);
  assign dispatch_identity_match = queue_has_stored_head && queue_out_valid &&
                                   table_dispatch_valid &&
                                   (queue_out_req.tag == table_dispatch_req.tag) &&
                                   (queue_out_req.epoch == table_dispatch_req.epoch);

  assign used_result_slots = result_occupancy_o + reserved_credits_q;
  assign credit_available = (used_result_slots < RESULT_DEPTH);
  assign reserved_result_credits_o = reserved_credits_q;

  assign skid_in_valid = dispatch_identity_match && credit_available;
  assign table_dispatch_ready = dispatch_identity_match && skid_in_ready &&
                                credit_available;
  assign dispatch_fire = skid_in_valid && skid_in_ready;

  // A queued entry whose table identity disappeared was killed or flushed.
  // Drain it without executing. A live matching head is popped only when the
  // engine accepts the same tagged request.
  assign tombstone_drop = queue_has_stored_head && queue_out_valid &&
                          !dispatch_identity_match;
  assign queue_out_ready = queue_has_stored_head &&
                           (tombstone_drop || dispatch_fire);

  autoisa_ci_engine_skid #(
      .COUNT_WIDTH(COUNT_WIDTH)
  ) i_engine_skid (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      .flush_i(flush_i),
      .in_valid_i(skid_in_valid),
      .in_ready_o(skid_in_ready),
      .in_req_i(table_dispatch_req),
      .out_valid_o(engine_req_valid),
      .out_ready_i(engine_req_ready),
      .out_req_o(engine_req),
      .kill_valid_i(kill_valid_i),
      .kill_tag_i(kill_tag_i),
      .kill_epoch_i(kill_epoch_i),
      .kill_hit_o(skid_kill_hit),
      .occupancy_o(engine_skid_occupancy_o),
      .high_watermark_o(engine_skid_high_watermark_o),
      .accepted_count_o(skid_accepted_count),
      .forwarded_count_o(engine_started_count_o),
      .killed_drop_count_o(skid_killed_drop_count_o),
      .flush_drop_count_o(skid_flush_drop_count_o)
  );

  autoisa_ci_dummy_engine i_dummy_engine (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      .req_valid_i(engine_req_valid),
      .req_ready_o(engine_req_ready),
      .req_i(engine_req),
      .rsp_valid_o(engine_rsp_valid),
      .rsp_ready_i(engine_rsp_ready),
      .rsp_o(engine_rsp)
  );

  assign table_complete_valid = engine_rsp_valid;
  assign table_complete_rsp = engine_rsp;
  assign engine_rsp_ready = table_complete_ready;

  autoisa_ci_result_queue #(
      .DEPTH(RESULT_DEPTH),
      .COUNT_WIDTH(COUNT_WIDTH)
  ) i_result_queue (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      .flush_i(flush_i),
      .in_valid_i(table_retire_valid),
      .in_ready_o(table_retire_ready),
      .in_rsp_i(table_retire_rsp),
      .out_valid_o(result_valid_o),
      .out_ready_i(result_ready_i),
      .out_rsp_o(result_o),
      .occupancy_o(result_occupancy_o),
      .high_watermark_o(result_high_watermark_o),
      .enqueue_count_o(result_enqueue_count),
      .dequeue_count_o(result_dequeue_count),
      .full_stall_count_o(result_full_stall_count_o),
      .flush_drop_count_o(result_flush_drop_count_o)
  );

  assign result_enqueue = table_retire_valid && table_retire_ready;
  assign kill_credit_release = kill_hit_o && table_kill_dispatched;

  always_comb begin
    credit_calc = {1'b0, reserved_credits_q};
    if (dispatch_fire) credit_calc = credit_calc + 1'b1;
    if (result_enqueue) credit_calc = credit_calc - 1'b1;
    if (kill_credit_release) credit_calc = credit_calc - 1'b1;
    reserved_credits_d = credit_calc[RES_OCC_WIDTH-1:0];
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      dispatched_count_o <= '0;
      completion_count_o <= '0;
      tombstone_drop_count_o <= '0;
      reserved_credits_q <= '0;
      credit_high_watermark_o <= '0;
      credit_stall_count_o <= '0;
    end else begin
      if (dispatch_fire) dispatched_count_o <= dispatched_count_o + 1'b1;
      if (engine_rsp_valid && engine_rsp_ready)
        completion_count_o <= completion_count_o + 1'b1;
      if (tombstone_drop && queue_out_ready)
        tombstone_drop_count_o <= tombstone_drop_count_o + 1'b1;
      if (dispatch_identity_match && !credit_available)
        credit_stall_count_o <= credit_stall_count_o + 1'b1;

      if (flush_i) begin
        reserved_credits_q <= '0;
        credit_high_watermark_o <= '0;
      end else begin
        reserved_credits_q <= reserved_credits_d;
        if (reserved_credits_d > credit_high_watermark_o)
          credit_high_watermark_o <= reserved_credits_d;
      end
    end
  end

`ifndef SYNTHESIS
  logic result_stalled_q;
  autoisa_ci_rsp_t stalled_result_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      result_stalled_q <= 1'b0;
      stalled_result_q <= '0;
    end else begin
      if (dispatch_fire) begin
        assert (queue_out_req == table_dispatch_req)
          else $error("concurrent shell queue/table dispatch mismatch");
      end
      assert (used_result_slots <= RESULT_DEPTH)
        else $error("concurrent shell result credit overflow");
      assert (!(kill_credit_release && (reserved_credits_q == '0) &&
               !dispatch_fire))
        else $error("concurrent shell result credit underflow on kill");
      assert (!(result_enqueue && (reserved_credits_q == '0) &&
               !dispatch_fire))
        else $error("concurrent shell result credit underflow on enqueue");
      if (result_stalled_q && !flush_i) begin
        assert (result_valid_o && (result_o == stalled_result_q))
          else $error("concurrent shell result changed while stalled");
      end
      result_stalled_q <= result_valid_o && !result_ready_i;
      if (result_valid_o && !result_ready_i) stalled_result_q <= result_o;
    end
  end
`endif

endmodule

`default_nettype wire
