// SPDX-License-Identifier: Apache-2.0
// Fixed-seed, bit-exact randomized regression for the concurrent CI shell.
`timescale 1ns / 1ps

module tb_autoisa_ci_random_100k #(
    parameter bit MULTI_ENGINE = 1'b0
);
  import autoisa_ci_types_pkg::*;

  localparam int unsigned REQUEST_DEPTH = 4;
  localparam int unsigned INFLIGHT_DEPTH = 4;
  localparam int unsigned RESULT_DEPTH = 4;
  localparam int unsigned STIMULUS_CYCLES = 100000;
  localparam logic [31:0] RANDOM_SEED = 32'h1a2b_3c4d;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic flush;
  logic req_valid, req_ready, req_duplicate;
  autoisa_ci_req_t req;
  logic commit_valid;
  logic [AUTOISA_TAG_WIDTH-1:0] commit_tag;
  logic [AUTOISA_EPOCH_WIDTH-1:0] commit_epoch;
  logic kill_valid, kill_hit;
  logic [  AUTOISA_TAG_WIDTH-1:0] kill_tag;
  logic [AUTOISA_EPOCH_WIDTH-1:0] kill_epoch;
  logic result_valid, result_ready;
  autoisa_ci_rsp_t result;
  logic [$clog2(REQUEST_DEPTH+1)-1:0] request_occupancy;
  logic [$clog2(REQUEST_DEPTH+1)-1:0] request_high_watermark;
  logic [$clog2(INFLIGHT_DEPTH+1)-1:0] inflight_occupancy;
  logic [$clog2(INFLIGHT_DEPTH+1)-1:0] inflight_high_watermark;
  logic [$clog2(RESULT_DEPTH+1)-1:0] result_occupancy;
  logic [$clog2(RESULT_DEPTH+1)-1:0] result_high_watermark;
  logic [$clog2(RESULT_DEPTH+1)-1:0] reserved_result_credits;
  logic [$clog2(RESULT_DEPTH+1)-1:0] credit_high_watermark;
  logic engine_skid_occupancy, engine_skid_high_watermark;
  logic [31:0] accepted_count, dispatched_count, engine_started_count;
  logic [31:0] completion_count, retired_count, killed_count;
  logic [31:0] orphan_completion_count, tombstone_drop_count;
  logic [31:0] credit_stall_count, result_full_stall_count;
  logic [31:0] result_flush_drop_count;
  logic [31:0] skid_killed_drop_count, skid_flush_drop_count;

  logic live[0:15];
  logic committed[0:15];
  autoisa_ci_rsp_t expected[0:15];
  autoisa_ci_req_t expected_req[0:15];
  autoisa_ci_rsp_t engine_expected;
  logic engine_tracking;
  integer ci_hits[0:11];
  integer model_accepted, model_retired, model_killed, model_flushes;
  integer observed_request_hwm, observed_inflight_hwm;
  integer observed_result_hwm, observed_credit_hwm;
  integer sb_i;

  always #5 clk = ~clk;

  function automatic logic [31:0] prng_next(input logic [31:0] value);
    logic [31:0] x;
    begin
      x = value;
      x = x ^ (x << 13);
      x = x ^ (x >> 17);
      x = x ^ (x << 5);
      prng_next = x;
    end
  endfunction

  function automatic autoisa_ci_rsp_t reference_execute(input autoisa_ci_req_t item);
    autoisa_ci_rsp_t answer;
    logic [31:0] ab;
    logic [4:0] shamt;
    begin
      answer = '0;
      answer.tag = item.tag;
      answer.epoch = item.epoch;
      answer.status = AUTOISA_STATUS_OK;
      case (item.ci_id)
        8'd0: begin
          answer.result_valid = 2'b01;
          answer.results[0]   = item.operands[0] + item.operands[1];
        end
        8'd1: begin
          answer.result_valid = 2'b01;
          answer.results[0]   = (item.operands[0] * item.operands[1]) + item.operands[2];
        end
        8'd2: begin
          answer.result_valid = 2'b01;
          answer.results[0] = ((item.operands[0] * item.operands[1]) +
                               item.operands[2]) ^ item.operands[3];
        end
        8'd3: begin
          answer.result_valid = 2'b11;
          answer.results[0]   = item.operands[0] + item.operands[1];
          answer.results[1]   = item.operands[0] - item.operands[1];
        end
        8'd4: begin
          answer.result_valid = 2'b11;
          answer.results[0] = (item.operands[0] * item.operands[2]) -
                              (item.operands[1] * item.operands[3]);
          answer.results[1] = (item.operands[0] * item.operands[3]) +
                              (item.operands[1] * item.operands[2]);
        end
        8'd5: begin
          answer.result_valid = 2'b01;
          answer.results[0] = item.operands[0] + item.operands[1] +
                              item.operands[2] + item.operands[3] +
                              item.operands[4] + item.operands[5];
        end
        8'd6: begin
          ab = item.operands[0] * item.operands[1];
          answer.result_valid = 2'b11;
          answer.results[0] = ab + (item.operands[2] * item.operands[3]) +
                              (item.operands[4] * item.operands[5]);
          answer.results[1] = ab - (item.operands[2] * item.operands[3]) +
                              (item.operands[4] * item.operands[5]);
        end
        8'd7: begin
          shamt = item.immediate[4:0];
          answer.result_valid = 2'b01;
          answer.results[0] = (item.operands[0] << shamt) ^ (item.operands[1] + item.immediate);
        end
        8'd8, 8'd10: begin
          answer.result_valid = 2'b01;
          answer.results[0]   = item.operands[0] + item.operands[1];
        end
        8'd9: begin
          answer.result_valid = 2'b01;
          answer.results[0]   = item.operands[0] ^ item.operands[1];
        end
        8'd11: begin
          answer.result_valid = 2'b00;
          answer.status = AUTOISA_STATUS_ENGINE_FAULT;
        end
        default: answer.status = AUTOISA_STATUS_UNSUPPORTED;
      endcase
      reference_execute = answer;
    end
  endfunction

  function automatic integer live_count;
    integer n;
    integer j;
    begin
      n = 0;
      for (j = 0; j < 16; j = j + 1) if (live[j]) n = n + 1;
      live_count = n;
    end
  endfunction

  function automatic integer committed_count;
    integer n;
    integer j;
    begin
      n = 0;
      for (j = 0; j < 16; j = j + 1) if (live[j] && committed[j]) n = n + 1;
      committed_count = n;
    end
  endfunction

  autoisa_ci_concurrent_shell #(
      .REQUEST_DEPTH (REQUEST_DEPTH),
      .INFLIGHT_DEPTH(INFLIGHT_DEPTH),
      .RESULT_DEPTH  (RESULT_DEPTH),
      .MULTI_ENGINE  (MULTI_ENGINE)
  ) dut (
      .clk_i(clk),
      .rst_ni(rst_n),
      .flush_i(flush),
      .req_valid_i(req_valid),
      .req_ready_o(req_ready),
      .req_i(req),
      .req_duplicate_o(req_duplicate),
      .commit_valid_i(commit_valid),
      .commit_tag_i(commit_tag),
      .commit_epoch_i(commit_epoch),
      .kill_valid_i(kill_valid),
      .kill_tag_i(kill_tag),
      .kill_epoch_i(kill_epoch),
      .kill_hit_o(kill_hit),
      .result_valid_o(result_valid),
      .result_ready_i(result_ready),
      .result_o(result),
      .request_occupancy_o(request_occupancy),
      .request_high_watermark_o(request_high_watermark),
      .inflight_occupancy_o(inflight_occupancy),
      .inflight_high_watermark_o(inflight_high_watermark),
      .result_occupancy_o(result_occupancy),
      .result_high_watermark_o(result_high_watermark),
      .reserved_result_credits_o(reserved_result_credits),
      .credit_high_watermark_o(credit_high_watermark),
      .engine_skid_occupancy_o(engine_skid_occupancy),
      .engine_skid_high_watermark_o(engine_skid_high_watermark),
      .accepted_count_o(accepted_count),
      .dispatched_count_o(dispatched_count),
      .engine_started_count_o(engine_started_count),
      .completion_count_o(completion_count),
      .retired_count_o(retired_count),
      .killed_count_o(killed_count),
      .orphan_completion_count_o(orphan_completion_count),
      .tombstone_drop_count_o(tombstone_drop_count),
      .credit_stall_count_o(credit_stall_count),
      .result_full_stall_count_o(result_full_stall_count),
      .result_flush_drop_count_o(result_flush_drop_count),
      .skid_killed_drop_count_o(skid_killed_drop_count),
      .skid_flush_drop_count_o(skid_flush_drop_count)
  );

  // Scoreboard samples the same pre-NBA handshake values as the DUT.
  always @(posedge clk) begin
    if (!rst_n) begin
      model_accepted = 0;
      model_retired = 0;
      model_killed = 0;
      model_flushes = 0;
      observed_request_hwm = 0;
      observed_inflight_hwm = 0;
      observed_result_hwm = 0;
      observed_credit_hwm = 0;
      engine_expected = '0;
      engine_tracking = 1'b0;
      for (sb_i = 0; sb_i < 16; sb_i = sb_i + 1) begin
        live[sb_i] = 1'b0;
        committed[sb_i] = 1'b0;
        expected[sb_i] = '0;
        expected_req[sb_i] = '0;
      end
      for (sb_i = 0; sb_i < 12; sb_i = sb_i + 1) ci_hits[sb_i] = 0;
    end else begin
      if (request_high_watermark > observed_request_hwm)
        observed_request_hwm = request_high_watermark;
      if (inflight_high_watermark > observed_inflight_hwm)
        observed_inflight_hwm = inflight_high_watermark;
      if (result_high_watermark > observed_result_hwm) observed_result_hwm = result_high_watermark;
      if (credit_high_watermark > observed_credit_hwm) observed_credit_hwm = credit_high_watermark;

      if (flush) begin
        model_flushes = model_flushes + 1;
        for (sb_i = 0; sb_i < 16; sb_i = sb_i + 1) begin
          if (live[sb_i]) model_killed = model_killed + 1;
          live[sb_i] = 1'b0;
          committed[sb_i] = 1'b0;
        end
      end else begin
        if (req_valid && req_ready) begin
          if (req_duplicate || live[req.tag])
            $fatal(1, "accepted duplicate identity tag=%0d epoch=%0d", req.tag, req.epoch);
          live[req.tag] = 1'b1;
          committed[req.tag] = 1'b0;
          expected[req.tag] = reference_execute(req);
          expected_req[req.tag] = req;
          model_accepted = model_accepted + 1;
          ci_hits[req.ci_id] = ci_hits[req.ci_id] + 1;
        end
        if (commit_valid) begin
          if (!live[commit_tag] || committed[commit_tag])
            $fatal(1, "invalid model commit tag=%0d", commit_tag);
          committed[commit_tag] = 1'b1;
        end
        if (kill_valid) begin
          if (!kill_hit || !live[kill_tag] || committed[kill_tag])
            $fatal(1, "invalid or missed kill tag=%0d hit=%0b", kill_tag, kill_hit);
          live[kill_tag] = 1'b0;
          committed[kill_tag] = 1'b0;
          model_killed = model_killed + 1;
        end
        if (result_valid && result_ready) begin
          if (!live[result.tag] || !committed[result.tag])
            $fatal(1, "unexpected result tag=%0d epoch=%0d", result.tag, result.epoch);
          if (result !== expected[result.tag])
            $fatal(
                1,
                "bit-exact mismatch tag=%0d ci=D%0d op0=%h op1=%h op2=%h op3=%h imm=%h got=%h expected=%h",
                result.tag,
                expected_req[result.tag].ci_id,
                expected_req[result.tag].operands[0],
                expected_req[result.tag].operands[1],
                expected_req[result.tag].operands[2],
                expected_req[result.tag].operands[3],
                expected_req[result.tag].immediate,
                result,
                expected[result.tag]
            );
          live[result.tag] = 1'b0;
          committed[result.tag] = 1'b0;
          model_retired = model_retired + 1;
        end
        if (!MULTI_ENGINE && dut.engine_req_valid && dut.engine_req_ready) begin
          if (!live[dut.engine_req.tag] || (dut.engine_req !== expected_req[dut.engine_req.tag]))
            $fatal(
                1,
                "engine request corruption tag=%0d got_ci=D%0d expected_ci=D%0d got_imm=%h expected_imm=%h",
                dut.engine_req.tag,
                dut.engine_req.ci_id,
                expected_req[dut.engine_req.tag].ci_id,
                dut.engine_req.immediate,
                expected_req[dut.engine_req.tag].immediate
            );
          engine_expected = reference_execute(dut.engine_req);
          engine_tracking = 1'b1;
        end
        if (!MULTI_ENGINE && dut.engine_rsp_valid && dut.engine_rsp_ready) begin
          if (!engine_tracking || (dut.engine_rsp !== engine_expected))
            $fatal(
                1,
                "engine response mismatch got=%h expected=%h tracking=%0b",
                dut.engine_rsp,
                engine_expected,
                engine_tracking
            );
          engine_tracking = 1'b0;
        end
      end
    end
  end

  initial begin : stimulus
    logic [31:0] random_state;
    logic [AUTOISA_EPOCH_WIDTH-1:0] current_epoch;
    integer cycle_number, j, selected_tag, start_tag, drain_cycles;
    integer json_file;
    logic   pending_flush;

    flush = 1'b0;
    req_valid = 1'b0;
    req = '0;
    commit_valid = 1'b0;
    commit_tag = '0;
    commit_epoch = '0;
    kill_valid = 1'b0;
    kill_tag = '0;
    kill_epoch = '0;
    result_ready = 1'b0;
    random_state = RANDOM_SEED;
    current_epoch = '0;
    pending_flush = 1'b0;

    repeat (4) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    for (cycle_number = 0; cycle_number < STIMULUS_CYCLES; cycle_number = cycle_number + 1) begin
      @(negedge clk);
      flush = 1'b0;
      commit_valid = 1'b0;
      kill_valid = 1'b0;

      if ((cycle_number != 0) && ((cycle_number % 20000) == 0)) pending_flush = 1'b1;

      random_state = prng_next(random_state);
      // Random backpressure plus a deterministic 16-cycle stall window.
      result_ready = random_state[0] && ((cycle_number % 257) >= 16);

      if (pending_flush) begin
        req_valid = 1'b0;
        result_ready = 1'b1;
        if ((committed_count() == 0) && (result_occupancy == 0)) begin
          flush = 1'b1;
          pending_flush = 1'b0;
          current_epoch = current_epoch + 1'b1;
        end
      end else begin
        // A valid request remains stable until accepted.
        if (req_valid && req_ready) req_valid = 1'b0;
        if (!req_valid) begin
          random_state = prng_next(random_state);
          if (random_state[2:0] < 3'd5) begin
            selected_tag = -1;
            start_tag = random_state[7:4];
            for (j = 0; j < 16; j = j + 1)
            if ((selected_tag < 0) && !live[(start_tag+j)&15]) selected_tag = (start_tag + j) & 15;
            if (selected_tag >= 0) begin
              req = '0;
              req.tag = selected_tag[AUTOISA_TAG_WIDTH-1:0];
              req.epoch = current_epoch;
              random_state = prng_next(random_state);
              req.ci_id = random_state % 12;
              req.operand_valid = 6'b11_1111;
              for (j = 0; j < 6; j = j + 1) begin
                random_state = prng_next(random_state);
                req.operands[j] = random_state;
              end
              random_state = prng_next(random_state);
              req.imm_valid = 1'b1;
              req.immediate = random_state;
              req_valid = 1'b1;
            end
          end
        end

        // Choose at most one terminal-control action each cycle.
        random_state = prng_next(random_state);
        if ((live_count() >= INFLIGHT_DEPTH) || (random_state[3:0] < 4'd2)) begin
          selected_tag = -1;
          start_tag = random_state[7:4];
          for (j = 0; j < 16; j = j + 1)
          if ((selected_tag < 0) && live[(start_tag+j)&15] && !committed[(start_tag+j)&15])
            selected_tag = (start_tag + j) & 15;
          if (selected_tag >= 0) begin
            if (random_state[8]) begin
              commit_valid = 1'b1;
              commit_tag   = selected_tag[AUTOISA_TAG_WIDTH-1:0];
              commit_epoch = current_epoch;
            end else begin
              kill_valid = 1'b1;
              kill_tag   = selected_tag[AUTOISA_TAG_WIDTH-1:0];
              kill_epoch = current_epoch;
            end
          end
        end
      end
      @(posedge clk);
    end

    // Deterministically drain every accepted request after the 100k stimulus.
    @(negedge clk);
    flush = 1'b0;
    req_valid = 1'b0;
    kill_valid = 1'b0;
    result_ready = 1'b1;
    drain_cycles = 0;
    while (((live_count() != 0) || (request_occupancy != 0) ||
            (inflight_occupancy != 0) || (result_occupancy != 0) ||
            engine_skid_occupancy || (reserved_result_credits != 0)) &&
           (drain_cycles < 10000)) begin
      commit_valid = 1'b0;
      selected_tag = -1;
      for (j = 0; j < 16; j = j + 1)
      if ((selected_tag < 0) && live[j] && !committed[j]) selected_tag = j;
      if (selected_tag >= 0) begin
        commit_valid = 1'b1;
        commit_tag   = selected_tag[AUTOISA_TAG_WIDTH-1:0];
        commit_epoch = current_epoch;
      end
      @(posedge clk);
      @(negedge clk);
      drain_cycles = drain_cycles + 1;
    end
    commit_valid = 1'b0;
    if (drain_cycles >= 10000)
      $fatal(
          1,
          "random regression drain timeout live=%0d committed=%0d req_occ=%0d inf_occ=%0d res_occ=%0d skid=%0b credits=%0d engine_tracking=%0b",
          live_count(),
          committed_count(),
          request_occupancy,
          inflight_occupancy,
          result_occupancy,
          engine_skid_occupancy,
          reserved_result_credits,
          engine_tracking
      );

    // Let any killed long-latency engine operation report its orphan response.
    repeat (32) @(posedge clk);
    @(negedge clk);

    if (accepted_count != model_accepted)
      $fatal(1, "accepted counter mismatch dut=%0d model=%0d", accepted_count, model_accepted);
    if (retired_count != model_retired)
      $fatal(1, "retired counter mismatch dut=%0d model=%0d", retired_count, model_retired);
    if (killed_count != model_killed)
      $fatal(1, "killed counter mismatch dut=%0d model=%0d", killed_count, model_killed);
    if (model_accepted != (model_retired + model_killed))
      $fatal(
          1,
          "accounting mismatch accepted=%0d retired=%0d killed=%0d",
          model_accepted,
          model_retired,
          model_killed
      );
    if (model_flushes != 4) $fatal(1, "expected four safe flushes, got %0d", model_flushes);
    if ((!MULTI_ENGINE && (observed_result_hwm != RESULT_DEPTH)) ||
        (MULTI_ENGINE && (observed_result_hwm < 2)))
      $fatal(1, "random backpressure did not fill result queue: hwm=%0d", observed_result_hwm);
    for (j = 0; j < 12; j = j + 1)
    if (ci_hits[j] == 0) $fatal(1, "D%0d received no accepted request", j);

    if (MULTI_ENGINE) json_file = $fopen("ci/autoisa/logs/autoisa_ci_random_100k_multi.json", "w");
    else json_file = $fopen("ci/autoisa/logs/autoisa_ci_random_100k.json", "w");
    if (json_file == 0) $fatal(1, "could not create random regression JSON");
    $fdisplay(json_file, "{");
    $fdisplay(json_file, "  \"seed\": \"0x%08x\",", RANDOM_SEED);
    $fdisplay(json_file, "  \"stimulus_cycles\": %0d,", STIMULUS_CYCLES);
    $fdisplay(json_file, "  \"accepted\": %0d,", model_accepted);
    $fdisplay(json_file, "  \"retired\": %0d,", model_retired);
    $fdisplay(json_file, "  \"killed\": %0d,", model_killed);
    $fdisplay(json_file, "  \"flushes\": %0d,", model_flushes);
    $fdisplay(json_file, "  \"orphan_completions\": %0d,", orphan_completion_count);
    $fdisplay(json_file, "  \"request_hwm\": %0d,", observed_request_hwm);
    $fdisplay(json_file, "  \"inflight_hwm\": %0d,", observed_inflight_hwm);
    $fdisplay(json_file, "  \"result_hwm\": %0d,", observed_result_hwm);
    $fdisplay(json_file, "  \"credit_hwm\": %0d,", observed_credit_hwm);
    $fdisplay(json_file, "  \"credit_stall_cycles\": %0d,", credit_stall_count);
    $fdisplay(json_file, "  \"errors\": 0");
    $fdisplay(json_file, "}");
    $fclose(json_file);

    $display(
        "DATA: seed=0x%08x cycles=%0d accepted=%0d retired=%0d killed=%0d flushes=%0d orphan=%0d req_hwm=%0d inf_hwm=%0d res_hwm=%0d credit_hwm=%0d credit_stall=%0d",
        RANDOM_SEED, STIMULUS_CYCLES, model_accepted, model_retired, model_killed, model_flushes,
        orphan_completion_count, observed_request_hwm, observed_inflight_hwm, observed_result_hwm,
        observed_credit_hwm, credit_stall_count);
    $display("PASS: autoisa_ci_random_100k");
    $finish;
  end
endmodule

module tb_autoisa_ci_random_100k_multi;
  tb_autoisa_ci_random_100k #(.MULTI_ENGINE(1'b1)) i_multi_random ();
endmodule
