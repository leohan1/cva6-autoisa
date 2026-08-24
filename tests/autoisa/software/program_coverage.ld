OUTPUT_ARCH("riscv")
ENTRY(_start)

SECTIONS
{
  . = 0x80000000;
  .text.init : { KEEP(*(.text.init)) }

  /* Keep completion and the structured software signature outside cached
     DRAM so the architectural testbench observes every store directly. */
  . = 0x10000000;
  .tohost : { KEEP(*(.tohost)) }

  . = 0x10000100;
  .signature : { KEEP(*(.signature)) }

  /DISCARD/ : { *(.comment) *(.riscv.attributes) }
}
