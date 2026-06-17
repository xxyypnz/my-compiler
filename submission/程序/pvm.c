#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "pvm.h"
#include "codegen.h"

static int stack[MAX_STACK];
static int sp;          /* stack pointer: next free slot */
static int pc;          /* program counter */

/* Frame stack: tracks base address of each nested block's locals */
static int frame_base[256];
static int frame_top;   /* number of active frames */

/* Global temp buffer for set literals, union, inter results */
static int temp_set[SET_SIZE];

/* ------------------------------------------------------------------ */
/* Helpers                                                              */
/* ------------------------------------------------------------------ */

static int get_frame_base(int ld) {
    /* ld=0 → current frame, ld=1 → parent, etc. */
    int idx = frame_top - 1 - ld;
    if (idx < 0) {
        fprintf(stderr, "runtime error: invalid level difference %d\n", ld);
        exit(1);
    }
    return frame_base[idx];
}

static int *var_addr(int ld, int off) {
    return &stack[get_frame_base(ld) + off];
}

static int *set_base(int ld, int off) {
    return var_addr(ld, off);
}

/* Push/pop helpers */
static void push(int v) {
    if (sp >= MAX_STACK) { fprintf(stderr, "runtime error: stack overflow\n"); exit(1); }
    stack[sp++] = v;
}

static int pop(void) {
    if (sp <= 0) { fprintf(stderr, "runtime error: stack underflow\n"); exit(1); }
    return stack[--sp];
}

/* ------------------------------------------------------------------ */
/* Set helpers                                                          */
/* ------------------------------------------------------------------ */

static int set_contains(int *base, int v) {
    int cnt = base[0];
    for (int i = 1; i <= cnt; i++)
        if (base[i] == v) return 1;
    return 0;
}

static void set_add_elem(int *base, int v) {
    if (set_contains(base, v)) return;
    int cnt = base[0];
    if (cnt >= SET_SIZE - 1) {
        fprintf(stderr, "runtime error: set overflow (max %d elements)\n", SET_SIZE - 1);
        exit(1);
    }
    base[cnt + 1] = v;
    base[0]++;
}

static void set_rem_elem(int *base, int v) {
    int cnt = base[0];
    for (int i = 1; i <= cnt; i++) {
        if (base[i] == v) {
            /* shift left */
            for (int j = i; j < cnt; j++) base[j] = base[j + 1];
            base[0]--;
            return;
        }
    }
    /* element not found: no-op */
}

static void set_copy(int *dst, int *src) {
    memcpy(dst, src, SET_SIZE * sizeof(int));
}

static void set_union(int *dst, int *a, int *b) {
    memset(dst, 0, SET_SIZE * sizeof(int));
    int ca = a[0];
    for (int i = 1; i <= ca; i++) set_add_elem(dst, a[i]);
    int cb = b[0];
    for (int i = 1; i <= cb; i++) set_add_elem(dst, b[i]);
}

static void set_inter(int *dst, int *a, int *b) {
    memset(dst, 0, SET_SIZE * sizeof(int));
    int ca = a[0];
    for (int i = 1; i <= ca; i++)
        if (set_contains(b, a[i])) set_add_elem(dst, a[i]);
}

static int set_equal(int *a, int *b) {
    if (a[0] != b[0]) return 0;
    int ca = a[0];
    for (int i = 1; i <= ca; i++)
        if (!set_contains(b, a[i])) return 0;
    return 1;
}

static int cmp_int(const void *x, const void *y) {
    return *(int *)x - *(int *)y;
}

static void print_set(int *base) {
    int cnt = base[0];
    int tmp[SET_SIZE - 1];
    for (int i = 0; i < cnt; i++) tmp[i] = base[i + 1];
    qsort(tmp, cnt, sizeof(int), cmp_int);
    printf("{");
    for (int i = 0; i < cnt; i++) {
        if (i) printf(", ");
        printf("%d", tmp[i]);
    }
    printf("}");
}

