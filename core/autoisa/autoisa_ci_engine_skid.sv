// SPDX-License-Identifier: Apache-2.0
// One-entry kill-aware elastic buffer between scheduler and CI engine.
`timescale 1ns/1ps
`default_nettype none

module autoisa_ci_engine_skid #(
    parameter int unsigned COUNT_WIDTH = 32
) (
    input  wire clk_i,
    input  wire rst_ni,
    input  wire flush_i,

    input  wire in_valid_i,
    output logic in_ready_o,
    input  autoisa_ci_types_pkg::autoisa_ci_req_t in_req_i,

    output logic out_valid_o,
    input  wire out_ready_i,
    output autoisa_ci_types_pkg::autoisa_ci_req_t out_req_o,

    input  wire kill_valid_i,
    input  wire [autoisa_ci_types_pkg::AUTOISA_TAG_WIDTH-1:0] kill_tag_i,
    input  wire [autoisa_ci_types_pkg::AUTOISA_EPOCH_WIDTH-1:0] kill_epoch_i,
    output logic kill_hit_o,

    output logic occupancy_o,
    output logic high_watermark_o,
    output logic [COUNT_WIDTH-1:0] accepted_count_o,
    output logic [COUNT_WIDTH-1:0] forwarded_count_o,
    output logic [COUNT_WIDTH-1:0] killed_drop_count_o,
    output logic [COUNT_WIDTH-1:0] flush_drop_count_o
);
  import autoisa_ci_types_pkg::*;

  logic full_q, full_d;
  autoisa_ci_req_t req_q, req_d;
  logic stored_kill, incoming_kill;
  logic in_fire, out_fire;
  logic [1:0] killed_this_cycle;

  assign out_req_o = full_q ? req_q : in_req_i;
  assign stored_kill = full_q && kill_valid_i &&
                       (req_q.tag == kill_tag_i) &&
                       (req_q.epoch == kill_epoch_i);
  assign incoming_kill = in_valid_i && kill_valid_i &&
                         (in_req_i.tag == kill_tag_i) &&
                         (in_req_i.epoch == kill_epoch_i);
  assign kill_hit_o = stored_kill || (!full_q && incoming_kill);

  assign out_valid_o = !flush_i && (full_q || in_valid_i) &&
                       !(stored_kill || (!full_q && incoming_kill));
  assign in_ready_o = !flush_i && (!full_q || out_ready_i || stored_kill);
  assign in_fire = in_valid_i && in_ready_o;
  assign out_fire = out_valid_o && out_ready_i;
  assign occupancy_o = full_q;

  always_comb begin
    full_d = full_q;
    req_d = req_q;

    if (full_q) begin
      if (stored_kill || out_fire) begin
        if (in_fire && !incoming_kill) begin
          full_d = 1'b1;
          req_d = in_req_i;
        end else begin
          full_d = 1'b0;
        end
      end
    end else if (in_fire) begin
      if (incoming_kill || out_fire) begin
        full_d = 1'b0;
      end else begin
        full_d = 1'b1;
        req_d = in_req_i;
      end
    end

    killed_this_cycle = 2'd0;
    if (stored_kill) killed_this_cycle = killed_this_cycle + 1'b1;
    if (in_fire && incoming_kill)
      killed_this_cycle = killed_this_cycle + 1'b1;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      full_q <= 1'b0;
      req_q <= '0;
      high_watermark_o <= 1'b0;
      accepted_count_o <= '0;
      forwarded_count_o <= '0;
      killed_drop_count_o <= '0;
      flush_drop_count_o <= '0;
    end else begin
      if (in_fire) accepted_count_o <= accepted_count_o + 1'b1;
      if (out_fire) forwarded_count_o <= forwarded_count_o + 1'b1;
      if (killed_this_cycle != 0)
        killed_drop_count_o <= killed_drop_count_o + killed_this_cycle;

      if (flush_i) begin
        if (full_q) flush_drop_count_o <= flush_drop_count_o + 1'b1;
        full_q <= 1'b0;
        high_watermark_o <= 1'b0;
      end else begin
        full_q <= full_d;
        req_q <= req_d;
        if (full_d) high_watermark_o <= 1'b1;
      end
    end
  end

`ifndef SYNTHESIS
  logic stalled_q;
  autoisa_ci_req_t stalled_req_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      stalled_q <= 1'b0;
      stalled_req_q <= '0;
    end else begin
      if (stalled_q && !flush_i && !stored_kill) begin
        assert (out_valid_o && (out_req_o == stalled_req_q))
          else $error("autoisa_ci_engine_skid output changed while stalled");
      end
      stalled_q <= out_valid_o && !out_ready_i;
      if (out_valid_o && !out_ready_i) stalled_req_q <= out_req_o;
    end
  end
`endif

endmodule

`default_nettype wire
