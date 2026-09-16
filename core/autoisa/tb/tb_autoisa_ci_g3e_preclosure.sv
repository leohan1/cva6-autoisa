// SPDX-License-Identifier: Apache-2.0
`timescale 1ns / 1ps
`default_nettype none

module tb_autoisa_ci_g3e_preclosure;
  import autoisa_ci_types_pkg::*;
  localparam int unsigned TID_W = 3;
  localparam int unsigned PROFILE_COUNT = 5;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic flush;
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

  logic [479:0] vectors[0:PROFILE_COUNT-1];
  logic [31:0] gpr[0:31];
  logic [31:0] vector_instr, profile_word, semantic_word;
  logic [31:0] source_count_word, destination_count_word;
  logic [31:0] source_pack, destination_pack;
  logic [5:0][31:0] input_words;
  logic [1:0][31:0] expected_words;

  always #5 clk = ~clk;
  always_comb begin
    rf_data[0] = rf_addr[0] == 0 ? 32'd0 : gpr[rf_addr[0]];
    rf_data[1] = rf_addr[1] == 0 ? 32'd0 : gpr[rf_addr[1]];
  end

  autoisa_ci_cva6_host_transport dut (
      .clk_i(clk),
      .rst_ni(rst_n),
      .flush_i(flush),
      .issue_valid_i(issue_valid),
      .issue_ready_o(issue_ready),
      .issue_instr_i(issue_instr),
      .issue_trans_id_i(issue_id),
      .issue_accept_o(issue_accept),
      .issue_recognized_o(issue_recognized),
      .issue_illegal_o(issue_illegal),
      .commit_valid_i(commit_valid),
      .commit_trans_id_i(commit_id),
      .commit_kill_i(commit_kill),
      .commit_identity_hit_o(commit_hit),
      .rf_req_valid_o(rf_req_valid),
      .rf_req_ready_i(rf_req_ready),
      .rf_lane_valid_o(rf_lane_valid),
      .rf_addr_o(rf_addr),
      .rf_data_i(rf_data),
      .standard_pending_write_mask_i(standard_pending_write_mask),
      .std_src_valid_i(std_src_valid),
      .std_src_addr_i(std_src_addr),
      .std_dst_valid_i(std_dst_valid),
      .std_dst_addr_i(std_dst_addr),
      .std_raw_hazard_o(std_raw),
      .std_waw_hazard_o(std_waw),
      .destination_busy_mask_o(busy_mask),
      .wb_valid_o(wb_valid),
      .wb_ready_i(wb_ready),
      .wb_trans_id_o(wb_id),
      .wb_addr_o(wb_addr),
      .wb_data_o(wb_data),
      .wb_we_o(wb_we),
      .wb_last_o(wb_last),
      .wb_status_o(wb_status),
      .commit_pending_mask_o(commit_pending),
      .destination_occupancy_o(destination_occupancy),
      .gather_occupancy_o(gather_occupancy),
      .shell_accepted_count_o(shell_accepted),
      .shell_retired_count_o(shell_retired),
      .wb_result_count_o(wb_results),
      .wb_beat_count_o(wb_beats)
  );

  task automatic issue_extended(input logic [TID_W-1:0] id,
                                input logic [31:0] instr);
    int unsigned cycles;
    begin
      @(negedge clk);
      issue_id = id;
      issue_instr = instr;
      issue_valid = 1'b1;
      cycles = 0;
      while (!issue_ready && cycles < 30) begin
        @(negedge clk);
        cycles++;
      end
      #1;
      if (!issue_ready || !issue_accept || !issue_recognized || issue_illegal)
        $fatal(1, "G3E issue failed id=%0d instr=%08x", id, instr);
      @(posedge clk);
      @(negedge clk);
      issue_valid = 1'b0;
    end
  endtask

  task automatic commit_extended(input logic [TID_W-1:0] id);
    begin
      commit_id = id;
      commit_kill = 1'b0;
      commit_valid = 1'b1;
      #1;
      if (!commit_hit) $fatal(1, "G3E commit identity miss id=%0d", id);
      @(posedge clk);
      @(negedge clk);
      commit_valid = 1'b0;
    end
  endtask

  task automatic check_hazards(input logic [4:0] destination);
    begin
      std_src_valid = 3'b001;
      std_src_addr[0] = destination;
      std_dst_valid = 1'b1;
      std_dst_addr = destination;
      #1;
      if (!std_raw || !std_waw || !busy_mask[destination])
        $fatal(1, "G3E destination ownership is not visible for x%0d", destination);
      std_src_valid = '0;
      std_dst_valid = 1'b0;
    end
  endtask

  task automatic receive_results(input logic [TID_W-1:0] id,
                                 input int unsigned destination_count,
                                 input logic [31:0] packed_destinations,
                                 input logic [1:0][31:0] expected);
    int unsigned beat, cycles;
    logic [4:0] destination;
    begin
      for (beat = 0; beat < destination_count; beat++) begin
        cycles = 0;
        while (!wb_valid && cycles < 100) begin
          @(negedge clk);
          cycles++;
        end
        destination = packed_destinations[beat*5+:5];
        if (!wb_valid || !wb_we || wb_id != id || wb_addr != destination ||
            wb_data != expected[beat] || wb_last != (beat == destination_count - 1) ||
            wb_status != AUTOISA_STATUS_OK)
          $fatal(1, "G3E writeback mismatch id=%0d beat=%0d", id, beat);
        if (!busy_mask[destination])
          $fatal(1, "G3E destination released before writeback id=%0d", id);
        gpr[destination] = wb_data;
        @(posedge clk);
        @(negedge clk);
      end
      if (destination_occupancy != 0)
        $fatal(1, "G3E destination ownership leaked id=%0d", id);
    end
  endtask

  initial begin : run_profiles
    int unsigned profile_index, source_index, destination_index;
    logic [4:0] register_address;
    $readmemh("generated/g3e/g3e_preclosure_vectors.hex", vectors);
    flush = 1'b0;
    issue_valid = 1'b0;
    issue_instr = '0;
    issue_id = '0;
    commit_valid = 1'b0;
    commit_id = '0;
    commit_kill = 1'b0;
    rf_req_ready = 1'b1;
    wb_ready = 1'b1;
    standard_pending_write_mask = '0;
    std_src_valid = '0;
    std_src_addr = '0;
    std_dst_valid = 1'b0;
    std_dst_addr = '0;
    for (int unsigned i = 0; i < 32; i++) gpr[i] = '0;

    repeat (4) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    for (profile_index = 0; profile_index < PROFILE_COUNT; profile_index++) begin
      {vector_instr, profile_word, semantic_word, source_count_word,
       destination_count_word, source_pack, destination_pack,
       input_words[0], input_words[1], input_words[2], input_words[3],
       input_words[4], input_words[5], expected_words[0], expected_words[1]} =
          vectors[profile_index];
      if (profile_word != profile_index + 3 || semantic_word != profile_index + 2)
        $fatal(1, "G3E oracle identity mismatch index=%0d", profile_index);
      for (source_index = 0; source_index < source_count_word; source_index++) begin
        register_address = source_pack[source_index*5+:5];
        gpr[register_address] = input_words[source_index];
      end

      issue_extended(profile_index + 1, vector_instr);
      for (destination_index = 0; destination_index < destination_count_word;
           destination_index++) begin
        check_hazards(destination_pack[destination_index*5+:5]);
      end
      commit_extended(profile_index + 1);
      receive_results(profile_index + 1, destination_count_word, destination_pack,
                      expected_words);
      for (destination_index = 0; destination_index < destination_count_word;
           destination_index++) begin
        register_address = destination_pack[destination_index*5+:5];
        if (gpr[register_address] != expected_words[destination_index])
          $fatal(1, "G3E architectural state mismatch P%0d", profile_word);
      end
    end

    if (shell_accepted != 5 || shell_retired != 5 || wb_results != 5 || wb_beats != 8)
      $fatal(1, "G3E counters mismatch accepted=%0d retired=%0d results=%0d beats=%0d",
             shell_accepted, shell_retired, wb_results, wb_beats);
    $display("DATA: profiles=5 scalar_results=2 pair_results=3 wb_beats=8");
    $display("PASS: G3E reference-backed P3-P7 transport architectural pre-closure");
    $finish;
  end

  initial begin
    #20000;
    $fatal(1, "G3E pre-closure timeout");
  end
endmodule

`default_nettype wire
