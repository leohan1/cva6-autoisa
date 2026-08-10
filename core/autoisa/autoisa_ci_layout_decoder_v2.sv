// SPDX-License-Identifier: Apache-2.0
// Initial v2 decoder.  Each layout owns an explicit match/mask entry; layout_id
// is an internal output and is not assumed to occupy one common instruction field.
`timescale 1ns/1ps
`default_nettype none

module autoisa_ci_layout_decoder_v2 (
    input  wire [31:0] instr_i,
    input  wire [autoisa_ci_types_pkg::AUTOISA_TAG_WIDTH-1:0] tag_i,
    input  wire [autoisa_ci_types_pkg::AUTOISA_EPOCH_WIDTH-1:0] epoch_i,
    output logic valid_o,
    output logic illegal_o,
    output autoisa_ci_types_pkg::autoisa_ci_host_desc_t desc_o
);
  import autoisa_ci_types_pkg::*;

  localparam logic [31:0] R_FUNCT3_MASK = 32'h0000_707f;

  localparam logic [31:0] L0_MATCH = 32'h0000_005b;
  localparam logic [31:0] L0_MASK  = R_FUNCT3_MASK;
  localparam logic [31:0] L1_MATCH = 32'h0000_105b;
  localparam logic [31:0] L1_MASK  = R_FUNCT3_MASK;
  localparam logic [31:0] L2_MATCH = 32'h0000_205b;
  localparam logic [31:0] L2_MASK  = R_FUNCT3_MASK;
  localparam logic [31:0] L3_MATCH = 32'h0000_305b;
  localparam logic [31:0] L3_MASK  = R_FUNCT3_MASK;
  localparam logic [31:0] L4_MATCH = 32'h0000_405b;
  localparam logic [31:0] L4_MASK  = 32'hc000_707f;
  // L5 uses custom-1 and requires the four spare high bits to be zero.
  localparam logic [31:0] L5_MATCH = 32'h0000_002b;
  localparam logic [31:0] L5_MASK  = 32'hf000_007f;
  // L6 consumes all but one payload bit; bit 31 is reserved and must be zero.
  localparam logic [31:0] L6_MATCH = 32'h0000_007b;
  localparam logic [31:0] L6_MASK  = 32'h8000_007f;
  localparam logic [31:0] L7_MATCH = 32'h0000_705b;
  localparam logic [31:0] L7_MASK  = R_FUNCT3_MASK;

  function automatic logic match_mask_hit(
      input logic [31:0] instruction,
      input logic [31:0] match_value,
      input logic [31:0] mask_value
  );
    begin
      match_mask_hit = ((instruction & mask_value) == match_value);
    end
  endfunction

  function automatic logic [4:0] rvc8(input logic [2:0] encoded);
    begin
      rvc8 = {2'b01, encoded};
    end
  endfunction

  always_comb begin
    valid_o   = 1'b0;
    illegal_o = 1'b0;
    desc_o    = '0;
    desc_o.tag   = tag_i;
    desc_o.epoch = epoch_i;

    if (match_mask_hit(instr_i, L0_MATCH, L0_MASK)) begin
      valid_o = 1'b1;
      desc_o.layout_id = 4'd0;
      desc_o.ci_id = {1'b0, instr_i[31:25]};
      desc_o.src_valid = 6'b00_0011;
      desc_o.src_addr[0] = instr_i[19:15];
      desc_o.src_addr[1] = instr_i[24:20];
      desc_o.dst_valid = 2'b01;
      desc_o.dst_addr[0] = instr_i[11:7];
      desc_o.backend = AUTOISA_CVXIF_NATIVE;
    end else if (match_mask_hit(instr_i, L1_MATCH, L1_MASK)) begin
      valid_o = 1'b1;
      desc_o.layout_id = 4'd1;
      desc_o.ci_id = {6'b0, instr_i[31:30]};
      desc_o.src_valid = 6'b00_0111;
      desc_o.src_addr[0] = instr_i[19:15];
      desc_o.src_addr[1] = instr_i[24:20];
      desc_o.src_addr[2] = instr_i[29:25];
      desc_o.dst_valid = 2'b01;
      desc_o.dst_addr[0] = instr_i[11:7];
      desc_o.backend = AUTOISA_CVXIF_NATIVE;
    end else if (match_mask_hit(instr_i, L2_MATCH, L2_MASK)) begin
      valid_o = 1'b1;
      desc_o.layout_id = 4'd2;
      desc_o.ci_id = {3'b0, instr_i[31:27]};
      desc_o.src_valid = 6'b00_1111;
      desc_o.src_addr[0] = rvc8(instr_i[17:15]);
      desc_o.src_addr[1] = rvc8(instr_i[20:18]);
      desc_o.src_addr[2] = rvc8(instr_i[23:21]);
      desc_o.src_addr[3] = rvc8(instr_i[26:24]);
      desc_o.dst_valid = 2'b01;
      desc_o.dst_addr[0] = rvc8(instr_i[11:9]);
      desc_o.backend = AUTOISA_DIRECT_CI_EXTENDED;
    end else if (match_mask_hit(instr_i, L3_MATCH, L3_MASK)) begin
      valid_o = 1'b1;
      desc_o.layout_id = 4'd3;
      desc_o.ci_id = {1'b0, instr_i[31:25]};
      desc_o.src_valid = 6'b00_0011;
      desc_o.src_addr[0] = instr_i[19:15];
      desc_o.src_addr[1] = instr_i[24:20];
      desc_o.dst_valid = 2'b11;
      desc_o.dst_addr[0] = instr_i[11:7];
      desc_o.dst_addr[1] = instr_i[11:7] + 5'd1;
      desc_o.pair_constrained = 1'b1;
      desc_o.backend = AUTOISA_DIRECT_CI_EXTENDED;
      if ((instr_i[11:7] == 5'd0) || instr_i[7] ||
          (instr_i[11:7] == 5'd31)) begin
        illegal_o = 1'b1;
      end
    end else if (match_mask_hit(instr_i, L4_MATCH, L4_MASK)) begin
      valid_o = 1'b1;
      desc_o.layout_id = 4'd4;
      desc_o.ci_id = 8'd4;
      desc_o.src_valid = 6'b00_1111;
      desc_o.src_addr[0] = rvc8(instr_i[17:15]);
      desc_o.src_addr[1] = rvc8(instr_i[20:18]);
      desc_o.src_addr[2] = rvc8(instr_i[23:21]);
      desc_o.src_addr[3] = rvc8(instr_i[26:24]);
      desc_o.dst_valid = 2'b11;
      desc_o.dst_addr[0] = rvc8(instr_i[9:7]);
      desc_o.dst_addr[1] = rvc8(instr_i[29:27]);
      desc_o.backend = AUTOISA_DIRECT_CI_EXTENDED;
    end else if (match_mask_hit(instr_i, L5_MATCH, L5_MASK)) begin
      valid_o = 1'b1;
      desc_o.layout_id = 4'd5;
      desc_o.ci_id = 8'd5;
      desc_o.src_valid = 6'b11_1111;
      desc_o.src_addr[0] = rvc8(instr_i[12:10]);
      desc_o.src_addr[1] = rvc8(instr_i[15:13]);
      desc_o.src_addr[2] = rvc8(instr_i[18:16]);
      desc_o.src_addr[3] = rvc8(instr_i[21:19]);
      desc_o.src_addr[4] = rvc8(instr_i[24:22]);
      desc_o.src_addr[5] = rvc8(instr_i[27:25]);
      desc_o.dst_valid = 2'b01;
      desc_o.dst_addr[0] = rvc8(instr_i[9:7]);
      desc_o.backend = AUTOISA_DIRECT_CI_EXTENDED;
    end else if (match_mask_hit(instr_i, L6_MATCH, L6_MASK)) begin
      valid_o = 1'b1;
      desc_o.layout_id = 4'd6;
      desc_o.ci_id = 8'd6;
      desc_o.src_valid = 6'b11_1111;
      desc_o.src_addr[0] = rvc8(instr_i[15:13]);
      desc_o.src_addr[1] = rvc8(instr_i[18:16]);
      desc_o.src_addr[2] = rvc8(instr_i[21:19]);
      desc_o.src_addr[3] = rvc8(instr_i[24:22]);
      desc_o.src_addr[4] = rvc8(instr_i[27:25]);
      desc_o.src_addr[5] = rvc8(instr_i[30:28]);
      desc_o.dst_valid = 2'b11;
      desc_o.dst_addr[0] = rvc8(instr_i[9:7]);
      desc_o.dst_addr[1] = rvc8(instr_i[12:10]);
      desc_o.backend = AUTOISA_DIRECT_CI_EXTENDED;
    end else if (match_mask_hit(instr_i, L7_MATCH, L7_MASK)) begin
      valid_o = 1'b1;
      desc_o.layout_id = 4'd7;
      desc_o.ci_id = 8'd7;
      desc_o.src_valid = 6'b00_0011;
      desc_o.src_addr[0] = instr_i[19:15];
      desc_o.src_addr[1] = instr_i[24:20];
      desc_o.dst_valid = 2'b01;
      desc_o.dst_addr[0] = instr_i[11:7];
      desc_o.imm_valid = 1'b1;
      desc_o.immediate = {{25{instr_i[31]}}, instr_i[31:25]};
      desc_o.backend = AUTOISA_CVXIF_NATIVE;
    end

    // Architectural x0 must never be reserved as a destination.
    if (valid_o && ((desc_o.dst_valid[0] && (desc_o.dst_addr[0] == 5'd0)) ||
                    (desc_o.dst_valid[1] && (desc_o.dst_addr[1] == 5'd0)))) begin
      illegal_o = 1'b1;
    end
  end

endmodule

`default_nettype wire
