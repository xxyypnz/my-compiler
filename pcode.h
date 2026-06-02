#ifndef PCODE_H
#define PCODE_H

#define SET_SIZE  201   /* 1 count word + 200 element words */
#define MAX_CODE  4096
#define MAX_STACK 16384

typedef enum {
    LIT = 0, LOD, STO, INT, JMP, JPC, OPR,
    READ, WRITE, WRITES, WRITET,
    SET_NEW, SET_LIT, SET_ADD, SET_REM,
    SET_IN, SET_EMPTY, SET_UNION, SET_INTER, SET_COPY,
    SET_EQL, SET_ELEM
} OpCode;

typedef struct {
    OpCode op;
    int    l;
    int    a;
} Instruction;

/* OPR sub-codes */
#define OPR_RET  0
#define OPR_NEG  1
#define OPR_ADD  2
#define OPR_SUB  3
#define OPR_MUL  4
#define OPR_DIV  5
#define OPR_EQ   7
#define OPR_NEQ  8
#define OPR_LT   9
#define OPR_GEQ  10
#define OPR_GT   11
#define OPR_LEQ  12
#define OPR_NOT  13
#define OPR_AND  14
#define OPR_OR   15

/*
 * Two-set instruction encoding (SET_UNION, SET_INTER, SET_EQL):
 *   l = ld1 * 10000 + offset1
 *   a = ld2 * 10000 + offset2
 * Level differences < 100, offsets < 9999, so no collision.
 */
#define ENCODE2(ld, off)       ((ld) * 10000 + (off))
#define DECODE_LD(enc)         ((enc) / 10000)
#define DECODE_OFF(enc)        ((enc) % 10000)

extern Instruction code[MAX_CODE];
extern int         code_len;

#endif /* PCODE_H */
