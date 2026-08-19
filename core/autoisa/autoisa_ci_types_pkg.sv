// SPDX-License-Identifier: Apache-2.0
// Canonical, compute-only AutoISA CI ABI (v1.0 implementation profile).
`timescale 1ns/1ps
package autoisa_ci_types_pkg;

  // Public compatibility number.  Increment MAJOR for incompatible field or
  // handshake changes; increment MINOR for backward-compatible additions.
  localparam int unsigned AUTOISA_CI_ABI_MAJOR = 1;
  localparam int unsigned AUTOISA_CI_ABI_MINOR = 0;
  localparam logic [31:0] AUTOISA_CI_ABI_VERSION =
      (AUTOISA_CI_ABI_MAJOR << 16) | AUTOISA_CI_ABI_MINOR;

  localparam int unsigned AUTOISA_XLEN            = 32;
  localparam int unsigned AUTOISA_MAX_SRC         = 6;
  localparam int unsigned AUTOISA_MAX_DST         = 2;
  localparam int unsigned AUTOISA_TAG_WIDTH       = 4;
  localparam int unsigned AUTOISA_EPOCH_WIDTH     = 2;
  localparam int unsigned AUTOISA_CI_ID_WIDTH     = 8;
  localparam int unsigned AUTOISA_LAYOUT_ID_WIDTH = 4;

  typedef enum logic [1:0] {
    AUTOISA_STATUS_OK          = 2'd0,
    AUTOISA_STATUS_ILLEGAL     = 2'd1,
    AUTOISA_STATUS_UNSUPPORTED = 2'd2,
    AUTOISA_STATUS_ENGINE_FAULT= 2'd3
  } autoisa_ci_status_e;

  typedef enum logic [1:0] {
    AUTOISA_HOST_LOCAL         = 2'd0,
    AUTOISA_CVXIF_NATIVE       = 2'd1,
    AUTOISA_DIRECT_CI_EXTENDED = 2'd2,
    AUTOISA_HOST_MEMORY_EXPERIMENTAL = 2'd3
  } autoisa_ci_backend_e;

  typedef enum logic [1:0] {
    AUTOISA_WRITE_NONE        = 2'd0,
    AUTOISA_WRITE_SCALAR      = 2'd1,
    AUTOISA_WRITE_PAIR_SERIAL = 2'd2,
    AUTOISA_WRITE_PAIR_DUAL   = 2'd3
  } autoisa_ci_write_policy_e;

  typedef struct packed {
    logic [AUTOISA_TAG_WIDTH-1:0]       tag;
    logic [AUTOISA_EPOCH_WIDTH-1:0]     epoch;
    logic [AUTOISA_CI_ID_WIDTH-1:0]     ci_id;
    logic [AUTOISA_LAYOUT_ID_WIDTH-1:0] layout_id;
    logic [AUTOISA_MAX_SRC-1:0]         src_valid;
    logic [AUTOISA_MAX_SRC-1:0][4:0]    src_addr;
    logic [AUTOISA_MAX_DST-1:0]         dst_valid;
    logic [AUTOISA_MAX_DST-1:0][4:0]    dst_addr;
    logic                                imm_valid;
    logic [31:0]                         immediate;
    logic                                pair_constrained;
    autoisa_ci_backend_e                 backend;
  } autoisa_ci_host_desc_t;

  typedef struct packed {
    logic [AUTOISA_TAG_WIDTH-1:0]   tag;
    logic [AUTOISA_EPOCH_WIDTH-1:0] epoch;
    logic [AUTOISA_CI_ID_WIDTH-1:0] ci_id;
    logic [AUTOISA_MAX_SRC-1:0]     operand_valid;
    logic [AUTOISA_MAX_SRC-1:0][31:0] operands;
    logic                            imm_valid;
    logic [31:0]                     immediate;
  } autoisa_ci_req_t;

  typedef struct packed {
    logic [AUTOISA_TAG_WIDTH-1:0]   tag;
    logic [AUTOISA_EPOCH_WIDTH-1:0] epoch;
    logic [AUTOISA_MAX_DST-1:0]     result_valid;
    logic [AUTOISA_MAX_DST-1:0][31:0] results;
    autoisa_ci_status_e             status;
  } autoisa_ci_rsp_t;

endpackage
