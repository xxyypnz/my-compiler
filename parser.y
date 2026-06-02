%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "symtab.h"
#include "codegen.h"
#include "pcode.h"

extern int yylineno;
void yyerror(const char *s);
int  yylex(void);

/* ------------------------------------------------------------------ */
/* Backpatch list                                                        */
/* ------------------------------------------------------------------ */
typedef struct PatchNode {
    int addr;
    struct PatchNode *next;
} PatchNode;

static PatchNode *make_patch(int addr) {
    PatchNode *p = (PatchNode *)malloc(sizeof(PatchNode));
    p->addr = addr;
    p->next = NULL;
    return p;
}

static void do_patch(PatchNode *list, int target) {
    for (PatchNode *p = list; p; p = p->next)
        patch(p->addr, target);
}

static void free_patch(PatchNode *list) {
    while (list) {
        PatchNode *next = list->next;
        free(list);
        list = next;
    }
}

/* ------------------------------------------------------------------ */
/* Semantic helpers                                                      */
/* ------------------------------------------------------------------ */
static void type_error(const char *msg) {
    fprintf(stderr, "type error at line %d: %s\n", yylineno, msg);
    exit(1);
}

static void check_int2(VarType t1, VarType t2, const char *op) {
    if (t1 != T_INT || t2 != T_INT) {
        char buf[128];
        snprintf(buf, sizeof(buf), "'%s' requires int operands", op);
        type_error(buf);
    }
}

static void check_bool2(VarType t1, VarType t2, const char *op) {
    if (t1 != T_BOOL || t2 != T_BOOL) {
        char buf[128];
        snprintf(buf, sizeof(buf), "'%s' requires bool operands", op);
        type_error(buf);
    }
}

/*
 * Global variable to pass jpc_end from comp_head to comp_filter.
 * Using a global is the simplest way to thread this value through
 * Bison's limited semantic value passing.
 */
static int g_comp_jpc_end = 0;

%}

%glr-parser

/* ------------------------------------------------------------------ */
/* Value types                                                           */
/* ------------------------------------------------------------------ */
%union {
    int     ival;
    char    sval[64];
    VarType vtype;
    struct {
        VarType type;
        int     level;
        int     offset;
    } expr;
    struct {
        int        addr;     /* loop_top for while; tmp_off for comp */
        int        jpc_idx;  /* JPC index; idx_off for comp */
        PatchNode *list;
    } ctrl;
    int count;
}

/* ------------------------------------------------------------------ */
/* Tokens                                                               */
/* ------------------------------------------------------------------ */
%token <ival> NUM TRUE_KW FALSE_KW
%token <sval> ID
%token INT_KW BOOL_KW SET_KW
%token IF ELSE WHILE
%token READ_KW WRITE_KW
%token ADD_KW REMOVE_KW
%token UNION_KW INTER_KW IN_KW ISEMPTY_KW
%token LE GE EQ_OP NE AND_OP OR_OP

/* ------------------------------------------------------------------ */
/* Nonterminal types                                                     */
/* ------------------------------------------------------------------ */
%type <expr>  expr
%type <vtype> type
%type <count> expr_list
%type <ctrl>  comp_head comp_filter

/* ------------------------------------------------------------------ */
/* Precedence (low to high)                                             */
/* ------------------------------------------------------------------ */
%nonassoc NO_ELSE
%nonassoc ELSE
%left OR_OP
%left AND_OP
%right '!'
%nonassoc '<' '>' LE GE EQ_OP NE
%left '+' '-'
%left '*' '/'
%right UMINUS
%left IN_KW
%left UNION_KW INTER_KW

%%

/* ------------------------------------------------------------------ */
/* Program                                                              */
/* ------------------------------------------------------------------ */
program
    : block
        { emit(OPR, 0, OPR_RET); }
    ;

/* ------------------------------------------------------------------ */
/* Block                                                                */
/*                                                                      */
/* Layout:                                                              */
/*   INT 0 n      -- allocate n words (patched after decls)            */
/*   <decl inits> -- SET_NEW for set vars                              */
/*   <stmts>                                                            */
/*   INT 0 -n     -- deallocate                                        */
/* ------------------------------------------------------------------ */
block
    : '{'
        {
            scope_enter();
            $<ival>$ = emit(INT, 0, 0);   /* placeholder */
        }
      decls
        {
            patch($<ival>2, scope_frame_size());
        }
      stmts
      '}'
        {
            int sz = scope_frame_size();
            scope_exit();
            emit(INT, 0, -sz);
        }
    ;

/* ------------------------------------------------------------------ */
/* Declarations                                                         */
/* ------------------------------------------------------------------ */
decls
    : /* empty */
    | decls decl
    ;

