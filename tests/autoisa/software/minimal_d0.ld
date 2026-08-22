OUTPUT_ARCH("riscv")
ENTRY(_start)

SECTIONS
{
  . = 0x80000000;
  .text.init : { KEEP(*(.text.init)) }

  /* Keep the completion store outside the configured cacheable DRAM range so
     the architectural testbench can observe it directly on AXI. */
  . = 0x10000000;
  .tohost : { KEEP(*(.tohost)) }

  /DISCARD/ : { *(.comment) *(.riscv.attributes) }
}
