#include "../../../generated/layout/autoisa_ci_encoding.S"

  .option norvc

  .equ SIGNATURE_MAGIC,       0x4155544f
  .equ SIGNATURE_VERSION,     1
  .equ SIGNATURE_PASS,        1
  .equ SIGNATURE_FAIL_BASE,   0x80000000
  .equ SIGNATURE_COVERAGE,    0x00001fff
  .equ SIGNATURE_SENTINEL,    0x5349474e
  .equ EXPECTED_ACCEPTED,     11
  .equ EXPECTED_TRAPS,        2

  .macro AUTOISA_L0 ci, rd, rs1, rs2
    .word AUTOISA_L_2R1W_GPR32_MATCH | ((\ci) << 25) | ((\rd) << 7) | ((\rs1) << 15) | ((\rs2) << 20)
  .endm

  .macro AUTOISA_L7 rd, rs1, rs2, imm
    .word AUTOISA_L_2R1W_IMM_MATCH | ((((\imm) >> 3) & 0x7f) << 25) | (((\imm) & 0x7) << 12) | ((\rd) << 7) | ((\rs1) << 15) | ((\rs2) << 20)
  .endm

  .section .text.init
  .align 2
  .globl _start
  .type _start, @function
_start:
  la x19, signature
  li x20, SIGNATURE_MAGIC
  sw x20, 0(x19)
  li x20, SIGNATURE_VERSION
  sw x20, 4(x19)
  sw x0, 8(x19)
  sw x0, 12(x19)
  sw x0, 16(x19)
  sw x0, 20(x19)
  sw x0, 24(x19)
  li x20, EXPECTED_ACCEPTED
  sw x20, 28(x19)

  la x20, trap_handler
  csrw mtvec, x20
  li x18, 0

  # Boundary operands: zero, unsigned maximum, and 32-bit wraparound.
  AUTOISA_L0 0, 5, 0, 0
  li x20, 0x101
  li x21, 0
  sw x5, 32(x19)
  bne x5, x21, fail

  li x6, -1
  li x7, 1
  AUTOISA_L0 0, 8, 6, 7
  li x20, 0x102
  li x21, 0
  sw x8, 36(x19)
  bne x8, x21, fail

  AUTOISA_L0 0, 9, 6, 6
  li x20, 0x103
  li x21, -2
  sw x9, 40(x19)
  bne x9, x21, fail

  # Three consecutive D0 instructions form a true RAW chain. There are no
  # scalar instructions between them, so issue/scoreboard errors are exposed.
  li x6, 1
  li x7, 2
  AUTOISA_L0 0, 10, 6, 7
  AUTOISA_L0 0, 11, 10, 7
  AUTOISA_L0 0, 12, 11, 10
  sw x10, 44(x19)
  sw x11, 48(x19)
  sw x12, 52(x19)
  li x20, 0x104
  li x21, 3
  bne x10, x21, fail
  li x20, 0x105
  li x21, 5
  bne x11, x21, fail
  li x20, 0x106
  li x21, 8
  bne x12, x21, fail

  # More two-source semantics carried by scalar L0/CV-X-IF.
  li x6, 10
  li x7, 20
  AUTOISA_L0 8, 13, 6, 7
  li x20, 0x107
  li x21, 30
  sw x13, 56(x19)
  bne x13, x21, fail

  li x6, 0xa5a5a5a5
  li x7, 0x0f0f0f0f
  AUTOISA_L0 9, 14, 6, 7
  li x20, 0x108
  li x21, 0xaaaaaaaa
  sw x14, 60(x19)
  bne x14, x21, fail

  # The testbench holds result_ready low for this D10 transaction and checks
  # that the result payload remains stable until the handshake completes.
  li x6, -1
  li x7, 2
  AUTOISA_L0 10, 15, 6, 7
  li x20, 0x109
  li x21, 1
  sw x15, 64(x19)
  bne x15, x21, fail

  # L7/D7 covers the scalar immediate layout: (5 << 3) ^ (9 + 3) = 36.
  li x6, 5
  li x7, 9
  AUTOISA_L7 16, 6, 7, 3
  li x20, 0x10a
  li x21, 36
  sw x16, 68(x19)
  bne x16, x21, fail

  # D11 returns ENGINE_FAULT with no architectural write enable. The sentinel
  # must survive, proving that a failed engine response cannot corrupt rd.
  li x17, 0x13579bdf
  AUTOISA_L0 11, 17, 6, 7
  li x20, 0x10b
  li x21, 0x13579bdf
  sw x17, 72(x19)
  bne x17, x21, fail

  # Illegal destination (rd=x0) and unsupported D12 must both be rejected by
  # CV-X-IF and return through the machine illegal-instruction trap handler.
  AUTOISA_L0 0, 0, 6, 7
  li x21, 0x2468ace0
  AUTOISA_L0 12, 21, 6, 7
  sw x21, 76(x19)
  li x20, 0x10c
  li x22, 0x2468ace0
  bne x21, x22, fail
  li x20, 0x10d
  li x22, EXPECTED_TRAPS
  bne x18, x22, fail

  li x20, SIGNATURE_COVERAGE
  sw x20, 12(x19)
  sw x18, 16(x19)
  li x20, SIGNATURE_SENTINEL
  sw x20, 80(x19)
  li x20, SIGNATURE_PASS
  sw x20, 8(x19)

pass:
  fence
  la x5, tohost
  li x6, 1
  sw x6, 0(x5)
  fence
1:
  j 1b

trap_handler:
  csrr x28, mcause
  li x29, 2
  bne x28, x29, unexpected_trap
  addi x18, x18, 1
  sw x28, 20(x19)
  csrr x30, mtval
  sw x30, 24(x19)
  csrr x28, mepc
  addi x28, x28, 4
  csrw mepc, x28
  mret

unexpected_trap:
  li x20, 0x1f0
  sw x28, 20(x19)
  csrr x30, mtval
  sw x30, 24(x19)

fail:
  sw x18, 16(x19)
  li x21, SIGNATURE_FAIL_BASE
  or x20, x20, x21
  sw x20, 8(x19)
  li x21, 0x4641494c
  sw x21, 80(x19)
  fence
  la x5, tohost
  li x6, 3
  sw x6, 0(x5)
  fence
1:
  j 1b

  .size _start, .-_start

  .section .signature,"aw",@progbits
  .align 3
  .globl signature
signature:
  .space 84

  .section .tohost,"aw",@progbits
  .align 3
  .globl tohost
tohost:
  .dword 0