decl
    : type ID ';'
        {
            Symbol *s = sym_declare($2, $1);
            if (!s) {
                fprintf(stderr, "error at line %d: duplicate declaration '%s'\n",
                        yylineno, $2);
                exit(1);
            }
            if ($1 == T_SET) {
                emit(SET_NEW, scope_level() - s->level, s->offset);
            }
        }
    ;

type
    : INT_KW  { $$ = T_INT; }
    | BOOL_KW { $$ = T_BOOL; }
    | SET_KW  { $$ = T_SET; }
    ;

/* ------------------------------------------------------------------ */
/* Statements                                                           */
/* ------------------------------------------------------------------ */
stmts
    : /* empty */
    | stmts stmt
    ;

stmt
    : assign_stmt
    | if_stmt
    | while_stmt
    | io_stmt
    | block
    | set_op_stmt
    ;

assign_stmt
    : ID '=' expr ';'
        {
            Symbol *s = sym_lookup($1);
            if (!s) {
                fprintf(stderr, "error at line %d: undeclared variable '%s'\n",
                        yylineno, $1);
                exit(1);
            }
            if (s->type != $3.type) {
                fprintf(stderr,
                    "error at line %d: type mismatch assigning to '%s' "
                    "(expected %d, got %d)\n",
                    yylineno, $1, s->type, $3.type);
                exit(1);
            }
            int ld = scope_level() - s->level;
            if (s->type == T_SET) {
                emit(SET_COPY, ld, s->offset);
            } else {
                emit(STO, ld, s->offset);
            }
        }
    ;

if_stmt
    : IF '(' expr ')'
        {
            if ($3.type != T_BOOL) type_error("if condition must be bool");
            $<ctrl>$.jpc_idx = emit(JPC, 0, 0);
            $<ctrl>$.list    = make_patch($<ctrl>$.jpc_idx);
        }
      stmt %prec NO_ELSE
        {
            do_patch($<ctrl>5.list, current_addr());
            free_patch($<ctrl>5.list);
        }
    | IF '(' expr ')'
        {
            if ($3.type != T_BOOL) type_error("if condition must be bool");
            $<ctrl>$.jpc_idx = emit(JPC, 0, 0);
            $<ctrl>$.list    = make_patch($<ctrl>$.jpc_idx);
        }
      stmt
        {
            int jmp_idx = emit(JMP, 0, 0);
            do_patch($<ctrl>5.list, current_addr());
            free_patch($<ctrl>5.list);
            $<ctrl>$.list = make_patch(jmp_idx);
        }
      ELSE stmt
        {
            do_patch($<ctrl>7.list, current_addr());
            free_patch($<ctrl>7.list);
        }
    ;

while_stmt
    : WHILE
        { $<ctrl>$.addr = current_addr(); }
      '(' expr ')'
        {
            if ($4.type != T_BOOL) type_error("while condition must be bool");
            $<ctrl>$.jpc_idx = emit(JPC, 0, 0);
            $<ctrl>$.list    = make_patch($<ctrl>$.jpc_idx);
        }
      stmt
        {
            emit(JMP, 0, $<ctrl>2.addr);
            do_patch($<ctrl>6.list, current_addr());
            free_patch($<ctrl>6.list);
        }
    ;

io_stmt
    : WRITE_KW expr ';'
        {
            if ($2.type == T_SET) {
                if ($2.level >= 0) {
                    /* named set variable: address directly */
                    emit(WRITES, $2.level, $2.offset);
                } else {
                    /* result of set literal / union / inter / comprehension
                       is in global temp_set */
                    emit(WRITET, 0, 0);
                }
            } else {
                emit(WRITE, 0, 0);
            }
        }
    | READ_KW ID ';'
        {
            Symbol *s = sym_lookup($2);
            if (!s) {
                fprintf(stderr, "error at line %d: undeclared variable '%s'\n",
                        yylineno, $2);
                exit(1);
            }
            if (s->type != T_INT) type_error("read requires int variable");
            emit(READ, 0, 0);
            emit(STO, scope_level() - s->level, s->offset);
        }
    ;

set_op_stmt
    : ADD_KW ID expr ';'
        {
            Symbol *s = sym_lookup($2);
            if (!s || s->type != T_SET) {
                fprintf(stderr, "error at line %d: 'add' requires a set variable\n",
                        yylineno);
                exit(1);
            }
            if ($3.type != T_INT) type_error("'add' element must be int");
            emit(SET_ADD, scope_level() - s->level, s->offset);
        }
    | REMOVE_KW ID expr ';'
        {
            Symbol *s = sym_lookup($2);
            if (!s || s->type != T_SET) {
                fprintf(stderr, "error at line %d: 'remove' requires a set variable\n",
                        yylineno);
                exit(1);
            }
            if ($3.type != T_INT) type_error("'remove' element must be int");
            emit(SET_REM, scope_level() - s->level, s->offset);
        }
    ;

