// SPDX-License-Identifier: Apache-2.0
// Convert an AutoISA scalar/pair Host result into CVA6-style scalar WB beats.
`timescale 1ns / 1ps
`default_nettype none

module autoisa_ci_pair_writeback_serializer #(
    parameter int unsigned TRANS_ID_WIDTH = 3,
    parameter int unsigned COUNT_WIDTH = 32
) (
    input wire clk_i,
    input wire rst_ni,
    input wire flush_i,

    input wire result_valid_i,
    output logic result_ready_o,
    input wire [TRANS_ID_WIDTH-1:0] result_trans_id_i,
    input wire [autoisa_ci_types_pkg::AUTOISA_MAX_DST-1:0] result_dst_valid_i,
    input wire [autoisa_ci_types_pkg::AUTOISA_MAX_DST-1:0][4:0] result_dst_addr_i,
    input wire [autoisa_ci_types_pkg::AUTOISA_MAX_DST-1:0][31:0] result_data_i,
    input wire autoisa_ci_types_pkg::autoisa_ci_write_policy_e result_write_policy_i,
    input wire autoisa_ci_types_pkg::autoisa_ci_status_e result_status_i,

    output logic wb_valid_o,
    input wire wb_ready_i,
    output logic [TRANS_ID_WIDTH-1:0] wb_trans_id_o,
    output logic [4:0] wb_addr_o,
    output logic [31:0] wb_data_o,
    output logic wb_we_o,
    output logic wb_last_o,
    output autoisa_ci_types_pkg::autoisa_ci_status_e wb_status_o,

    output logic pair_second_pending_o,
    output logic [COUNT_WIDTH-1:0] result_count_o,
    output logic [COUNT_WIDTH-1:0] wb_beat_count_o
);
  import autoisa_ci_types_pkg::*;

  logic second_q;
  logic pair_result, successful_result, wb_fire;

  assign successful_result = (result_status_i == AUTOISA_STATUS_OK);
  assign pair_result = successful_result &&
                       (result_write_policy_i == AUTOISA_WRITE_PAIR_SERIAL) &&
                       (&result_dst_valid_i);

  // The input remains held by the Host adapter through beat zero.  Its ready
  // only rises with the terminal beat, so destination ownership is not
  // released between the two architectural writes.
  assign wb_valid_o = result_valid_i && !flush_i;
  assign wb_trans_id_o = result_trans_id_i;
  assign wb_addr_o = second_q ? result_dst_addr_i[1] : result_dst_addr_i[0];
  assign wb_data_o = second_q ? result_data_i[1] : result_data_i[0];
  assign wb_we_o = successful_result &&
                   (second_q ? result_dst_valid_i[1] : result_dst_valid_i[0]) &&
                   (result_write_policy_i != AUTOISA_WRITE_NONE);
  assign wb_last_o = !pair_result || second_q;
  assign wb_status_o = result_status_i;
  assign wb_fire = wb_valid_o && wb_ready_i;
  assign result_ready_o = wb_fire && wb_last_o;
  assign pair_second_pending_o = second_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      second_q <= 1'b0;
      result_count_o <= '0;
      wb_beat_count_o <= '0;
    end else if (flush_i) begin
      second_q <= 1'b0;
    end else begin
      if (wb_fire) begin
        wb_beat_count_o <= wb_beat_count_o + 1'b1;
        if (pair_result && !second_q) second_q <= 1'b1;
        else begin
          second_q <= 1'b0;
          result_count_o <= result_count_o + 1'b1;
        end
      end
    end
  end

  logic stalled_q;
  logic [TRANS_ID_WIDTH-1:0] stalled_id_q;
  logic [4:0] stalled_addr_q;
  logic [31:0] stalled_data_q;
  logic stalled_we_q, stalled_last_q;
  autoisa_ci_status_e stalled_status_q;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      stalled_q <= 1'b0;
      stalled_id_q <= '0;
      stalled_addr_q <= '0;
      stalled_data_q <= '0;
      stalled_we_q <= 1'b0;
      stalled_last_q <= 1'b0;
      stalled_status_q <= AUTOISA_STATUS_OK;
    end else begin
      if (stalled_q && !flush_i)
        assert (wb_valid_o && wb_trans_id_o == stalled_id_q &&
                wb_addr_o == stalled_addr_q && wb_data_o == stalled_data_q &&
                wb_we_o == stalled_we_q && wb_last_o == stalled_last_q &&
                wb_status_o == stalled_status_q)
        else $error("AutoISA scalar WB beat changed while stalled");
      stalled_q <= wb_valid_o && !wb_ready_i;
      stalled_id_q <= wb_trans_id_o;
      stalled_addr_q <= wb_addr_o;
      stalled_data_q <= wb_data_o;
      stalled_we_q <= wb_we_o;
      stalled_last_q <= wb_last_o;
      stalled_status_q <= wb_status_o;
    end
  end
endmodule

`default_nettype wire
