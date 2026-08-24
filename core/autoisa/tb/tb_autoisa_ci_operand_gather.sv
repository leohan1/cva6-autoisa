// SPDX-License-Identifier: Apache-2.0
`timescale 1ns / 1ps

module tb_autoisa_ci_operand_gather;
  import autoisa_ci_types_pkg::*;

  logic clk = 0, rst_n = 0, flush;
  logic desc_valid, desc_ready, desc_illegal;
  autoisa_ci_host_desc_t desc;
  logic rf_req_valid, rf_req_ready;
  logic [1:0] rf_lane_valid;
  logic [1:0][4:0] rf_addr;
  logic [1:0][31:0] rf_data;
  logic req_valid, req_ready;
  autoisa_ci_req_t req;
  logic kill_valid, kill_hit;
  logic [3:0] kill_tag;
  logic [1:0] kill_epoch;
  logic [2:0] occupancy, hwm, observed_hwm;
  logic [31:0] accepted, emitted, beats, killed, flush_drop;

  always #5 clk = ~clk;
  always_comb begin
    rf_data[0] = 32'h1000_0000 | rf_addr[0];
    rf_data[1] = 32'h1000_0000 | rf_addr[1];
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) observed_hwm <= '0;
    else if (hwm > observed_hwm) observed_hwm <= hwm;
  end

  autoisa_ci_operand_gather #(
      .PENDING_DEPTH(4)
  ) dut (
      .clk_i(clk),
      .rst_ni(rst_n),
      .flush_i(flush),
      .desc_valid_i(desc_valid),
      .desc_ready_o(desc_ready),
      .desc_i(desc),
      .desc_illegal_o(desc_illegal),
      .rf_req_valid_o(rf_req_valid),
      .rf_req_ready_i(rf_req_ready),
      .rf_lane_valid_o(rf_lane_valid),
      .rf_addr_o(rf_addr),
      .rf_data_i(rf_data),
      .req_valid_o(req_valid),
      .req_ready_i(req_ready),
      .req_o(req),
      .kill_valid_i(kill_valid),
      .kill_tag_i(kill_tag),
      .kill_epoch_i(kill_epoch),
      .kill_hit_o(kill_hit),
      .occupancy_o(occupancy),
      .high_watermark_o(hwm),
      .accepted_count_o(accepted),
      .emitted_count_o(emitted),
      .gather_beat_count_o(beats),
      .killed_count_o(killed),
      .flush_drop_count_o(flush_drop)
  );

  task automatic make_desc(input logic [3:0] tag, input int unsigned nsrc, input logic [4:0] base);
    begin
      desc = '0;
      desc.tag = tag;
      desc.epoch = 0;
      desc.ci_id = tag;
      desc.layout_id = tag;
      desc.imm_valid = tag[0];
      desc.immediate = 32'h8000_0000 | tag;
      for (int unsigned i = 0; i < AUTOISA_MAX_SRC; i++) begin
        if (i < nsrc) begin
          desc.src_valid[i] = 1'b1;
          desc.src_addr[i]  = base + i;
        end
      end
    end
  endtask

  task automatic submit(input logic [3:0] tag, input int unsigned nsrc, input logic [4:0] base);
    begin
      @(negedge clk);
      make_desc(tag, nsrc, base);
      desc_valid = 1;
      #1;
      while (!desc_ready) begin
        @(negedge clk);
        #1;
      end
      if (desc_illegal) $fatal(1, "legal descriptor rejected tag=%0d", tag);
      @(posedge clk);
      @(negedge clk);
      desc_valid = 0;
    end
  endtask

  task automatic consume(input logic [3:0] tag, input int unsigned nsrc, input logic [4:0] base);
    autoisa_ci_req_t held;
    begin
      while (!req_valid) @(negedge clk);
      held = req;
      repeat (2) begin
        @(posedge clk);
        @(negedge clk);
        if (!req_valid || (req != held)) $fatal(1, "gather output unstable tag=%0d", tag);
      end
      if ((req.tag != tag) || (req.ci_id != tag) ||
          (req.operand_valid != ((1 << nsrc) - 1)) ||
          (req.imm_valid != tag[0]) ||
          (req.immediate != (32'h8000_0000 | tag)))
        $fatal(1, "gather metadata mismatch tag=%0d", tag);
      for (int unsigned i = 0; i < nsrc; i++) begin
        if (req.operands[i] != (32'h1000_0000 | (base + i)))
          $fatal(1, "operand mismatch tag=%0d src=%0d got=%h", tag, i, req.operands[i]);
      end
      req_ready = 1;
      @(posedge clk);
      @(negedge clk);
      req_ready = 0;
    end
  endtask

  task automatic do_kill(input logic [3:0] tag);
    begin
      @(negedge clk);
      kill_tag   = tag;
      kill_epoch = 0;
      kill_valid = 1;
      #1;
      if (!kill_hit) $fatal(1, "kill missed gather tag=%0d", tag);
      @(posedge clk);
      @(negedge clk);
      kill_valid = 0;
    end
  endtask

  initial begin
    flush = 0;
    desc_valid = 0;
    desc = '0;
    rf_req_ready = 1;
    req_ready = 0;
    kill_valid = 0;
    kill_tag = 0;
    kill_epoch = 0;
    repeat (4) @(posedge clk);
    @(negedge clk);
    rst_n = 1;

    // Exact 1/2/3-beat behavior for all source counts 1 through 6.
    for (int unsigned n = 1; n <= 6; n++) begin
      submit(n[3:0], n, 5'd1);
      consume(n[3:0], n, 5'd1);
    end

    // Four-descriptor burst while the physical RF arbiter is blocked.
    rf_req_ready = 0;
    submit(7, 2, 1);
    submit(8, 2, 3);
    submit(9, 2, 5);
    submit(10, 2, 7);
    if ((occupancy != 4) || (hwm < 4))
      $fatal(1, "four-descriptor burst not retained occ=%0d hwm=%0d", occupancy, hwm);
    rf_req_ready = 1;
    consume(7, 2, 1);
    consume(8, 2, 3);
    consume(9, 2, 5);
    consume(10, 2, 7);

    // Queued kill leaves the active descriptor intact.
    rf_req_ready = 0;
    submit(11, 6, 1);
    submit(12, 2, 9);
    wait (rf_req_valid && (occupancy == 2));
    do_kill(12);
    rf_req_ready = 1;
    consume(11, 6, 1);

    // Kill after one gather beat must discard the partial snapshot.
    rf_req_ready = 0;
    submit(13, 6, 2);
    wait (rf_req_valid);
    @(negedge clk);
    rf_req_ready = 1;
    @(posedge clk);
    @(negedge clk);
    rf_req_ready = 0;
    do_kill(13);
    repeat (2) @(posedge clk);
    if (req_valid) $fatal(1, "active killed descriptor emitted a request");

    // Flush drops both active and queued descriptors with no metadata leak.
    submit(14, 4, 1);
    submit(15, 2, 9);
    wait (occupancy == 2);
    @(negedge clk);
    flush = 1;
    @(posedge clk);
    @(negedge clk);
    flush = 0;
    if ((occupancy != 0) || req_valid || rf_req_valid || (flush_drop != 2))
      $fatal(1, "gather flush failed occ=%0d flush_drop=%0d", occupancy, flush_drop);

    if ((accepted != 15) || (emitted != 11) || (beats != 20) ||
        (killed != 2) || (flush_drop != 2) || (observed_hwm < 4))
      $fatal(
          1,
          "gather counters mismatch accepted=%0d emitted=%0d beats=%0d killed=%0d flush=%0d hwm=%0d",
          accepted,
          emitted,
          beats,
          killed,
          flush_drop,
          observed_hwm
      );

    $display("DATA: accepted=%0d emitted=%0d gather_beats=%0d killed=%0d flush_drop=%0d hwm=%0d",
             accepted, emitted, beats, killed, flush_drop, observed_hwm);
    $display("PASS: autoisa_ci_operand_gather");
    $finish;
  end

  initial begin
    #20000;
    $fatal(1, "timeout accepted=%0d emitted=%0d occ=%0d", accepted, emitted, occupancy);
  end
endmodule
