# Step 5：词法分析 `lexer.l`

本阶段读一个文件：

```text
lexer.l
```

目标：理解源码字符如何被 Flex 扫描成 token，并交给 `parser.y` 继续做语法分析。

## Step 4 承接

Step 4 读完符号表后，我们知道变量最终会进入 `symtab`，并带上：

```text
name / type / level / offset
```

但 parser 最早是怎么知道源码里出现了 `int`、`x`、`123`、`<=` 这些东西的？

本阶段要回答：

1. parser 的 token 从哪里来？
2. `ID` / `NUM` 的值如何传给 parser？
3. 关键字和普通标识符如何区分？
4. 为什么 `<=` 要写在 `<` 前面？
5. `yylineno` 是怎么来的？
6. 遇到不认识的字符会发生什么？

## 1. Flex 文件整体结构

`lexer.l` 是 Flex 词法文件，整体分成三段：

```lex
%{
    C 代码
%}

%%
    词法规则
%%
    额外 C 代码
```

本项目里：

- 第一段：写 `#include`。
- 第二段：写正则规则和对应动作。
- 第三段：为空。

Flex 会根据 `lexer.l` 生成 `lexer.c`，其中最核心的函数是：

```c
int yylex(void);
```

parser 调用 `yylex()`，每次拿到一个 token。

## 2. 文件开头的 C 代码块

```lex
%{
#include <stdlib.h>
#include <string.h>
#include "symtab.h"
#include "codegen.h"
#include "parser.tab.h"
%}
```

`%{ ... %}` 里的内容会原样复制到生成的 `lexer.c` 顶部。

### `stdlib.h`

```c
#include <stdlib.h>
```

用于：

```c
atoi(yytext)
```

把数字字符串转成 `int`。

### `string.h`

```c
#include <string.h>
```

用于：

```c
strncpy(yylval.sval, yytext, 63)
```

把标识符名字复制到 `yylval.sval`。

### `symtab.h`

```c
#include "symtab.h"
```

提供 `VarType` 等类型。`parser.tab.h` 里的 `%union` 会用到项目类型，所以 lexer 需要能看见这些定义。

### `codegen.h`

```c
#include "codegen.h"
```

提供代码生成相关声明。lexer 本身几乎不直接调用它，但 parser 头文件依赖的类型和声明链需要这些项目头文件保持一致。

### `parser.tab.h`

```c
#include "parser.tab.h"
```

这是 Bison 从 `parser.y` 生成的头文件。

它给 lexer 提供两类东西：

```text
token 名称：INT_KW / ID / NUM / LE ...
yylval 类型：lexer 给 parser 传值用
```

所以 lexer 才能写：

```c
return INT_KW;
yylval.ival = 123;
yylval.sval = "x";
```

## 3. Flex 选项

```lex
%option noyywrap
%option yylineno
```

### `noyywrap`

```lex
%option noyywrap
```

告诉 Flex：输入结束后不需要调用 `yywrap()`。

如果没有这个选项，链接时通常需要额外提供：

```c
int yywrap(void) { return 1; }
```

本项目选择让 Flex 自动处理。

### `yylineno`

```lex
%option yylineno
```

让 Flex 自动维护当前行号变量：

```c
int yylineno;
```

当规则匹配到换行时，Flex 会更新它。

项目里词法错误会打印：

```c
yylineno
```

parser 里也通过：

```c
extern int yylineno;
```

拿到当前行号。

## 4. 规则区开始

```lex
%%
```

第一个 `%%` 后面进入词法规则区。

每条规则格式是：

```lex
正则表达式    { C 动作 }
```

Flex 扫描时有两个重要规则：

1. 优先匹配最长的字符串。
2. 如果长度一样，优先使用写在前面的规则。

这两个规则解释了为什么关键字要写在 `ID` 前面。

## 5. 跳过空白和注释

```lex
[ \t\r]+            { /* skip whitespace */ }
\n                  { /* skip newline (yylineno auto-incremented) */ }
"//"[^\n]*          { /* line comment */ }
"/*"([^*]|\*[^/])*"*/" { /* block comment */ }
```

这些规则都没有 `return`，意思是：

```text
匹配到后直接丢弃，继续扫描下一个 token
```

### 空格、Tab、回车

```lex
[ \t\r]+
```

