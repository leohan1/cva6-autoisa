// SPDX-License-Identifier: Apache-2.0
// CVA6 scoreboard identity, destination ownership and commit/kill boundary.
`timescale 1ns/1ps

module autoisa_ci_cva6_host_adapter #(
    parameter int unsigned TRANS_ID_WIDTH = 3,
    parameter int unsigned MAP_ENTRIES = 8,
    parameter int unsigned STD_SRC_PORTS = 3,
    parameter int unsigned COUNT_WIDTH = 32,
    localparam int unsigned TRANS_IDS = 1 << TRANS_ID_WIDTH,
    localparam int unsigned OCC_WIDTH = $clog2(MAP_ENTRIES + 1)
) (
    input  wire clk_i,
    input  wire rst_ni,
    input  wire flush_i,

    input  wire issue_valid_i,
    output logic issue_ready_o,
    input  wire [31:0] issue_instr_i,
    input  wire [TRANS_ID_WIDTH-1:0] issue_trans_id_i,
    output logic issue_accept_o,
    output logic issue_recognized_o,
    output logic issue_illegal_o,
    output logic issue_identity_busy_o,
    output logic issue_raw_hazard_o,
    output logic issue_waw_hazard_o,
    output logic issue_desc_valid_o,
    input  wire issue_desc_ready_i,
    output autoisa_ci_types_pkg::autoisa_ci_host_desc_t issue_desc_o,

    input  wire commit_valid_i,
    input  wire [TRANS_ID_WIDTH-1:0] commit_trans_id_i,
    input  wire commit_kill_i,
    output logic commit_identity_hit_o,
    output logic shell_commit_valid_o,
    output logic [autoisa_ci_types_pkg::AUTOISA_TAG_WIDTH-1:0] shell_commit_tag_o,
    output logic [autoisa_ci_types_pkg::AUTOISA_EPOCH_WIDTH-1:0] shell_commit_epoch_o,
    output logic shell_kill_valid_o,
    output logic [autoisa_ci_types_pkg::AUTOISA_TAG_WIDTH-1:0] shell_kill_tag_o,
    output logic [autoisa_ci_types_pkg::AUTOISA_EPOCH_WIDTH-1:0] shell_kill_epoch_o,
    output logic shell_flush_o,

    input  wire shell_result_valid_i,
    output logic shell_result_ready_o,
    input  autoisa_ci_types_pkg::autoisa_ci_rsp_t shell_result_i,
    output logic host_result_valid_o,
    input  wire host_result_ready_i,
    output logic [TRANS_ID_WIDTH-1:0] host_result_trans_id_o,
    output logic [autoisa_ci_types_pkg::AUTOISA_MAX_DST-1:0] host_result_dst_valid_o,
    output logic [autoisa_ci_types_pkg::AUTOISA_MAX_DST-1:0][4:0] host_result_dst_addr_o,
    output logic [autoisa_ci_types_pkg::AUTOISA_MAX_DST-1:0][31:0] host_result_data_o,
    output autoisa_ci_types_pkg::autoisa_ci_write_policy_e host_result_write_policy_o,
    output autoisa_ci_types_pkg::autoisa_ci_status_e host_result_status_o,

    input  wire [31:0] standard_pending_write_mask_i,
    input  wire [STD_SRC_PORTS-1:0] std_src_valid_i,
    input  wire [STD_SRC_PORTS-1:0][4:0] std_src_addr_i,
    input  wire std_dst_valid_i,
    input  wire [4:0] std_dst_addr_i,
    output logic std_raw_hazard_o,
    output logic std_waw_hazard_o,
    output logic [31:0] destination_busy_mask_o,
    output logic [OCC_WIDTH-1:0] destination_occupancy_o,
    output logic [OCC_WIDTH-1:0] destination_high_watermark_o,
    output logic [COUNT_WIDTH-1:0] issue_accept_count_o,
    output logic [COUNT_WIDTH-1:0] issue_reject_count_o,
    output logic [COUNT_WIDTH-1:0] stale_result_drop_count_o,
    output logic [COUNT_WIDTH-1:0] unknown_commit_count_o
);
  import autoisa_ci_types_pkg::*;

  logic decoded_valid, decoded_illegal;
  autoisa_ci_host_desc_t decoded_desc;
  autoisa_ci_write_policy_e decoded_policy;
  logic [AUTOISA_TAG_WIDTH-1:0] issue_tag;
  logic [AUTOISA_EPOCH_WIDTH-1:0] issue_epoch;

  logic [TRANS_IDS-1:0] live_q;
  logic [TRANS_IDS-1:0][AUTOISA_EPOCH_WIDTH-1:0] epoch_q;
  logic issue_fire, issue_accepted_fire;
  logic commit_live, kill_fire, result_fire, stale_result_fire;
  logic result_tag_in_range;
  logic [TRANS_ID_WIDTH-1:0] result_trans_id;

  logic map_reserve_ready, map_duplicate, map_tag_busy, map_illegal;
  logic map_release_valid, map_release_hit, map_release_stale;
  logic [AUTOISA_TAG_WIDTH-1:0] map_release_tag;
  logic [AUTOISA_EPOCH_WIDTH-1:0] map_release_epoch;
  logic map_lookup_hit, map_lookup_stale;
  logic [AUTOISA_MAX_DST-1:0] map_lookup_dst_valid;
  logic [AUTOISA_MAX_DST-1:0][4:0] map_lookup_dst_addr;
  autoisa_ci_write_policy_e map_lookup_policy;
  logic [COUNT_WIDTH-1:0] unused_reserve_count, unused_release_count;
  logic [COUNT_WIDTH-1:0] unused_conflict_count, unused_stale_release_count;
  logic [COUNT_WIDTH-1:0] unused_flush_drop_count;

  always_comb begin
    issue_tag = '0;
    issue_tag[TRANS_ID_WIDTH-1:0] = issue_trans_id_i;
    issue_epoch = epoch_q[issue_trans_id_i];
  end

  autoisa_ci_layout_decoder_v2 i_decoder (
      .instr_i(issue_instr_i), .tag_i(issue_tag), .epoch_i(issue_epoch),
      .valid_o(decoded_valid), .illegal_o(decoded_illegal), .desc_o(decoded_desc)
  );

  always_comb begin
    decoded_policy = AUTOISA_WRITE_NONE;
    if (decoded_desc.dst_valid == 2'b01)
      decoded_policy = AUTOISA_WRITE_SCALAR;
    else if (decoded_desc.dst_valid == 2'b11)
      decoded_policy = AUTOISA_WRITE_PAIR_SERIAL;
  end

  assign issue_recognized_o = issue_valid_i && decoded_valid;
  assign issue_illegal_o = issue_valid_i && decoded_valid && decoded_illegal;
  assign issue_identity_busy_o = issue_valid_i && live_q[issue_trans_id_i];
  assign issue_desc_o = decoded_desc;

  // Unsupported and illegal instructions are consumed as explicit rejects.
  // A legal CI only handshakes when descriptor transport and destination map
  // can accept the transaction atomically.
  assign issue_accept_o = issue_valid_i && decoded_valid && !decoded_illegal &&
                          !live_q[issue_trans_id_i] && map_reserve_ready;
  assign issue_desc_valid_o = issue_accept_o;
  assign issue_ready_o = !issue_valid_i || !decoded_valid || decoded_illegal ||
                         live_q[issue_trans_id_i] ||
                         (map_reserve_ready && issue_desc_ready_i);
  assign issue_fire = issue_valid_i && issue_ready_o;
  assign issue_accepted_fire = issue_fire && issue_accept_o && issue_desc_ready_i;

  assign commit_live = live_q[commit_trans_id_i];
  assign commit_identity_hit_o = commit_valid_i && commit_live;
  assign shell_commit_valid_o = commit_valid_i && commit_live && !commit_kill_i;
  assign shell_kill_valid_o = commit_valid_i && commit_live && commit_kill_i;
  always_comb begin
    shell_commit_tag_o = '0;
    shell_commit_tag_o[TRANS_ID_WIDTH-1:0] = commit_trans_id_i;
    shell_commit_epoch_o = epoch_q[commit_trans_id_i];
    shell_kill_tag_o = shell_commit_tag_o;
    shell_kill_epoch_o = shell_commit_epoch_o;
  end
  assign shell_flush_o = flush_i;
  assign kill_fire = shell_kill_valid_o;

  assign result_tag_in_range = !(|shell_result_i.tag[AUTOISA_TAG_WIDTH-1:TRANS_ID_WIDTH]);
  assign result_trans_id = shell_result_i.tag[TRANS_ID_WIDTH-1:0];
  assign host_result_valid_o = shell_result_valid_i && map_lookup_hit &&
                               !(kill_fire &&
                                 (shell_kill_tag_o == shell_result_i.tag) &&
                                 (shell_kill_epoch_o == shell_result_i.epoch));
  assign host_result_trans_id_o = result_trans_id;
  assign host_result_dst_valid_o = map_lookup_dst_valid;
  assign host_result_dst_addr_o = map_lookup_dst_addr;
  assign host_result_data_o = shell_result_i.results;
  assign host_result_write_policy_o = map_lookup_policy;
  assign host_result_status_o = shell_result_i.status;

  // Stale/unknown completions are always drained. A valid mapped result follows
  // downstream backpressure. Kill wins over a same-cycle result.
  assign shell_result_ready_o = shell_result_valid_i &&
                                (!map_lookup_hit ||
                                 (!(kill_fire &&
                                    (shell_kill_tag_o == shell_result_i.tag) &&
                                    (shell_kill_epoch_o == shell_result_i.epoch)) &&
                                  host_result_ready_i)) && !kill_fire;
  assign result_fire = shell_result_valid_i && shell_result_ready_o && map_lookup_hit;
  assign stale_result_fire = shell_result_valid_i && shell_result_ready_o &&
                             (!map_lookup_hit || map_lookup_stale || !result_tag_in_range);

  always_comb begin
    map_release_valid = 1'b0;
    map_release_tag = '0;
    map_release_epoch = '0;
    if (kill_fire) begin
      map_release_valid = 1'b1;
      map_release_tag = shell_kill_tag_o;
      map_release_epoch = shell_kill_epoch_o;
    end else if (result_fire) begin
      map_release_valid = 1'b1;
      map_release_tag = shell_result_i.tag;
      map_release_epoch = shell_result_i.epoch;
    end
  end

  autoisa_ci_destination_map #(
      .ENTRIES(MAP_ENTRIES), .STD_SRC_PORTS(STD_SRC_PORTS),
      .COUNT_WIDTH(COUNT_WIDTH)
  ) i_destination_map (
      .clk_i(clk_i), .rst_ni(rst_ni), .flush_i(flush_i),
      .reserve_valid_i(issue_accepted_fire), .reserve_ready_o(map_reserve_ready),
      .reserve_desc_i(decoded_desc), .reserve_write_policy_i(decoded_policy),
      .reserve_duplicate_o(map_duplicate), .reserve_tag_busy_o(map_tag_busy),
      .reserve_raw_hazard_o(issue_raw_hazard_o),
      .reserve_waw_hazard_o(issue_waw_hazard_o), .reserve_illegal_o(map_illegal),
      .release_valid_i(map_release_valid), .release_tag_i(map_release_tag),
      .release_epoch_i(map_release_epoch), .release_hit_o(map_release_hit),
      .release_stale_o(map_release_stale),
      .lookup_valid_i(shell_result_valid_i), .lookup_tag_i(shell_result_i.tag),
      .lookup_epoch_i(shell_result_i.epoch), .lookup_hit_o(map_lookup_hit),
      .lookup_stale_o(map_lookup_stale), .lookup_dst_valid_o(map_lookup_dst_valid),
      .lookup_dst_addr_o(map_lookup_dst_addr),
      .lookup_write_policy_o(map_lookup_policy),
      .standard_pending_write_mask_i(standard_pending_write_mask_i),
      .std_src_valid_i(std_src_valid_i), .std_src_addr_i(std_src_addr_i),
      .std_dst_valid_i(std_dst_valid_i), .std_dst_addr_i(std_dst_addr_i),
      .std_raw_hazard_o(std_raw_hazard_o), .std_waw_hazard_o(std_waw_hazard_o),
      .busy_mask_o(destination_busy_mask_o),
      .occupancy_o(destination_occupancy_o),
      .high_watermark_o(destination_high_watermark_o),
      .reserve_count_o(unused_reserve_count), .release_count_o(unused_release_count),
      .conflict_count_o(unused_conflict_count),
      .stale_release_count_o(unused_stale_release_count),
      .flush_drop_count_o(unused_flush_drop_count)
  );

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      live_q <= '0;
      epoch_q <= '0;
      issue_accept_count_o <= '0;
      issue_reject_count_o <= '0;
      stale_result_drop_count_o <= '0;
      unknown_commit_count_o <= '0;
    end else if (flush_i) begin
      live_q <= '0;
      for (int unsigned i = 0; i < TRANS_IDS; i++)
        epoch_q[i] <= epoch_q[i] + 1'b1;
    end else begin
      if (issue_accepted_fire) begin
        live_q[issue_trans_id_i] <= 1'b1;
        issue_accept_count_o <= issue_accept_count_o + 1'b1;
      end else if (issue_fire) begin
        issue_reject_count_o <= issue_reject_count_o + 1'b1;
      end

      if (kill_fire) begin
        live_q[commit_trans_id_i] <= 1'b0;
        epoch_q[commit_trans_id_i] <= epoch_q[commit_trans_id_i] + 1'b1;
      end else if (result_fire && result_tag_in_range) begin
        live_q[result_trans_id] <= 1'b0;
        epoch_q[result_trans_id] <= epoch_q[result_trans_id] + 1'b1;
      end
      if (stale_result_fire)
        stale_result_drop_count_o <= stale_result_drop_count_o + 1'b1;
      if (commit_valid_i && !commit_live)
        unknown_commit_count_o <= unknown_commit_count_o + 1'b1;
    end
  end

  initial begin
    assert (TRANS_ID_WIDTH <= AUTOISA_TAG_WIDTH)
      else $error("CVA6 trans_id must fit canonical AutoISA tag");
    assert (MAP_ENTRIES <= TRANS_IDS)
      else $error("destination map cannot exceed CVA6 identity slots");
  end

  always_ff @(posedge clk_i) begin
    if (rst_ni) begin
      assert (!(shell_commit_valid_o && shell_kill_valid_o))
        else $error("commit and kill asserted for one identity");
      if (host_result_valid_o && !host_result_ready_i)
        assert (!shell_result_ready_o)
          else $error("host result backpressure not propagated");
      assert (!(map_release_valid && !map_release_hit))
        else $error("terminal event failed to release destination ownership");
    end
  end
endmodule
