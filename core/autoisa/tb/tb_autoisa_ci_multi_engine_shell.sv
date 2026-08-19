// SPDX-License-Identifier: Apache-2.0
`timescale 1ns/1ps

module tb_autoisa_ci_multi_engine_shell;
  import autoisa_ci_types_pkg::*;
  localparam int unsigned DEPTH = 4;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic flush, req_valid, req_ready, req_duplicate;
  autoisa_ci_req_t req;
  logic commit_valid, kill_valid, kill_hit;
  logic [3:0] commit_tag, kill_tag;
  logic [1:0] commit_epoch, kill_epoch;
  logic result_valid, result_ready;
  autoisa_ci_rsp_t result;
  logic [2:0] request_occupancy, request_hwm;
  logic [2:0] inflight_occupancy, inflight_hwm;
  logic [2:0] result_occupancy, result_hwm;
  logic [2:0] reserved_credits, credit_hwm;
  logic pending_occupancy, pending_hwm;
  logic [31:0] accepted, dispatched, started, completed, retired, killed, orphan;
  logic [31:0] tombstone_drop, credit_stall, result_full_stall;
  logic [31:0] result_flush_drop, pending_kill_drop, pending_flush_drop;
  logic [2:0] observed_inflight_hwm, observed_credit_hwm;

  always #5 clk = ~clk;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      observed_inflight_hwm <= '0;
      observed_credit_hwm <= '0;
    end else begin
      if (inflight_hwm > observed_inflight_hwm)
        observed_inflight_hwm <= inflight_hwm;
      if (credit_hwm > observed_credit_hwm)
        observed_credit_hwm <= credit_hwm;
    end
  end

  autoisa_ci_concurrent_shell #(
      .REQUEST_DEPTH(DEPTH), .INFLIGHT_DEPTH(DEPTH), .RESULT_DEPTH(DEPTH),
      .MULTI_ENGINE(1'b1)
  ) dut (
      .clk_i(clk), .rst_ni(rst_n), .flush_i(flush),
      .req_valid_i(req_valid), .req_ready_o(req_ready), .req_i(req),
      .req_duplicate_o(req_duplicate),
      .commit_valid_i(commit_valid), .commit_tag_i(commit_tag),
      .commit_epoch_i(commit_epoch),
      .kill_valid_i(kill_valid), .kill_tag_i(kill_tag),
      .kill_epoch_i(kill_epoch), .kill_hit_o(kill_hit),
      .result_valid_o(result_valid), .result_ready_i(result_ready), .result_o(result),
      .request_occupancy_o(request_occupancy), .request_high_watermark_o(request_hwm),
      .inflight_occupancy_o(inflight_occupancy), .inflight_high_watermark_o(inflight_hwm),
      .result_occupancy_o(result_occupancy), .result_high_watermark_o(result_hwm),
      .reserved_result_credits_o(reserved_credits), .credit_high_watermark_o(credit_hwm),
      .engine_skid_occupancy_o(pending_occupancy),
      .engine_skid_high_watermark_o(pending_hwm),
      .accepted_count_o(accepted), .dispatched_count_o(dispatched),
      .engine_started_count_o(started), .completion_count_o(completed),
      .retired_count_o(retired), .killed_count_o(killed),
      .orphan_completion_count_o(orphan), .tombstone_drop_count_o(tombstone_drop),
      .credit_stall_count_o(credit_stall), .result_full_stall_count_o(result_full_stall),
      .result_flush_drop_count_o(result_flush_drop),
      .skid_killed_drop_count_o(pending_kill_drop),
      .skid_flush_drop_count_o(pending_flush_drop)
  );

  task automatic submit(input logic [3:0] tag, input logic [7:0] ci,
                        input logic [31:0] a, input logic [31:0] b);
    begin
      @(negedge clk);
      req = '0;
      req.tag = tag; req.epoch = 0; req.ci_id = ci;
      req.operand_valid = 6'b000011;
      req.operands[0] = a; req.operands[1] = b;
      req_valid = 1'b1;
      #1;
      while (!req_ready) begin
        @(negedge clk);
        #1;
      end
      if (req_duplicate) $fatal(1, "unexpected duplicate tag=%0d", tag);
      @(posedge clk); @(negedge clk); req_valid = 1'b0;
    end
  endtask

  task automatic do_commit(input logic [3:0] tag);
    begin
      @(negedge clk); commit_tag = tag; commit_epoch = 0; commit_valid = 1'b1;
      @(posedge clk); @(negedge clk); commit_valid = 1'b0;
    end
  endtask

  task automatic do_kill(input logic [3:0] tag);
    begin
      @(negedge clk); kill_tag = tag; kill_epoch = 0; kill_valid = 1'b1;
      #1; if (!kill_hit) $fatal(1, "kill missed tag=%0d", tag);
      @(posedge clk); @(negedge clk); kill_valid = 1'b0;
    end
  endtask

  task automatic consume(input logic [3:0] tag, input logic [31:0] value);
    begin
      while (!result_valid) @(negedge clk);
      if ((result.tag != tag) || (result.status != AUTOISA_STATUS_OK) ||
          (result.results[0] != value))
        $fatal(1, "result mismatch expected tag=%0d value=%h got tag=%0d value=%h",
               tag, value, result.tag, result.results[0]);
      result_ready = 1'b1;
      @(posedge clk); @(negedge clk); result_ready = 1'b0;
    end
  endtask

  initial begin
    flush = 0; req_valid = 0; req = '0; commit_valid = 0; commit_tag = 0;
    commit_epoch = 0; kill_valid = 0; kill_tag = 0; kill_epoch = 0;
    result_ready = 0;
    repeat (4) @(posedge clk); @(negedge clk); rst_n = 1'b1;

    // End-to-end oldest-ready/OOO: D0 on engine 0 bypasses two D9 requests
    // serialized on engine 1, while all completions still pass commit/result.
    submit(1, 9, 32'hffff0000, 32'h0f0f0f0f);
    submit(2, 9, 32'haaaa5555, 32'h12345678);
    submit(3, 0, 7, 35);
    submit(4, 8, 7, 9);
    do_commit(1); do_commit(2); do_commit(3); do_commit(4);
    consume(3, 42);
    consume(1, 32'hf0f00f0f);
    consume(2, 32'hb89e032d);
    consume(4, 16);

    // Pending kill releases its reserved credit immediately; running kill
    // retains a table tombstone until the engine's late response is drained.
    submit(5, 9, 32'h11110000, 32'h00ff00ff);
    submit(6, 9, 32'h22220000, 32'h0f0f0f0f);
    wait ((started == 5) && pending_occupancy);
    do_kill(6);
    do_kill(5);
    wait (orphan == 1);

    // Flush drops one cluster-pending request and clears the table/credits;
    // the already running response is later counted as an orphan.
    submit(7, 9, 32'h33330000, 32'h00ff00ff);
    submit(8, 9, 32'h44440000, 32'h0f0f0f0f);
    wait ((started == 6) && pending_occupancy);
    @(negedge clk); flush = 1'b1;
    @(posedge clk); @(negedge clk); flush = 1'b0;
    if ((request_occupancy != 0) || (inflight_occupancy != 0) ||
        (result_occupancy != 0) || (reserved_credits != 0))
      $fatal(1, "multi-engine flush left structural state");
    wait (orphan == 2);
    repeat (2) @(posedge clk); @(negedge clk);

    if ((accepted != 8) || (dispatched != 8) || (started != 6) ||
        (completed != 6) || (retired != 4) || (killed != 4) ||
        (orphan != 2) || (pending_kill_drop != 1) ||
        (pending_flush_drop != 1) || (reserved_credits != 0) ||
        (observed_inflight_hwm < 2) || (observed_credit_hwm < 2) ||
        ((retired + killed) != accepted))
      $fatal(1, "multi-shell accounting acc=%0d disp=%0d start=%0d comp=%0d ret=%0d kill=%0d orphan=%0d pkill=%0d pflush=%0d credit=%0d",
             accepted, dispatched, started, completed, retired, killed, orphan,
             pending_kill_drop, pending_flush_drop, reserved_credits);

    $display("DATA: accepted=%0d dispatched=%0d started=%0d completed=%0d retired=%0d killed=%0d orphan=%0d pending_kill=%0d pending_flush=%0d inflight_hwm=%0d credit_hwm=%0d",
             accepted, dispatched, started, completed, retired, killed, orphan,
             pending_kill_drop, pending_flush_drop,
             observed_inflight_hwm, observed_credit_hwm);
    $display("PASS: autoisa_ci_multi_engine_shell");
    $finish;
  end

  initial begin
    #10000;
    $fatal(1, "timeout acc=%0d disp=%0d start=%0d comp=%0d ret=%0d kill=%0d orphan=%0d rq=%0d inf=%0d res=%0d pending=%0b credits=%0d result_valid=%0b result_tag=%0d reqv=%0b reqtag=%0d ready=%0b qready=%0b tready=%0b qmatch=%0b tdup=%0b",
           accepted, dispatched, started, completed, retired, killed, orphan,
           request_occupancy, inflight_occupancy, result_occupancy,
           pending_occupancy, reserved_credits, result_valid, result.tag,
           req_valid, req.tag, req_ready, dut.queue_in_ready,
           dut.table_alloc_ready, dut.queue_identity_match,
           dut.table_alloc_duplicate);
  end
endmodule
