// SPDX-License-Identifier: Apache-2.0
`timescale 1ns/1ps

module tb_autoisa_ci_harness_v0;
  import autoisa_ci_types_pkg::*;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  logic issue_valid, issue_ready;
  logic [31:0] issue_instr;
  logic [3:0] issue_tag;
  logic [1:0] issue_epoch;
  logic [5:0][31:0] issue_operands;
  logic issue_accept, issue_reject;
  autoisa_ci_status_e issue_reject_status;
  autoisa_ci_host_desc_t issue_desc;
  logic commit_valid;
  logic [3:0] commit_tag;
  logic [1:0] commit_epoch;
  logic kill_valid;
  logic [3:0] kill_tag;
  logic [1:0] kill_epoch;
  logic result_valid, result_ready;
  autoisa_ci_rsp_t result_value;
  logic killed, busy;

  autoisa_ci_harness_v0 dut (
      .clk_i(clk), .rst_ni(rst_n),
      .issue_valid_i(issue_valid), .issue_ready_o(issue_ready),
      .issue_instr_i(issue_instr), .issue_tag_i(issue_tag),
      .issue_epoch_i(issue_epoch), .issue_operands_i(issue_operands),
      .issue_accept_o(issue_accept), .issue_reject_o(issue_reject),
      .issue_reject_status_o(issue_reject_status), .issue_desc_o(issue_desc),
      .commit_valid_i(commit_valid), .commit_tag_i(commit_tag),
      .commit_epoch_i(commit_epoch), .kill_valid_i(kill_valid),
      .kill_tag_i(kill_tag), .kill_epoch_i(kill_epoch),
      .result_valid_o(result_valid), .result_ready_i(result_ready),
      .result_o(result_value), .killed_o(killed), .busy_o(busy)
  );

  function automatic logic [31:0] enc_r(
      input logic [6:0] ci_id, input logic [2:0] layout,
      input logic [4:0] rd, input logic [4:0] rs1, input logic [4:0] rs2
  );
    enc_r = {ci_id, rs2, rs1, layout, rd, 7'h5b};
  endfunction

  function automatic logic [31:0] enc_l1;
    enc_l1 = (32'd1 << 30) | (32'd3 << 25) | (32'd2 << 20) |
             (32'd1 << 15) | (32'd1 << 12) | (32'd5 << 7) | 32'h5b;
  endfunction

  function automatic logic [31:0] enc_l2;
    enc_l2 = (32'd2 << 27) | (32'd3 << 24) | (32'd2 << 21) |
             (32'd1 << 18) | (32'd0 << 15) | (32'd2 << 12) |
             (32'd1 << 9) | 32'h5b;
  endfunction

  function automatic logic [31:0] enc_l4;
    enc_l4 = (32'd0 << 30) | (32'd2 << 27) | (32'd3 << 24) |
             (32'd2 << 21) | (32'd1 << 18) | (32'd0 << 15) |
             (32'd4 << 12) | (32'd1 << 7) | 32'h5b;
  endfunction

  function automatic logic [31:0] enc_l5;
    enc_l5 = (32'd5 << 25) | (32'd4 << 22) | (32'd3 << 19) |
             (32'd2 << 16) | (32'd1 << 13) | (32'd0 << 10) |
             (32'd1 << 7) | 32'h2b;
  endfunction

  function automatic logic [31:0] enc_l6;
    enc_l6 = (32'd5 << 28) | (32'd4 << 25) | (32'd3 << 22) |
             (32'd2 << 19) | (32'd1 << 16) | (32'd0 << 13) |
             (32'd2 << 10) | (32'd1 << 7) | 32'h7b;
  endfunction

  function automatic logic [31:0] enc_l7(input logic [6:0] imm7);
    enc_l7 = ({25'd0, imm7} << 25) | (32'd2 << 20) | (32'd1 << 15) |
             (32'd7 << 12) | (32'd5 << 7) | 32'h5b;
  endfunction

  task automatic issue_current(input logic [31:0] instruction, input logic [3:0] tag);
    begin
      while (!issue_ready) @(negedge clk);
      issue_instr = instruction;
      issue_tag = tag;
      issue_epoch = 2'd0;
      issue_valid = 1'b1;
      #1;
      if (!issue_accept) $fatal(1, "instruction was not accepted: %08x", instruction);
      @(posedge clk);
      @(negedge clk);
      issue_valid = 1'b0;
    end
  endtask

  task automatic commit_current(input logic [3:0] tag);
    begin
      commit_tag = tag;
      commit_epoch = 2'd0;
      commit_valid = 1'b1;
      @(posedge clk);
      @(negedge clk);
      commit_valid = 1'b0;
    end
  endtask

  task automatic expect_result(
      input logic [1:0] mask, input logic [31:0] expected0,
      input logic [31:0] expected1
  );
    begin
      wait (result_valid);
      if ((result_value.result_valid != mask) ||
          (result_value.results[0] != expected0) ||
          (mask[1] && (result_value.results[1] != expected1))) begin
        $fatal(1, "result mismatch: mask=%b r0=%08x r1=%08x",
               result_value.result_valid, result_value.results[0],
               result_value.results[1]);
      end
      @(posedge clk);
      @(negedge clk);
    end
  endtask

  task automatic run_ci(
      input logic [31:0] instruction, input logic [3:0] tag,
      input logic [1:0] mask, input logic [31:0] expected0,
      input logic [31:0] expected1
  );
    begin
      issue_current(instruction, tag);
      commit_current(tag);
      expect_result(mask, expected0, expected1);
    end
  endtask

  initial begin
    issue_valid = 1'b0;
    issue_instr = '0;
    issue_tag = '0;
    issue_epoch = '0;
    issue_operands = '0;
    commit_valid = 1'b0;
    commit_tag = '0;
    commit_epoch = '0;
    kill_valid = 1'b0;
    kill_tag = '0;
    kill_epoch = '0;
    result_ready = 1'b1;

    repeat (3) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    issue_operands = '{32'd0, 32'd0, 32'd0, 32'd0, 32'd20, 32'd10};
    issue_current(enc_r(7'd0, 3'd0, 5'd5, 5'd1, 5'd2), 4'd1);
    repeat (2) begin
      @(posedge clk);
      if (result_valid) $fatal(1, "D0 result became visible before commit");
    end
    @(negedge clk);
    commit_current(4'd1);
    expect_result(2'b01, 32'd30, 32'd0);

    issue_operands = '{32'd0, 32'd0, 32'd0, 32'd3, 32'd4, 32'd2};
    run_ci(enc_l1(), 4'd2, 2'b01, 32'd11, 32'd0);

    issue_operands = '{32'd0, 32'd0, 32'd7, 32'd3, 32'd4, 32'd2};
    run_ci(enc_l2(), 4'd3, 2'b01, 32'd12, 32'd0);

    issue_operands = '{32'd0, 32'd0, 32'd0, 32'd0, 32'd4, 32'd15};
    run_ci(enc_r(7'd3, 3'd3, 5'd6, 5'd1, 5'd2), 4'd4, 2'b11, 32'd19, 32'd11);

    issue_operands = '{32'd0, 32'd0, 32'd4, 32'd3, 32'd2, 32'd5};
    run_ci(enc_l4(), 4'd5, 2'b11, 32'd7, 32'd26);

    issue_operands = '{32'd6, 32'd5, 32'd4, 32'd3, 32'd2, 32'd1};
    run_ci(enc_l5(), 4'd6, 2'b01, 32'd21, 32'd0);

    issue_operands = '{32'd6, 32'd5, 32'd4, 32'd3, 32'd2, 32'd1};
    run_ci(enc_l6(), 4'd7, 2'b11, 32'd44, 32'd20);

    issue_operands = '{32'd0, 32'd0, 32'd0, 32'd0, 32'd7, 32'd3};
    run_ci(enc_l7(7'd2), 4'd8, 2'b01, 32'd5, 32'd0);

    // Pair rd0 must be nonzero, even and not x31.
    issue_instr = enc_r(7'd3, 3'd3, 5'd5, 5'd1, 5'd2);
    issue_tag = 4'd9;
    issue_valid = 1'b1;
    #1;
    if (!issue_reject || issue_reject_status != AUTOISA_STATUS_ILLEGAL)
      $fatal(1, "illegal pair was not rejected");
    @(posedge clk);
    @(negedge clk);
    issue_valid = 1'b0;

    // A recognized layout with an unimplemented semantic is explicit UNSUPPORTED.
    issue_instr = enc_r(7'd9, 3'd0, 5'd5, 5'd1, 5'd2);
    issue_tag = 4'd9;
    issue_valid = 1'b1;
    #1;
    if (!issue_reject || issue_reject_status != AUTOISA_STATUS_UNSUPPORTED)
      $fatal(1, "unsupported semantic was not rejected");
    @(posedge clk);
    @(negedge clk);
    issue_valid = 1'b0;

    // Backpressure must not alter a completed result.
    result_ready = 1'b0;
    issue_operands = '{32'd0, 32'd0, 32'd0, 32'd0, 32'd9, 32'd8};
    issue_current(enc_r(7'd0, 3'd0, 5'd7, 5'd1, 5'd2), 4'd10);
    commit_current(4'd10);
    wait (result_valid);
    repeat (3) begin
      @(posedge clk);
      if (!result_valid || result_value.results[0] != 32'd17)
        $fatal(1, "result changed while stalled");
    end
    @(negedge clk);
    result_ready = 1'b1;
    @(posedge clk);
    @(negedge clk);

    // Kill an accepted D3 before completion and prove no writeback occurs.
    issue_operands = '{32'd0, 32'd0, 32'd0, 32'd0, 32'd4, 32'd15};
    issue_current(enc_r(7'd3, 3'd3, 5'd6, 5'd1, 5'd2), 4'd11);
    kill_tag = 4'd11;
    kill_epoch = 2'd0;
    kill_valid = 1'b1;
    @(posedge clk);
    @(negedge clk);
    kill_valid = 1'b0;
    wait (killed);
    if (result_valid) $fatal(1, "killed transaction produced a result");

    $display("PASS: autoisa_ci_harness_v0");
    $finish;
  end

  initial begin
    #5000;
    $fatal(1, "timeout");
  end
endmodule
