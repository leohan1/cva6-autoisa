`timescale 1ns / 1ps
`default_nettype none

module autoisa_ci_cva6_decode_adapter (
    input wire [31:0] instr_i,
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
  import autoisa_ci_types_pkg::*;

  logic decoded_valid, decoded_illegal;
  autoisa_ci_host_desc_t desc;

  autoisa_ci_layout_decoder_v2 i_layout_decoder (
      .instr_i,
      .tag_i('0),
      .epoch_i('0),
      .valid_o(decoded_valid),
      .illegal_o(decoded_illegal),
      .desc_o(desc)
  );

  always_comb begin
    ci_valid_o = decoded_valid;
    ci_illegal_o = decoded_illegal;
    layout_id_o = desc.layout_id[2:0];
    semantic_id_o = desc.ci_id[6:0];
    rs1_o = desc.src_valid[0] ? desc.src_addr[0] : 5'd0;
    rs2_o = desc.src_valid[1] ? desc.src_addr[1] : 5'd0;
    rs3_o = desc.src_valid[2] ? desc.src_addr[2] : 5'd0;
    rd_o = desc.dst_valid[0] ? desc.dst_addr[0] : 5'd0;
    second_destination_o = desc.dst_valid[1];
    rd2_o = desc.dst_valid[1] ? desc.dst_addr[1] : 5'd0;
    gather_required_o = |desc.src_valid[AUTOISA_MAX_SRC-1:3];
    memory_form_o = 1'b0;
    native_cvxif_supported_o = decoded_valid && !decoded_illegal &&
                               (desc.backend == AUTOISA_CVXIF_NATIVE) &&
                               !gather_required_o && !second_destination_o;
  end

endmodule

`default_nettype wire
