`timescale 1ns/1ps
`default_nettype none

module autoisa_ci_cva6_decode_adapter (
    input  wire [31:0] instr_i,
    output logic ci_valid_o,
    output logic ci_illegal_o,
    output logic native_cvxif_supported_o,
    output logic gather_required_o,
    output logic memory_form_o,
    output logic [4:0] rs1_o,
    output logic [4:0] rs2_o,
    output logic [4:0] rs3_o,
    output logic [4:0] rd_o,
    output logic second_destination_o,
    output logic [4:0] rd2_o,
    output logic [2:0] layout_id_o,
    output logic [6:0] semantic_id_o
);

  logic [3:0] src_valid;
  logic [3:0][4:0] src_addr;
  logic [1:0] dst_valid;
  logic [1:0][4:0] dst_addr;
  logic [31:0] immediate;
  logic [2:0] memory_profile;
  logic pair_constrained;

  autoisa_ci_layout_decoder #(
      .MAX_SRC(4),
      .MAX_DST(2)
  ) i_layout_decoder (
      .instr_i,
      .valid_o(ci_valid_o),
      .illegal_o(ci_illegal_o),
      .layout_id_o,
      .semantic_id_o,
      .src_valid_o(src_valid),
      .src_addr_o(src_addr),
      .dst_valid_o(dst_valid),
      .dst_addr_o(dst_addr),
      .immediate_o(immediate),
      .memory_profile_o(memory_profile),
      .pair_constrained_o(pair_constrained)
  );

  always_comb begin
    rs1_o = src_valid[0] ? src_addr[0] : 5'd0;
    rs2_o = src_valid[1] ? src_addr[1] : 5'd0;
    rs3_o = src_valid[2] ? src_addr[2] : 5'd0;
    rd_o = dst_valid[0] ? dst_addr[0] : 5'd0;
    second_destination_o = dst_valid[1];
    rd2_o = dst_valid[1] ? dst_addr[1] : 5'd0;
    gather_required_o = src_valid[3];
    memory_form_o = memory_profile != 0;
    native_cvxif_supported_o = ci_valid_o && !ci_illegal_o &&
                               !memory_form_o && !gather_required_o &&
                               !second_destination_o;
  end

  logic unused;
  always_comb begin
    unused = ^{immediate, pair_constrained};
  end

endmodule

`default_nettype wire