/* ------------------------------------------------------------------ */
/* Single-step display                                                  */
/* ------------------------------------------------------------------ */

static const char *opr_names[] = {
    "RET","NEG","ADD","SUB","MUL","DIV","?","EQ",
    "NEQ","LT","GEQ","GT","LEQ","NOT","AND","OR"
};

static void print_instruction(int addr) {
    Instruction *ins = &code[addr];
    const char *names[] = {
        "LIT","LOD","STO","INT","JMP","JPC","OPR",
        "READ","WRITE","WRITES","WRITET",
        "SET_NEW","SET_LIT","SET_ADD","SET_REM",
        "SET_IN","SET_EMPTY","SET_UNION","SET_INTER","SET_COPY",
        "SET_EQL","SET_ELEM"
    };
    const char *nm = (ins->op <= SET_ELEM) ? names[ins->op] : "???";
    if (ins->op == OPR && ins->a >= 0 && ins->a <= 15)
        printf("  [%4d] %-10s %3d %3d  ; %s", addr, nm, ins->l, ins->a, opr_names[ins->a]);
    else if (ins->op == SET_UNION || ins->op == SET_INTER || ins->op == SET_EQL)
        printf("  [%4d] %-10s  ld1=%d off1=%d  ld2=%d off2=%d",
               addr, nm,
               DECODE_LD(ins->l), DECODE_OFF(ins->l),
               DECODE_LD(ins->a), DECODE_OFF(ins->a));
    else
        printf("  [%4d] %-10s %3d %3d", addr, nm, ins->l, ins->a);
}

/* ------------------------------------------------------------------ */
/* Main execution loop                                                  */
/* ------------------------------------------------------------------ */

