#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "symtab.h"

static Scope *current_scope = NULL;

int type_width(VarType t) {
    return (t == T_SET) ? SET_SIZE : 1;
}

void scope_enter(void) {
    Scope *s = (Scope *)malloc(sizeof(Scope));
    if (!s) { fprintf(stderr, "out of memory\n"); exit(1); }
    s->head        = NULL;
    s->frame_size  = 0;
    s->base_offset = current_scope
                     ? current_scope->base_offset + current_scope->frame_size
                     : 0;
    s->parent      = current_scope;
    current_scope  = s;
}

void scope_exit(void) {
    if (!current_scope) return;
    Symbol *sym = current_scope->head;
    while (sym) {
        Symbol *next = sym->next;
        free(sym);
        sym = next;
    }
    Scope *parent  = current_scope->parent;
    free(current_scope);
    current_scope  = parent;
}

int scope_level(void) {
    int level = 0;
    Scope *s = current_scope;
    while (s) { level++; s = s->parent; }
    return level;
}

int scope_frame_size(void) {
    return current_scope ? current_scope->frame_size : 0;
}

int scope_total_size(void) {
    return current_scope
           ? current_scope->base_offset + current_scope->frame_size
           : 0;
}

Symbol *sym_declare(const char *name, VarType type) {
    if (!current_scope) return NULL;
    /* check duplicate in current scope only */
    for (Symbol *s = current_scope->head; s; s = s->next)
        if (strcmp(s->name, name) == 0) return NULL;

    Symbol *sym = (Symbol *)malloc(sizeof(Symbol));
    if (!sym) { fprintf(stderr, "out of memory\n"); exit(1); }
    strncpy(sym->name, name, 63);
    sym->name[63] = '\0';
    sym->type     = type;
    sym->level    = scope_level();
    sym->offset   = current_scope->base_offset + current_scope->frame_size;
    current_scope->frame_size += type_width(type);
    sym->next     = current_scope->head;
    current_scope->head = sym;
    return sym;
}

Symbol *sym_lookup(const char *name) {
    for (Scope *sc = current_scope; sc; sc = sc->parent)
        for (Symbol *s = sc->head; s; s = s->next)
            if (strcmp(s->name, name) == 0) return s;
    return NULL;
}
