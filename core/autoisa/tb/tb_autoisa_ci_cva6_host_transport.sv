// SPDX-License-Identifier: Apache-2.0
`timescale 1ns/1ps

module tb_autoisa_ci_cva6_host_transport;
  import autoisa_ci_types_pkg::*;
  localparam int unsigned TID_W = 3;

  logic clk = 0, rst_n = 0, flush;
  logic issue_valid, issue_ready, issue_accept, issue_recognized, issue_illegal;
  logic [31:0] issue_instr;
  logic [TID_W-1:0] issue_id;
  logic commit_valid, commit_kill, commit_hit;
  logic [TID_W-1:0] commit_id;
  logic rf_req_valid, rf_req_ready;
  logic [1:0] rf_lane_valid;
  logic [1:0][4:0] rf_addr;
  logic [1:0][31:0] rf_data;
  logic [31:0] standard_pending_write_mask;
  logic [2:0] std_src_valid;
  logic [2:0][4:0] std_src_addr;
  logic std_dst_valid, std_raw, std_waw;
  logic [4:0] std_dst_addr;
  logic [31:0] busy_mask;
  logic wb_valid, wb_ready, wb_we, wb_last;
  logic [TID_W-1:0] wb_id;
  logic [4:0] wb_addr;
  logic [31:0] wb_data;
  autoisa_ci_status_e wb_status;
  logic [7:0] commit_pending;
  logic [3:0] destination_occupancy;
  logic [2:0] gather_occupancy;
  logic [31:0] shell_accepted, shell_retired, wb_results, wb_beats;

  always #5 clk = ~clk;
  always_comb begin
    rf_data[0] = {27'd0, rf_addr[0]};
    rf_data[1] = {27'd0, rf_addr[1]};
  end

  autoisa_ci_cva6_host_transport dut (
      .clk_i(clk), .rst_ni(rst_n), .flush_i(flush),
      .issue_valid_i(issue_valid), .issue_ready_o(issue_ready),
      .issue_instr_i(issue_instr), .issue_trans_id_i(issue_id),
      .issue_accept_o(issue_accept), .issue_recognized_o(issue_recognized),
      .issue_illegal_o(issue_illegal), .commit_valid_i(commit_valid),
      .commit_trans_id_i(commit_id), .commit_kill_i(commit_kill),
      .commit_identity_hit_o(commit_hit), .rf_req_valid_o(rf_req_valid),
      .rf_req_ready_i(rf_req_ready), .rf_lane_valid_o(rf_lane_valid),
      .rf_addr_o(rf_addr), .rf_data_i(rf_data),
      .standard_pending_write_mask_i(standard_pending_write_mask),
      .std_src_valid_i(std_src_valid), .std_src_addr_i(std_src_addr),
      .std_dst_valid_i(std_dst_valid), .std_dst_addr_i(std_dst_addr),
      .std_raw_hazard_o(std_raw), .std_waw_hazard_o(std_waw),
      .destination_busy_mask_o(busy_mask), .wb_valid_o(wb_valid),
      .wb_ready_i(wb_ready), .wb_trans_id_o(wb_id), .wb_addr_o(wb_addr),
      .wb_data_o(wb_data), .wb_we_o(wb_we), .wb_last_o(wb_last),
      .wb_status_o(wb_status), .commit_pending_mask_o(commit_pending),
      .destination_occupancy_o(destination_occupancy),
      .gather_occupancy_o(gather_occupancy),
      .shell_accepted_count_o(shell_accepted),
      .shell_retired_count_o(shell_retired), .wb_result_count_o(wb_results),
      .wb_beat_count_o(wb_beats)
  );

  function automatic logic [31:0] enc_l0(input logic [6:0] ci,
                                         input logic [4:0] rd,
                                         input logic [4:0] rs1,
                                         input logic [4:0] rs2);
    enc_l0 = {ci, rs2, rs1, 3'd0, rd, 7'h5b};
  endfunction

  function automatic logic [31:0] enc_l3(input logic [6:0] ci,
                                         input logic [4:0] rd,
                                         input logic [4:0] rs1,
                                         input logic [4:0] rs2);
    enc_l3 = {ci, rs2, rs1, 3'd3, rd, 7'h5b};
  endfunction

  function automatic logic [31:0] enc_l5;
    logic [31:0] value;
    begin
      value = '0;
      value[6:0] = 7'h2b;
      value[9:7] = 3'd6;   // rd=x14
      value[12:10] = 3'd0; // x8
      value[15:13] = 3'd1; // x9
      value[18:16] = 3'd2; // x10
      value[21:19] = 3'd3; // x11
      value[24:22] = 3'd4; // x12
      value[27:25] = 3'd5; // x13
      enc_l5 = value;
    end
  endfunction

  task automatic issue_ci(input logic [TID_W-1:0] id,
                          input logic [31:0] instr);
    integer cycles;
    begin
      @(negedge clk);
      issue_id = id; issue_instr = instr; issue_valid = 1;
      cycles = 0;
      while (!issue_ready && cycles < 30) begin
        @(negedge clk); cycles = cycles + 1;
      end
      #1;
      if (!issue_ready || !issue_accept || !issue_recognized || issue_illegal)
        $fatal(1, "issue failed id=%0d", id);
      @(posedge clk); @(negedge clk); issue_valid = 0;
    end
  endtask

  task automatic commit_ci(input logic [TID_W-1:0] id, input logic kill);
    begin
      commit_id = id; commit_kill = kill; commit_valid = 1; #1;
      if (!commit_hit) $fatal(1, "commit identity miss id=%0d", id);
      @(posedge clk); @(negedge clk); commit_valid = 0; commit_kill = 0;
    end
  endtask

  task automatic expect_scalar(input logic [TID_W-1:0] id,
                               input logic [4:0] addr,
                               input logic [31:0] data);
    integer cycles;
    begin
      cycles = 0;
      while (!wb_valid && cycles < 100) begin
        @(negedge clk); cycles = cycles + 1;
      end
      if (!wb_valid || wb_id != id || wb_addr != addr || wb_data != data ||
          !wb_we || !wb_last || wb_status != AUTOISA_STATUS_OK)
        $fatal(1, "scalar WB mismatch id=%0d addr=%0d data=%h", wb_id, wb_addr, wb_data);
      @(posedge clk); @(negedge clk);
    end
  endtask

  initial begin
    flush = 0; issue_valid = 0; issue_instr = 0; issue_id = 0;
    commit_valid = 0; commit_id = 0; commit_kill = 0;
    rf_req_ready = 1; wb_ready = 1;
    standard_pending_write_mask = 0; std_src_valid = 0; std_src_addr = '0;
    std_dst_valid = 0; std_dst_addr = 0;
    repeat (4) @(posedge clk); @(negedge clk); rst_n = 1;

    // Commit arrives while the descriptor is still gathering operands.
    issue_ci(1, enc_l0(0, 5, 1, 2));
    commit_ci(1, 0);
    if (!commit_pending[1]) $fatal(1, "early commit was not retained");
    expect_scalar(1, 5, 32'd3);
    if (busy_mask[5] || commit_pending[1])
      $fatal(1, "scalar terminal event did not release state");

    // Pair result: stall beat zero, then prove ownership survives until beat one.
    wb_ready = 0;
    issue_ci(2, enc_l3(3, 8, 1, 2));
    commit_ci(2, 0);
    while (!wb_valid) @(negedge clk);
    if (wb_id != 2 || wb_addr != 8 || wb_data != 3 || !wb_we || wb_last)
      $fatal(1, "pair first WB beat mismatch");
    if (!busy_mask[8] || !busy_mask[9])
      $fatal(1, "pair destination released before first beat");
    repeat (2) begin
      @(posedge clk); @(negedge clk);
      if (!wb_valid || wb_addr != 8 || wb_data != 3 || wb_last)
        $fatal(1, "stalled pair first beat changed");
    end
    wb_ready = 1;
    @(posedge clk); @(negedge clk);
    if (!wb_valid || wb_id != 2 || wb_addr != 9 ||
        wb_data != 32'hffff_ffff || !wb_we || !wb_last)
      $fatal(1, "pair second WB beat mismatch");
    if (!busy_mask[8] || !busy_mask[9])
      $fatal(1, "pair destination released between WB beats");
    @(posedge clk); @(negedge clk);
    if (busy_mask[8] || busy_mask[9])
      $fatal(1, "pair destination not released after final beat");

    // Six logical reads are collected in three physical RF beats.
    issue_ci(3, enc_l5());
    commit_ci(3, 0);
    expect_scalar(3, 14, 32'd63);

    // A kill before gather completes must suppress shell allocation and WB.
    rf_req_ready = 0;
    issue_ci(4, enc_l0(0, 16, 3, 4));
    commit_ci(4, 1);
    rf_req_ready = 1;
    repeat (30) begin
      @(negedge clk);
      if (wb_valid && wb_id == 4) $fatal(1, "killed gather produced WB");
    end
    if (busy_mask[16] || commit_pending[4])
      $fatal(1, "kill did not release Host transport state");

    // Flush clears every transport stage and destination reservation.
    rf_req_ready = 0;
    issue_ci(5, enc_l0(0, 17, 5, 6));
    flush = 1; @(posedge clk); @(negedge clk); flush = 0; rf_req_ready = 1;
    if (busy_mask != 0 || destination_occupancy != 0 ||
        gather_occupancy != 0 || commit_pending != 0)
      $fatal(1, "flush left visible transport state");

    if (shell_accepted != 3 || shell_retired != 3 ||
        wb_results != 3 || wb_beats != 4)
      $fatal(1, "transport counters mismatch accepted=%0d retired=%0d results=%0d beats=%0d",
             shell_accepted, shell_retired, wb_results, wb_beats);
    $display("PASS: CVA6 Host transport early-commit, 1-6R gather, pair WB, kill and flush");
    $finish;
  end

  initial begin
    #10000;
    $fatal(1, "timeout");
  end
endmodule
