// SPDX-License-Identifier: Apache-2.0
// Protocol wrapper around generated D0-D7 semantics and D8-D11 stress cases.
`timescale 1ns / 1ps
`default_nettype none

module autoisa_ci_dummy_engine (
    input wire clk_i,
    input wire rst_ni,
    input wire req_valid_i,
    output logic req_ready_o,
    input autoisa_ci_types_pkg::autoisa_ci_req_t req_i,
    output logic rsp_valid_o,
    input wire rsp_ready_i,
    output autoisa_ci_types_pkg::autoisa_ci_rsp_t rsp_o
);
  import autoisa_ci_types_pkg::*;

  logic busy_q;
  logic [4:0] cycles_left_q;
  autoisa_ci_rsp_t rsp_q;
  logic semantic_supported;
  logic [4:0] semantic_latency;
  logic [1:0] semantic_result_valid;
  logic [1:0][31:0] semantic_results;
  logic [4:0] selected_latency;
  autoisa_ci_rsp_t selected_rsp;

  autoisa_ci_semantic_engine i_semantic_engine (
      .ci_id_i(req_i.ci_id),
      .operands_i(req_i.operands),
      .immediate_i(req_i.immediate),
      .supported_o(semantic_supported),
      .latency_o(semantic_latency),
      .result_valid_o(semantic_result_valid),
      .results_o(semantic_results)
  );

  always_comb begin
    selected_latency = semantic_supported ? semantic_latency : 5'd1;
    selected_rsp = '0;
    selected_rsp.tag = req_i.tag;
    selected_rsp.epoch = req_i.epoch;
    selected_rsp.status = AUTOISA_STATUS_OK;
    if (semantic_supported) begin
      selected_rsp.result_valid = semantic_result_valid;
      selected_rsp.results = semantic_results;
    end else begin
      unique case (req_i.ci_id)
        8'd8: begin
          selected_latency = {2'b00, req_i.operands[0][2:0]} + 1'b1;
          selected_rsp.result_valid = 2'b01;
          selected_rsp.results[0] = req_i.operands[0] + req_i.operands[1];
        end
        8'd9: begin
          selected_latency = 5'd16;
          selected_rsp.result_valid = 2'b01;
          selected_rsp.results[0] = req_i.operands[0] ^ req_i.operands[1];
        end
        8'd10: begin
          selected_latency = 5'd2;
          selected_rsp.result_valid = 2'b01;
          selected_rsp.results[0] = req_i.operands[0] + req_i.operands[1];
        end
        8'd11:   selected_rsp.status = AUTOISA_STATUS_ENGINE_FAULT;
        default: selected_rsp.status = AUTOISA_STATUS_UNSUPPORTED;
      endcase
    end
  end

  assign req_ready_o = !busy_q;
  assign rsp_valid_o = busy_q && (cycles_left_q == 5'd0);
  assign rsp_o = rsp_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      busy_q <= 1'b0;
      cycles_left_q <= '0;
      rsp_q <= '0;
    end else begin
      if (req_valid_i && req_ready_o) begin
        busy_q <= 1'b1;
        cycles_left_q <= selected_latency - 1'b1;
        rsp_q <= selected_rsp;
      end else if (busy_q && (cycles_left_q != 5'd0)) begin
        cycles_left_q <= cycles_left_q - 1'b1;
      end else if (rsp_valid_o && rsp_ready_i) begin
        busy_q <= 1'b0;
      end
    end
  end

endmodule

`default_nettype wire
