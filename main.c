#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "codegen.h"
#include "pvm.h"

extern FILE *yyin;
extern int   yyparse(void);

static void usage(const char *prog) {
    fprintf(stderr, "Usage: %s [-s] [-p] <source.l26>\n", prog);
    fprintf(stderr, "  -s   single-step mode\n");
    fprintf(stderr, "  -p   print P-Code only (no execution)\n");
    exit(1);
}

int main(int argc, char *argv[]) {
    int step_mode  = 0;
    int print_only = 0;
    const char *filename = NULL;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-s") == 0)      step_mode  = 1;
        else if (strcmp(argv[i], "-p") == 0) print_only = 1;
        else if (argv[i][0] == '-')          usage(argv[0]);
        else                                 filename = argv[i];
    }

    if (!filename) usage(argv[0]);

    yyin = fopen(filename, "r");
    if (!yyin) {
        fprintf(stderr, "error: cannot open '%s'\n", filename);
        return 1;
    }

    if (yyparse() != 0) {
        fclose(yyin);
        return 1;
    }
    fclose(yyin);

    print_pcode();

    if (print_only) return 0;

    printf("=== Running ===\n");
    pvm_run(step_mode);
    printf("=== Done ===\n");
    return 0;
}
