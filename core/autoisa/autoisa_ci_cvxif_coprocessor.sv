// SPDX-License-Identifier: Apache-2.0
// Native CV-X-IF bridge for the scalar 2R/3R AutoISA subset.
`timescale 1ns/1ps
`default_nettype none

module autoisa_ci_cvxif_coprocessor #(
    parameter int unsigned NR_RS = 2,
    parameter int unsigned XLEN = 32,
    parameter int unsigned TRANS_ID_WIDTH = 3,
    parameter type hartid_t = logic [XLEN-1:0],
    parameter type x_issue_req_t = logic,
    parameter type x_issue_resp_t = logic,
    parameter type x_register_t = logic,
    parameter type x_commit_t = logic,
    parameter type x_result_t = logic,
    parameter type cvxif_req_t = logic,
    parameter type cvxif_resp_t = logic,
    parameter int unsigned TRANS_IDS = 1 << TRANS_ID_WIDTH
) (
    input  wire clk_i,
    input  wire rst_ni,
    input  cvxif_req_t cvxif_req_i,
    output cvxif_resp_t cvxif_resp_o
);
  import autoisa_ci_types_pkg::*;

  autoisa_ci_host_desc_t decoded_desc;
  autoisa_ci_req_t shell_req;
  autoisa_ci_rsp_t shell_result;
  logic decoded_valid, decoded_illegal, engine_supported, unused_engine_id;
  logic native_eligible, source_shape_supported, operands_valid;
  logic shell_req_valid, shell_req_ready, shell_req_fire;
  logic shell_result_valid, shell_result_fire;
  logic [TRANS_IDS-1:0] live_q;
  logic [TRANS_IDS-1:0] committed_q;
  logic [TRANS_IDS-1:0][AUTOISA_EPOCH_WIDTH-1:0] epoch_q;
  logic [TRANS_IDS-1:0][4:0] rd_q;
  hartid_t hartid_q [TRANS_IDS];
  logic [TRANS_ID_WIDTH-1:0] issue_id, commit_id, result_id;
  logic commit_valid, kill_valid;
  logic commit_matches_issue, commit_live;
  logic [AUTOISA_TAG_WIDTH-1:0] commit_tag;
  logic [AUTOISA_EPOCH_WIDTH-1:0] commit_epoch;

  assign issue_id = cvxif_req_i.issue_req.id;
  assign commit_id = cvxif_req_i.commit.id;
  assign result_id = shell_result.tag[TRANS_ID_WIDTH-1:0];

  autoisa_ci_layout_decoder_v2 i_decoder (
      .instr_i(cvxif_req_i.issue_req.instr),
      .tag_i({{(AUTOISA_TAG_WIDTH-TRANS_ID_WIDTH){1'b0}}, issue_id}),
      .epoch_i(epoch_q[issue_id]), .valid_o(decoded_valid),
      .illegal_o(decoded_illegal), .desc_o(decoded_desc)
  );

  autoisa_ci_engine_descriptor i_descriptor (
      .ci_id_i(decoded_desc.ci_id), .supported_o(engine_supported),
      .engine_id_o(unused_engine_id)
  );

  always_comb begin
    source_shape_supported = 1'b1;
    operands_valid = 1'b1;
    for (int unsigned i = 0; i < AUTOISA_MAX_SRC; i++) begin
      if ((i >= NR_RS) && decoded_desc.src_valid[i])
        source_shape_supported = 1'b0;
      if ((i < NR_RS) && decoded_desc.src_valid[i] &&
          !cvxif_req_i.register.rs_valid[i])
        operands_valid = 1'b0;
    end
  end

  assign native_eligible = decoded_valid && !decoded_illegal && engine_supported &&
      (decoded_desc.backend == AUTOISA_CVXIF_NATIVE) &&
      (decoded_desc.dst_valid == 2'b01) && source_shape_supported;

  always_comb begin
    cvxif_resp_o = '0;
    cvxif_resp_o.compressed_ready = 1'b1;
    cvxif_resp_o.issue_ready = native_eligible ?
        (cvxif_req_i.register_valid && operands_valid && !live_q[issue_id] &&
         shell_req_ready) : 1'b1;
    cvxif_resp_o.register_ready = cvxif_resp_o.issue_ready;
    cvxif_resp_o.issue_resp.accept = native_eligible && operands_valid &&
                                     !live_q[issue_id];
    cvxif_resp_o.issue_resp.writeback = '0;
    cvxif_resp_o.issue_resp.writeback[0] = native_eligible;
    cvxif_resp_o.issue_resp.register_read = '0;
    for (int unsigned i = 0; i < NR_RS; i++)
      cvxif_resp_o.issue_resp.register_read[i] =
          native_eligible && decoded_desc.src_valid[i];

    cvxif_resp_o.result_valid = shell_result_valid;
    cvxif_resp_o.result.hartid = hartid_q[result_id];
    cvxif_resp_o.result.id = result_id;
    cvxif_resp_o.result.data = shell_result.results[0];
    cvxif_resp_o.result.rd = rd_q[result_id];
    cvxif_resp_o.result.we = '0;
    cvxif_resp_o.result.we[0] = shell_result_valid &&
                                (shell_result.status == AUTOISA_STATUS_OK) &&
                                shell_result.result_valid[0];
  end

  always_comb begin
    shell_req = '0;
    shell_req.tag = decoded_desc.tag;
    shell_req.epoch = decoded_desc.epoch;
    shell_req.ci_id = decoded_desc.ci_id;
    shell_req.operand_valid = decoded_desc.src_valid;
    shell_req.imm_valid = decoded_desc.imm_valid;
    shell_req.immediate = decoded_desc.immediate;
    for (int unsigned i = 0; i < NR_RS; i++)
      if (i < AUTOISA_MAX_SRC)
        shell_req.operands[i] = cvxif_req_i.register.rs[i][31:0];
  end
  assign shell_req_valid = cvxif_req_i.issue_valid &&
                           cvxif_req_i.register_valid && native_eligible &&
                           operands_valid && !live_q[issue_id];
  assign shell_req_fire = shell_req_valid && shell_req_ready;

  assign commit_tag = {{(AUTOISA_TAG_WIDTH-TRANS_ID_WIDTH){1'b0}}, commit_id};
  assign commit_epoch = epoch_q[commit_id];
  assign commit_matches_issue = shell_req_fire && (issue_id == commit_id);
  assign commit_live = live_q[commit_id] || commit_matches_issue;
  assign commit_valid = cvxif_req_i.commit_valid &&
                        !cvxif_req_i.commit.commit_kill && commit_live &&
                        (!committed_q[commit_id] || commit_matches_issue);
  assign kill_valid = cvxif_req_i.commit_valid &&
                      cvxif_req_i.commit.commit_kill && commit_live;
  assign shell_result_fire = shell_result_valid && cvxif_req_i.result_ready;

  autoisa_ci_concurrent_shell #(
      .REQUEST_DEPTH(4), .INFLIGHT_DEPTH(4), .RESULT_DEPTH(4),
      .MULTI_ENGINE(1'b1), .COUNT_WIDTH(32)
  ) i_shell (
      .clk_i(clk_i), .rst_ni(rst_ni), .flush_i(1'b0),
      .req_valid_i(shell_req_valid), .req_ready_o(shell_req_ready),
      .req_i(shell_req), .req_duplicate_o(),
      .commit_valid_i(commit_valid), .commit_tag_i(commit_tag),
      .commit_epoch_i(commit_epoch), .kill_valid_i(kill_valid),
      .kill_tag_i(commit_tag), .kill_epoch_i(commit_epoch), .kill_hit_o(),
      .result_valid_o(shell_result_valid),
      .result_ready_i(cvxif_req_i.result_ready), .result_o(shell_result),
      .request_occupancy_o(), .request_high_watermark_o(),
      .inflight_occupancy_o(), .inflight_high_watermark_o(),
      .result_occupancy_o(), .result_high_watermark_o(),
      .reserved_result_credits_o(), .credit_high_watermark_o(),
      .engine_skid_occupancy_o(), .engine_skid_high_watermark_o(),
      .accepted_count_o(), .dispatched_count_o(), .engine_started_count_o(),
      .completion_count_o(), .retired_count_o(), .killed_count_o(),
      .orphan_completion_count_o(), .tombstone_drop_count_o(),
      .credit_stall_count_o(), .result_full_stall_count_o(),
      .result_flush_drop_count_o(), .skid_killed_drop_count_o(),
      .skid_flush_drop_count_o()
  );

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      live_q <= '0;
      committed_q <= '0;
      epoch_q <= '0;
      rd_q <= '0;
      for (int unsigned i = 0; i < TRANS_IDS; i++)
        hartid_q[i] <= '0;
    end else begin
      if (shell_req_fire) begin
        live_q[issue_id] <= 1'b1;
        committed_q[issue_id] <= 1'b0;
        rd_q[issue_id] <= decoded_desc.dst_addr[0];
        hartid_q[issue_id] <= cvxif_req_i.issue_req.hartid;
      end
      if (commit_valid)
        committed_q[commit_id] <= 1'b1;
      if (kill_valid && live_q[commit_id]) begin
        live_q[commit_id] <= 1'b0;
        committed_q[commit_id] <= 1'b0;
        epoch_q[commit_id] <= epoch_q[commit_id] + 1'b1;
      end else if (shell_result_fire) begin
        live_q[result_id] <= 1'b0;
        committed_q[result_id] <= 1'b0;
        epoch_q[result_id] <= epoch_q[result_id] + 1'b1;
      end
    end
  end

  initial begin
    assert (XLEN == 32) else $error("AutoISA CV-X-IF bridge currently requires XLEN=32");
    assert (NR_RS >= 2 && NR_RS <= 3)
      else $error("AutoISA CV-X-IF bridge supports two or three CV-X-IF operands");
    assert (TRANS_ID_WIDTH <= AUTOISA_TAG_WIDTH)
      else $error("CV-X-IF id must fit AutoISA tag");
  end
endmodule

`default_nettype wire