/* ------------------------------------------------------------------ */
/* Expressions                                                          */
/* ------------------------------------------------------------------ */
expr
    : NUM
        {
            $$.type = T_INT; $$.level = 0; $$.offset = 0;
            emit(LIT, 0, $1);
        }
    | TRUE_KW
        {
            $$.type = T_BOOL; $$.level = 0; $$.offset = 0;
            emit(LIT, 0, 1);
        }
    | FALSE_KW
        {
            $$.type = T_BOOL; $$.level = 0; $$.offset = 0;
            emit(LIT, 0, 0);
        }
    | ID
        {
            Symbol *s = sym_lookup($1);
            if (!s) {
                fprintf(stderr, "error at line %d: undeclared variable '%s'\n",
                        yylineno, $1);
                exit(1);
            }
            int ld = scope_level() - s->level;
            $$.type   = s->type;
            $$.level  = ld;
            $$.offset = s->offset;
            if (s->type != T_SET) {
                emit(LOD, ld, s->offset);
            }
            /* T_SET: carry (level,offset); no stack push */
        }
    | expr '+' expr
        {
            check_int2($1.type, $3.type, "+");
            $$.type = T_INT; $$.level = 0; $$.offset = 0;
            emit(OPR, 0, OPR_ADD);
        }
    | expr '-' expr
        {
            check_int2($1.type, $3.type, "-");
            $$.type = T_INT; $$.level = 0; $$.offset = 0;
            emit(OPR, 0, OPR_SUB);
        }
    | expr '*' expr
        {
            check_int2($1.type, $3.type, "*");
            $$.type = T_INT; $$.level = 0; $$.offset = 0;
            emit(OPR, 0, OPR_MUL);
        }
    | expr '/' expr
        {
            check_int2($1.type, $3.type, "/");
            $$.type = T_INT; $$.level = 0; $$.offset = 0;
            emit(OPR, 0, OPR_DIV);
        }
    | '-' expr %prec UMINUS
        {
            if ($2.type != T_INT) type_error("unary minus requires int");
            $$.type = T_INT; $$.level = 0; $$.offset = 0;
            emit(OPR, 0, OPR_NEG);
        }
    | expr '<' expr
        {
            check_int2($1.type, $3.type, "<");
            $$.type = T_BOOL; $$.level = 0; $$.offset = 0;
            emit(OPR, 0, OPR_LT);
        }
    | expr '>' expr
        {
            check_int2($1.type, $3.type, ">");
            $$.type = T_BOOL; $$.level = 0; $$.offset = 0;
            emit(OPR, 0, OPR_GT);
        }
    | expr LE expr
        {
            check_int2($1.type, $3.type, "<=");
            $$.type = T_BOOL; $$.level = 0; $$.offset = 0;
            emit(OPR, 0, OPR_LEQ);
        }
    | expr GE expr
        {
            check_int2($1.type, $3.type, ">=");
            $$.type = T_BOOL; $$.level = 0; $$.offset = 0;
            emit(OPR, 0, OPR_GEQ);
        }
    | expr EQ_OP expr
        {
            $$.type = T_BOOL; $$.level = 0; $$.offset = 0;
            if ($1.type == T_SET && $3.type == T_SET) {
                /* bonus: set equality — both sides are set vars */
                emit(SET_EQL,
                     ENCODE2($1.level, $1.offset),
                     ENCODE2($3.level, $3.offset));
            } else if ($1.type == $3.type) {
                emit(OPR, 0, OPR_EQ);
            } else {
                type_error("'==' operands must have the same type");
            }
        }
    | expr NE expr
        {
            if ($1.type != $3.type) type_error("'!=' operands must have the same type");
            $$.type = T_BOOL; $$.level = 0; $$.offset = 0;
            emit(OPR, 0, OPR_NEQ);
        }
    | expr AND_OP expr
        {
            check_bool2($1.type, $3.type, "&&");
            $$.type = T_BOOL; $$.level = 0; $$.offset = 0;
            emit(OPR, 0, OPR_AND);
        }
    | expr OR_OP expr
        {
            check_bool2($1.type, $3.type, "||");
            $$.type = T_BOOL; $$.level = 0; $$.offset = 0;
            emit(OPR, 0, OPR_OR);
        }
    | '!' expr
        {
            if ($2.type != T_BOOL) type_error("'!' requires bool");
            $$.type = T_BOOL; $$.level = 0; $$.offset = 0;
            emit(OPR, 0, OPR_NOT);
        }
    | '(' expr ')'
        { $$ = $2; }

    /* set literal: { e1, e2, ... } */
    | '{' expr_list '}'
        {
            $$.type = T_SET; $$.level = -1; $$.offset = $2;
            emit(SET_LIT, 0, $2);
        }
    | '{' '}'
        {
            $$.type = T_SET; $$.level = -1; $$.offset = 0;
            emit(SET_LIT, 0, 0);
        }

    /* set union: ID union ID */
    | ID UNION_KW ID
        {
            Symbol *s1 = sym_lookup($1);
            Symbol *s3 = sym_lookup($3);
            if (!s1 || s1->type != T_SET) {
                fprintf(stderr, "error at line %d: '%s' is not a set\n", yylineno, $1);
                exit(1);
            }
            if (!s3 || s3->type != T_SET) {
                fprintf(stderr, "error at line %d: '%s' is not a set\n", yylineno, $3);
                exit(1);
            }
            int ld1 = scope_level() - s1->level;
            int ld3 = scope_level() - s3->level;
            emit(SET_UNION, ENCODE2(ld1, s1->offset), ENCODE2(ld3, s3->offset));
            $$.type = T_SET; $$.level = -2; $$.offset = 0;
        }

    /* set intersection: ID inter ID */
    | ID INTER_KW ID
        {
            Symbol *s1 = sym_lookup($1);
            Symbol *s3 = sym_lookup($3);
            if (!s1 || s1->type != T_SET) {
                fprintf(stderr, "error at line %d: '%s' is not a set\n", yylineno, $1);
                exit(1);
            }
            if (!s3 || s3->type != T_SET) {
                fprintf(stderr, "error at line %d: '%s' is not a set\n", yylineno, $3);
                exit(1);
            }
            int ld1 = scope_level() - s1->level;
            int ld3 = scope_level() - s3->level;
            emit(SET_INTER, ENCODE2(ld1, s1->offset), ENCODE2(ld3, s3->offset));
            $$.type = T_SET; $$.level = -2; $$.offset = 0;
        }

    /* set membership: expr in ID */
    | expr IN_KW ID
        {
            if ($1.type != T_INT) type_error("'in' left operand must be int");
            Symbol *s = sym_lookup($3);
            if (!s || s->type != T_SET) {
                fprintf(stderr, "error at line %d: '%s' is not a set\n", yylineno, $3);
                exit(1);
            }
            emit(SET_IN, scope_level() - s->level, s->offset);
            $$.type = T_BOOL; $$.level = 0; $$.offset = 0;
        }

    /* isempty(ID) */
    | ISEMPTY_KW '(' ID ')'
        {
            Symbol *s = sym_lookup($3);
            if (!s || s->type != T_SET) {
                fprintf(stderr, "error at line %d: '%s' is not a set\n", yylineno, $3);
                exit(1);
            }
            emit(SET_EMPTY, scope_level() - s->level, s->offset);
            $$.type = T_BOOL; $$.level = 0; $$.offset = 0;
        }

    /* ----------------------------------------------------------------
     * Bonus: set comprehension  { body_expr | ID in ID if filter_expr }
     *
     * Grammar split:
     *   comp_head   ::= ID in ID
     *     - opens a new scope
     *     - allocates hidden __comp_tmp (T_SET) and __comp_idx (T_INT)
     *     - allocates iterator variable ID
     *     - emits: SET_NEW, LIT 0, STO (init), loop condition, SET_ELEM, STO
     *     - stores jpc_end in g_comp_jpc_end
     *     - returns: addr=tmp_off, jpc_idx=idx_off
     *
     *   body_expr   ::= expr   (emitted after loop header, inside loop)
     *
     *   comp_filter ::= IF expr
     *     - emits JPC skip after filter bexpr
     *     - returns: addr=jpc_end (from global), jpc_idx=jpc_skip
     *
     * Final action:
     *   - emit SET_ADD __tmp  (add body result)
     *   - patch jpc_skip
     *   - emit increment + JMP loop_top
     *   - patch jpc_end
     *   - copy __tmp to global temp via SET_UNION(__tmp, __tmp)
     *   - close scope (INT 0 -sz)
     *   - result: T_SET, level=-2 (global temp)
     * ---------------------------------------------------------------- */
    | '{' comp_head expr comp_filter '}'
        {
            if ($3.type != T_INT) type_error("set comprehension body must be int");

            int tmp_off  = $2.addr;
            int idx_off  = $2.jpc_idx;
            int loop_top = (int)(intptr_t)$2.list;
            int jpc_end  = $4.addr;
            int jpc_skip = $4.jpc_idx;

            /* add body result to __comp_tmp */
            emit(SET_ADD, 0, tmp_off);

            /* patch skip (filter was false) */
            patch(jpc_skip, current_addr());

            /* increment __comp_idx */
            emit(LOD, 0, idx_off);
            emit(LIT, 0, 1);
            emit(OPR, 0, OPR_ADD);
            emit(STO, 0, idx_off);

            /* jump back to loop top */
            emit(JMP, 0, loop_top);

            /* patch loop end */
            patch(jpc_end, current_addr());

            /* copy __comp_tmp to global temp_set before dealloc */
            emit(SET_UNION, ENCODE2(0, tmp_off), ENCODE2(0, tmp_off));

            /* close comprehension scope */
            int sz = scope_frame_size();
            scope_exit();
            emit(INT, 0, -sz);

            $$.type   = T_SET;
            $$.level  = -2;   /* result is in global temp_set */
            $$.offset = 0;
        }
    ;

