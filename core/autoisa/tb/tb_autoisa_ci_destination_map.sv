// SPDX-License-Identifier: Apache-2.0
`timescale 1ns / 1ps

module tb_autoisa_ci_destination_map;
  import autoisa_ci_types_pkg::*;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic flush;
  logic reserve_valid, reserve_ready;
  autoisa_ci_host_desc_t reserve_desc;
  autoisa_ci_write_policy_e reserve_policy;
  logic reserve_duplicate, reserve_tag_busy, reserve_raw, reserve_waw, reserve_illegal;
  logic release_valid, release_hit, release_stale;
  logic [  AUTOISA_TAG_WIDTH-1:0] release_tag;
  logic [AUTOISA_EPOCH_WIDTH-1:0] release_epoch;
  logic lookup_valid, lookup_hit, lookup_stale;
  logic [AUTOISA_TAG_WIDTH-1:0] lookup_tag;
  logic [AUTOISA_EPOCH_WIDTH-1:0] lookup_epoch;
  logic [AUTOISA_MAX_DST-1:0] lookup_dst_valid;
  logic [AUTOISA_MAX_DST-1:0][4:0] lookup_dst_addr;
  autoisa_ci_write_policy_e lookup_policy;
  logic [31:0] standard_pending_write_mask;
  logic [2:0] std_src_valid;
  logic [2:0][4:0] std_src_addr;
  logic std_dst_valid;
  logic [4:0] std_dst_addr;
  logic std_raw, std_waw;
  logic [31:0] busy_mask;
  logic [2:0] occupancy, high_watermark;
  logic [31:0] reserve_count, release_count, conflict_count;
  logic [31:0] stale_release_count, flush_drop_count;
  logic [2:0] observed_hwm;

  always #5 clk = ~clk;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) observed_hwm <= '0;
    else if (high_watermark > observed_hwm) observed_hwm <= high_watermark;
  end

  autoisa_ci_destination_map #(
      .ENTRIES(4),
      .STD_SRC_PORTS(3)
  ) dut (
      .clk_i(clk),
      .rst_ni(rst_n),
      .flush_i(flush),
      .reserve_valid_i(reserve_valid),
      .reserve_ready_o(reserve_ready),
      .reserve_desc_i(reserve_desc),
      .reserve_write_policy_i(reserve_policy),
      .reserve_duplicate_o(reserve_duplicate),
      .reserve_tag_busy_o(reserve_tag_busy),
      .reserve_raw_hazard_o(reserve_raw),
      .reserve_waw_hazard_o(reserve_waw),
      .reserve_illegal_o(reserve_illegal),
      .release_valid_i(release_valid),
      .release_tag_i(release_tag),
      .release_epoch_i(release_epoch),
      .release_hit_o(release_hit),
      .release_stale_o(release_stale),
      .lookup_valid_i(lookup_valid),
      .lookup_tag_i(lookup_tag),
      .lookup_epoch_i(lookup_epoch),
      .lookup_hit_o(lookup_hit),
      .lookup_stale_o(lookup_stale),
      .lookup_dst_valid_o(lookup_dst_valid),
      .lookup_dst_addr_o(lookup_dst_addr),
      .lookup_write_policy_o(lookup_policy),
      .standard_pending_write_mask_i(standard_pending_write_mask),
      .std_src_valid_i(std_src_valid),
      .std_src_addr_i(std_src_addr),
      .std_dst_valid_i(std_dst_valid),
      .std_dst_addr_i(std_dst_addr),
      .std_raw_hazard_o(std_raw),
      .std_waw_hazard_o(std_waw),
      .busy_mask_o(busy_mask),
      .occupancy_o(occupancy),
      .high_watermark_o(high_watermark),
      .reserve_count_o(reserve_count),
      .release_count_o(release_count),
      .conflict_count_o(conflict_count),
      .stale_release_count_o(stale_release_count),
      .flush_drop_count_o(flush_drop_count)
  );

  task automatic make_scalar(input logic [3:0] tag, input logic [1:0] epoch, input logic [4:0] dst);
    begin
      reserve_desc = '0;
      reserve_desc.tag = tag;
      reserve_desc.epoch = epoch;
      reserve_desc.dst_valid = 2'b01;
      reserve_desc.dst_addr[0] = dst;
      reserve_policy = AUTOISA_WRITE_SCALAR;
    end
  endtask

  task automatic make_pair(input logic [3:0] tag, input logic [1:0] epoch, input logic [4:0] dst0);
    begin
      reserve_desc = '0;
      reserve_desc.tag = tag;
      reserve_desc.epoch = epoch;
      reserve_desc.dst_valid = 2'b11;
      reserve_desc.dst_addr[0] = dst0;
      reserve_desc.dst_addr[1] = dst0 + 1'b1;
      reserve_desc.pair_constrained = 1'b1;
      reserve_policy = AUTOISA_WRITE_PAIR_SERIAL;
    end
  endtask

  task automatic accept_current;
    begin
      reserve_valid = 1'b1;
      #1;
      if (!reserve_ready)
        $fatal(
            1,
            "expected reservation accept tag=%0d epoch=%0d raw=%0b waw=%0b illegal=%0b dup=%0b tagbusy=%0b",
            reserve_desc.tag,
            reserve_desc.epoch,
            reserve_raw,
            reserve_waw,
            reserve_illegal,
            reserve_duplicate,
            reserve_tag_busy
        );
      @(posedge clk);
      @(negedge clk);
      reserve_valid = 1'b0;
    end
  endtask

  task automatic reject_current(input logic expect_raw, input logic expect_waw,
                                input logic expect_illegal, input logic expect_dup,
                                input logic expect_tag_busy);
    begin
      reserve_valid = 1'b1;
      #1;
      if (reserve_ready || (reserve_raw != expect_raw) || (reserve_waw != expect_waw) ||
          (reserve_illegal != expect_illegal) ||
          (reserve_duplicate != expect_dup) || (reserve_tag_busy != expect_tag_busy))
        $fatal(
            1,
            "reservation reject reason mismatch ready=%0b raw=%0b waw=%0b illegal=%0b dup=%0b tagbusy=%0b",
            reserve_ready,
            reserve_raw,
            reserve_waw,
            reserve_illegal,
            reserve_duplicate,
            reserve_tag_busy
        );
      @(posedge clk);
      @(negedge clk);
      reserve_valid = 1'b0;
    end
  endtask

  task automatic do_release(input logic [3:0] tag, input logic [1:0] epoch, input logic expect_hit,
                            input logic expect_stale);
    begin
      release_tag   = tag;
      release_epoch = epoch;
      release_valid = 1'b1;
      #1;
      if ((release_hit != expect_hit) || (release_stale != expect_stale))
        $fatal(
            1,
            "release mismatch tag=%0d epoch=%0d hit=%0b stale=%0b",
            tag,
            epoch,
            release_hit,
            release_stale
        );
      @(posedge clk);
      @(negedge clk);
      release_valid = 1'b0;
    end
  endtask

  initial begin
    flush = 0;
    reserve_valid = 0;
    reserve_desc = '0;
    reserve_policy = AUTOISA_WRITE_NONE;
    release_valid = 0;
    release_tag = 0;
    release_epoch = 0;
    lookup_valid = 0;
    lookup_tag = 0;
    lookup_epoch = 0;
    standard_pending_write_mask = '0;
    std_src_valid = 0;
    std_src_addr = '0;
    std_dst_valid = 0;
    std_dst_addr = 0;
    repeat (4) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    make_scalar(1, 0, 5);
    accept_current();
    make_pair(2, 0, 6);
    accept_current();
    if ((occupancy != 2) || !busy_mask[5] || !busy_mask[6] || !busy_mask[7] || busy_mask[0])
      $fatal(1, "initial destination ownership mismatch");

    lookup_tag   = 2;
    lookup_epoch = 0;
    lookup_valid = 1;
    #1;
    if (!lookup_hit || lookup_stale || (lookup_dst_valid != 2'b11) ||
        (lookup_dst_addr[0] != 6) || (lookup_dst_addr[1] != 7) ||
        (lookup_policy != AUTOISA_WRITE_PAIR_SERIAL))
      $fatal(1, "pair lookup mismatch");
    lookup_valid = 0;

    make_scalar(3, 0, 8);
    reserve_desc.src_valid[0] = 1;
    reserve_desc.src_addr[0]  = 5;
    reject_current(1, 0, 0, 0, 0);
    make_scalar(3, 0, 6);
    reject_current(0, 1, 0, 0, 0);

    standard_pending_write_mask[12] = 1'b1;
    make_scalar(3, 0, 13);
    reserve_desc.src_valid[0] = 1;
    reserve_desc.src_addr[0]  = 12;
    reject_current(1, 0, 0, 0, 0);
    standard_pending_write_mask = '0;
    standard_pending_write_mask[14] = 1'b1;
    make_scalar(3, 0, 14);
    reject_current(0, 1, 0, 0, 0);
    standard_pending_write_mask = '0;

    std_src_valid = 3'b001;
    std_src_addr[0] = 6;
    std_dst_valid = 1;
    std_dst_addr = 7;
    #1;
    if (!std_raw || !std_waw) $fatal(1, "standard RAW/WAW hazards not reported");
    std_src_valid = 0;
    std_dst_valid = 0;

    make_scalar(1, 0, 9);
    reject_current(0, 0, 0, 1, 0);
    make_scalar(1, 1, 9);
    reject_current(0, 0, 0, 0, 1);
    make_scalar(3, 0, 0);
    reject_current(0, 0, 1, 0, 0);
    make_pair(3, 0, 9);
    reject_current(0, 0, 1, 0, 0);

    do_release(2, 1, 0, 1);
    if ((occupancy != 2) || !busy_mask[6]) $fatal(1, "stale release changed ownership");
    do_release(1, 0, 1, 0);
    make_scalar(3, 0, 5);
    accept_current();

    // Full-map replacement: release tag 2 and atomically reserve pair tag 4.
    make_pair(4, 0, 8);
    release_tag   = 2;
    release_epoch = 0;
    release_valid = 1;
    reserve_valid = 1;
    #1;
    if (!release_hit || !reserve_ready) $fatal(1, "same-cycle release/reserve failed");
    @(posedge clk);
    @(negedge clk);
    release_valid = 0;
    reserve_valid = 0;
    if ((occupancy != 2) || busy_mask[6] || busy_mask[7] || !busy_mask[8] || !busy_mask[9])
      $fatal(1, "same-cycle replacement ownership mismatch");

    make_scalar(5, 0, 10);
    accept_current();
    make_scalar(6, 0, 11);
    accept_current();
    if ((occupancy != 4) || (high_watermark != 4)) $fatal(1, "map did not reach depth 4");
    make_scalar(7, 0, 12);
    reject_current(0, 0, 0, 0, 0);

    @(negedge clk);
    flush = 1;
    @(posedge clk);
    @(negedge clk);
    flush = 0;
    if ((occupancy != 0) || (busy_mask != 0) || (flush_drop_count != 4))
      $fatal(1, "flush did not atomically clear destination map");

    // Reused tag with a new epoch must survive an old stale completion/release.
    make_scalar(1, 1, 5);
    accept_current();
    do_release(1, 0, 0, 1);
    if ((occupancy != 1) || !busy_mask[5]) $fatal(1, "old epoch released new owner");
    do_release(1, 1, 1, 0);

    if ((occupancy != 0) || (reserve_count != 7) || (release_count != 3) ||
        (conflict_count != 9) || (stale_release_count != 2) ||
        (flush_drop_count != 4))
      $fatal(
          1,
          "counter mismatch occ=%0d reserve=%0d release=%0d conflict=%0d stale=%0d flush=%0d",
          occupancy,
          reserve_count,
          release_count,
          conflict_count,
          stale_release_count,
          flush_drop_count
      );

    $display(
        "DATA: reserved=%0d released=%0d conflicts=%0d stale_release=%0d flush_drop=%0d hwm=%0d",
        reserve_count, release_count, conflict_count, stale_release_count, flush_drop_count,
        observed_hwm);
    $display("PASS: autoisa_ci_destination_map");
    $finish;
  end

  initial begin
    #10000;
    $fatal(1, "timeout occupancy=%0d busy=%h", occupancy, busy_mask);
  end
endmodule