含义：

- `[ ... ]`：匹配集合中的任意一个字符。
- 空格：普通空格。
- `\t`：Tab。
- `\r`：回车。
- `+`：一个或多个。

这些字符不影响语法，所以跳过。

### 换行

```lex
\n
```

匹配换行。

动作里什么都不做，因为：

```lex
%option yylineno
```

已经让 Flex 自动更新行号。

### 单行注释

```lex
"//"[^\n]*
```

含义：

- `"//"`：必须以两个斜杠开头。
- `[^\n]*`：后面跟任意多个非换行字符。

所以：

```l26
// this is comment
```

整行注释会被跳过。

### 块注释

```lex
"/*"([^*]|\*[^/])*"*/"
```

含义：

- `"/*"`：块注释开始。
- `([^*]|\*[^/])*`：中间内容。
- `"*/"`：块注释结束。

它能跳过：

```c
/* comment */
```

注意：这个简单规则不处理嵌套块注释。

## 6. 关键字规则

```lex
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
```

这些是 L26 语言的保留字。

例如源码：

```l26
int x;
```

lexer 读到 `int`，返回：

```text
INT_KW
```

parser 里对应声明：

```yacc
%token INT_KW BOOL_KW SET_KW
```

### `true`

```lex
"true" { yylval.ival = 1; return TRUE_KW; }
```

`true` 不只是返回 token，还把语义值设成：

```text
yylval.ival = 1
```

parser 后续可以把它当布尔真。

### `false`

```lex
"false" { yylval.ival = 0; return FALSE_KW; }
```

`false` 的语义值是：

```text
yylval.ival = 0
```

parser 后续可以把它当布尔假。

## 7. 标识符 `ID`

```lex
[a-zA-Z_][a-zA-Z0-9_]*  {
    strncpy(yylval.sval, yytext, 63);
    yylval.sval[63] = '\0';
    return ID;
}
```

这条规则匹配变量名。

### 正则部分

```lex
[a-zA-Z_][a-zA-Z0-9_]*
```

拆开看：

```text
[a-zA-Z_]       第一个字符必须是字母或下划线
[a-zA-Z0-9_]*   后续字符可以是字母、数字或下划线，数量可以为 0 个或多个
```

合法例子：

```text
x
count
_tmp
set1
```

非法例子：

```text
1abc
```

因为不能用数字开头。

### `yytext`

```c
yytext
```

是 Flex 提供的变量，表示本次匹配到的原始文本。

例如源码是：

```l26
count = 3;
```

匹配 `count` 时：

```text
yytext = "count"
```

### `yylval.sval`

```c
strncpy(yylval.sval, yytext, 63);
```

把标识符名字复制给 parser。

`parser.y` 里定义：

```yacc
%token <sval> ID
```

意思是：

```text
ID 这个 token 携带字符串值，字段名是 sval
```

### 手动补 `'\0'`

```c
yylval.sval[63] = '\0';
```

保证字符串一定以 `'\0'` 结尾。

因为 `strncpy` 在源字符串过长时不一定自动补结尾。

### 返回 `ID`

```c
return ID;
```

告诉 parser：这次读到的是一个标识符。

## 8. 数字 `NUM`

```lex
[0-9]+  {
    yylval.ival = atoi(yytext);
    return NUM;
}
```

这条规则匹配整数常量。

### 正则部分

```lex
[0-9]+
```

含义：

```text
一个或多个数字
```

例子：

```text
0
12
345
```

### `atoi`

```c
atoi(yytext)
```

把字符串转成整数。

例如：

```text
yytext = "123"
atoi(yytext) = 123
```

### `yylval.ival`

```c
yylval.ival = atoi(yytext);
```

把整数值传给 parser。

`parser.y` 里定义：

```yacc
%token <ival> NUM TRUE_KW FALSE_KW
```

意思是：

```text
NUM / TRUE_KW / FALSE_KW 都携带整数值，字段名是 ival
```

## 9. 多字符运算符

```lex
"<="    { return LE; }
">="    { return GE; }
"=="    { return EQ_OP; }
"!="    { return NE; }
"&&"    { return AND_OP; }
"||"    { return OR_OP; }
```

这些运算符长度都是 2。

对应关系：

