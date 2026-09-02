// SPDX-License-Identifier: Apache-2.0
// Program-level AutoISA D0/D1/D7 closure on the real cv32a65x Ariane hierarchy.
`timescale 1ns / 1ps

module autoisa_ci_axi_memory #(
    parameter int unsigned MEM_WORDS = 1024,
    parameter ariane_axi::addr_t MEM_BASE = 64'h8000_0000,
    parameter ariane_axi::addr_t TOHOST_ADDR = 64'h1000_0000,
    parameter ariane_axi::addr_t SIGNATURE_BASE = 64'h1000_0100,
    parameter int unsigned SIGNATURE_WORDS = 32,
    parameter string DEFAULT_HEX = "ci/autoisa/build/software/program_coverage.hex"
) (
    input logic clk_i,
    input logic rst_ni,
    input ariane_axi::req_t req_i,
    output ariane_axi::resp_t resp_o,
    output logic tohost_valid_o,
    output logic [31:0] tohost_value_o
);
  localparam int unsigned DATA_BYTES = ariane_axi::DataWidth / 8;

  ariane_axi::data_t mem[0:MEM_WORDS-1];
  logic [31:0] signature_q[0:SIGNATURE_WORDS-1];
  string mem_hex;

  logic rd_active_q;
  ariane_axi::id_t rd_id_q;
  ariane_axi::addr_t rd_base_q;
  axi_pkg::len_t rd_len_q;
  axi_pkg::size_t rd_size_q;
  axi_pkg::burst_t rd_burst_q;
  logic [7:0] rd_beat_q;

  logic wr_active_q, b_valid_q;
  ariane_axi::id_t wr_id_q;
  ariane_axi::addr_t wr_base_q;
  axi_pkg::len_t wr_len_q;
  axi_pkg::size_t wr_size_q;
  axi_pkg::burst_t wr_burst_q;
  logic [7:0] wr_beat_q;
  ariane_axi::data_t tohost_shadow_q, merged_write;

  function automatic ariane_axi::addr_t beat_addr(
      input ariane_axi::addr_t base, input axi_pkg::size_t size, input axi_pkg::len_t len,
      input axi_pkg::burst_t burst, input logic [7:0] beat);
    ariane_axi::addr_t aligned, boundary, next_addr;
    begin
      aligned = (base >> size) << size;
      next_addr = (beat == 0 || burst == axi_pkg::BURST_FIXED) ?
                  base : aligned + (ariane_axi::addr_t'(beat) << size);
      if (burst == axi_pkg::BURST_WRAP) begin
        boundary = (base >> (size + $clog2(len + 1))) << (size + $clog2(len + 1));
        if (next_addr >= boundary + ((len + 1) << size))
          next_addr = next_addr - ((len + 1) << size);
      end
      beat_addr = next_addr;
    end
  endfunction

  function automatic ariane_axi::data_t read_word(input ariane_axi::addr_t addr);
    longint unsigned index;
    begin
      read_word = '0;
      if (addr >= MEM_BASE && addr < MEM_BASE + MEM_WORDS * DATA_BYTES) begin
        index = (addr - MEM_BASE) >> $clog2(DATA_BYTES);
        read_word = mem[index];
      end
    end
  endfunction

  wire ariane_axi::addr_t rd_addr = beat_addr(
      rd_base_q, rd_size_q, rd_len_q, rd_burst_q, rd_beat_q
  );
  wire ariane_axi::addr_t wr_addr = beat_addr(
      wr_base_q, wr_size_q, wr_len_q, wr_burst_q, wr_beat_q
  );

  always_comb begin
    merged_write = tohost_shadow_q;
    for (int unsigned byte_idx = 0; byte_idx < DATA_BYTES; byte_idx++)
    if (req_i.w.strb[byte_idx]) merged_write[byte_idx*8+:8] = req_i.w.data[byte_idx*8+:8];
  end

  always_comb begin
    resp_o = '0;
    resp_o.ar_ready = !rd_active_q;
    resp_o.r_valid = rd_active_q;
    resp_o.r.id = rd_id_q;
    resp_o.r.data = read_word(rd_addr);
    resp_o.r.resp = axi_pkg::RESP_OKAY;
    resp_o.r.last = (rd_beat_q == rd_len_q);
    resp_o.r.user = '0;

    resp_o.aw_ready = !wr_active_q && !b_valid_q;
    resp_o.w_ready = wr_active_q && !b_valid_q;
    resp_o.b_valid = b_valid_q;
    resp_o.b.id = wr_id_q;
    resp_o.b.resp = axi_pkg::RESP_OKAY;
    resp_o.b.user = '0;
  end

  initial begin
    for (int unsigned i = 0; i < MEM_WORDS; i++) mem[i] = '0;
    if (!$value$plusargs("mem_hex=%s", mem_hex)) mem_hex = DEFAULT_HEX;
    $display("INFO: loading minimal AutoISA image from %s", mem_hex);
    $readmemh(mem_hex, mem);
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    longint unsigned write_index, bus_base, byte_addr, signature_offset;
    if (!rst_ni) begin
      rd_active_q <= 1'b0;
      rd_id_q <= '0;
      rd_base_q <= '0;
      rd_len_q <= '0;
      rd_size_q <= '0;
      rd_burst_q <= '0;
      rd_beat_q <= '0;
      wr_active_q <= 1'b0;
      wr_id_q <= '0;
      wr_base_q <= '0;
      wr_len_q <= '0;
      wr_size_q <= '0;
      wr_burst_q <= '0;
      wr_beat_q <= '0;
      b_valid_q <= 1'b0;
      tohost_shadow_q <= '0;
      tohost_valid_o <= 1'b0;
      tohost_value_o <= '0;
      for (int unsigned i = 0; i < SIGNATURE_WORDS; i++) signature_q[i] <= '0;
    end else begin
      tohost_valid_o <= 1'b0;

      if (req_i.ar_valid && resp_o.ar_ready) begin
        rd_active_q <= 1'b1;
        rd_id_q <= req_i.ar.id;
        rd_base_q <= req_i.ar.addr;
        rd_len_q <= req_i.ar.len;
        rd_size_q <= req_i.ar.size;
        rd_burst_q <= req_i.ar.burst;
        rd_beat_q <= '0;
      end else if (resp_o.r_valid && req_i.r_ready) begin
        if (resp_o.r.last) rd_active_q <= 1'b0;
        else rd_beat_q <= rd_beat_q + 1'b1;
      end

      if (req_i.aw_valid && resp_o.aw_ready) begin
        wr_active_q <= 1'b1;
        wr_id_q <= req_i.aw.id;
        wr_base_q <= req_i.aw.addr;
        wr_len_q <= req_i.aw.len;
        wr_size_q <= req_i.aw.size;
        wr_burst_q <= req_i.aw.burst;
        wr_beat_q <= '0;
      end

      if (req_i.w_valid && resp_o.w_ready) begin
        if (wr_addr == TOHOST_ADDR) begin
          tohost_shadow_q <= merged_write;
          tohost_value_o  <= merged_write[31:0];
          tohost_valid_o  <= 1'b1;
        end else if (wr_addr >= SIGNATURE_BASE &&
                     wr_addr < SIGNATURE_BASE + SIGNATURE_WORDS * 4) begin
          $display("SIGNATURE_WRITE: addr=%016x data=%016x strb=%02x", wr_addr, req_i.w.data,
                   req_i.w.strb);
          bus_base = (wr_addr >> $clog2(DATA_BYTES)) << $clog2(DATA_BYTES);
          for (int unsigned byte_idx = 0; byte_idx < DATA_BYTES; byte_idx++) begin
            byte_addr = bus_base + byte_idx;
            if (req_i.w.strb[byte_idx] && byte_addr >= SIGNATURE_BASE &&
                byte_addr < SIGNATURE_BASE + SIGNATURE_WORDS * 4) begin
              signature_offset = byte_addr - SIGNATURE_BASE;
              signature_q[signature_offset >> 2][(signature_offset & 3) * 8 +: 8]
                  <= req_i.w.data[byte_idx*8 +: 8];
            end
          end
        end else if (wr_addr >= MEM_BASE && wr_addr < MEM_BASE + MEM_WORDS * DATA_BYTES) begin
          write_index = (wr_addr - MEM_BASE) >> $clog2(DATA_BYTES);
          for (int unsigned byte_idx = 0; byte_idx < DATA_BYTES; byte_idx++)
          if (req_i.w.strb[byte_idx])
            mem[write_index][byte_idx*8+:8] <= req_i.w.data[byte_idx*8+:8];
        end
        if (req_i.w.last) begin
          wr_active_q <= 1'b0;
          b_valid_q   <= 1'b1;
        end else begin
          wr_beat_q <= wr_beat_q + 1'b1;
        end
      end
      if (b_valid_q && req_i.b_ready) b_valid_q <= 1'b0;
    end
  end
endmodule


module tb_autoisa_ci_ariane_elf;
  function automatic config_pkg::cva6_cfg_t elf_config();
    config_pkg::cva6_cfg_t cfg;
    cfg = build_config_pkg::build_config(cva6_config_pkg::cva6_cfg);
    return cfg;
  endfunction

  localparam config_pkg::cva6_cfg_t CVA6Cfg = elf_config();
  localparam logic [CVA6Cfg.VLEN-1:0] BOOT_ADDR = 64'h8000_0000;

  logic clk_i = 1'b0;
  logic rst_ni = 1'b0;
  ariane_axi::req_t noc_req;
  ariane_axi::resp_t noc_resp;
  logic tohost_valid;
  logic [31:0] tohost_value;
  int unsigned cycles, issue_count, commit_count, result_count;
  int unsigned reject_count, fault_count, backpressure_cycles;
  logic [31:0] issue_rd_seen, result_rd_seen;
  logic [7:0] transaction_live, transaction_committed;
  autoisa_ci_types_pkg::autoisa_ci_rsp_t stalled_result;
  logic stalled_result_captured, backpressure_done;

  localparam int unsigned EXPECTED_ACCEPTED = 12;
  localparam int unsigned SIGNATURE_CHECK_WORDS = 22;
  logic [31:0] expected_signature[0:SIGNATURE_CHECK_WORDS-1];
  logic [31:0] expected_signature_mask[0:SIGNATURE_CHECK_WORDS-1];
  string signature_oracle_hex, signature_mask_hex;
  localparam logic [31:0] EXPECTED_RD_MASK =
      (32'd1 << 5) | (32'd1 << 8) | (32'd1 << 9) |
      (32'd1 << 10) | (32'd1 << 11) | (32'd1 << 12) |
      (32'd1 << 13) | (32'd1 << 14) | (32'd1 << 15) |
      (32'd1 << 16) | (32'd1 << 17) | (32'd1 << 23);

  function automatic logic expected_destination(input logic [4:0] rd);
    expected_destination = EXPECTED_RD_MASK[rd];
  endfunction

  function automatic logic [7:0] expected_ci(input logic [4:0] rd);
    unique case (rd)
      5'd13:   expected_ci = 8'd8;
      5'd14:   expected_ci = 8'd9;
      5'd15:   expected_ci = 8'd10;
      5'd16:   expected_ci = 8'd7;
      5'd17:   expected_ci = 8'd11;
      5'd23:   expected_ci = 8'd1;
      default: expected_ci = 8'd0;
    endcase
  endfunction

  function automatic logic [31:0] expected_result(input logic [4:0] rd);
    unique case (rd)
      5'd5, 5'd8: expected_result = 32'd0;
      5'd9: expected_result = 32'hffff_fffe;
      5'd10: expected_result = 32'd3;
      5'd11: expected_result = 32'd5;
      5'd12: expected_result = 32'd8;
      5'd13: expected_result = 32'd30;
      5'd14: expected_result = 32'haaaa_aaaa;
      5'd15: expected_result = 32'd1;
      5'd16: expected_result = 32'd36;
      5'd23: expected_result = 32'd50;
      default: expected_result = '0;
    endcase
  endfunction

  always #5ns clk_i = ~clk_i;

  initial begin
    if (!$value$plusargs("signature_oracle=%s", signature_oracle_hex))
      signature_oracle_hex = "ci/autoisa/build/software/program_signature_oracle.hex";
    if (!$value$plusargs("signature_mask=%s", signature_mask_hex))
      signature_mask_hex = "ci/autoisa/build/software/program_signature_mask.hex";
    $readmemh(signature_oracle_hex, expected_signature);
    $readmemh(signature_mask_hex, expected_signature_mask);
  end

  ariane #(
      .CVA6Cfg(CVA6Cfg)
  ) dut (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      .boot_addr_i(BOOT_ADDR),
      .hart_id_i('0),
      .irq_i('0),
      .ipi_i(1'b0),
      .time_irq_i(1'b0),
      .debug_req_i(1'b0),
      .rvfi_probes_o(),
      .noc_req_o(noc_req),
      .noc_resp_i(noc_resp)
  );

  autoisa_ci_axi_memory i_memory (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      .req_i(noc_req),
      .resp_o(noc_resp),
      .tohost_valid_o(tohost_valid),
      .tohost_value_o(tohost_value)
  );

  initial begin
    repeat (12) @(posedge clk_i);
    rst_ni = 1'b1;
  end

  initial begin : inject_result_backpressure
    backpressure_done = 1'b0;
    wait (rst_ni);
    wait (dut.gen_cvxif.i_autoisa_ci_cvxif.shell_req_fire &&
          dut.gen_cvxif.i_autoisa_ci_cvxif.decoded_desc.dst_addr[0] == 5'd15);
    @(negedge clk_i);
    force dut.cvxif_req.result_ready = 1'b0;
    wait (backpressure_cycles >= 4);
    @(negedge clk_i);
    release dut.cvxif_req.result_ready;
    backpressure_done = 1'b1;
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      cycles <= 0;
      issue_count <= 0;
      commit_count <= 0;
      result_count <= 0;
      reject_count <= 0;
      fault_count <= 0;
      backpressure_cycles <= 0;
      issue_rd_seen <= '0;
      result_rd_seen <= '0;
      transaction_live <= '0;
      transaction_committed <= '0;
      stalled_result <= '0;
      stalled_result_captured <= 1'b0;
    end else begin
      cycles <= cycles + 1;
      if (dut.gen_cvxif.i_autoisa_ci_cvxif.shell_req_fire) begin
        $display("EVENT: issue id=%0d rd=%0d ci=%0d operands=%08x/%08x/%08x src3=x%0d",
                 dut.gen_cvxif.i_autoisa_ci_cvxif.issue_id,
                 dut.gen_cvxif.i_autoisa_ci_cvxif.decoded_desc.dst_addr[0],
                 dut.gen_cvxif.i_autoisa_ci_cvxif.decoded_desc.ci_id,
                 dut.gen_cvxif.i_autoisa_ci_cvxif.cvxif_req_i.register.rs[0],
                 dut.gen_cvxif.i_autoisa_ci_cvxif.cvxif_req_i.register.rs[1],
                 dut.gen_cvxif.i_autoisa_ci_cvxif.cvxif_req_i.register.rs[2],
                 dut.gen_cvxif.i_autoisa_ci_cvxif.decoded_desc.src_addr[2]);
        issue_count <= issue_count + 1;
        if (!expected_destination(dut.gen_cvxif.i_autoisa_ci_cvxif.decoded_desc.dst_addr[0]))
          $fatal(1, "unexpected AutoISA destination accepted");
        if (issue_rd_seen[dut.gen_cvxif.i_autoisa_ci_cvxif.decoded_desc.dst_addr[0]])
          $fatal(
              1,
              "duplicate AutoISA issue for rd=%0d",
              dut.gen_cvxif.i_autoisa_ci_cvxif.decoded_desc.dst_addr[0]
          );
        if (dut.gen_cvxif.i_autoisa_ci_cvxif.decoded_desc.ci_id != expected_ci(
                dut.gen_cvxif.i_autoisa_ci_cvxif.decoded_desc.dst_addr[0]
            ))
          $fatal(
              1,
              "wrong D/L combination accepted for rd=%0d",
              dut.gen_cvxif.i_autoisa_ci_cvxif.decoded_desc.dst_addr[0]
          );
        if (transaction_live[dut.gen_cvxif.i_autoisa_ci_cvxif.issue_id])
          $fatal(1, "CV-X-IF transaction ID reused while live");
        issue_rd_seen[dut.gen_cvxif.i_autoisa_ci_cvxif.decoded_desc.dst_addr[0]] <= 1'b1;
        transaction_live[dut.gen_cvxif.i_autoisa_ci_cvxif.issue_id] <= 1'b1;
        transaction_committed[dut.gen_cvxif.i_autoisa_ci_cvxif.issue_id] <= 1'b0;
      end

      if (dut.gen_cvxif.i_autoisa_ci_cvxif.commit_valid) begin
        $display("EVENT: commit id=%0d live=%0d committed=%0d",
                 dut.gen_cvxif.i_autoisa_ci_cvxif.commit_id,
                 transaction_live[dut.gen_cvxif.i_autoisa_ci_cvxif.commit_id],
                 transaction_committed[dut.gen_cvxif.i_autoisa_ci_cvxif.commit_id]);
        commit_count <= commit_count + 1;
        if (!(transaction_live[dut.gen_cvxif.i_autoisa_ci_cvxif.commit_id] ||
              (dut.gen_cvxif.i_autoisa_ci_cvxif.shell_req_fire &&
               dut.gen_cvxif.i_autoisa_ci_cvxif.issue_id ==
                   dut.gen_cvxif.i_autoisa_ci_cvxif.commit_id)))
          $fatal(1, "AutoISA commit without an accepted issue");
        if (transaction_committed[dut.gen_cvxif.i_autoisa_ci_cvxif.commit_id])
          $fatal(1, "duplicate AutoISA commit");
        transaction_committed[dut.gen_cvxif.i_autoisa_ci_cvxif.commit_id] <= 1'b1;
      end

      if (dut.gen_cvxif.i_autoisa_ci_cvxif.cvxif_req_i.issue_valid &&
          dut.gen_cvxif.i_autoisa_ci_cvxif.cvxif_resp_o.issue_ready &&
          !dut.gen_cvxif.i_autoisa_ci_cvxif.cvxif_resp_o.issue_resp.accept)
        reject_count <= reject_count + 1;

      if (dut.gen_cvxif.i_autoisa_ci_cvxif.shell_result_valid &&
          !dut.gen_cvxif.i_autoisa_ci_cvxif.cvxif_req_i.result_ready) begin
        backpressure_cycles <= backpressure_cycles + 1;
        if (!stalled_result_captured) begin
          stalled_result <= dut.gen_cvxif.i_autoisa_ci_cvxif.shell_result;
          stalled_result_captured <= 1'b1;
        end else if (dut.gen_cvxif.i_autoisa_ci_cvxif.shell_result != stalled_result) begin
          $fatal(1, "AutoISA result payload changed under backpressure");
        end
      end

      if (dut.gen_cvxif.i_autoisa_ci_cvxif.shell_result_fire) begin
        $display("EVENT: result id=%0d rd=%0d status=%0d data=%08x",
                 dut.gen_cvxif.i_autoisa_ci_cvxif.result_id,
                 dut.gen_cvxif.i_autoisa_ci_cvxif.rd_q[dut.gen_cvxif.i_autoisa_ci_cvxif.result_id],
                 dut.gen_cvxif.i_autoisa_ci_cvxif.shell_result.status,
                 dut.gen_cvxif.i_autoisa_ci_cvxif.shell_result.results[0]);
        result_count <= result_count + 1;
        if (!transaction_live[dut.gen_cvxif.i_autoisa_ci_cvxif.result_id])
          $fatal(1, "AutoISA result without an accepted issue");
        if (!(transaction_committed[dut.gen_cvxif.i_autoisa_ci_cvxif.result_id] ||
              (dut.gen_cvxif.i_autoisa_ci_cvxif.commit_valid &&
               dut.gen_cvxif.i_autoisa_ci_cvxif.commit_id ==
                   dut.gen_cvxif.i_autoisa_ci_cvxif.result_id)))
          $fatal(1, "AutoISA result arrived without commit");
        if (result_rd_seen[
                dut.gen_cvxif.i_autoisa_ci_cvxif.rd_q[
                    dut.gen_cvxif.i_autoisa_ci_cvxif.result_id]])
          $fatal(1, "duplicate AutoISA result/writeback");
        result_rd_seen[
            dut.gen_cvxif.i_autoisa_ci_cvxif.rd_q[
                dut.gen_cvxif.i_autoisa_ci_cvxif.result_id]] <= 1'b1;
        transaction_live[dut.gen_cvxif.i_autoisa_ci_cvxif.result_id] <= 1'b0;
        transaction_committed[dut.gen_cvxif.i_autoisa_ci_cvxif.result_id] <= 1'b0;

        if (dut.gen_cvxif.i_autoisa_ci_cvxif.rd_q[
                dut.gen_cvxif.i_autoisa_ci_cvxif.result_id] == 5'd17) begin
          fault_count <= fault_count + 1;
          if (dut.gen_cvxif.i_autoisa_ci_cvxif.shell_result.status !=
                  autoisa_ci_types_pkg::AUTOISA_STATUS_ENGINE_FAULT ||
              dut.gen_cvxif.i_autoisa_ci_cvxif.cvxif_resp_o.result.we[0])
            $fatal(1, "D11 fault incorrectly enabled architectural writeback");
        end else begin
          if (dut.gen_cvxif.i_autoisa_ci_cvxif.shell_result.status !=
                  autoisa_ci_types_pkg::AUTOISA_STATUS_OK ||
              dut.gen_cvxif.i_autoisa_ci_cvxif.shell_result.results[0] !=
                  expected_result(
                  dut.gen_cvxif.i_autoisa_ci_cvxif.rd_q[dut.gen_cvxif.i_autoisa_ci_cvxif.result_id]
              ) || !dut.gen_cvxif.i_autoisa_ci_cvxif.cvxif_resp_o.result.we[0] ||
                  dut.gen_cvxif.i_autoisa_ci_cvxif.cvxif_resp_o.result.rd !=
                  dut.gen_cvxif.i_autoisa_ci_cvxif.rd_q[dut.gen_cvxif.i_autoisa_ci_cvxif.result_id]
                  || dut.gen_cvxif.i_autoisa_ci_cvxif.cvxif_resp_o.result.data !=
                  dut.gen_cvxif.i_autoisa_ci_cvxif.shell_result.results[0])
            $fatal(1, "AutoISA result or architectural writeback mismatch");
        end
      end

      if (tohost_valid) begin
        $display(
            "DATA: cycles=%0d issue=%0d commit=%0d result=%0d reject=%0d fault=%0d backpressure=%0d tohost=%0d",
            cycles, issue_count, commit_count, result_count, reject_count, fault_count,
            backpressure_cycles, tohost_value);
        if (tohost_value != 32'd1)
          $fatal(1, "AutoISA coverage program reported failure through tohost");
        if (issue_count != EXPECTED_ACCEPTED ||
            commit_count != EXPECTED_ACCEPTED ||
            result_count != EXPECTED_ACCEPTED || reject_count != 2 ||
            fault_count != 1 || backpressure_cycles < 4 ||
            !backpressure_done || issue_rd_seen != EXPECTED_RD_MASK ||
            result_rd_seen != EXPECTED_RD_MASK || transaction_live != '0)
          $fatal(1, "AutoISA protocol evidence is incomplete");
        for (int unsigned i = 0; i < SIGNATURE_CHECK_WORDS; i++) begin
          $display("SIGNATURE[%0d]=%08x", i, i_memory.signature_q[i]);
          if ((i_memory.signature_q[i] & expected_signature_mask[i]) !==
              (expected_signature[i] & expected_signature_mask[i]))
            $fatal(
                1,
                "software signature mismatch word=%0d actual=%08x expected=%08x mask=%08x",
                i,
                i_memory.signature_q[i],
                expected_signature[i],
                expected_signature_mask[i]
            );
        end
        $display("PASS: expanded AutoISA program-level architectural gate");
        $finish;
      end

      if (cycles == 40000) $fatal(1, "timeout waiting for AutoISA program coverage tohost");
    end
  end

  initial begin
`ifndef AUTOISA_CI_CVXIF
    $fatal(1, "ELF closure test requires AUTOISA_CI_CVXIF");
`endif
`ifndef AUTOISA_CI_3R
    $fatal(1, "ELF closure test requires AUTOISA_CI_3R for L1/D1");
`endif
  end
endmodule
