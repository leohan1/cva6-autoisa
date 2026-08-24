// See LICENSE for license details.

#ifndef __HART_LOCAL_H
#define __HART_LOCAL_H

// crt.S reserves a private region for each hart and stores its base in tp.
// Access it directly so the freestanding tests do not depend on libgcc's
// malloc-backed emulated TLS implementation.
typedef struct {
  char print_buf[64] __attribute__((aligned(64)));
  int print_buflen;
  int barrier_threadsense;
} hart_local_t;

static inline hart_local_t *hart_local(void)
{
  register hart_local_t *state asm("tp");
  return state;
}

#endif // __HART_LOCAL_H
