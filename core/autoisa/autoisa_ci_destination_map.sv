// SPDX-License-Identifier: Apache-2.0
// Tagged Host-side architectural destination ownership for AutoISA CI.
`timescale 1ns/1ps

module autoisa_ci_destination_map #(
    parameter int unsigned ENTRIES = 4,
    parameter int unsigned STD_SRC_PORTS = 3,
    parameter int unsigned COUNT_WIDTH = 32,
    localparam int unsigned OCC_WIDTH = $clog2(ENTRIES + 1)
) (
    input  wire clk_i,
    input  wire rst_ni,
    input  wire flush_i,

    input  wire reserve_valid_i,
    output logic reserve_ready_o,
    input  autoisa_ci_types_pkg::autoisa_ci_host_desc_t reserve_desc_i,
    input  autoisa_ci_types_pkg::autoisa_ci_write_policy_e reserve_write_policy_i,
    output logic reserve_duplicate_o,
    output logic reserve_tag_busy_o,
    output logic reserve_raw_hazard_o,
    output logic reserve_waw_hazard_o,
    output logic reserve_illegal_o,

    input  wire release_valid_i,
    input  wire [autoisa_ci_types_pkg::AUTOISA_TAG_WIDTH-1:0] release_tag_i,
    input  wire [autoisa_ci_types_pkg::AUTOISA_EPOCH_WIDTH-1:0] release_epoch_i,
    output logic release_hit_o,
    output logic release_stale_o,

    input  wire lookup_valid_i,
    input  wire [autoisa_ci_types_pkg::AUTOISA_TAG_WIDTH-1:0] lookup_tag_i,
    input  wire [autoisa_ci_types_pkg::AUTOISA_EPOCH_WIDTH-1:0] lookup_epoch_i,
    output logic lookup_hit_o,
    output logic lookup_stale_o,
    output logic [autoisa_ci_types_pkg::AUTOISA_MAX_DST-1:0] lookup_dst_valid_o,
    output logic [autoisa_ci_types_pkg::AUTOISA_MAX_DST-1:0][4:0] lookup_dst_addr_o,
    output autoisa_ci_types_pkg::autoisa_ci_write_policy_e lookup_write_policy_o,

    input  wire [31:0] standard_pending_write_mask_i,
    input  wire [STD_SRC_PORTS-1:0] std_src_valid_i,
    input  wire [STD_SRC_PORTS-1:0][4:0] std_src_addr_i,
    input  wire std_dst_valid_i,
    input  wire [4:0] std_dst_addr_i,
    output logic std_raw_hazard_o,
    output logic std_waw_hazard_o,

    output logic [31:0] busy_mask_o,
    output logic [OCC_WIDTH-1:0] occupancy_o,
    output logic [OCC_WIDTH-1:0] high_watermark_o,
    output logic [COUNT_WIDTH-1:0] reserve_count_o,
    output logic [COUNT_WIDTH-1:0] release_count_o,
    output logic [COUNT_WIDTH-1:0] conflict_count_o,
    output logic [COUNT_WIDTH-1:0] stale_release_count_o,
    output logic [COUNT_WIDTH-1:0] flush_drop_count_o
);
  import autoisa_ci_types_pkg::*;

  localparam int unsigned INDEX_WIDTH = (ENTRIES <= 1) ? 1 : $clog2(ENTRIES);

  logic [ENTRIES-1:0] valid_q;
  logic [ENTRIES-1:0][AUTOISA_TAG_WIDTH-1:0] tag_q;
  logic [ENTRIES-1:0][AUTOISA_EPOCH_WIDTH-1:0] epoch_q;
  logic [ENTRIES-1:0][AUTOISA_MAX_DST-1:0] dst_valid_q;
  logic [ENTRIES-1:0][AUTOISA_MAX_DST-1:0][4:0] dst_addr_q;
  autoisa_ci_write_policy_e write_policy_q [ENTRIES];

  logic free_found, duplicate_found, tag_found, release_found, lookup_found;
  logic release_tag_found, lookup_tag_found;
  logic [INDEX_WIDTH-1:0] free_index, release_index, lookup_index;
  logic reserve_fire;
  logic [31:0] busy_mask_effective;
  logic [OCC_WIDTH-1:0] occupancy_next;
  logic [OCC_WIDTH-1:0] flush_drop_count_comb;

  always_comb begin
    free_found = 1'b0;
    free_index = '0;
    duplicate_found = 1'b0;
    tag_found = 1'b0;
    release_found = 1'b0;
    release_tag_found = 1'b0;
    release_index = '0;
    lookup_found = 1'b0;
    lookup_tag_found = 1'b0;
    lookup_index = '0;
    busy_mask_o = '0;

    for (int unsigned i = 0; i < ENTRIES; i++) begin
      if (!valid_q[i] && !free_found) begin
        free_found = 1'b1;
        free_index = INDEX_WIDTH'(i);
      end
      if (valid_q[i]) begin
        if (tag_q[i] == reserve_desc_i.tag) begin
          tag_found = 1'b1;
          if (epoch_q[i] == reserve_desc_i.epoch)
            duplicate_found = 1'b1;
        end
        if (tag_q[i] == release_tag_i) begin
          release_tag_found = 1'b1;
          if ((epoch_q[i] == release_epoch_i) && !release_found) begin
            release_found = 1'b1;
            release_index = INDEX_WIDTH'(i);
          end
        end
        if (tag_q[i] == lookup_tag_i) begin
          lookup_tag_found = 1'b1;
          if ((epoch_q[i] == lookup_epoch_i) && !lookup_found) begin
            lookup_found = 1'b1;
            lookup_index = INDEX_WIDTH'(i);
          end
        end
        for (int unsigned d = 0; d < AUTOISA_MAX_DST; d++) begin
          if (dst_valid_q[i][d] && (dst_addr_q[i][d] != 5'd0))
            busy_mask_o[dst_addr_q[i][d]] = 1'b1;
        end
      end
    end
  end

  // An exact release may be replaced in the same cycle without a bubble.
  always_comb begin
    busy_mask_effective = busy_mask_o;
    if (release_valid_i && release_found) begin
      for (int unsigned d = 0; d < AUTOISA_MAX_DST; d++) begin
        if (dst_valid_q[release_index][d] && (dst_addr_q[release_index][d] != 5'd0))
          busy_mask_effective[dst_addr_q[release_index][d]] = 1'b0;
      end
    end

    reserve_raw_hazard_o = 1'b0;
    reserve_waw_hazard_o = 1'b0;
    reserve_illegal_o = 1'b0;
    for (int unsigned s = 0; s < AUTOISA_MAX_SRC; s++) begin
      if (reserve_desc_i.src_valid[s] &&
          (reserve_desc_i.src_addr[s] != 5'd0) &&
          (busy_mask_effective[reserve_desc_i.src_addr[s]] ||
           standard_pending_write_mask_i[reserve_desc_i.src_addr[s]]))
        reserve_raw_hazard_o = 1'b1;
    end
    for (int unsigned d = 0; d < AUTOISA_MAX_DST; d++) begin
      if (reserve_desc_i.dst_valid[d]) begin
        if (reserve_desc_i.dst_addr[d] == 5'd0)
          reserve_illegal_o = 1'b1;
        else if (busy_mask_effective[reserve_desc_i.dst_addr[d]] ||
                 standard_pending_write_mask_i[reserve_desc_i.dst_addr[d]])
          reserve_waw_hazard_o = 1'b1;
      end
    end
    if (reserve_desc_i.dst_valid[0] && reserve_desc_i.dst_valid[1] &&
        (reserve_desc_i.dst_addr[0] == reserve_desc_i.dst_addr[1]))
      reserve_illegal_o = 1'b1;
    if (reserve_desc_i.pair_constrained &&
        (!reserve_desc_i.dst_valid[0] || !reserve_desc_i.dst_valid[1] ||
         (reserve_desc_i.dst_addr[1] != (reserve_desc_i.dst_addr[0] + 5'd1)) ||
         reserve_desc_i.dst_addr[0][0] || (reserve_desc_i.dst_addr[0] == 5'd31)))
      reserve_illegal_o = 1'b1;
    if ((reserve_write_policy_i == AUTOISA_WRITE_NONE) ||
        ((reserve_write_policy_i == AUTOISA_WRITE_SCALAR) &&
         (reserve_desc_i.dst_valid != 2'b01)) ||
        (((reserve_write_policy_i == AUTOISA_WRITE_PAIR_SERIAL) ||
          (reserve_write_policy_i == AUTOISA_WRITE_PAIR_DUAL)) &&
         !(reserve_desc_i.dst_valid[0] && reserve_desc_i.dst_valid[1])))
      reserve_illegal_o = 1'b1;
  end

  assign reserve_duplicate_o = reserve_valid_i && duplicate_found;
  assign reserve_tag_busy_o = reserve_valid_i && tag_found && !duplicate_found;
  assign release_hit_o = release_valid_i && release_found;
  assign release_stale_o = release_valid_i && release_tag_found && !release_found;
  assign lookup_hit_o = lookup_valid_i && lookup_found;
  assign lookup_stale_o = lookup_valid_i && lookup_tag_found && !lookup_found;

  always_comb begin
    lookup_dst_valid_o = '0;
    lookup_dst_addr_o = '0;
    lookup_write_policy_o = AUTOISA_WRITE_NONE;
    if (lookup_found) begin
      lookup_dst_valid_o = dst_valid_q[lookup_index];
      lookup_dst_addr_o = dst_addr_q[lookup_index];
      lookup_write_policy_o = write_policy_q[lookup_index];
    end
  end

  always_comb begin
    std_raw_hazard_o = 1'b0;
    for (int unsigned s = 0; s < STD_SRC_PORTS; s++) begin
      if (std_src_valid_i[s] && (std_src_addr_i[s] != 5'd0) &&
          busy_mask_o[std_src_addr_i[s]])
        std_raw_hazard_o = 1'b1;
    end
    std_waw_hazard_o = std_dst_valid_i && (std_dst_addr_i != 5'd0) &&
                       busy_mask_o[std_dst_addr_i];
  end

  assign reserve_ready_o = !flush_i &&
                           (free_found || (release_valid_i && release_found)) &&
                           !duplicate_found && !tag_found &&
                           !reserve_raw_hazard_o && !reserve_waw_hazard_o &&
                           !reserve_illegal_o;
  assign reserve_fire = reserve_valid_i && reserve_ready_o;

  always_comb begin
    occupancy_o = OCC_WIDTH'($countones(valid_q));
    occupancy_next = occupancy_o;
    if (reserve_fire && !(release_valid_i && release_found))
      occupancy_next = occupancy_o + 1'b1;
    else if (!reserve_fire && release_valid_i && release_found)
      occupancy_next = occupancy_o - 1'b1;
    flush_drop_count_comb = occupancy_o;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      valid_q <= '0;
      tag_q <= '0;
      epoch_q <= '0;
      dst_valid_q <= '0;
      dst_addr_q <= '0;
      for (int unsigned i = 0; i < ENTRIES; i++)
        write_policy_q[i] <= AUTOISA_WRITE_NONE;
      high_watermark_o <= '0;
      reserve_count_o <= '0;
      release_count_o <= '0;
      conflict_count_o <= '0;
      stale_release_count_o <= '0;
      flush_drop_count_o <= '0;
    end else if (flush_i) begin
      valid_q <= '0;
      high_watermark_o <= '0;
      flush_drop_count_o <= flush_drop_count_o + flush_drop_count_comb;
    end else begin
      if (release_valid_i && release_found) begin
        valid_q[release_index] <= 1'b0;
        dst_valid_q[release_index] <= '0;
        write_policy_q[release_index] <= AUTOISA_WRITE_NONE;
        release_count_o <= release_count_o + 1'b1;
      end else if (release_stale_o) begin
        stale_release_count_o <= stale_release_count_o + 1'b1;
      end

      if (reserve_fire) begin
        if (release_valid_i && release_found) begin
          valid_q[release_index] <= 1'b1;
          tag_q[release_index] <= reserve_desc_i.tag;
          epoch_q[release_index] <= reserve_desc_i.epoch;
          dst_valid_q[release_index] <= reserve_desc_i.dst_valid;
          dst_addr_q[release_index] <= reserve_desc_i.dst_addr;
          write_policy_q[release_index] <= reserve_write_policy_i;
        end else begin
          valid_q[free_index] <= 1'b1;
          tag_q[free_index] <= reserve_desc_i.tag;
          epoch_q[free_index] <= reserve_desc_i.epoch;
          dst_valid_q[free_index] <= reserve_desc_i.dst_valid;
          dst_addr_q[free_index] <= reserve_desc_i.dst_addr;
          write_policy_q[free_index] <= reserve_write_policy_i;
        end
        reserve_count_o <= reserve_count_o + 1'b1;
      end else if (reserve_valid_i) begin
        conflict_count_o <= conflict_count_o + 1'b1;
      end

      if (occupancy_next > high_watermark_o)
        high_watermark_o <= occupancy_next;
    end
  end

  initial begin
    assert ((ENTRIES == 2) || (ENTRIES == 4) || (ENTRIES == 8))
      else $error("autoisa_ci_destination_map ENTRIES must be 2, 4, or 8");
  end

  always_ff @(posedge clk_i) begin
    if (rst_ni) begin
      assert (occupancy_o <= ENTRIES)
        else $error("destination map occupancy overflow");
      assert (!busy_mask_o[0])
        else $error("destination map reserved x0");
      if (lookup_hit_o)
        assert (lookup_dst_valid_o != '0)
          else $error("destination lookup returned empty destination set");
    end
  end
endmodule
