// SPDX-License-Identifier: Apache-2.0
//
// AutoISA H1 experiment: one aligned 64-bit host load becomes one atomic
// pair result for an RV32 core.  This block intentionally stops at the
// cache-response/result-transaction boundary; architectural register-file
// integration is a separate step.
module autoisa_h1_pair_load #(
    parameter int unsigned ADDR_WIDTH   = 64,
    parameter int unsigned IMM_WIDTH    = 32,
    parameter int unsigned TXN_ID_WIDTH = 4,
    parameter int unsigned COUNT_WIDTH  = 32
) (
    input logic clk_i,
    input logic rst_ni,

    input  logic                    req_valid_i,
    output logic                    req_ready_o,
    input  logic [  ADDR_WIDTH-1:0] req_base_i,
    input  logic [   IMM_WIDTH-1:0] req_imm_i,
    input  logic [             4:0] req_rd_even_i,
    input  logic [TXN_ID_WIDTH-1:0] req_txn_id_i,

    input logic                    kill_valid_i,
    input logic [TXN_ID_WIDTH-1:0] kill_txn_id_i,

    output logic                    mem_req_valid_o,
    input  logic                    mem_req_ready_i,
    output logic [  ADDR_WIDTH-1:0] mem_req_addr_o,
    output logic [             2:0] mem_req_size_o,
    output logic [             7:0] mem_req_be_o,
    output logic [TXN_ID_WIDTH-1:0] mem_req_txn_id_o,

    input  logic                    mem_rsp_valid_i,
    output logic                    mem_rsp_ready_o,
    input  logic [            63:0] mem_rsp_data_i,
    input  logic                    mem_rsp_error_i,
    input  logic [TXN_ID_WIDTH-1:0] mem_rsp_txn_id_i,

    output logic                    result_valid_o,
    input  logic                    result_ready_i,
    output logic                    result_pair_we_o,
    output logic [             4:0] result_rd0_o,
    output logic [             4:0] result_rd1_o,
    output logic [            31:0] result_data0_o,
    output logic [            31:0] result_data1_o,
    output logic                    result_exception_o,
    output logic [             1:0] result_exception_code_o,
    output logic                    result_killed_o,
    output logic [TXN_ID_WIDTH-1:0] result_txn_id_o,

    output logic [COUNT_WIDTH-1:0] accepted_count_o,
    output logic [COUNT_WIDTH-1:0] mem_request_count_o,
    output logic [COUNT_WIDTH-1:0] mem_response_count_o,
    output logic [COUNT_WIDTH-1:0] alignment_reject_count_o,
    output logic [COUNT_WIDTH-1:0] killed_count_o
);

  localparam logic [1:0] EXC_NONE      = 2'd0;
  localparam logic [1:0] EXC_ALIGNMENT = 2'd1;
  localparam logic [1:0] EXC_MEMORY    = 2'd2;

  typedef enum logic [1:0] {
    IDLE,
    SEND_MEMORY_REQUEST,
    WAIT_MEMORY_RESPONSE,
    HOLD_RESULT
  } state_t;

  state_t state_q;

  logic [ADDR_WIDTH-1:0] addr_q;
  logic [4:0] rd_even_q;
  logic [TXN_ID_WIDTH-1:0] txn_id_q;
  logic killed_q;

  logic [31:0] result_data0_q, result_data1_q;
  logic result_exception_q, result_killed_q;
  logic [1:0] result_exception_code_q;

  logic [ADDR_WIDTH-1:0] effective_addr;
  logic kill_matches_active;
  logic kill_matches_request;

  assign effective_addr =
      req_base_i + {{(ADDR_WIDTH-IMM_WIDTH){req_imm_i[IMM_WIDTH-1]}}, req_imm_i};
  assign kill_matches_active = kill_valid_i && (kill_txn_id_i == txn_id_q);
  assign kill_matches_request = kill_valid_i && (kill_txn_id_i == req_txn_id_i);

  assign req_ready_o = (state_q == IDLE);

  assign mem_req_valid_o = (state_q == SEND_MEMORY_REQUEST);
  assign mem_req_addr_o = addr_q;
  assign mem_req_size_o = 3'd3;
  assign mem_req_be_o = 8'hff;
  assign mem_req_txn_id_o = txn_id_q;

  // A mismatched response must not be consumed.  H1 v1 permits one
  // outstanding pair load per controller.
  assign mem_rsp_ready_o = (state_q == WAIT_MEMORY_RESPONSE) && (mem_rsp_txn_id_i == txn_id_q);

  assign result_valid_o = (state_q == HOLD_RESULT);
  assign result_pair_we_o = result_valid_o && !result_exception_q && !result_killed_q;
  assign result_rd0_o = rd_even_q;
  assign result_rd1_o = rd_even_q + 5'd1;
  assign result_data0_o = result_data0_q;
  assign result_data1_o = result_data1_q;
  assign result_exception_o = result_exception_q;
  assign result_exception_code_o = result_exception_code_q;
  assign result_killed_o = result_killed_q;
  assign result_txn_id_o = txn_id_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= IDLE;
      addr_q <= '0;
      rd_even_q <= '0;
      txn_id_q <= '0;
      killed_q <= 1'b0;
      result_data0_q <= '0;
      result_data1_q <= '0;
      result_exception_q <= 1'b0;
      result_exception_code_q <= EXC_NONE;
      result_killed_q <= 1'b0;
      accepted_count_o <= '0;
      mem_request_count_o <= '0;
      mem_response_count_o <= '0;
      alignment_reject_count_o <= '0;
      killed_count_o <= '0;
    end else begin
      unique case (state_q)
        IDLE: begin
          killed_q <= 1'b0;
          result_exception_q <= 1'b0;
          result_exception_code_q <= EXC_NONE;
          result_killed_q <= 1'b0;
          if (req_valid_i) begin
            accepted_count_o <= accepted_count_o + 1'b1;
            addr_q <= effective_addr;
            rd_even_q <= req_rd_even_i;
            txn_id_q <= req_txn_id_i;
            if (kill_matches_request) begin
              result_killed_q <= 1'b1;
              killed_count_o <= killed_count_o + 1'b1;
              state_q <= HOLD_RESULT;
            end else if (effective_addr[2:0] != 3'b000) begin
              result_exception_q <= 1'b1;
              result_exception_code_q <= EXC_ALIGNMENT;
              alignment_reject_count_o <= alignment_reject_count_o + 1'b1;
              state_q <= HOLD_RESULT;
            end else begin
              state_q <= SEND_MEMORY_REQUEST;
            end
          end
        end

        SEND_MEMORY_REQUEST: begin
          if (kill_matches_active) begin
            result_killed_q <= 1'b1;
            killed_count_o <= killed_count_o + 1'b1;
            state_q <= HOLD_RESULT;
          end else if (mem_req_ready_i) begin
            mem_request_count_o <= mem_request_count_o + 1'b1;
            state_q <= WAIT_MEMORY_RESPONSE;
          end
        end

        WAIT_MEMORY_RESPONSE: begin
          if (kill_matches_active && !killed_q) begin
            killed_q <= 1'b1;
            killed_count_o <= killed_count_o + 1'b1;
          end
          if (mem_rsp_valid_i && mem_rsp_ready_o) begin
            mem_response_count_o <= mem_response_count_o + 1'b1;
            result_data0_q <= mem_rsp_data_i[31:0];
            result_data1_q <= mem_rsp_data_i[63:32];
            result_exception_q <= mem_rsp_error_i;
            result_exception_code_q <= mem_rsp_error_i ? EXC_MEMORY : EXC_NONE;
            result_killed_q <= killed_q || kill_matches_active;
            state_q <= HOLD_RESULT;
          end
        end

        HOLD_RESULT: begin
          if (result_ready_i) begin
            state_q <= IDLE;
          end
        end

        default: state_q <= IDLE;
      endcase
    end
  end

endmodule
