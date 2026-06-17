#include <stdio.h>
#include <stdlib.h>
#include "codegen.h"

Instruction code[MAX_CODE];
int         code_len = 0;

int emit(OpCode op, int l, int a) {
    if (code_len >= MAX_CODE) {
        fprintf(stderr, "error: code buffer overflow\n");
        exit(1);
    }
    int idx = code_len++;
    code[idx].op = op;
    code[idx].l  = l;
    code[idx].a  = a;
    return idx;
}

void patch(int idx, int new_a) {
    code[idx].a = new_a;
}

int current_addr(void) {
    return code_len;
}

static const char *opcode_name(OpCode op) {
    switch (op) {
        case LIT:       return "LIT";
        case LOD:       return "LOD";
        case STO:       return "STO";
        case INT:       return "INT";
        case JMP:       return "JMP";
        case JPC:       return "JPC";
        case OPR:       return "OPR";
        case READ:      return "READ";
        case WRITE:     return "WRITE";
        case WRITES:    return "WRITES";
        case WRITET:    return "WRITET";
        case SET_NEW:   return "SET_NEW";
        case SET_LIT:   return "SET_LIT";
        case SET_ADD:   return "SET_ADD";
        case SET_REM:   return "SET_REM";
        case SET_IN:    return "SET_IN";
        case SET_EMPTY: return "SET_EMPTY";
        case SET_UNION: return "SET_UNION";
        case SET_INTER: return "SET_INTER";
        case SET_COPY:  return "SET_COPY";
        case SET_EQL:   return "SET_EQL";
        case SET_ELEM:  return "SET_ELEM";
        default:        return "???";
    }
}

static const char *opr_name(int n) {
    switch (n) {
        case OPR_RET: return "RET";
        case OPR_NEG: return "NEG";
        case OPR_ADD: return "ADD";
        case OPR_SUB: return "SUB";
        case OPR_MUL: return "MUL";
        case OPR_DIV: return "DIV";
        case OPR_EQ:  return "EQ";
        case OPR_NEQ: return "NEQ";
        case OPR_LT:  return "LT";
        case OPR_GEQ: return "GEQ";
        case OPR_GT:  return "GT";
        case OPR_LEQ: return "LEQ";
        case OPR_NOT: return "NOT";
        case OPR_AND: return "AND";
        case OPR_OR:  return "OR";
        default:      return "?";
    }
}

void print_pcode(void) {
    printf("\n=== Generated P-Code ===\n");
    printf("%-6s %-10s %6s %6s\n", "Addr", "Op", "L", "A");
    printf("-------------------------------\n");
    for (int i = 0; i < code_len; i++) {
        Instruction *ins = &code[i];
        if (ins->op == OPR) {
            printf("%4d:  %-10s %6d %6d  ; %s\n",
                   i, opcode_name(ins->op), ins->l, ins->a,
                   opr_name(ins->a));
        } else if (ins->op == SET_UNION || ins->op == SET_INTER || ins->op == SET_EQL) {
            printf("%4d:  %-10s  ld1=%d off1=%d  ld2=%d off2=%d\n",
                   i, opcode_name(ins->op),
                   DECODE_LD(ins->l), DECODE_OFF(ins->l),
                   DECODE_LD(ins->a), DECODE_OFF(ins->a));
        } else {
            printf("%4d:  %-10s %6d %6d\n",
                   i, opcode_name(ins->op), ins->l, ins->a);
        }
    }
    printf("================================\n\n");
}
