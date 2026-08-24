// SPDX-License-Identifier: Apache-2.0
`timescale 1ns/1ps

module tb_autoisa_ci_cvxif_coprocessor;
  typedef logic [1:0] readregflags_t;
  typedef logic [0:0] writeregflags_t;
  typedef logic [2:0] id_t;
  typedef logic [31:0] hartid_t;
  typedef struct packed { logic [15:0] instr; hartid_t hartid; } x_compressed_req_t;
  typedef struct packed { logic [31:0] instr; logic accept; } x_compressed_resp_t;
  typedef struct packed { logic [31:0] instr; hartid_t hartid; id_t id; } x_issue_req_t;
  typedef struct packed {
    logic accept; writeregflags_t writeback; readregflags_t register_read;
  } x_issue_resp_t;
  typedef struct packed {
    hartid_t hartid; id_t id; logic [1:0][31:0] rs; readregflags_t rs_valid;
  } x_register_t;
  typedef struct packed { hartid_t hartid; id_t id; logic commit_kill; } x_commit_t;
  typedef struct packed {
    hartid_t hartid; id_t id; logic [31:0] data; logic [4:0] rd;
    writeregflags_t we;
  } x_result_t;
  typedef struct packed {
    logic compressed_valid; x_compressed_req_t compressed_req;
    logic issue_valid; x_issue_req_t issue_req;
    logic register_valid; x_register_t register;
    logic commit_valid; x_commit_t commit; logic result_ready;
  } cvxif_req_t;
  typedef struct packed {
    logic compressed_ready; x_compressed_resp_t compressed_resp;
    logic issue_ready; x_issue_resp_t issue_resp; logic register_ready;
    logic result_valid; x_result_t result;
  } cvxif_resp_t;

  logic clk = 0, rst_n = 0;
  cvxif_req_t req;
  cvxif_resp_t resp;
  always #5 clk = ~clk;

  autoisa_ci_cvxif_coprocessor #(
      .NR_RS(2), .XLEN(32), .TRANS_ID_WIDTH(3), .hartid_t(hartid_t),
      .x_issue_req_t(x_issue_req_t), .x_issue_resp_t(x_issue_resp_t),
      .x_register_t(x_register_t), .x_commit_t(x_commit_t),
      .x_result_t(x_result_t), .cvxif_req_t(cvxif_req_t),
      .cvxif_resp_t(cvxif_resp_t)
  ) dut (.clk_i(clk), .rst_ni(rst_n), .cvxif_req_i(req), .cvxif_resp_o(resp));

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

  task automatic issue_commit(input id_t id, input logic [31:0] instr,
                              input logic [31:0] a, input logic [31:0] b);
    begin
      @(negedge clk);
      req.issue_valid = 1; req.register_valid = 1; req.commit_valid = 1;
      req.issue_req.instr = instr; req.issue_req.id = id;
      req.issue_req.hartid = 32'h1234;
      req.register.id = id; req.register.hartid = 32'h1234;
      req.register.rs[0] = a; req.register.rs[1] = b;
      req.register.rs_valid = 2'b11;
      req.commit.id = id; req.commit.hartid = 32'h1234;
      req.commit.commit_kill = 0;
      #1;
      if (!resp.issue_ready || !resp.issue_resp.accept ||
          resp.issue_resp.register_read != 2'b11 || !resp.issue_resp.writeback[0])
        $fatal(1, "native CV-X-IF issue rejected id=%0d", id);
      @(posedge clk); @(negedge clk);
      // CVA6 can hold the commit level for an additional cycle after issue.
      // The bridge must not forward that level as a second shell commit.
      req.issue_valid = 0; req.register_valid = 0;
      #1;
      if (dut.commit_valid)
        $fatal(1, "held CV-X-IF commit was forwarded twice id=%0d", id);
      @(posedge clk); @(negedge clk);
      req.commit_valid = 0;
    end
  endtask

  initial begin
    req = '0; req.result_ready = 0;
    repeat (4) @(posedge clk); @(negedge clk); rst_n = 1;

    // Unsupported instruction is rejected through the real CV-X-IF contract.
    req.issue_valid = 1; req.register_valid = 1;
    req.issue_req.instr = 32'h0000_0013; #1;
    if (!resp.issue_ready || resp.issue_resp.accept)
      $fatal(1, "unsupported CV-X-IF instruction response mismatch");
    req.issue_valid = 0; req.register_valid = 0;

    issue_commit(1, enc_l0(0, 6, 1, 2), 32'd4, 32'd5);
    while (!resp.result_valid) @(negedge clk);
    if (resp.result.id != 1 || resp.result.rd != 6 ||
        resp.result.data != 9 || !resp.result.we[0] ||
        resp.result.hartid != 32'h1234)
      $fatal(1, "native CV-X-IF result mismatch");
    repeat (2) begin
      @(posedge clk); @(negedge clk);
      if (!resp.result_valid || resp.result.data != 9)
        $fatal(1, "CV-X-IF result changed under backpressure");
    end
    req.result_ready = 1; @(posedge clk); @(negedge clk);

    // Pair layouts require Direct-CI pair writeback and are rejected here.
    req.issue_valid = 1; req.register_valid = 1;
    req.issue_req.instr = enc_l3(3, 8, 1, 2); req.issue_req.id = 2;
    req.register.rs_valid = 2'b11; #1;
    if (!resp.issue_ready || resp.issue_resp.accept)
      $fatal(1, "pair layout incorrectly accepted by scalar CV-X-IF bridge");
    req.issue_valid = 0; req.register_valid = 0;

    $display("PASS: real CV-X-IF scalar AutoISA bridge issue/register/commit/result path");
    $finish;
  end

  initial begin #5000; $fatal(1, "timeout"); end
endmodule