void pvm_run(int step_mode) {
    pc        = 0;
    sp        = 0;
    frame_top = 0;
    memset(stack, 0, sizeof(stack));

    while (1) {
        if (pc < 0 || pc >= code_len) {
            fprintf(stderr, "runtime error: pc=%d out of range\n", pc);
            break;
        }

        if (step_mode) {
            print_instruction(pc);
            printf("\n  sp=%-4d  stack top: %s  [Enter=step  r=run  q=quit] ",
                   sp, sp > 0 ? "" : "(empty)");
            if (sp > 0) printf("%d  ", stack[sp - 1]);
            char buf[16];
            if (!fgets(buf, sizeof(buf), stdin)) break;
            if (buf[0] == 'q') break;
            if (buf[0] == 'r') step_mode = 0;
        }

        Instruction ins = code[pc++];

        switch (ins.op) {

        case LIT:
            push(ins.a);
            break;

        case LOD:
            push(*var_addr(ins.l, ins.a));
            break;

        case STO:
            *var_addr(ins.l, ins.a) = pop();
            break;

        case INT:
            if (ins.a >= 0) {
                /* allocate: push new frame */
                if (frame_top >= 256) {
                    fprintf(stderr, "runtime error: frame stack overflow\n");
                    exit(1);
                }
                frame_base[frame_top++] = sp;
                sp += ins.a;
                if (sp > MAX_STACK) {
                    fprintf(stderr, "runtime error: stack overflow\n");
                    exit(1);
                }
            } else {
                /* deallocate: pop frame */
                sp -= (-ins.a);
                frame_top--;
            }
            break;

        case JMP:
            pc = ins.a;
            break;

        case JPC:
            if (pop() == 0) pc = ins.a;
            break;

        case OPR: {
            int b, a;
            switch (ins.a) {
            case OPR_RET:
                return;
            case OPR_NEG:
                stack[sp - 1] = -stack[sp - 1];
                break;
            case OPR_ADD: b = pop(); push(pop() + b); break;
            case OPR_SUB: b = pop(); push(pop() - b); break;
            case OPR_MUL: b = pop(); push(pop() * b); break;
            case OPR_DIV:
                b = pop(); a = pop();
                if (b == 0) { fprintf(stderr, "runtime error: division by zero\n"); exit(1); }
                push(a / b);
                break;
            case OPR_EQ:  b = pop(); push(pop() == b ? 1 : 0); break;
            case OPR_NEQ: b = pop(); push(pop() != b ? 1 : 0); break;
            case OPR_LT:  b = pop(); push(pop() <  b ? 1 : 0); break;
            case OPR_GEQ: b = pop(); push(pop() >= b ? 1 : 0); break;
            case OPR_GT:  b = pop(); push(pop() >  b ? 1 : 0); break;
            case OPR_LEQ: b = pop(); push(pop() <= b ? 1 : 0); break;
            case OPR_NOT: push(pop() == 0 ? 1 : 0); break;
            case OPR_AND: b = pop(); push(pop() & b); break;
            case OPR_OR:  b = pop(); push(pop() | b); break;
            default:
                fprintf(stderr, "runtime error: unknown OPR %d\n", ins.a);
                exit(1);
            }
            break;
        }

        case READ: {
            int v;
            if (scanf("%d", &v) != 1) {
                fprintf(stderr, "runtime error: read failed\n");
                exit(1);
            }
            push(v);
            break;
        }

        case WRITE:
            printf("%d\n", pop());
            break;

        case WRITES:
            print_set(set_base(ins.l, ins.a));
            printf("\n");
            break;

        case WRITET:
            print_set(temp_set);
            printf("\n");
            break;

        case SET_NEW:
            memset(set_base(ins.l, ins.a), 0, SET_SIZE * sizeof(int));
            break;

        case SET_LIT: {
            /* pop ins.a ints (pushed left-to-right, so last pushed = last element) */
            int elems[SET_SIZE - 1];
            int n = ins.a;
            for (int i = n - 1; i >= 0; i--) elems[i] = pop();
            memset(temp_set, 0, SET_SIZE * sizeof(int));
            for (int i = 0; i < n; i++) set_add_elem(temp_set, elems[i]);
            break;
        }

        case SET_ADD: {
            int v = pop();
            set_add_elem(set_base(ins.l, ins.a), v);
            break;
        }

        case SET_REM: {
            int v = pop();
            set_rem_elem(set_base(ins.l, ins.a), v);
            break;
        }

        case SET_IN: {
            int v = pop();
            push(set_contains(set_base(ins.l, ins.a), v) ? 1 : 0);
            break;
        }

        case SET_EMPTY:
            push(set_base(ins.l, ins.a)[0] == 0 ? 1 : 0);
            break;

        case SET_UNION: {
            int *a = set_base(DECODE_LD(ins.l), DECODE_OFF(ins.l));
            int *b = set_base(DECODE_LD(ins.a), DECODE_OFF(ins.a));
            set_union(temp_set, a, b);
            break;
        }

        case SET_INTER: {
            int *a = set_base(DECODE_LD(ins.l), DECODE_OFF(ins.l));
            int *b = set_base(DECODE_LD(ins.a), DECODE_OFF(ins.a));
            set_inter(temp_set, a, b);
            break;
        }

        case SET_COPY:
            set_copy(set_base(ins.l, ins.a), temp_set);
            break;

        case SET_EQL: {
            int *a = set_base(DECODE_LD(ins.l), DECODE_OFF(ins.l));
            int *b = set_base(DECODE_LD(ins.a), DECODE_OFF(ins.a));
            push(set_equal(a, b) ? 1 : 0);
            break;
        }

        case SET_ELEM: {
            int idx = pop();
            int *base = set_base(ins.l, ins.a);
            int cnt = base[0];
            if (idx < 0 || idx >= cnt) {
                fprintf(stderr, "runtime error: set index %d out of range (size=%d)\n", idx, cnt);
                exit(1);
            }
            push(base[idx + 1]);
            break;
        }

        default:
            fprintf(stderr, "runtime error: unknown opcode %d at pc=%d\n", ins.op, pc - 1);
            exit(1);
        }
    }
}
