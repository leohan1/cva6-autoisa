// SPDX-License-Identifier: Apache-2.0
// Queued 1-6R operand gather over two physical Host register-read ports.
`timescale 1ns / 1ps

module autoisa_ci_operand_gather #(
    parameter int unsigned PENDING_DEPTH = 4,
    parameter int unsigned COUNT_WIDTH = 32,
    localparam int unsigned INDEX_WIDTH = (PENDING_DEPTH <= 1) ? 1 : $clog2(PENDING_DEPTH),
    localparam int unsigned OCC_WIDTH = $clog2(PENDING_DEPTH + 3)
) (
    input wire clk_i,
    input wire rst_ni,
    input wire flush_i,

    input wire desc_valid_i,
    output logic desc_ready_o,
    input autoisa_ci_types_pkg::autoisa_ci_host_desc_t desc_i,
    output logic desc_illegal_o,

    output logic rf_req_valid_o,
    input wire rf_req_ready_i,
    output logic [1:0] rf_lane_valid_o,
    output logic [1:0][4:0] rf_addr_o,
    input wire [1:0][31:0] rf_data_i,

    output logic req_valid_o,
    input wire req_ready_i,
    output autoisa_ci_types_pkg::autoisa_ci_req_t req_o,

    input wire kill_valid_i,
    input wire [autoisa_ci_types_pkg::AUTOISA_TAG_WIDTH-1:0] kill_tag_i,
    input wire [autoisa_ci_types_pkg::AUTOISA_EPOCH_WIDTH-1:0] kill_epoch_i,
    output logic kill_hit_o,

    output logic [  OCC_WIDTH-1:0] occupancy_o,
    output logic [  OCC_WIDTH-1:0] high_watermark_o,
    output logic [COUNT_WIDTH-1:0] accepted_count_o,
    output logic [COUNT_WIDTH-1:0] emitted_count_o,
    output logic [COUNT_WIDTH-1:0] gather_beat_count_o,
    output logic [COUNT_WIDTH-1:0] killed_count_o,
    output logic [COUNT_WIDTH-1:0] flush_drop_count_o
);
  import autoisa_ci_types_pkg::*;

  logic [PENDING_DEPTH-1:0] pending_valid_q;
  autoisa_ci_host_desc_t pending_desc_q[PENDING_DEPTH];
  logic [PENDING_DEPTH-1:0][31:0] pending_age_q;
  logic [31:0] next_age_q;

  logic free_found, oldest_found, pending_kill_found;
  logic [INDEX_WIDTH-1:0] free_index, oldest_index, pending_kill_index;
  logic [31:0] oldest_age;
  logic active_q, out_valid_q;
  autoisa_ci_host_desc_t active_desc_q;
  logic [1:0] beat_q;
  logic [AUTOISA_MAX_SRC-1:0][31:0] operands_q;
  autoisa_ci_req_t out_req_q, completed_req;
  logic active_kill, out_kill;
  logic desc_fire, rf_fire, req_fire;
  logic [1:0] last_beat;
  logic [2:0] killed_this_cycle;
  logic [OCC_WIDTH-1:0] occupancy_next, flush_drop_comb;

  function automatic logic legal_source_mask(input logic [AUTOISA_MAX_SRC-1:0] mask);
    begin
      unique case (mask)
        6'b00_0001, 6'b00_0011, 6'b00_0111, 6'b00_1111, 6'b01_1111, 6'b11_1111:
        legal_source_mask = 1'b1;
        default: legal_source_mask = 1'b0;
      endcase
    end
  endfunction

  always_comb begin
    free_found = 1'b0;
    free_index = '0;
    oldest_found = 1'b0;
    oldest_index = '0;
    oldest_age = '1;
    pending_kill_found = 1'b0;
    pending_kill_index = '0;
    for (int unsigned i = 0; i < PENDING_DEPTH; i++) begin
      if (!pending_valid_q[i] && !free_found) begin
        free_found = 1'b1;
        free_index = INDEX_WIDTH'(i);
      end
      if (pending_valid_q[i] && (pending_age_q[i] < oldest_age)) begin
        oldest_found = 1'b1;
        oldest_index = INDEX_WIDTH'(i);
        oldest_age   = pending_age_q[i];
      end
      if (pending_valid_q[i] && kill_valid_i &&
          (pending_desc_q[i].tag == kill_tag_i) &&
          (pending_desc_q[i].epoch == kill_epoch_i) && !pending_kill_found) begin
        pending_kill_found = 1'b1;
        pending_kill_index = INDEX_WIDTH'(i);
      end
    end
  end

  assign desc_illegal_o = desc_valid_i && !legal_source_mask(desc_i.src_valid);
  assign desc_ready_o = !flush_i && free_found && !desc_illegal_o &&
                        !(kill_valid_i && (desc_i.tag == kill_tag_i) &&
                          (desc_i.epoch == kill_epoch_i));
  assign desc_fire = desc_valid_i && desc_ready_o;

  assign active_kill = active_q && kill_valid_i &&
                       (active_desc_q.tag == kill_tag_i) &&
                       (active_desc_q.epoch == kill_epoch_i);
  assign out_kill = out_valid_q && kill_valid_i &&
                    (out_req_q.tag == kill_tag_i) &&
                    (out_req_q.epoch == kill_epoch_i);
  assign kill_hit_o = pending_kill_found || active_kill || out_kill;

  always_comb begin
    if (active_desc_q.src_valid[4] || active_desc_q.src_valid[5]) last_beat = 2'd2;
    else if (active_desc_q.src_valid[2] || active_desc_q.src_valid[3]) last_beat = 2'd1;
    else last_beat = 2'd0;

    rf_lane_valid_o = '0;
    rf_addr_o = '0;
    for (int unsigned lane = 0; lane < 2; lane++) begin
      if (((beat_q * 2) + lane) < AUTOISA_MAX_SRC) begin
        rf_lane_valid_o[lane] = active_desc_q.src_valid[(beat_q*2)+lane];
        rf_addr_o[lane] = active_desc_q.src_addr[(beat_q*2)+lane];
      end
    end
  end

  assign rf_req_valid_o = active_q && !active_kill && !flush_i;
  assign rf_fire = rf_req_valid_o && rf_req_ready_i;
  assign req_valid_o = out_valid_q && !out_kill && !flush_i;
  assign req_o = out_req_q;
  assign req_fire = req_valid_o && req_ready_i;

  always_comb begin
    completed_req = '0;
    completed_req.tag = active_desc_q.tag;
    completed_req.epoch = active_desc_q.epoch;
    completed_req.ci_id = active_desc_q.ci_id;
    completed_req.operand_valid = active_desc_q.src_valid;
    completed_req.operands = operands_q;
    completed_req.imm_valid = active_desc_q.imm_valid;
    completed_req.immediate = active_desc_q.immediate;
    for (int unsigned lane = 0; lane < 2; lane++) begin
      if (((beat_q * 2) + lane) < AUTOISA_MAX_SRC && rf_lane_valid_o[lane])
        completed_req.operands[(beat_q*2)+lane] = rf_data_i[lane];
    end
  end

  always_comb begin
    occupancy_o = OCC_WIDTH'($countones(pending_valid_q)) + active_q + out_valid_q;
    occupancy_next = occupancy_o;
    if (desc_fire) occupancy_next = occupancy_next + 1'b1;
    if (req_fire || out_kill) occupancy_next = occupancy_next - 1'b1;
    if (active_kill) occupancy_next = occupancy_next - 1'b1;
    if (pending_kill_found) occupancy_next = occupancy_next - 1'b1;
    flush_drop_comb   = occupancy_o;
    killed_this_cycle = pending_kill_found + active_kill + out_kill;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      pending_valid_q <= '0;
      pending_age_q <= '0;
      next_age_q <= '0;
      active_q <= 1'b0;
      active_desc_q <= '0;
      beat_q <= '0;
      operands_q <= '0;
      out_valid_q <= 1'b0;
      out_req_q <= '0;
      high_watermark_o <= '0;
      accepted_count_o <= '0;
      emitted_count_o <= '0;
      gather_beat_count_o <= '0;
      killed_count_o <= '0;
      flush_drop_count_o <= '0;
    end else if (flush_i) begin
      pending_valid_q <= '0;
      active_q <= 1'b0;
      out_valid_q <= 1'b0;
      beat_q <= '0;
      operands_q <= '0;
      high_watermark_o <= '0;
      flush_drop_count_o <= flush_drop_count_o + flush_drop_comb;
    end else begin
      if (pending_kill_found) pending_valid_q[pending_kill_index] <= 1'b0;
      if (active_kill) begin
        active_q <= 1'b0;
        beat_q <= '0;
        operands_q <= '0;
      end
      if (out_kill) out_valid_q <= 1'b0;

      if (req_fire) begin
        out_valid_q <= 1'b0;
        emitted_count_o <= emitted_count_o + 1'b1;
      end

      if (desc_fire) begin
        pending_valid_q[free_index] <= 1'b1;
        pending_desc_q[free_index] <= desc_i;
        pending_age_q[free_index] <= next_age_q;
        next_age_q <= next_age_q + 1'b1;
        accepted_count_o <= accepted_count_o + 1'b1;
      end

      if (!active_q && !out_valid_q && oldest_found && !pending_kill_found) begin
        active_q <= 1'b1;
        active_desc_q <= pending_desc_q[oldest_index];
        pending_valid_q[oldest_index] <= 1'b0;
        beat_q <= '0;
        operands_q <= '0;
      end

      if (rf_fire && !active_kill) begin
        for (int unsigned lane = 0; lane < 2; lane++) begin
          if (((beat_q * 2) + lane) < AUTOISA_MAX_SRC && rf_lane_valid_o[lane])
            operands_q[(beat_q*2)+lane] <= rf_data_i[lane];
        end
        gather_beat_count_o <= gather_beat_count_o + 1'b1;
        if (beat_q == last_beat) begin
          out_req_q <= completed_req;
          out_valid_q <= 1'b1;
          active_q <= 1'b0;
          beat_q <= '0;
        end else begin
          beat_q <= beat_q + 1'b1;
        end
      end

      if (killed_this_cycle != 0) killed_count_o <= killed_count_o + killed_this_cycle;
      if (occupancy_next > high_watermark_o) high_watermark_o <= occupancy_next;
    end
  end

  initial begin
    assert ((PENDING_DEPTH == 1) || (PENDING_DEPTH == 2) ||
            (PENDING_DEPTH == 4) || (PENDING_DEPTH == 8))
    else $error("operand gather PENDING_DEPTH must be 1, 2, 4, or 8");
  end

  autoisa_ci_req_t stalled_req_q;
  logic stalled_q;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      stalled_q <= 1'b0;
      stalled_req_q <= '0;
    end else begin
      if (stalled_q && !flush_i && !out_kill)
        assert (req_valid_o && (req_o == stalled_req_q))
        else $error("operand gather output changed while stalled");
      stalled_q <= req_valid_o && !req_ready_i;
      stalled_req_q <= req_o;
      assert (occupancy_o <= (PENDING_DEPTH + 2))
      else $error("operand gather occupancy overflow");
    end
  end
endmodule
