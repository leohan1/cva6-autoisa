#include "../../../generated/layout/autoisa_ci_encoding.S"

  .option norvc
  .equ G5_MAGIC, 0x47354142
#ifndef G5_ITERATIONS
#define G5_ITERATIONS 64
#endif
#ifndef G5_THROUGHPUT
#define G5_THROUGHPUT 0
#endif
  .macro AUTOISA_WORD value
    .word \value
  .endm

  .section .text.init
  .align 2
  .globl _start
  .type _start, @function
_start:
  li x8, 17
  li x9, 29
#if G5_PROFILE == 2
  li x8, 6
  li x9, 7
  li x10, 8
#elif G5_PROFILE == 3
  li x8, 3
  li x9, 5
  li x10, 7
  li x11, 11
#elif G5_PROFILE == 4
  li x8, 21
  li x9, 8
#elif G5_PROFILE == 5
  li x8, 2
  li x9, 3
  li x10, 5
  li x11, 7
#elif G5_PROFILE == 6
  li x8, 1
  li x9, 2
  li x10, 3
  li x11, 4
  li x12, 5
  li x13, 6
#elif G5_PROFILE == 7
  li x8, 2
  li x9, 3
  li x10, 4
  li x11, 5
  li x12, 6
  li x13, 7
#elif G5_PROFILE == 8
  li x8, 5
  li x9, 9
#endif

#if G5_THROUGHPUT
  li x18, G5_ITERATIONS / 4
#else
  li x18, G5_ITERATIONS
#endif
  li x16, 0
  li x17, 0
  csrr x20, mcycle
  csrr x21, minstret
1:
#if G5_THROUGHPUT
# if G5_PROFILE == 1
#  if G5_AUTOISA
  AUTOISA_WORD 0x0094055b
  AUTOISA_WORD 0x009405db
  AUTOISA_WORD 0x0094065b
  AUTOISA_WORD 0x009406db
#  else
  add x10, x8, x9
  add x11, x8, x9
  add x12, x8, x9
  add x13, x8, x9
#  endif
  add x14, x10, x11
  add x15, x12, x13
  add x14, x14, x15
# elif G5_PROFILE == 2
#  if G5_AUTOISA
  AUTOISA_WORD 0x549415db
  AUTOISA_WORD 0x5494165b
  AUTOISA_WORD 0x549416db
  AUTOISA_WORD 0x5494175b
#  else
  mul x11, x8, x9
  add x11, x11, x10
  mul x12, x8, x9
  add x12, x12, x10
  mul x13, x8, x9
  add x13, x13, x10
  mul x14, x8, x9
  add x14, x14, x10
#  endif
  add x15, x11, x12
  add x19, x13, x14
  add x14, x15, x19
# elif G5_PROFILE == 8
#  if G5_AUTOISA
  AUTOISA_WORD 0x0094350b
  AUTOISA_WORD 0x0094358b
  AUTOISA_WORD 0x0094360b
  AUTOISA_WORD 0x0094368b
#  else
  slli x10, x8, 3
  addi x14, x9, 3
  xor x10, x10, x14
  slli x11, x8, 3
  addi x14, x9, 3
  xor x11, x11, x14
  slli x12, x8, 3
  addi x14, x9, 3
  xor x12, x12, x14
  slli x13, x8, 3
  addi x14, x9, 3
  xor x13, x13, x14
#  endif
  add x14, x10, x11
  add x15, x12, x13
  add x14, x14, x15
# endif
#else
#if G5_PROFILE == 0
  add x14, x8, x9
#elif G5_PROFILE == 1
# if G5_AUTOISA
  AUTOISA_WORD 0x0094055b
# else
  add x10, x8, x9
# endif
  mv x14, x10
#elif G5_PROFILE == 2
# if G5_AUTOISA
  AUTOISA_WORD 0x549415db
# else
  mul x11, x8, x9
  add x11, x11, x10
# endif
  mv x14, x11
#elif G5_PROFILE == 3
# if G5_AUTOISA
  AUTOISA_WORD 0x1344285b
# else
  mul x12, x8, x9
  add x12, x12, x10
  xor x12, x12, x11
# endif
  mv x14, x12
#elif G5_PROFILE == 4
# if G5_AUTOISA
  AUTOISA_WORD 0x0694355b
# else
  add x10, x8, x9
  sub x11, x8, x9
# endif
  mv x14, x10
  mv x15, x11
#elif G5_PROFILE == 5
# if G5_AUTOISA
  AUTOISA_WORD 0x2b44425b
# else
  mul x12, x8, x10
  mul x14, x9, x11
  sub x12, x12, x14
  mul x13, x8, x11
  mul x14, x9, x10
  add x13, x13, x14
# endif
  mv x14, x12
  mv x15, x13
#elif G5_PROFILE == 6
# if G5_AUTOISA
  AUTOISA_WORD 0x0b1a232b
# else
  add x14, x8, x9
  add x15, x10, x11
  add x14, x14, x15
  add x15, x12, x13
  add x14, x14, x15
# endif
#elif G5_PROFILE == 7
# if G5_AUTOISA
  AUTOISA_WORD 0x58d11f7b
# else
  mul x14, x8, x9
  mul x15, x10, x11
  mul x19, x12, x13
  add x14, x14, x15
  add x14, x14, x19
  mul x15, x8, x9
  mul x19, x10, x11
  sub x15, x15, x19
  mul x19, x12, x13
  add x15, x15, x19
# endif
#elif G5_PROFILE == 8
# if G5_AUTOISA
  AUTOISA_WORD 0x0094350b
# else
  slli x10, x8, 3
  addi x11, x9, 3
  xor x10, x10, x11
# endif
  mv x14, x10
#endif
#endif
  add x16, x16, x14
#if !G5_THROUGHPUT && (G5_PROFILE == 4 || G5_PROFILE == 5 || G5_PROFILE == 7)
  add x17, x17, x15
#endif
  addi x18, x18, -1
  bnez x18, 1b
  csrr x22, mcycle
  csrr x23, minstret
  sub x22, x22, x20
  sub x23, x23, x21

  la x19, signature
  li x20, G5_MAGIC
  sw x20, 0(x19)
  li x20, G5_PROFILE
  sw x20, 4(x19)
  li x20, G5_AUTOISA
  sw x20, 8(x19)
  sw x16, 12(x19)
  sw x17, 16(x19)
  sw x22, 20(x19)
  sw x23, 24(x19)
  li x20, G5_ITERATIONS
  sw x20, 28(x19)
  li x20, G5_THROUGHPUT
  sw x20, 32(x19)
  fence
  la x5, tohost
  li x6, 1
  sw x6, 0(x5)
  fence
2:
  j 2b
  .size _start, .-_start

  .section .signature,"aw",@progbits
  .align 3
  .globl signature
signature:
  .space 36
  .section .tohost,"aw",@progbits
  .align 3
  .globl tohost
tohost:
  .dword 0
