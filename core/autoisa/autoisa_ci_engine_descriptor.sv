// SPDX-License-Identifier: Apache-2.0
// Static CI-to-physical-engine mapping for the initial two-engine cluster.
`timescale 1ns/1ps
`default_nettype none

module autoisa_ci_engine_descriptor (
    input  wire [autoisa_ci_types_pkg::AUTOISA_CI_ID_WIDTH-1:0] ci_id_i,
    output logic supported_o,
    output logic engine_id_o
);
  always_comb begin
    supported_o = 1'b1;
    engine_id_o = 1'b0;
    unique case (ci_id_i)
      // Compute layouts use engine 0. Protocol/long-latency dummies use
      // engine 1 so the scheduler can demonstrate independent progress.
      8'd0, 8'd1, 8'd2, 8'd3, 8'd4, 8'd5, 8'd6, 8'd7:
        engine_id_o = 1'b0;
      8'd8, 8'd9, 8'd10, 8'd11:
        engine_id_o = 1'b1;
      default: begin
        supported_o = 1'b0;
        engine_id_o = 1'b0;
      end
    endcase
  end
endmodule

`default_nettype wire
