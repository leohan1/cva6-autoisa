// SPDX-License-Identifier: Apache-2.0
// Multi-entry transaction tracking for the AutoISA compute-only CI path.
`timescale 1ns / 1ps
`default_nettype none

module autoisa_ci_inflight_table #(
    parameter int unsigned DEPTH       = 4,
    parameter int unsigned COUNT_WIDTH = 32,
    parameter int unsigned INDEX_WIDTH = (DEPTH > 1) ? $clog2(DEPTH) : 1,
    parameter int unsigned OCC_WIDTH   = $clog2(DEPTH + 1)
) (
    input wire clk_i,
    input wire rst_ni,
    input wire flush_i,

    input wire alloc_valid_i,
    output logic alloc_ready_o,
    input autoisa_ci_types_pkg::autoisa_ci_req_t alloc_req_i,
    output logic alloc_duplicate_o,

    output logic dispatch_valid_o,
    input wire dispatch_ready_i,
    output autoisa_ci_types_pkg::autoisa_ci_req_t dispatch_req_o,

    input wire complete_valid_i,
    output logic complete_ready_o,
    input autoisa_ci_types_pkg::autoisa_ci_rsp_t complete_rsp_i,

    input wire commit_valid_i,
    input wire [autoisa_ci_types_pkg::AUTOISA_TAG_WIDTH-1:0] commit_tag_i,
    input wire [autoisa_ci_types_pkg::AUTOISA_EPOCH_WIDTH-1:0] commit_epoch_i,

    input wire kill_valid_i,
    input wire [autoisa_ci_types_pkg::AUTOISA_TAG_WIDTH-1:0] kill_tag_i,
    input wire [autoisa_ci_types_pkg::AUTOISA_EPOCH_WIDTH-1:0] kill_epoch_i,
    input wire kill_wait_completion_i,
    output logic kill_hit_o,
    output logic kill_dispatched_o,

    output logic retire_valid_o,
    input wire retire_ready_i,
    output autoisa_ci_types_pkg::autoisa_ci_rsp_t retire_rsp_o,

    output logic [  OCC_WIDTH-1:0] occupancy_o,
    output logic [  OCC_WIDTH-1:0] high_watermark_o,
    output logic [COUNT_WIDTH-1:0] allocated_count_o,
    output logic [COUNT_WIDTH-1:0] retired_count_o,
    output logic [COUNT_WIDTH-1:0] killed_count_o,
    output logic [COUNT_WIDTH-1:0] orphan_completion_count_o
);
  import autoisa_ci_types_pkg::*;

  logic [DEPTH-1:0] valid_q, valid_d;
  logic [DEPTH-1:0] dispatched_q, dispatched_d;
  logic [DEPTH-1:0] completed_q, completed_d;
  logic [DEPTH-1:0] committed_q, committed_d;
  // A dispatched kill retains its identity until the late engine response is
  // absorbed. This prevents same-epoch tag reuse from creating an ABA match.
  logic [DEPTH-1:0] killed_q, killed_d;
  autoisa_ci_req_t req_q[0:DEPTH-1];
  autoisa_ci_req_t req_d[0:DEPTH-1];
  autoisa_ci_rsp_t rsp_q[0:DEPTH-1];
  autoisa_ci_rsp_t rsp_d[0:DEPTH-1];
  logic [COUNT_WIDTH-1:0] age_q[0:DEPTH-1];
  logic [COUNT_WIDTH-1:0] age_d[0:DEPTH-1];
  logic [COUNT_WIDTH-1:0] next_age_q, next_age_d;

  logic free_found, duplicate_found;
  logic dispatch_found, completion_found, commit_found, kill_found;
  logic retire_found;
  logic [INDEX_WIDTH-1:0] free_index, dispatch_index;
  logic [INDEX_WIDTH-1:0] completion_index, commit_index, kill_index;
  logic [INDEX_WIDTH-1:0] retire_index;
  logic [COUNT_WIDTH-1:0] dispatch_age, retire_age;
  logic retire_lock_q, retire_lock_d;
  logic [INDEX_WIDTH-1:0] retire_lock_index_q, retire_lock_index_d;
  logic [OCC_WIDTH-1:0] occupancy_next;
  logic [OCC_WIDTH-1:0] flush_kill_count;
  logic alloc_fire, dispatch_fire, complete_fire, retire_fire;
  logic   completion_killed;

  integer scan_i;
  integer next_i;
  integer seq_i;
  always_comb begin
    free_found = 1'b0;
    free_index = '0;
    duplicate_found = 1'b0;
    dispatch_found = 1'b0;
    dispatch_index = '0;
    dispatch_age = '1;
    completion_found = 1'b0;
    completion_index = '0;
    commit_found = 1'b0;
    commit_index = '0;
    kill_found = 1'b0;
    kill_index = '0;
    retire_found = 1'b0;
    retire_index = '0;
    retire_age = '1;
    occupancy_o = '0;
    flush_kill_count = '0;

    for (scan_i = 0; scan_i < DEPTH; scan_i = scan_i + 1) begin
      if (valid_q[scan_i]) occupancy_o = occupancy_o + 1'b1;
      if (valid_q[scan_i] && !killed_q[scan_i]) flush_kill_count = flush_kill_count + 1'b1;
      if (!valid_q[scan_i] && !free_found) begin
        free_found = 1'b1;
        free_index = INDEX_WIDTH'(scan_i);
      end
      if (valid_q[scan_i] &&
          (req_q[scan_i].tag == alloc_req_i.tag) &&
          (req_q[scan_i].epoch == alloc_req_i.epoch))
        duplicate_found = 1'b1;
      if (valid_q[scan_i] && !dispatched_q[scan_i] &&
          (!dispatch_found || (age_q[scan_i] < dispatch_age))) begin
        dispatch_found = 1'b1;
        dispatch_index = INDEX_WIDTH'(scan_i);
        dispatch_age   = age_q[scan_i];
      end
      if (valid_q[scan_i] && dispatched_q[scan_i] && !completed_q[scan_i] &&
          (req_q[scan_i].tag == complete_rsp_i.tag) &&
          (req_q[scan_i].epoch == complete_rsp_i.epoch) && !completion_found) begin
        completion_found = 1'b1;
        completion_index = INDEX_WIDTH'(scan_i);
      end
      if (valid_q[scan_i] &&
          (req_q[scan_i].tag == commit_tag_i) &&
          (req_q[scan_i].epoch == commit_epoch_i) && !commit_found) begin
        commit_found = 1'b1;
        commit_index = INDEX_WIDTH'(scan_i);
      end
      if (valid_q[scan_i] && !killed_q[scan_i] &&
          (req_q[scan_i].tag == kill_tag_i) &&
          (req_q[scan_i].epoch == kill_epoch_i) && !kill_found) begin
        kill_found = 1'b1;
        kill_index = INDEX_WIDTH'(scan_i);
      end
      if (valid_q[scan_i] && completed_q[scan_i] && committed_q[scan_i] &&
          (!retire_found || (age_q[scan_i] < retire_age))) begin
        retire_found = 1'b1;
        retire_index = INDEX_WIDTH'(scan_i);
        retire_age   = age_q[scan_i];
      end
    end

    if (retire_lock_q) begin
      retire_found = valid_q[retire_lock_index_q] &&
                     completed_q[retire_lock_index_q] &&
                     committed_q[retire_lock_index_q];
      retire_index = retire_lock_index_q;
    end
  end

  // Expose the identity lookup independently of alloc_valid_i so an upstream
  // atomic acceptance arbiter can distinguish duplicate from capacity stall.
  assign alloc_duplicate_o = duplicate_found;
  assign alloc_ready_o = !flush_i && free_found && !duplicate_found;
  assign alloc_fire = alloc_valid_i && alloc_ready_o;

  assign dispatch_valid_o = !flush_i && dispatch_found &&
                            !(kill_valid_i && kill_found &&
                              (kill_index == dispatch_index));
  assign dispatch_req_o = dispatch_found ? req_q[dispatch_index] : '0;
  assign dispatch_fire = dispatch_valid_o && dispatch_ready_i;

  // Completions are always consumed. A late response for a killed/flushed or
  // otherwise unknown transaction is counted instead of blocking an engine.
  assign complete_ready_o = !flush_i;
  assign complete_fire = complete_valid_i && complete_ready_o;
  assign completion_killed = completion_found &&
                             (killed_q[completion_index] ||
                              (kill_valid_i && kill_found &&
                               (kill_index == completion_index)));

  assign kill_hit_o = kill_valid_i && kill_found;
  assign kill_dispatched_o = kill_valid_i && kill_found && dispatched_q[kill_index];

  assign retire_valid_o = !flush_i && retire_found &&
                          !(kill_valid_i && kill_found &&
                            (kill_index == retire_index));
  assign retire_rsp_o = retire_found ? rsp_q[retire_index] : '0;
  assign retire_fire = retire_valid_o && retire_ready_i;

  always_comb begin
    valid_d = valid_q;
    dispatched_d = dispatched_q;
    completed_d = completed_q;
    committed_d = committed_q;
    killed_d = killed_q;
    next_age_d = next_age_q;
    retire_lock_d = retire_lock_q;
    retire_lock_index_d = retire_lock_index_q;
    for (next_i = 0; next_i < DEPTH; next_i = next_i + 1) begin
      req_d[next_i] = req_q[next_i];
      rsp_d[next_i] = rsp_q[next_i];
      age_d[next_i] = age_q[next_i];
    end

    if (dispatch_fire) dispatched_d[dispatch_index] = 1'b1;

    if (complete_fire && completion_found) begin
      if (completion_killed) begin
        valid_d[completion_index] = 1'b0;
        dispatched_d[completion_index] = 1'b0;
        killed_d[completion_index] = 1'b0;
      end else begin
        completed_d[completion_index] = 1'b1;
        rsp_d[completion_index] = complete_rsp_i;
      end
    end

    if (commit_valid_i && commit_found) committed_d[commit_index] = 1'b1;

    // Kill has priority over completion, commit, dispatch and retirement.
    if (kill_valid_i && kill_found) begin
      // An undispatched request can disappear immediately. Once dispatched,
      // preserve a tombstone unless its response arrives on this same cycle.
      if (kill_wait_completion_i && dispatched_q[kill_index] &&
          !completed_q[kill_index] &&
          !(complete_fire && completion_found &&
            (completion_index == kill_index))) begin
        valid_d[kill_index]  = 1'b1;
        killed_d[kill_index] = 1'b1;
      end else begin
        valid_d[kill_index] = 1'b0;
        dispatched_d[kill_index] = 1'b0;
        killed_d[kill_index] = 1'b0;
      end
      completed_d[kill_index] = 1'b0;
      committed_d[kill_index] = 1'b0;
      if (retire_lock_q && (retire_lock_index_q == kill_index)) retire_lock_d = 1'b0;
    end

    if (retire_fire) begin
      valid_d[retire_index] = 1'b0;
      dispatched_d[retire_index] = 1'b0;
      completed_d[retire_index] = 1'b0;
      committed_d[retire_index] = 1'b0;
      killed_d[retire_index] = 1'b0;
      retire_lock_d = 1'b0;
    end else if (retire_valid_o && !retire_ready_i && !retire_lock_q) begin
      retire_lock_d = 1'b1;
      retire_lock_index_d = retire_index;
    end

    if (alloc_fire) begin
      valid_d[free_index] = 1'b1;
      dispatched_d[free_index] = 1'b0;
      completed_d[free_index] = 1'b0;
      committed_d[free_index] = commit_valid_i &&
                                (commit_tag_i == alloc_req_i.tag) &&
                                (commit_epoch_i == alloc_req_i.epoch);
      killed_d[free_index] = 1'b0;
      req_d[free_index] = alloc_req_i;
      rsp_d[free_index] = '0;
      age_d[free_index] = next_age_q;
      next_age_d = next_age_q + 1'b1;
    end

    occupancy_next = '0;
    for (next_i = 0; next_i < DEPTH; next_i = next_i + 1)
    if (valid_d[next_i]) occupancy_next = occupancy_next + 1'b1;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      valid_q <= '0;
      dispatched_q <= '0;
      completed_q <= '0;
      committed_q <= '0;
      killed_q <= '0;
      next_age_q <= '0;
      retire_lock_q <= 1'b0;
      retire_lock_index_q <= '0;
      high_watermark_o <= '0;
      allocated_count_o <= '0;
      retired_count_o <= '0;
      killed_count_o <= '0;
      orphan_completion_count_o <= '0;
      for (seq_i = 0; seq_i < DEPTH; seq_i = seq_i + 1) begin
        req_q[seq_i] <= '0;
        rsp_q[seq_i] <= '0;
        age_q[seq_i] <= '0;
      end
    end else begin
      if (alloc_fire) allocated_count_o <= allocated_count_o + 1'b1;
      if (retire_fire) retired_count_o <= retired_count_o + 1'b1;
      if (flush_i) killed_count_o <= killed_count_o + flush_kill_count;
      else if (kill_valid_i && kill_found) killed_count_o <= killed_count_o + 1'b1;
      if (complete_fire && (!completion_found || completion_killed))
        orphan_completion_count_o <= orphan_completion_count_o + 1'b1;

      if (flush_i) begin
        valid_q <= '0;
        dispatched_q <= '0;
        completed_q <= '0;
        committed_q <= '0;
        killed_q <= '0;
        next_age_q <= '0;
        retire_lock_q <= 1'b0;
        retire_lock_index_q <= '0;
        high_watermark_o <= '0;
      end else begin
        valid_q <= valid_d;
        dispatched_q <= dispatched_d;
        completed_q <= completed_d;
        committed_q <= committed_d;
        killed_q <= killed_d;
        next_age_q <= next_age_d;
        retire_lock_q <= retire_lock_d;
        retire_lock_index_q <= retire_lock_index_d;
        if (occupancy_next > high_watermark_o) high_watermark_o <= occupancy_next;
        for (seq_i = 0; seq_i < DEPTH; seq_i = seq_i + 1) begin
          req_q[seq_i] <= req_d[seq_i];
          rsp_q[seq_i] <= rsp_d[seq_i];
          age_q[seq_i] <= age_d[seq_i];
        end
      end
    end
  end

`ifndef SYNTHESIS
  initial begin
    assert ((DEPTH == 2) || (DEPTH == 4) || (DEPTH == 8))
    else $error("autoisa_ci_inflight_table DEPTH must be 2, 4, or 8");
  end

  always_ff @(posedge clk_i) begin
    if (rst_ni && !flush_i) begin
      assert (occupancy_o <= DEPTH)
      else $error("autoisa_ci_inflight_table occupancy overflow");
      assert (!(alloc_fire && duplicate_found))
      else $error("autoisa_ci_inflight_table accepted duplicate identity");
    end
  end
`endif

endmodule

`default_nettype wire
