// SPDX-License-Identifier: Apache-2.0
// Two-engine pending scheduler with oldest-ready selection and response merge.
`timescale 1ns / 1ps
`default_nettype none

module autoisa_ci_multi_engine_cluster #(
    parameter int unsigned PENDING_DEPTH = 4,
    parameter int unsigned COUNT_WIDTH = 32,
    parameter int unsigned INDEX_WIDTH = (PENDING_DEPTH > 1) ? $clog2(PENDING_DEPTH) : 1,
    parameter int unsigned OCC_WIDTH = $clog2(PENDING_DEPTH + 1)
) (
    input wire clk_i,
    input wire rst_ni,
    input wire flush_i,

    input wire req_valid_i,
    output logic req_ready_o,
    input autoisa_ci_types_pkg::autoisa_ci_req_t req_i,
    output logic req_supported_o,

    input wire kill_valid_i,
    input wire [autoisa_ci_types_pkg::AUTOISA_TAG_WIDTH-1:0] kill_tag_i,
    input wire [autoisa_ci_types_pkg::AUTOISA_EPOCH_WIDTH-1:0] kill_epoch_i,
    output logic kill_pending_hit_o,
    output logic kill_running_hit_o,

    output logic rsp_valid_o,
    input wire rsp_ready_i,
    output autoisa_ci_types_pkg::autoisa_ci_rsp_t rsp_o,

    output logic [OCC_WIDTH-1:0] pending_occupancy_o,
    output logic [OCC_WIDTH-1:0] pending_high_watermark_o,
    output logic engine0_busy_o,
    output logic engine1_busy_o,
    output logic engine0_running_o,
    output logic engine1_running_o,
    output logic [COUNT_WIDTH-1:0] accepted_count_o,
    output logic [COUNT_WIDTH-1:0] engine0_dispatch_count_o,
    output logic [COUNT_WIDTH-1:0] engine1_dispatch_count_o,
    output logic [COUNT_WIDTH-1:0] completion_count_o,
    output logic [COUNT_WIDTH-1:0] unsupported_stall_count_o,
    output logic [COUNT_WIDTH-1:0] pending_kill_drop_count_o,
    output logic [COUNT_WIDTH-1:0] pending_flush_drop_count_o
);
  import autoisa_ci_types_pkg::*;

  logic [PENDING_DEPTH-1:0] valid_q;
  logic [PENDING_DEPTH-1:0] pending_engine_q;
  autoisa_ci_req_t pending_req_q[0:PENDING_DEPTH-1];
  logic [COUNT_WIDTH-1:0] age_q[0:PENDING_DEPTH-1];
  logic [COUNT_WIDTH-1:0] next_age_q;

  logic input_supported, input_engine_id;
  logic free_found, selected_found, selected_engine_id;
  logic pending_kill_found;
  logic [INDEX_WIDTH-1:0] free_index, selected_index;
  logic [INDEX_WIDTH-1:0] pending_kill_index;
  logic [COUNT_WIDTH-1:0] selected_age;
  logic selected_target_ready;
  logic accept_fire, dispatch_fire;

  logic engine0_req_valid, engine0_req_ready;
  logic engine1_req_valid, engine1_req_ready;
  autoisa_ci_req_t selected_req;
  logic engine0_rsp_valid, engine0_rsp_ready;
  logic engine1_rsp_valid, engine1_rsp_ready;
  autoisa_ci_rsp_t engine0_rsp, engine1_rsp;
  logic rsp_select_engine1;
  logic rsp_lock_q, rsp_lock_engine1_q;
  logic engine0_active_q, engine1_active_q;
  logic [AUTOISA_TAG_WIDTH-1:0] engine0_tag_q, engine1_tag_q;
  logic [AUTOISA_EPOCH_WIDTH-1:0] engine0_epoch_q, engine1_epoch_q;

  integer scan_i;
  integer seq_i;

  autoisa_ci_engine_descriptor i_input_descriptor (
      .ci_id_i(req_i.ci_id),
      .supported_o(input_supported),
      .engine_id_o(input_engine_id)
  );
  assign req_supported_o = input_supported;

  always_comb begin
    free_found = 1'b0;
    free_index = '0;
    selected_found = 1'b0;
    selected_index = '0;
    selected_engine_id = 1'b0;
    selected_age = '1;
    pending_kill_found = 1'b0;
    pending_kill_index = '0;
    pending_occupancy_o = '0;

    for (scan_i = 0; scan_i < PENDING_DEPTH; scan_i = scan_i + 1) begin
      if (valid_q[scan_i]) pending_occupancy_o = pending_occupancy_o + 1'b1;
      if (!valid_q[scan_i] && !free_found) begin
        free_found = 1'b1;
        free_index = INDEX_WIDTH'(scan_i);
      end
      if (valid_q[scan_i] && kill_valid_i &&
          (pending_req_q[scan_i].tag == kill_tag_i) &&
          (pending_req_q[scan_i].epoch == kill_epoch_i) &&
          !pending_kill_found) begin
        pending_kill_found = 1'b1;
        pending_kill_index = INDEX_WIDTH'(scan_i);
      end
      if (valid_q[scan_i] &&
          !(kill_valid_i &&
            (pending_req_q[scan_i].tag == kill_tag_i) &&
            (pending_req_q[scan_i].epoch == kill_epoch_i)) &&
          ((!pending_engine_q[scan_i] && engine0_req_ready) ||
           (pending_engine_q[scan_i] && engine1_req_ready)) &&
          (!selected_found || (age_q[scan_i] < selected_age))) begin
        selected_found = 1'b1;
        selected_index = INDEX_WIDTH'(scan_i);
        selected_engine_id = pending_engine_q[scan_i];
        selected_age = age_q[scan_i];
      end
    end
  end

  assign req_ready_o = !flush_i && input_supported && free_found;
  assign accept_fire = req_valid_i && req_ready_o;
  assign selected_req = selected_found ? pending_req_q[selected_index] : '0;
  assign selected_target_ready = selected_engine_id ? engine1_req_ready : engine0_req_ready;
  assign dispatch_fire = !flush_i && selected_found && selected_target_ready;
  assign engine0_req_valid = !flush_i && selected_found && !selected_engine_id;
  assign engine1_req_valid = !flush_i && selected_found && selected_engine_id;
  assign kill_pending_hit_o = kill_valid_i && pending_kill_found;
  assign kill_running_hit_o = kill_valid_i &&
      ((engine0_active_q && (engine0_tag_q == kill_tag_i) &&
        (engine0_epoch_q == kill_epoch_i)) ||
       (engine1_active_q && (engine1_tag_q == kill_tag_i) &&
        (engine1_epoch_q == kill_epoch_i)));

  autoisa_ci_dummy_engine i_engine0 (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      .req_valid_i(engine0_req_valid),
      .req_ready_o(engine0_req_ready),
      .req_i(selected_req),
      .rsp_valid_o(engine0_rsp_valid),
      .rsp_ready_i(engine0_rsp_ready),
      .rsp_o(engine0_rsp)
  );

  autoisa_ci_dummy_engine i_engine1 (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      .req_valid_i(engine1_req_valid),
      .req_ready_o(engine1_req_ready),
      .req_i(selected_req),
      .rsp_valid_o(engine1_rsp_valid),
      .rsp_ready_i(engine1_rsp_ready),
      .rsp_o(engine1_rsp)
  );

  assign engine0_busy_o = !engine0_req_ready;
  assign engine1_busy_o = !engine1_req_ready;
  assign engine0_running_o = engine0_active_q;
  assign engine1_running_o = engine1_active_q;

  // Lock a stalled grant so a later response from the other engine cannot
  // change the merged ready/valid payload under backpressure.
  assign rsp_select_engine1 = rsp_lock_q ? rsp_lock_engine1_q :
                              (!engine0_rsp_valid && engine1_rsp_valid);
  assign rsp_valid_o = rsp_select_engine1 ? engine1_rsp_valid : engine0_rsp_valid;
  assign rsp_o = rsp_select_engine1 ? engine1_rsp : engine0_rsp;
  assign engine0_rsp_ready = rsp_ready_i && !rsp_select_engine1;
  assign engine1_rsp_ready = rsp_ready_i && rsp_select_engine1;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      valid_q <= '0;
      pending_engine_q <= '0;
      next_age_q <= '0;
      pending_high_watermark_o <= '0;
      accepted_count_o <= '0;
      engine0_dispatch_count_o <= '0;
      engine1_dispatch_count_o <= '0;
      completion_count_o <= '0;
      unsupported_stall_count_o <= '0;
      pending_kill_drop_count_o <= '0;
      pending_flush_drop_count_o <= '0;
      rsp_lock_q <= 1'b0;
      rsp_lock_engine1_q <= 1'b0;
      engine0_active_q <= 1'b0;
      engine1_active_q <= 1'b0;
      engine0_tag_q <= '0;
      engine1_tag_q <= '0;
      engine0_epoch_q <= '0;
      engine1_epoch_q <= '0;
      for (seq_i = 0; seq_i < PENDING_DEPTH; seq_i = seq_i + 1) begin
        pending_req_q[seq_i] <= '0;
        age_q[seq_i] <= '0;
      end
    end else begin
      if (dispatch_fire) begin
        valid_q[selected_index] <= 1'b0;
        if (selected_engine_id) engine1_dispatch_count_o <= engine1_dispatch_count_o + 1'b1;
        else engine0_dispatch_count_o <= engine0_dispatch_count_o + 1'b1;
      end

      if (accept_fire) begin
        valid_q[free_index] <= 1'b1;
        pending_req_q[free_index] <= req_i;
        pending_engine_q[free_index] <= input_engine_id;
        age_q[free_index] <= next_age_q;
        next_age_q <= next_age_q + 1'b1;
        accepted_count_o <= accepted_count_o + 1'b1;
      end

      if (kill_pending_hit_o) begin
        valid_q[pending_kill_index] <= 1'b0;
        pending_kill_drop_count_o   <= pending_kill_drop_count_o + 1'b1;
      end

      if (engine0_req_valid && engine0_req_ready) begin
        engine0_active_q <= 1'b1;
        engine0_tag_q <= selected_req.tag;
        engine0_epoch_q <= selected_req.epoch;
      end
      if (engine1_req_valid && engine1_req_ready) begin
        engine1_active_q <= 1'b1;
        engine1_tag_q <= selected_req.tag;
        engine1_epoch_q <= selected_req.epoch;
      end
      if (engine0_rsp_valid && engine0_rsp_ready) engine0_active_q <= 1'b0;
      if (engine1_rsp_valid && engine1_rsp_ready) engine1_active_q <= 1'b0;

      if (accept_fire && (pending_occupancy_o + 1'b1 > pending_high_watermark_o))
        pending_high_watermark_o <= pending_occupancy_o + 1'b1;
      if (rsp_valid_o && rsp_ready_i) completion_count_o <= completion_count_o + 1'b1;
      if (req_valid_i && !input_supported)
        unsupported_stall_count_o <= unsupported_stall_count_o + 1'b1;

      if (!rsp_lock_q && rsp_valid_o && !rsp_ready_i) begin
        rsp_lock_q <= 1'b1;
        rsp_lock_engine1_q <= rsp_select_engine1;
      end else if (rsp_lock_q && rsp_valid_o && rsp_ready_i) begin
        rsp_lock_q <= 1'b0;
      end

      if (flush_i) begin
        valid_q <= '0;
        next_age_q <= '0;
        pending_high_watermark_o <= '0;
        pending_flush_drop_count_o <= pending_flush_drop_count_o + pending_occupancy_o;
      end
    end
  end

`ifndef SYNTHESIS
  logic rsp_stalled_q;
  autoisa_ci_rsp_t stalled_rsp_q;

  initial begin
    assert ((PENDING_DEPTH == 2) || (PENDING_DEPTH == 4) || (PENDING_DEPTH == 8))
    else $error("autoisa_ci_multi_engine_cluster PENDING_DEPTH must be 2, 4, or 8");
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rsp_stalled_q <= 1'b0;
      stalled_rsp_q <= '0;
    end else begin
      assert (pending_occupancy_o <= PENDING_DEPTH)
      else $error("multi-engine pending occupancy overflow");
      assert (!(engine0_req_valid && engine1_req_valid))
      else $error("multi-engine scheduler dispatched twice in one cycle");
      if (rsp_stalled_q) begin
        assert (rsp_valid_o && (rsp_o == stalled_rsp_q))
        else $error("multi-engine merged response changed while stalled");
      end
      rsp_stalled_q <= rsp_valid_o && !rsp_ready_i;
      if (rsp_valid_o && !rsp_ready_i) stalled_rsp_q <= rsp_o;
    end
  end
`endif
endmodule

`default_nettype wire
