// SPDX-License-Identifier: Apache-2.0
// Functional AutoISA CI Harness slice: decode -> pure compute -> commit/kill gate.
// This v0 intentionally supports one live transaction. Its public tag/epoch and
// canonical request/result ABI are retained for the multi-inflight v1 upgrade.
`timescale 1ns/1ps
`default_nettype none

module autoisa_ci_harness_v0 (
    input  wire clk_i,
    input  wire rst_ni,
    input  wire issue_valid_i,
    output logic issue_ready_o,
    input  wire [31:0] issue_instr_i,
    input  wire [autoisa_ci_types_pkg::AUTOISA_TAG_WIDTH-1:0] issue_tag_i,
    input  wire [autoisa_ci_types_pkg::AUTOISA_EPOCH_WIDTH-1:0] issue_epoch_i,
    input  wire [autoisa_ci_types_pkg::AUTOISA_MAX_SRC-1:0][31:0] issue_operands_i,
    output logic issue_accept_o,
    output logic issue_reject_o,
    output autoisa_ci_types_pkg::autoisa_ci_status_e issue_reject_status_o,
    output autoisa_ci_types_pkg::autoisa_ci_host_desc_t issue_desc_o,
    input  wire commit_valid_i,
    input  wire [autoisa_ci_types_pkg::AUTOISA_TAG_WIDTH-1:0] commit_tag_i,
    input  wire [autoisa_ci_types_pkg::AUTOISA_EPOCH_WIDTH-1:0] commit_epoch_i,
    input  wire kill_valid_i,
    input  wire [autoisa_ci_types_pkg::AUTOISA_TAG_WIDTH-1:0] kill_tag_i,
    input  wire [autoisa_ci_types_pkg::AUTOISA_EPOCH_WIDTH-1:0] kill_epoch_i,
    output logic result_valid_o,
    input  wire result_ready_i,
    output autoisa_ci_types_pkg::autoisa_ci_rsp_t result_o,
    output logic killed_o,
    output logic busy_o
);
  import autoisa_ci_types_pkg::*;

  logic decode_valid, decode_illegal, semantic_supported;
  autoisa_ci_host_desc_t decoded_desc;
  autoisa_ci_host_desc_t active_desc_q;
  autoisa_ci_req_t engine_req;
  autoisa_ci_rsp_t engine_rsp, result_q;
  logic engine_req_valid, engine_req_ready;
  logic engine_rsp_valid, engine_rsp_ready;
  logic live_q, commit_seen_q, killed_q, engine_done_q;
  logic commit_matches, kill_matches;

  autoisa_ci_layout_decoder_v2 i_decoder (
      .instr_i(issue_instr_i), .tag_i(issue_tag_i), .epoch_i(issue_epoch_i),
      .valid_o(decode_valid), .illegal_o(decode_illegal), .desc_o(decoded_desc)
  );

  always_comb begin
    semantic_supported = 1'b0;
    unique case (decoded_desc.layout_id)
      4'd0: semantic_supported = decoded_desc.ci_id == 8'd0;
      4'd1: semantic_supported = decoded_desc.ci_id == 8'd1;
      4'd2: semantic_supported = decoded_desc.ci_id == 8'd2;
      4'd3: semantic_supported = decoded_desc.ci_id == 8'd3;
      4'd4: semantic_supported = decoded_desc.ci_id == 8'd4;
      4'd5: semantic_supported = decoded_desc.ci_id == 8'd5;
      4'd6: semantic_supported = decoded_desc.ci_id == 8'd6;
      4'd7: semantic_supported = decoded_desc.ci_id == 8'd7;
      default: semantic_supported = 1'b0;
    endcase
  end

  always_comb begin
    engine_req = '0;
    engine_req.tag = decoded_desc.tag;
    engine_req.epoch = decoded_desc.epoch;
    engine_req.ci_id = decoded_desc.ci_id;
    engine_req.operand_valid = decoded_desc.src_valid;
    engine_req.imm_valid = decoded_desc.imm_valid;
    engine_req.immediate = decoded_desc.immediate;
    for (int unsigned i = 0; i < AUTOISA_MAX_SRC; i++) begin
      engine_req.operands[i] = (decoded_desc.src_addr[i] == 5'd0) ?
                               32'd0 : issue_operands_i[i];
    end
  end

  assign issue_ready_o = !live_q && engine_req_ready;
  assign issue_accept_o = issue_valid_i && issue_ready_o && decode_valid &&
                          !decode_illegal && semantic_supported;
  assign issue_reject_o = issue_valid_i && issue_ready_o && !issue_accept_o;
  assign issue_reject_status_o = (!decode_valid || decode_illegal) ?
                                 AUTOISA_STATUS_ILLEGAL :
                                 AUTOISA_STATUS_UNSUPPORTED;
  assign issue_desc_o = decoded_desc;
  assign engine_req_valid = issue_accept_o;

  assign commit_matches = commit_valid_i && live_q &&
                          (commit_tag_i == active_desc_q.tag) &&
                          (commit_epoch_i == active_desc_q.epoch);
  assign kill_matches = kill_valid_i && live_q &&
                        (kill_tag_i == active_desc_q.tag) &&
                        (kill_epoch_i == active_desc_q.epoch);
  assign engine_rsp_ready = live_q && !engine_done_q;
  assign result_valid_o = live_q && engine_done_q && commit_seen_q &&
                          !killed_q && !kill_matches;
  assign result_o = result_q;
  assign busy_o = live_q;

  autoisa_ci_dummy_engine i_dummy_engine (
      .clk_i, .rst_ni, .req_valid_i(engine_req_valid),
      .req_ready_o(engine_req_ready), .req_i(engine_req),
      .rsp_valid_o(engine_rsp_valid), .rsp_ready_i(engine_rsp_ready),
      .rsp_o(engine_rsp)
  );

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      active_desc_q <= '0;
      result_q <= '0;
      live_q <= 1'b0;
      commit_seen_q <= 1'b0;
      killed_q <= 1'b0;
      engine_done_q <= 1'b0;
      killed_o <= 1'b0;
    end else begin
      killed_o <= 1'b0;
      if (issue_accept_o) begin
        active_desc_q <= decoded_desc;
        live_q <= 1'b1;
        commit_seen_q <= 1'b0;
        killed_q <= 1'b0;
        engine_done_q <= 1'b0;
      end
      if (commit_matches && !kill_matches) commit_seen_q <= 1'b1;
      if (engine_rsp_valid && engine_rsp_ready) begin
        result_q <= engine_rsp;
        engine_done_q <= 1'b1;
      end

      // Kill has priority over commit, engine completion and writeback.
      if (kill_matches) begin
        killed_q <= 1'b1;
        if (engine_done_q || (engine_rsp_valid && engine_rsp_ready)) begin
          live_q <= 1'b0;
          killed_o <= 1'b1;
        end
      end else if (killed_q &&
                   (engine_done_q || (engine_rsp_valid && engine_rsp_ready))) begin
        live_q <= 1'b0;
        killed_o <= 1'b1;
      end else if (result_valid_o && result_ready_i) begin
        live_q <= 1'b0;
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
      assert (!(killed_q && result_valid_o))
        else $error("killed transaction exposed a result");
      if (result_stalled_q && !kill_matches) begin
        assert (result_valid_o && (result_o == stalled_result_q))
          else $error("result payload changed while backpressured");
      end
      result_stalled_q <= result_valid_o && !result_ready_i;
      if (result_valid_o && !result_ready_i) stalled_result_q <= result_o;
    end
  end
`endif

endmodule

`default_nettype wire
