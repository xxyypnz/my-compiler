/* A Bison parser, made by GNU Bison 3.8.2.  */

/* Bison interface for Yacc-like parsers in C

   Copyright (C) 1984, 1989-1990, 2000-2015, 2018-2021 Free Software Foundation,
   Inc.

   This program is free software: you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation, either version 3 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program.  If not, see <https://www.gnu.org/licenses/>.  */

/* As a special exception, you may create a larger work that contains
   part or all of the Bison parser skeleton and distribute that work
   under terms of your choice, so long as that work isn't itself a
   parser generator using the skeleton or a modified version thereof
   as a parser skeleton.  Alternatively, if you modify or redistribute
   the parser skeleton itself, you may (at your option) remove this
   special exception, which will cause the skeleton and the resulting
   Bison output files to be licensed under the GNU General Public
   License without this special exception.

   This special exception was added by the Free Software Foundation in
   version 2.2 of Bison.  */

/* DO NOT RELY ON FEATURES THAT ARE NOT DOCUMENTED in the manual,
   especially those whose name start with YY_ or yy_.  They are
   private implementation details that can be changed or removed.  */

#ifndef YY_YY_PARSER_TAB_H_INCLUDED
# define YY_YY_PARSER_TAB_H_INCLUDED
/* Debug traces.  */
#ifndef YYDEBUG
# define YYDEBUG 0
#endif
#if YYDEBUG
extern int yydebug;
#endif
/* "%code requires" blocks.  */
#line 208 "parser.y"

typedef struct PatchNode PatchNode;
typedef struct ExprAst ExprAst;
typedef struct AstList AstList;

#line 55 "parser.tab.h"

/* Token kinds.  */
#ifndef YYTOKENTYPE
# define YYTOKENTYPE
  enum yytokentype
  {
    YYEMPTY = -2,
    YYEOF = 0,                     /* "end of file"  */
    YYerror = 256,                 /* error  */
    YYUNDEF = 257,                 /* "invalid token"  */
    NUM = 258,                     /* NUM  */
    TRUE_KW = 259,                 /* TRUE_KW  */
    FALSE_KW = 260,                /* FALSE_KW  */
    ID = 261,                      /* ID  */
    INT_KW = 262,                  /* INT_KW  */
    BOOL_KW = 263,                 /* BOOL_KW  */
    SET_KW = 264,                  /* SET_KW  */
    IF = 265,                      /* IF  */
    ELSE = 266,                    /* ELSE  */
    WHILE = 267,                   /* WHILE  */
    READ_KW = 268,                 /* READ_KW  */
    WRITE_KW = 269,                /* WRITE_KW  */
    ADD_KW = 270,                  /* ADD_KW  */
    REMOVE_KW = 271,               /* REMOVE_KW  */
    UNION_KW = 272,                /* UNION_KW  */
    INTER_KW = 273,                /* INTER_KW  */
    IN_KW = 274,                   /* IN_KW  */
    ISEMPTY_KW = 275,              /* ISEMPTY_KW  */
    LE = 276,                      /* LE  */
    GE = 277,                      /* GE  */
    EQ_OP = 278,                   /* EQ_OP  */
    NE = 279,                      /* NE  */
    AND_OP = 280,                  /* AND_OP  */
    OR_OP = 281,                   /* OR_OP  */
    NO_ELSE = 282,                 /* NO_ELSE  */
    UMINUS = 283                   /* UMINUS  */
  };
  typedef enum yytokentype yytoken_kind_t;
#endif

/* Value type.  */
#if ! defined YYSTYPE && ! defined YYSTYPE_IS_DECLARED
union YYSTYPE
{
#line 217 "parser.y"

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
        int        loop_top;
        int        end_jpc;
        PatchNode *list;
    } ctrl;
    ExprAst *ast;
    AstList *alist;
    int count;

#line 121 "parser.tab.h"

};
typedef union YYSTYPE YYSTYPE;
# define YYSTYPE_IS_TRIVIAL 1
# define YYSTYPE_IS_DECLARED 1
#endif


extern YYSTYPE yylval;


int yyparse (void);


#endif /* !YY_YY_PARSER_TAB_H_INCLUDED  */
