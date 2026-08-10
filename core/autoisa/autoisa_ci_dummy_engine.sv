// SPDX-License-Identifier: Apache-2.0
// Pure-compute reference engine for dummy semantics D0-D7.
`timescale 1ns/1ps
`default_nettype none

module autoisa_ci_dummy_engine (
    input  wire clk_i,
    input  wire rst_ni,
    input  wire req_valid_i,
    output logic req_ready_o,
    input  autoisa_ci_types_pkg::autoisa_ci_req_t req_i,
    output logic rsp_valid_o,
    input  wire rsp_ready_i,
    output autoisa_ci_types_pkg::autoisa_ci_rsp_t rsp_o
);
  import autoisa_ci_types_pkg::*;

  logic busy_q;
  logic [4:0] cycles_left_q;
  autoisa_ci_rsp_t rsp_q;

  function automatic logic [4:0] latency_for(input autoisa_ci_req_t req);
    unique case (req.ci_id)
      8'd0: latency_for = 5'd1;
      8'd1: latency_for = 5'd2;
      8'd2: latency_for = 5'd3;
      8'd3: latency_for = 5'd2;
      8'd4: latency_for = 5'd4;
      8'd5: latency_for = 5'd3;
      8'd6: latency_for = 5'd5;
      8'd7: latency_for = 5'd1;
      8'd8: latency_for = {2'b00, req.operands[0][2:0]} + 1'b1;
      8'd9: latency_for = 5'd16;
      8'd10: latency_for = 5'd2;
      8'd11: latency_for = 5'd1;
      default: latency_for = 5'd1;
    endcase
  endfunction

  function automatic autoisa_ci_rsp_t execute(input autoisa_ci_req_t req);
    autoisa_ci_rsp_t result;
    logic [31:0] ab;
    logic [4:0] shamt;
    begin
      result = '0;
      result.tag = req.tag;
      result.epoch = req.epoch;
      result.status = AUTOISA_STATUS_OK;
      unique case (req.ci_id)
        8'd0: begin
          result.result_valid = 2'b01;
          result.results[0] = req.operands[0] + req.operands[1];
        end
        8'd1: begin
          result.result_valid = 2'b01;
          result.results[0] = (req.operands[0] * req.operands[1]) + req.operands[2];
        end
        8'd2: begin
          result.result_valid = 2'b01;
          result.results[0] = ((req.operands[0] * req.operands[1]) +
                               req.operands[2]) ^ req.operands[3];
        end
        8'd3: begin
          result.result_valid = 2'b11;
          result.results[0] = req.operands[0] + req.operands[1];
          result.results[1] = req.operands[0] - req.operands[1];
        end
        8'd4: begin
          result.result_valid = 2'b11;
          result.results[0] = (req.operands[0] * req.operands[2]) -
                              (req.operands[1] * req.operands[3]);
          result.results[1] = (req.operands[0] * req.operands[3]) +
                              (req.operands[1] * req.operands[2]);
        end
        8'd5: begin
          result.result_valid = 2'b01;
          result.results[0] = req.operands[0] + req.operands[1] +
                              req.operands[2] + req.operands[3] +
                              req.operands[4] + req.operands[5];
        end
        8'd6: begin
          ab = req.operands[0] * req.operands[1];
          result.result_valid = 2'b11;
          result.results[0] = ab + (req.operands[2] * req.operands[3]) +
                              (req.operands[4] * req.operands[5]);
          result.results[1] = ab - (req.operands[2] * req.operands[3]) +
                              (req.operands[4] * req.operands[5]);
        end
        8'd7: begin
          shamt = req.immediate[4:0];
          result.result_valid = 2'b01;
          result.results[0] = (req.operands[0] << shamt) ^
                              (req.operands[1] + req.immediate);
        end
        8'd9: begin
          result.result_valid = 2'b01;
          result.results[0] = req.operands[0] ^ req.operands[1];
        end
        8'd8: begin
          result.result_valid = 2'b01;
          result.results[0] = req.operands[0] + req.operands[1];
        end
        8'd10: begin
          result.result_valid = 2'b01;
          result.results[0] = req.operands[0] + req.operands[1];
        end
        8'd11: begin
          result.result_valid = 2'b00;
          result.status = AUTOISA_STATUS_ENGINE_FAULT;
        end
        default: begin
          result.status = AUTOISA_STATUS_UNSUPPORTED;
        end
      endcase
      execute = result;
    end
  endfunction

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
        cycles_left_q <= latency_for(req_i) - 1'b1;
        rsp_q <= execute(req_i);
      end else if (busy_q && (cycles_left_q != 5'd0)) begin
        cycles_left_q <= cycles_left_q - 1'b1;
      end else if (rsp_valid_o && rsp_ready_i) begin
        busy_q <= 1'b0;
      end
    end
  end

endmodule

`default_nettype wire
