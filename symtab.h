#ifndef SYMTAB_H
#define SYMTAB_H

#include "pcode.h"

typedef enum { T_INT, T_BOOL, T_SET } VarType;

typedef struct Symbol {
    char          name[64];
    VarType       type;
    int           level;   /* nesting depth, outermost block = 1 */
    int           offset;  /* word offset within activation record */
    struct Symbol *next;
} Symbol;

typedef struct Scope {
    Symbol      *head;
    int          frame_size;   /* words allocated in this scope so far */
    int          base_offset;  /* cumulative offset at scope entry */
    struct Scope *parent;
} Scope;

void    scope_enter(void);
void    scope_exit(void);
int     scope_level(void);        /* current nesting level (outermost=1) */
int     scope_frame_size(void);   /* words in current scope (for INT patch) */
int     scope_total_size(void);   /* total words from frame base to sp */

Symbol *sym_declare(const char *name, VarType type); /* NULL = duplicate */
Symbol *sym_lookup(const char *name);                /* NULL = not found */

int     type_width(VarType t);   /* 1 for int/bool, SET_SIZE for set */

#endif /* SYMTAB_H */
