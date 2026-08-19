#include "../../../generated/layout/autoisa_ci_encoding.S"

  .option norvc
  .section .text.init
  .align 2
  .globl _start
  .type _start, @function
_start:
  li x6, 11
  li x7, 31

  # L0/D0: x5 = x6 + x7. Keep the instruction as a literal so an unmodified
  # GNU assembler can build the ELF before compiler mnemonic support exists.
  .word AUTOISA_L_2R1W_GPR32_MATCH | (5 << 7) | (6 << 15) | (7 << 20)

  li x28, 42
  bne x5, x28, fail

pass:
  la x5, tohost
  li x6, 1
  sw x6, 0(x5)
  fence
1:
  j 1b

fail:
  la x5, tohost
  li x6, 3
  sw x6, 0(x5)
  fence
1:
  j 1b

  .size _start, .-_start

  .section .tohost,"aw",@progbits
  .align 3
  .globl tohost
tohost:
  .dword 0
