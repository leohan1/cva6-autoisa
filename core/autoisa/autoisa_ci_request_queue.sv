// SPDX-License-Identifier: Apache-2.0
// Parameterized ready/valid ingress queue for canonical AutoISA CI requests.
`timescale 1ns / 1ps
`default_nettype none

module autoisa_ci_request_queue #(
    parameter int unsigned DEPTH       = 4,
    parameter int unsigned COUNT_WIDTH = 32,
    parameter int unsigned PTR_WIDTH   = (DEPTH > 1) ? $clog2(DEPTH) : 1,
    parameter int unsigned OCC_WIDTH   = $clog2(DEPTH + 1)
) (
    input wire clk_i,
    input wire rst_ni,
    input wire flush_i,

    input wire in_valid_i,
    output logic in_ready_o,
    input autoisa_ci_types_pkg::autoisa_ci_req_t in_req_i,

    input wire identity_query_valid_i,
    input wire [autoisa_ci_types_pkg::AUTOISA_TAG_WIDTH-1:0] identity_query_tag_i,
    input wire [autoisa_ci_types_pkg::AUTOISA_EPOCH_WIDTH-1:0] identity_query_epoch_i,
    output logic identity_query_match_o,

    output logic out_valid_o,
    input wire out_ready_i,
    output autoisa_ci_types_pkg::autoisa_ci_req_t out_req_o,

    output logic [  OCC_WIDTH-1:0] occupancy_o,
    output logic [  OCC_WIDTH-1:0] high_watermark_o,
    output logic [COUNT_WIDTH-1:0] enqueue_count_o,
    output logic [COUNT_WIDTH-1:0] dequeue_count_o,
    output logic [COUNT_WIDTH-1:0] full_stall_count_o
);
  import autoisa_ci_types_pkg::*;

  autoisa_ci_req_t mem_q[0:DEPTH-1];
  logic [DEPTH-1:0] entry_valid_q;
  logic [PTR_WIDTH-1:0] read_ptr_q, write_ptr_q;
  logic [OCC_WIDTH-1:0] occupancy_q, occupancy_d;
  logic enqueue, dequeue, bypass, push_mem, pop_mem;

  assign out_valid_o = !flush_i && ((occupancy_q != '0) || in_valid_i);
  assign out_req_o = (occupancy_q != '0) ? mem_q[read_ptr_q] : in_req_i;

  // A full queue can accept a replacement when its current head is consumed.
  assign in_ready_o = !flush_i &&
                      ((occupancy_q < DEPTH) ||
                       ((occupancy_q == DEPTH) && out_ready_i && out_valid_o));
  assign enqueue = in_valid_i && in_ready_o;
  assign dequeue = out_valid_o && out_ready_i;
  assign bypass = (occupancy_q == '0) && enqueue && dequeue;
  assign push_mem = enqueue && !bypass;
  assign pop_mem = dequeue && (occupancy_q != '0);

  always_comb begin
    occupancy_d = occupancy_q;
    unique case ({
      push_mem, pop_mem
    })
      2'b10:   occupancy_d = occupancy_q + 1'b1;
      2'b01:   occupancy_d = occupancy_q - 1'b1;
      default: occupancy_d = occupancy_q;
    endcase
  end

  assign occupancy_o = occupancy_q;

  integer query_i;
  always_comb begin
    identity_query_match_o = 1'b0;
    for (query_i = 0; query_i < DEPTH; query_i = query_i + 1) begin
      if (identity_query_valid_i && entry_valid_q[query_i] &&
          (mem_q[query_i].tag == identity_query_tag_i) &&
          (mem_q[query_i].epoch == identity_query_epoch_i))
        identity_query_match_o = 1'b1;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      read_ptr_q <= '0;
      write_ptr_q <= '0;
      occupancy_q <= '0;
      entry_valid_q <= '0;
      high_watermark_o <= '0;
      enqueue_count_o <= '0;
      dequeue_count_o <= '0;
      full_stall_count_o <= '0;
    end else begin
      if (in_valid_i && !in_ready_o) full_stall_count_o <= full_stall_count_o + 1'b1;
      if (enqueue) enqueue_count_o <= enqueue_count_o + 1'b1;
      if (dequeue) dequeue_count_o <= dequeue_count_o + 1'b1;

      if (flush_i) begin
        read_ptr_q <= '0;
        write_ptr_q <= '0;
        occupancy_q <= '0;
        entry_valid_q <= '0;
        high_watermark_o <= '0;
      end else begin
        occupancy_q <= occupancy_d;
        if (occupancy_d > high_watermark_o) high_watermark_o <= occupancy_d;

        if (push_mem) begin
          mem_q[write_ptr_q] <= in_req_i;
          entry_valid_q[write_ptr_q] <= 1'b1;
          if (write_ptr_q == (DEPTH - 1)) write_ptr_q <= '0;
          else write_ptr_q <= write_ptr_q + 1'b1;
        end

        if (pop_mem) begin
          entry_valid_q[read_ptr_q] <= 1'b0;
          if (read_ptr_q == (DEPTH - 1)) read_ptr_q <= '0;
          else read_ptr_q <= read_ptr_q + 1'b1;
        end

        // When full, read_ptr_q == write_ptr_q. A simultaneous replacement
        // leaves that physical slot valid with the newly enqueued request.
        if (push_mem && pop_mem && (write_ptr_q == read_ptr_q)) entry_valid_q[write_ptr_q] <= 1'b1;
      end
    end
  end

`ifndef SYNTHESIS
  logic output_stalled_q;
  autoisa_ci_req_t stalled_req_q;

  initial begin
    assert ((DEPTH == 1) || (DEPTH == 2) || (DEPTH == 4) || (DEPTH == 8))
    else $error("autoisa_ci_request_queue DEPTH must be 1, 2, 4, or 8");
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      output_stalled_q <= 1'b0;
      stalled_req_q <= '0;
    end else begin
      assert (occupancy_q <= DEPTH)
      else $error("autoisa_ci_request_queue occupancy overflow");
      if (output_stalled_q && !flush_i) begin
        assert (out_valid_o && (out_req_o == stalled_req_q))
        else $error("autoisa_ci_request_queue output changed while stalled");
      end
      output_stalled_q <= out_valid_o && !out_ready_i;
      if (out_valid_o && !out_ready_i) stalled_req_q <= out_req_o;
    end
  end
`endif

endmodule

`default_nettype wire