/* ------------------------------------------------------------------ */
/* comp_head: opens comprehension scope, emits loop header             */
/* Returns: addr=tmp_off, jpc_idx=idx_off, list=(intptr_t)loop_top    */
/* Side effect: sets g_comp_jpc_end                                    */
/* ------------------------------------------------------------------ */
comp_head
    : ID IN_KW ID
        {
            Symbol *src = sym_lookup($3);
            if (!src || src->type != T_SET) {
                fprintf(stderr, "error at line %d: '%s' is not a set\n", yylineno, $3);
                exit(1);
            }
            int src_level = src->level;
            int src_off   = src->offset;

            /* open comprehension scope — level increases by 1 after this */
            scope_enter();
            /* recompute ld using new scope level */
            int src_ld = scope_level() - src_level;
            int int_ph = emit(INT, 0, 0);   /* placeholder */

            /* allocate hidden locals and iterator */
            Symbol *tmp_sym  = sym_declare("__comp_tmp", T_SET);
            Symbol *idx_sym  = sym_declare("__comp_idx", T_INT);
            Symbol *iter_sym = sym_declare($1, T_INT);
            if (!iter_sym) {
                fprintf(stderr, "error at line %d: duplicate iterator '%s'\n",
                        yylineno, $1);
                exit(1);
            }

            /* patch INT with actual frame size */
            patch(int_ph, scope_frame_size());

            int tmp_off  = tmp_sym->offset;
            int idx_off  = idx_sym->offset;
            int iter_off = iter_sym->offset;

            /* init __comp_tmp = empty set */
            emit(SET_NEW, 0, tmp_off);

            /* init __comp_idx = 0 */
            emit(LIT, 0, 0);
            emit(STO, 0, idx_off);

            /* loop top: __comp_idx < src.count */
            int loop_top = current_addr();
            emit(LOD, 0, idx_off);
            emit(LOD, src_ld, src_off);   /* pushes count word (first word of set) */
            emit(OPR, 0, OPR_LT);
            int jpc_end = emit(JPC, 0, 0);   /* patched at loop end */
            g_comp_jpc_end = jpc_end;

            /* load src.elements[__comp_idx] into iterator */
            emit(LOD, 0, idx_off);
            emit(SET_ELEM, src_ld, src_off);
            emit(STO, 0, iter_off);

            $$.addr    = tmp_off;
            $$.jpc_idx = idx_off;
            $$.list    = (PatchNode *)(intptr_t)loop_top;
        }
    ;

/* ------------------------------------------------------------------ */
/* comp_filter: emits filter JPC after bexpr                           */
/* Returns: addr=jpc_end (from global), jpc_idx=jpc_skip              */
/* ------------------------------------------------------------------ */
comp_filter
    : IF expr
        {
            if ($2.type != T_BOOL) type_error("set comprehension filter must be bool");
            $$.addr    = g_comp_jpc_end;
            $$.jpc_idx = emit(JPC, 0, 0);   /* jpc_skip: patched after body */
            $$.list    = NULL;
        }
    ;

/* ------------------------------------------------------------------ */
/* expr_list: comma-separated int expressions for set literals         */
/* ------------------------------------------------------------------ */
expr_list
    : expr
        { $$ = 1; }
    | expr_list ',' expr
        { $$ = $1 + 1; }
    ;

%%

void yyerror(const char *s) {
    fprintf(stderr, "parse error at line %d: %s\n", yylineno, s);
    exit(1);
}
