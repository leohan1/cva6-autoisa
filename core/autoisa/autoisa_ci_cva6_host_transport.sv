// SPDX-License-Identifier: Apache-2.0
// End-to-end Direct-CI transport at the CVA6 integration boundary.
`timescale 1ns/1ps
`default_nettype none

module autoisa_ci_cva6_host_transport #(
    parameter int unsigned TRANS_ID_WIDTH = 3,
    parameter int unsigned MAP_ENTRIES = 8,
    parameter int unsigned STD_SRC_PORTS = 3,
    parameter int unsigned GATHER_DEPTH = 4,
    parameter int unsigned REQUEST_DEPTH = 4,
    parameter int unsigned INFLIGHT_DEPTH = 4,
    parameter int unsigned RESULT_DEPTH = 4,
    parameter int unsigned COUNT_WIDTH = 32,
    localparam int unsigned TRANS_IDS = 1 << TRANS_ID_WIDTH,
    localparam int unsigned MAP_OCC_WIDTH = $clog2(MAP_ENTRIES + 1),
    localparam int unsigned GATHER_OCC_WIDTH = $clog2(GATHER_DEPTH + 3)
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

    input  wire commit_valid_i,
    input  wire [TRANS_ID_WIDTH-1:0] commit_trans_id_i,
    input  wire commit_kill_i,
    output logic commit_identity_hit_o,

    output logic rf_req_valid_o,
    input  wire rf_req_ready_i,
    output logic [1:0] rf_lane_valid_o,
    output logic [1:0][4:0] rf_addr_o,
    input  wire [1:0][31:0] rf_data_i,

    input  wire [31:0] standard_pending_write_mask_i,
    input  wire [STD_SRC_PORTS-1:0] std_src_valid_i,
    input  wire [STD_SRC_PORTS-1:0][4:0] std_src_addr_i,
    input  wire std_dst_valid_i,
    input  wire [4:0] std_dst_addr_i,
    output logic std_raw_hazard_o,
    output logic std_waw_hazard_o,
    output logic [31:0] destination_busy_mask_o,

    output logic wb_valid_o,
    input  wire wb_ready_i,
    output logic [TRANS_ID_WIDTH-1:0] wb_trans_id_o,
    output logic [4:0] wb_addr_o,
    output logic [31:0] wb_data_o,
    output logic wb_we_o,
    output logic wb_last_o,
    output autoisa_ci_types_pkg::autoisa_ci_status_e wb_status_o,

    output logic [TRANS_IDS-1:0] commit_pending_mask_o,
    output logic [MAP_OCC_WIDTH-1:0] destination_occupancy_o,
    output logic [GATHER_OCC_WIDTH-1:0] gather_occupancy_o,
    output logic [COUNT_WIDTH-1:0] shell_accepted_count_o,
    output logic [COUNT_WIDTH-1:0] shell_retired_count_o,
    output logic [COUNT_WIDTH-1:0] wb_result_count_o,
    output logic [COUNT_WIDTH-1:0] wb_beat_count_o
);
  import autoisa_ci_types_pkg::*;

  autoisa_ci_host_desc_t host_desc;
  autoisa_ci_req_t shell_req;
  autoisa_ci_rsp_t shell_result;
  logic host_desc_valid, host_desc_ready;
  logic adapter_commit_valid, adapter_kill_valid;
  logic [AUTOISA_TAG_WIDTH-1:0] adapter_commit_tag, adapter_kill_tag;
  logic [AUTOISA_EPOCH_WIDTH-1:0] adapter_commit_epoch, adapter_kill_epoch;
  logic shell_req_valid, shell_req_ready, shell_req_fire;
  logic shell_commit_valid;
  logic [AUTOISA_TAG_WIDTH-1:0] shell_commit_tag;
  logic [AUTOISA_EPOCH_WIDTH-1:0] shell_commit_epoch;
  logic shell_result_valid, shell_result_ready;
  logic host_result_valid, host_result_ready;
  logic [TRANS_ID_WIDTH-1:0] host_result_trans_id;
  logic [AUTOISA_MAX_DST-1:0] host_result_dst_valid;
  logic [AUTOISA_MAX_DST-1:0][4:0] host_result_dst_addr;
  logic [AUTOISA_MAX_DST-1:0][31:0] host_result_data;
  autoisa_ci_write_policy_e host_result_write_policy;
  autoisa_ci_status_e host_result_status;

  logic [TRANS_IDS-1:0] shell_allocated_q, commit_pending_q;
  logic [TRANS_IDS-1:0][AUTOISA_EPOCH_WIDTH-1:0] allocated_epoch_q;
  logic [TRANS_IDS-1:0][AUTOISA_EPOCH_WIDTH-1:0] pending_epoch_q;
  logic [TRANS_ID_WIDTH-1:0] req_id, adapter_commit_id, adapter_kill_id;
  logic adapter_commit_id_in_range, adapter_kill_id_in_range;
  logic commit_matches_allocated, commit_matches_req;
  logic pending_matches_req, terminal_fire;

  assign req_id = shell_req.tag[TRANS_ID_WIDTH-1:0];
  assign adapter_commit_id = adapter_commit_tag[TRANS_ID_WIDTH-1:0];
  assign adapter_kill_id = adapter_kill_tag[TRANS_ID_WIDTH-1:0];
  assign adapter_commit_id_in_range =
      !(|adapter_commit_tag[AUTOISA_TAG_WIDTH-1:TRANS_ID_WIDTH]);
  assign adapter_kill_id_in_range =
      !(|adapter_kill_tag[AUTOISA_TAG_WIDTH-1:TRANS_ID_WIDTH]);
  assign shell_req_fire = shell_req_valid && shell_req_ready;
  assign terminal_fire = host_result_valid && host_result_ready;

  assign commit_matches_allocated = adapter_commit_valid &&
      adapter_commit_id_in_range && shell_allocated_q[adapter_commit_id] &&
      (allocated_epoch_q[adapter_commit_id] == adapter_commit_epoch);
  assign commit_matches_req = adapter_commit_valid && shell_req_fire &&
      (adapter_commit_tag == shell_req.tag) &&
      (adapter_commit_epoch == shell_req.epoch);
  assign pending_matches_req = shell_req_fire && commit_pending_q[req_id] &&
      (pending_epoch_q[req_id] == shell_req.epoch);

  assign shell_commit_valid = commit_matches_allocated || commit_matches_req ||
                              pending_matches_req;
  always_comb begin
    if (commit_matches_allocated || commit_matches_req) begin
      shell_commit_tag = adapter_commit_tag;
      shell_commit_epoch = adapter_commit_epoch;
    end else begin
      shell_commit_tag = shell_req.tag;
      shell_commit_epoch = shell_req.epoch;
    end
  end
  assign commit_pending_mask_o = commit_pending_q;

  autoisa_ci_cva6_host_adapter #(
      .TRANS_ID_WIDTH(TRANS_ID_WIDTH), .MAP_ENTRIES(MAP_ENTRIES),
      .STD_SRC_PORTS(STD_SRC_PORTS), .COUNT_WIDTH(COUNT_WIDTH)
  ) i_host_adapter (
      .clk_i(clk_i), .rst_ni(rst_ni), .flush_i(flush_i),
      .issue_valid_i(issue_valid_i), .issue_ready_o(issue_ready_o),
      .issue_instr_i(issue_instr_i), .issue_trans_id_i(issue_trans_id_i),
      .issue_accept_o(issue_accept_o), .issue_recognized_o(issue_recognized_o),
      .issue_illegal_o(issue_illegal_o), .issue_identity_busy_o(),
      .issue_raw_hazard_o(), .issue_waw_hazard_o(),
      .issue_desc_valid_o(host_desc_valid), .issue_desc_ready_i(host_desc_ready),
      .issue_desc_o(host_desc),
      .commit_valid_i(commit_valid_i), .commit_trans_id_i(commit_trans_id_i),
      .commit_kill_i(commit_kill_i), .commit_identity_hit_o(commit_identity_hit_o),
      .shell_commit_valid_o(adapter_commit_valid),
      .shell_commit_tag_o(adapter_commit_tag),
      .shell_commit_epoch_o(adapter_commit_epoch),
      .shell_kill_valid_o(adapter_kill_valid), .shell_kill_tag_o(adapter_kill_tag),
      .shell_kill_epoch_o(adapter_kill_epoch), .shell_flush_o(),
      .shell_result_valid_i(shell_result_valid),
      .shell_result_ready_o(shell_result_ready), .shell_result_i(shell_result),
      .host_result_valid_o(host_result_valid),
      .host_result_ready_i(host_result_ready),
      .host_result_trans_id_o(host_result_trans_id),
      .host_result_dst_valid_o(host_result_dst_valid),
      .host_result_dst_addr_o(host_result_dst_addr),
      .host_result_data_o(host_result_data),
      .host_result_write_policy_o(host_result_write_policy),
      .host_result_status_o(host_result_status),
      .standard_pending_write_mask_i(standard_pending_write_mask_i),
      .std_src_valid_i(std_src_valid_i), .std_src_addr_i(std_src_addr_i),
      .std_dst_valid_i(std_dst_valid_i), .std_dst_addr_i(std_dst_addr_i),
      .std_raw_hazard_o(std_raw_hazard_o), .std_waw_hazard_o(std_waw_hazard_o),
      .destination_busy_mask_o(destination_busy_mask_o),
      .destination_occupancy_o(destination_occupancy_o),
      .destination_high_watermark_o(), .issue_accept_count_o(),
      .issue_reject_count_o(), .stale_result_drop_count_o(),
      .unknown_commit_count_o()
  );

  autoisa_ci_operand_gather #(
      .PENDING_DEPTH(GATHER_DEPTH), .COUNT_WIDTH(COUNT_WIDTH)
  ) i_operand_gather (
      .clk_i(clk_i), .rst_ni(rst_ni), .flush_i(flush_i),
      .desc_valid_i(host_desc_valid), .desc_ready_o(host_desc_ready),
      .desc_i(host_desc), .desc_illegal_o(),
      .rf_req_valid_o(rf_req_valid_o), .rf_req_ready_i(rf_req_ready_i),
      .rf_lane_valid_o(rf_lane_valid_o), .rf_addr_o(rf_addr_o),
      .rf_data_i(rf_data_i), .req_valid_o(shell_req_valid),
      .req_ready_i(shell_req_ready), .req_o(shell_req),
      .kill_valid_i(adapter_kill_valid), .kill_tag_i(adapter_kill_tag),
      .kill_epoch_i(adapter_kill_epoch), .kill_hit_o(),
      .occupancy_o(gather_occupancy_o), .high_watermark_o(),
      .accepted_count_o(), .emitted_count_o(), .gather_beat_count_o(),
      .killed_count_o(), .flush_drop_count_o()
  );

  autoisa_ci_concurrent_shell #(
      .REQUEST_DEPTH(REQUEST_DEPTH), .INFLIGHT_DEPTH(INFLIGHT_DEPTH),
      .RESULT_DEPTH(RESULT_DEPTH), .MULTI_ENGINE(1'b1),
      .COUNT_WIDTH(COUNT_WIDTH)
  ) i_shell (
      .clk_i(clk_i), .rst_ni(rst_ni), .flush_i(flush_i),
      .req_valid_i(shell_req_valid), .req_ready_o(shell_req_ready),
      .req_i(shell_req), .req_duplicate_o(),
      .commit_valid_i(shell_commit_valid), .commit_tag_i(shell_commit_tag),
      .commit_epoch_i(shell_commit_epoch),
      .kill_valid_i(adapter_kill_valid), .kill_tag_i(adapter_kill_tag),
      .kill_epoch_i(adapter_kill_epoch), .kill_hit_o(),
      .result_valid_o(shell_result_valid), .result_ready_i(shell_result_ready),
      .result_o(shell_result), .request_occupancy_o(),
      .request_high_watermark_o(), .inflight_occupancy_o(),
      .inflight_high_watermark_o(), .result_occupancy_o(),
      .result_high_watermark_o(), .reserved_result_credits_o(),
      .credit_high_watermark_o(), .engine_skid_occupancy_o(),
      .engine_skid_high_watermark_o(),
      .accepted_count_o(shell_accepted_count_o), .dispatched_count_o(),
      .engine_started_count_o(), .completion_count_o(),
      .retired_count_o(shell_retired_count_o), .killed_count_o(),
      .orphan_completion_count_o(), .tombstone_drop_count_o(),
      .credit_stall_count_o(), .result_full_stall_count_o(),
      .result_flush_drop_count_o(), .skid_killed_drop_count_o(),
      .skid_flush_drop_count_o()
  );

  autoisa_ci_pair_writeback_serializer #(
      .TRANS_ID_WIDTH(TRANS_ID_WIDTH), .COUNT_WIDTH(COUNT_WIDTH)
  ) i_wb_serializer (
      .clk_i(clk_i), .rst_ni(rst_ni), .flush_i(flush_i),
      .result_valid_i(host_result_valid), .result_ready_o(host_result_ready),
      .result_trans_id_i(host_result_trans_id),
      .result_dst_valid_i(host_result_dst_valid),
      .result_dst_addr_i(host_result_dst_addr), .result_data_i(host_result_data),
      .result_write_policy_i(host_result_write_policy),
      .result_status_i(host_result_status), .wb_valid_o(wb_valid_o),
      .wb_ready_i(wb_ready_i), .wb_trans_id_o(wb_trans_id_o),
      .wb_addr_o(wb_addr_o), .wb_data_o(wb_data_o), .wb_we_o(wb_we_o),
      .wb_last_o(wb_last_o), .wb_status_o(wb_status_o),
      .pair_second_pending_o(), .result_count_o(wb_result_count_o),
      .wb_beat_count_o(wb_beat_count_o)
  );

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      shell_allocated_q <= '0;
      commit_pending_q <= '0;
      allocated_epoch_q <= '0;
      pending_epoch_q <= '0;
    end else if (flush_i) begin
      shell_allocated_q <= '0;
      commit_pending_q <= '0;
    end else begin
      if (shell_req_fire) begin
        shell_allocated_q[req_id] <= 1'b1;
        allocated_epoch_q[req_id] <= shell_req.epoch;
        if (pending_matches_req)
          commit_pending_q[req_id] <= 1'b0;
      end

      if (adapter_commit_valid && adapter_commit_id_in_range) begin
        if (commit_matches_allocated || commit_matches_req) begin
          commit_pending_q[adapter_commit_id] <= 1'b0;
        end else begin
          commit_pending_q[adapter_commit_id] <= 1'b1;
          pending_epoch_q[adapter_commit_id] <= adapter_commit_epoch;
        end
      end

      if (adapter_kill_valid && adapter_kill_id_in_range) begin
        shell_allocated_q[adapter_kill_id] <= 1'b0;
        commit_pending_q[adapter_kill_id] <= 1'b0;
      end
      if (terminal_fire) begin
        shell_allocated_q[host_result_trans_id] <= 1'b0;
        commit_pending_q[host_result_trans_id] <= 1'b0;
      end
    end
  end

  always_ff @(posedge clk_i) begin
    if (rst_ni) begin
      assert (!(adapter_commit_valid && adapter_kill_valid))
        else $error("Host transport observed commit and kill together");
      if (pending_matches_req)
        assert (shell_commit_valid)
          else $error("early Host commit was not replayed at shell allocation");
    end
  end
endmodule

`default_nettype wire
