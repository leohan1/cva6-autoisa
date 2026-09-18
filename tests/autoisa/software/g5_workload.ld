OUTPUT_ARCH("riscv")
ENTRY(_start)

SECTIONS
{
  . = 0x80000000;
  .text.init : { KEEP(*(.text.init)) }
  . = 0x10000000;
  .tohost : { KEEP(*(.tohost)) }
  . = 0x10000100;
  .signature : { KEEP(*(.signature)) }
  /DISCARD/ : { *(.comment) *(.riscv.attributes) }
}
