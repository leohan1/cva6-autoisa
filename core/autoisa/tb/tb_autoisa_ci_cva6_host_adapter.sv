// SPDX-License-Identifier: Apache-2.0
`timescale 1ns/1ps

module tb_autoisa_ci_cva6_host_adapter;
  import autoisa_ci_types_pkg::*;
  localparam int unsigned TID_W = 3;

  logic clk = 0, rst_n = 0, flush;
  logic issue_valid, issue_ready, issue_accept, issue_recognized, issue_illegal;
  logic issue_identity_busy, issue_raw, issue_waw, desc_valid, desc_ready;
  logic [31:0] issue_instr;
  logic [TID_W-1:0] issue_id;
  autoisa_ci_host_desc_t desc;
  logic commit_valid, commit_kill, commit_hit;
  logic [TID_W-1:0] commit_id;
  logic shell_commit_valid, shell_kill_valid, shell_flush;
  logic [AUTOISA_TAG_WIDTH-1:0] shell_commit_tag, shell_kill_tag;
  logic [AUTOISA_EPOCH_WIDTH-1:0] shell_commit_epoch, shell_kill_epoch;
  logic shell_result_valid, shell_result_ready;
  autoisa_ci_rsp_t shell_result;
  logic host_result_valid, host_result_ready;
  logic [TID_W-1:0] host_result_id;
  logic [AUTOISA_MAX_DST-1:0] host_dst_valid;
  logic [AUTOISA_MAX_DST-1:0][4:0] host_dst_addr;
  logic [AUTOISA_MAX_DST-1:0][31:0] host_data;
  autoisa_ci_write_policy_e host_policy;
  autoisa_ci_status_e host_status;
  logic [31:0] standard_pending_write_mask;
  logic [2:0] std_src_valid;
  logic [2:0][4:0] std_src_addr;
  logic std_dst_valid;
  logic [4:0] std_dst_addr;
  logic std_raw, std_waw;
  logic [31:0] busy_mask;
  logic [3:0] occupancy, hwm;
  logic [31:0] accepts, rejects, stale_drops, unknown_commits;
  logic [TID_W-1:0] observed_host_id;
  logic [AUTOISA_MAX_DST-1:0] observed_dst_valid;
  logic [AUTOISA_MAX_DST-1:0][4:0] observed_dst_addr;
  logic [AUTOISA_MAX_DST-1:0][31:0] observed_data;
  autoisa_ci_write_policy_e observed_policy;
  logic [3:0] observed_hwm;

  always #5 clk = ~clk;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      observed_hwm <= '0;
    else if (hwm > observed_hwm)
      observed_hwm <= hwm;
  end

  autoisa_ci_cva6_host_adapter #(.TRANS_ID_WIDTH(TID_W), .MAP_ENTRIES(8)) dut (
      .clk_i(clk), .rst_ni(rst_n), .flush_i(flush),
      .issue_valid_i(issue_valid), .issue_ready_o(issue_ready),
      .issue_instr_i(issue_instr), .issue_trans_id_i(issue_id),
      .issue_accept_o(issue_accept), .issue_recognized_o(issue_recognized),
      .issue_illegal_o(issue_illegal), .issue_identity_busy_o(issue_identity_busy),
      .issue_raw_hazard_o(issue_raw), .issue_waw_hazard_o(issue_waw),
      .issue_desc_valid_o(desc_valid), .issue_desc_ready_i(desc_ready),
      .issue_desc_o(desc), .commit_valid_i(commit_valid),
      .commit_trans_id_i(commit_id), .commit_kill_i(commit_kill),
      .commit_identity_hit_o(commit_hit), .shell_commit_valid_o(shell_commit_valid),
      .shell_commit_tag_o(shell_commit_tag), .shell_commit_epoch_o(shell_commit_epoch),
      .shell_kill_valid_o(shell_kill_valid), .shell_kill_tag_o(shell_kill_tag),
      .shell_kill_epoch_o(shell_kill_epoch), .shell_flush_o(shell_flush),
      .shell_result_valid_i(shell_result_valid),
      .shell_result_ready_o(shell_result_ready), .shell_result_i(shell_result),
      .host_result_valid_o(host_result_valid), .host_result_ready_i(host_result_ready),
      .host_result_trans_id_o(host_result_id),
      .host_result_dst_valid_o(host_dst_valid), .host_result_dst_addr_o(host_dst_addr),
      .host_result_data_o(host_data), .host_result_write_policy_o(host_policy),
      .host_result_status_o(host_status),
      .standard_pending_write_mask_i(standard_pending_write_mask),
      .std_src_valid_i(std_src_valid),
      .std_src_addr_i(std_src_addr), .std_dst_valid_i(std_dst_valid),
      .std_dst_addr_i(std_dst_addr), .std_raw_hazard_o(std_raw),
      .std_waw_hazard_o(std_waw), .destination_busy_mask_o(busy_mask),
      .destination_occupancy_o(occupancy), .destination_high_watermark_o(hwm),
      .issue_accept_count_o(accepts), .issue_reject_count_o(rejects),
      .stale_result_drop_count_o(stale_drops),
      .unknown_commit_count_o(unknown_commits)
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

  task automatic issue_ci(input logic [TID_W-1:0] id, input logic [31:0] instr,
                          input logic [1:0] expect_epoch);
    begin
      @(negedge clk); issue_id = id; issue_instr = instr; issue_valid = 1;
      #1;
      if (!issue_ready || !issue_accept || !desc_valid ||
          (desc.tag != id) || (desc.epoch != expect_epoch))
        $fatal(1, "issue failed id=%0d ready=%0b accept=%0b descv=%0b tag=%0d epoch=%0d raw=%0b waw=%0b",
               id, issue_ready, issue_accept, desc_valid, desc.tag, desc.epoch,
               issue_raw, issue_waw);
      @(posedge clk); @(negedge clk); issue_valid = 0;
    end
  endtask

  task automatic commit_ci(input logic [TID_W-1:0] id, input logic kill,
                           input logic [1:0] expect_epoch);
    begin
      @(negedge clk); commit_id = id; commit_kill = kill; commit_valid = 1; #1;
      if (!commit_hit || (shell_commit_valid != !kill) ||
          (shell_kill_valid != kill) ||
          ((kill ? shell_kill_epoch : shell_commit_epoch) != expect_epoch))
        $fatal(1, "commit/kill map failed id=%0d kill=%0b", id, kill);
      @(posedge clk); @(negedge clk); commit_valid = 0;
    end
  endtask

  task automatic return_result(input logic [TID_W-1:0] id,
                               input logic [1:0] epoch,
                               input logic [31:0] r0,
                               input logic [31:0] r1,
                               input logic expect_host);
    begin
      @(negedge clk);
      shell_result = '0;
      shell_result.tag = id;
      shell_result.epoch = epoch;
      shell_result.result_valid = (r1 == 32'hdead_dead) ? 2'b01 : 2'b11;
      shell_result.results[0] = r0;
      shell_result.results[1] = r1;
      shell_result.status = AUTOISA_STATUS_OK;
      shell_result_valid = 1;
      #1;
      if (!shell_result_ready || (host_result_valid != expect_host))
        $fatal(1, "result route mismatch id=%0d epoch=%0d ready=%0b host=%0b",
               id, epoch, shell_result_ready, host_result_valid);
      if (expect_host) begin
        observed_host_id = host_result_id;
        observed_dst_valid = host_dst_valid;
        observed_dst_addr = host_dst_addr;
        observed_data = host_data;
        observed_policy = host_policy;
      end
      @(posedge clk); @(negedge clk); shell_result_valid = 0;
    end
  endtask

  initial begin
    flush = 0; issue_valid = 0; issue_instr = 0; issue_id = 0; desc_ready = 1;
    commit_valid = 0; commit_id = 0; commit_kill = 0;
    shell_result_valid = 0; shell_result = '0; host_result_ready = 1;
    standard_pending_write_mask = '0;
    std_src_valid = 0; std_src_addr = '0; std_dst_valid = 0; std_dst_addr = 0;
    observed_host_id = '0; observed_dst_valid = '0; observed_dst_addr = '0;
    observed_data = '0; observed_policy = AUTOISA_WRITE_NONE;
    repeat (4) @(posedge clk); @(negedge clk); rst_n = 1;

    issue_ci(2, enc_l0(0, 5, 1, 2), 0);
    if (!busy_mask[5] || (occupancy != 1)) $fatal(1, "scalar destination not reserved");
    std_src_valid = 3'b001; std_src_addr[0] = 5;
    std_dst_valid = 1; std_dst_addr = 5; #1;
    if (!std_raw || !std_waw) $fatal(1, "CVA6 standard hazard visibility failed");
    std_src_valid = 0; std_dst_valid = 0;

    standard_pending_write_mask[12] = 1'b1;
    @(negedge clk); issue_id = 3; issue_instr = enc_l0(0, 13, 12, 2); issue_valid = 1; #1;
    if (issue_ready || !issue_raw)
      $fatal(1, "standard scoreboard destination did not block CI RAW");
    issue_valid = 0; standard_pending_write_mask = '0;

    // A second CI reading x5 must stall until id2 produces its result.
    @(negedge clk); issue_id = 3; issue_instr = enc_l0(0, 6, 5, 2); issue_valid = 1; #1;
    if (issue_ready || !issue_raw) $fatal(1, "CI RAW dependency did not stall");
    issue_valid = 0;

    commit_ci(2, 0, 0);
    return_result(2, 0, 32'h1234_5678, 32'hdead_dead, 1);
    if (busy_mask[5] || (occupancy != 0) || (observed_host_id != 2) ||
        (observed_dst_valid != 2'b01) || (observed_dst_addr[0] != 5) ||
        (observed_data[0] != 32'h1234_5678) ||
        (observed_policy != AUTOISA_WRITE_SCALAR))
      $fatal(1, "scalar result/destination transaction mismatch");

    // Reuse the CVA6 scoreboard id: epoch increments and stale result is drained.
    issue_ci(2, enc_l0(0, 7, 1, 2), 1);
    return_result(2, 0, 32'haaaa_aaaa, 32'hdead_dead, 0);
    if (!busy_mask[7] || (occupancy != 1)) $fatal(1, "stale result released new epoch");
    return_result(2, 1, 32'h8765_4321, 32'hdead_dead, 1);

    issue_ci(3, enc_l0(0, 6, 1, 2), 0);
    commit_ci(3, 1, 0);
    if (busy_mask[6] || (occupancy != 0)) $fatal(1, "kill did not release destination");

    issue_ci(4, enc_l3(3, 8, 1, 2), 0);
    commit_ci(4, 0, 0);
    return_result(4, 0, 32'h0000_002a, 32'hffff_fff8, 1);
    if ((observed_dst_valid != 2'b11) || (observed_dst_addr[0] != 8) ||
        (observed_dst_addr[1] != 9) ||
        (observed_policy != AUTOISA_WRITE_PAIR_SERIAL))
      $fatal(1, "pair destination transaction mismatch");

    issue_ci(5, enc_l0(0, 10, 1, 2), 0);
    @(negedge clk); flush = 1; #1;
    if (!shell_flush) $fatal(1, "flush not forwarded");
    @(posedge clk); @(negedge clk); flush = 0;
    if ((occupancy != 0) || (busy_mask != 0)) $fatal(1, "flush left destination ownership");
    return_result(5, 0, 32'h5555_5555, 32'hdead_dead, 0);

    // Unsupported instruction is consumed as an explicit reject.
    @(negedge clk); issue_id = 6; issue_instr = 32'h0000_0013; issue_valid = 1; #1;
    if (!issue_ready || issue_accept || issue_recognized)
      $fatal(1, "unsupported instruction rejection mismatch");
    @(posedge clk); @(negedge clk); issue_valid = 0;

    // Commit for a non-live scoreboard id is observable but not forwarded.
    @(negedge clk); commit_id = 7; commit_kill = 0; commit_valid = 1; #1;
    if (commit_hit || shell_commit_valid || shell_kill_valid)
      $fatal(1, "unknown commit was forwarded");
    @(posedge clk); @(negedge clk); commit_valid = 0;

    if ((accepts != 5) || (rejects != 1) || (stale_drops != 2) ||
        (unknown_commits != 1) || (occupancy != 0))
      $fatal(1, "adapter counters mismatch accepts=%0d rejects=%0d stale=%0d unknown_commit=%0d occ=%0d",
             accepts, rejects, stale_drops, unknown_commits, occupancy);

    $display("DATA: accepted=%0d rejected=%0d stale_result_drop=%0d unknown_commit=%0d destination_hwm=%0d",
             accepts, rejects, stale_drops, unknown_commits, observed_hwm);
    $display("PASS: autoisa_ci_cva6_host_adapter");
    $finish;
  end

  initial begin
    #10000;
    $fatal(1, "timeout accepts=%0d occupancy=%0d", accepts, occupancy);
  end
endmodule
