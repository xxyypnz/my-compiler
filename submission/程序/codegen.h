#ifndef CODEGEN_H
#define CODEGEN_H

#include "pcode.h"

int  emit(OpCode op, int l, int a);  /* append instruction, return index */
void patch(int idx, int new_a);      /* backpatch jump target */
int  current_addr(void);             /* next free instruction index */
void print_pcode(void);              /* print full P-Code listing */

#endif /* CODEGEN_H */