```text
<=  -> LE
>=  -> GE
==  -> EQ_OP
!=  -> NE
&&  -> AND_OP
||  -> OR_OP
```

parser 里对应：

```yacc
%token LE GE EQ_OP NE AND_OP OR_OP
```

为什么要单独写？

因为 parser 需要区分：

```text
<   单字符 token
<=  LE token
```

虽然 Flex 会优先最长匹配，但把多字符运算符清楚写出来，parser 才能拿到专门的 token 名称。

## 10. 单字符 token

```lex
[+\-*/<>!(){};,|=]  { return yytext[0]; }
```

这条规则处理单字符符号。

字符集合包括：

```text
+  -  *  /  <  >  !  (  )  {  }  ;  ,  |  =
```

动作是：

```c
return yytext[0];
```

也就是直接返回这个字符本身。

例如源码：

```l26
x = 1 + 2;
```

lexer 返回：

```text
ID '=' NUM '+' NUM ';'
```

parser 可以直接写字符 token：

```yacc
assign_stmt : ID '=' expr ';'
expr        : expr '+' expr
```

### `\-`

```lex
\-
```

在字符集合里，`-` 可能表示范围，例如：

```lex
[a-z]
```

所以这里写成 `\-`，明确表示普通减号字符。

## 11. 未知字符错误

```lex
.   {
    fprintf(stderr, "lexer error: unknown character '%s' at line %d\n",
            yytext, yylineno);
}
```

`.` 匹配任意一个还没有被前面规则处理的字符。

例如源码里出现：

```text
@
```

前面没有任何规则能识别它，就会进入这里。

错误信息包括：

```text
yytext    当前未知字符
yylineno  当前行号
```

注意：这里没有 `return`，所以报错后 lexer 会继续扫描后面的字符。

## 12. 规则区结束

```lex
%%
```

第二个 `%%` 后面是用户自定义 C 代码区。

本项目没有额外代码，所以这里为空。

## 13. 和 `parser.y` 的关系

lexer 返回的 token 必须和 `parser.y` 声明一致。

`parser.y` 里有：

```yacc
%union {
    int     ival;
    char    sval[64];
    VarType vtype;
    struct { VarType type; int level; int offset; } expr;
    struct { int addr; int jpc_idx; int loop_top; int end_jpc; PatchNode *list; } ctrl;
    ExprAst *ast;
    AstList *alist;
    int count;
}
```

这定义了 token 和非终结符可以携带哪些类型的值。

跟 lexer 直接相关的是：

```text
ival  整数值
sval  字符串值
```

对应 token 声明：

```yacc
%token <ival> NUM TRUE_KW FALSE_KW
%token <sval> ID
```

所以：

- `NUM` 必须写 `yylval.ival`。
- `TRUE_KW` / `FALSE_KW` 必须写 `yylval.ival`。
- `ID` 必须写 `yylval.sval`。
- 普通关键字和符号不需要额外值，只要 `return TOKEN`。

## 14. 一个完整例子

源码：

```l26
int x;
x = 12 + 3;
write x;
```

lexer 产生的 token 流：

```text
INT_KW ID ';'
ID '=' NUM '+' NUM ';'
WRITE_KW ID ';'
```

同时携带的语义值：

```text
第一个 ID:  yylval.sval = "x"
第一个 NUM: yylval.ival = 12
第二个 NUM: yylval.ival = 3
第二个 ID:  yylval.sval = "x"
```

parser 看到的是 token，不再直接处理原始字符。

## 15. 本阶段你要记住

1. `lexer.l` 负责把字符流切成 token。
2. `return TOKEN` 是 lexer 和 parser 的交接口。
3. `parser.tab.h` 提供 token 编号和 `yylval` 类型。
4. `yytext` 是当前匹配到的文本。
5. `yylval.ival` 传数字和布尔值。
6. `yylval.sval` 传标识符名字。
7. 关键字要写在 `ID` 规则之前。
8. 单字符符号可以直接 `return yytext[0]`。
9. `%option yylineno` 让错误报告能带行号。

## 下一步

Step 6 建议进入 `parser.y`。

不要一开始就逐条 production 深挖，先看三件事：

1. Bison 文件结构。
2. `%union` / `%token` / `%type` 如何描述语义值。
3. 顶层语法如何从 `program -> block` 开始驱动整个编译流程。
