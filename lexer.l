%{
#include <stdlib.h>
#include <string.h>
#include "symtab.h"
#include "codegen.h"
#include "parser.tab.h"

int yylineno = 1;
%}

%option noyywrap
%option yylineno

%%

[ \t\r]+            { /* skip whitespace */ }
\n                  { /* skip newline (yylineno auto-incremented) */ }
"//"[^\n]*          { /* line comment */ }
"/*"([^*]|\*[^/])*"*/" { /* block comment */ }

"int"       { return INT_KW; }
"bool"      { return BOOL_KW; }
"set"       { return SET_KW; }
"if"        { return IF; }
"else"      { return ELSE; }
"while"     { return WHILE; }
"read"      { return READ_KW; }
"write"     { return WRITE_KW; }
"true"      { yylval.ival = 1; return TRUE_KW; }
"false"     { yylval.ival = 0; return FALSE_KW; }
"add"       { return ADD_KW; }
"remove"    { return REMOVE_KW; }
"union"     { return UNION_KW; }
"inter"     { return INTER_KW; }
"in"        { return IN_KW; }
"isempty"   { return ISEMPTY_KW; }

[a-zA-Z_][a-zA-Z0-9_]*  {
    strncpy(yylval.sval, yytext, 63);
    yylval.sval[63] = '\0';
    return ID;
}

[0-9]+  {
    yylval.ival = atoi(yytext);
    return NUM;
}

"<="    { return LE; }
">="    { return GE; }
"=="    { return EQ_OP; }
"!="    { return NE; }
"&&"    { return AND_OP; }
"||"    { return OR_OP; }

[+\-*/<>!(){};,|=]  { return yytext[0]; }

.   {
    fprintf(stderr, "lexer error: unknown character '%s' at line %d\n",
            yytext, yylineno);
}

%%
