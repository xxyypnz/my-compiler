# Step 6：语法分析 `parser.y` 总览

本阶段读一个文件：

```text
parser.y
```

但只读总览和主干部分。

目标：先看懂 Bison 文件结构、语义值、token 声明、优先级声明，以及程序如何从 `program -> block` 开始生成 P-code。

表达式、集合字面量、集合推导式会留到 Step 7。

## Step 5 承接

Step 5 里 lexer 每次返回一个 token：

```text
INT_KW / ID / NUM / IF / WHILE / '+' / '{' ...
```

现在的问题是：

1. parser 如何声明这些 token？
2. `ID` 的字符串和 `NUM` 的整数值如何被接住？
3. `program -> block` 代表什么？
4. 声明语句如何进入符号表？
5. block 进入和退出时为什么要 `scope_enter()` / `scope_exit()`？
6. `if` / `while` 为什么要先生成占位跳转再 patch？

## 1. Bison 文件整体结构

`parser.y` 和 `lexer.l` 一样，也分成三段：

```yacc
%{
    C 代码：只进入 parser.c
%}

声明区：
    %code requires
    %union
    %token
    %type
    优先级

%%
语法规则区
%%

额外 C 代码
```

本项目里生成文件是：

```text
parser.tab.c
parser.tab.h
```

其中：

- `parser.tab.c`：语法分析实现。
- `parser.tab.h`：token 编号、`YYSTYPE`、`yylval` 等给 lexer 使用。

## 2. 第一段 C 代码

```yacc
%{
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include "symtab.h"
#include "codegen.h"
#include "pcode.h"

extern int yylineno;
void yyerror(const char *s);
int  yylex(void);
...
%}
```

这段会被复制到 `parser.tab.c`，但不会复制到 `parser.tab.h`。

### `stdio.h`

```c
#include <stdio.h>
```

用于：

```c
fprintf(stderr, ...)
snprintf(...)
```

parser 发现语法错误、类型错误、未声明变量等情况时会打印错误。

### `stdlib.h`

```c
#include <stdlib.h>
```

用于：

```c
malloc(...)
calloc(...)
free(...)
exit(...)
```

parser 里会创建 AST、patch 链表，出错时会 `exit(1)`。

### `stdint.h`

```c
#include <stdint.h>
```

提供固定宽度整数类型。本文件目前没有大量直接使用，但属于安全包含。

### `string.h`

```c
#include <string.h>
```

用于：

```c
strncpy(...)
```

把标识符名字复制进 AST 节点。

### `symtab.h`

```c
#include "symtab.h"
```

parser 需要符号表做这些事：

```text
声明变量：sym_declare
查找变量：sym_lookup
进入作用域：scope_enter
退出作用域：scope_exit
取得当前层级：scope_level
取得当前帧大小：scope_frame_size
```

### `codegen.h`

```c
#include "codegen.h"
```

parser 在归约语法规则时直接生成 P-code：

```c
emit(...)
patch(...)
current_addr(...)
```

所以 parser 是“语法分析 + 语义检查 + 代码生成”的中心。

### `pcode.h`

```c
#include "pcode.h"
```

提供 P-code 指令和操作码：

```text
LIT / LOD / STO / INT / JMP / JPC / OPR
OPR_ADD / OPR_SUB / OPR_LT / OPR_RET ...
SET_NEW / SET_ADD / SET_UNION ...
```

## 3. parser 和 lexer 的接口

```c
extern int yylineno;
void yyerror(const char *s);
int  yylex(void);
```

### `yylineno`

```c
extern int yylineno;
```

来自 lexer。

parser 用它打印错误行号：

```c
fprintf(stderr, "type error at line %d: ...", yylineno);
```

### `yyerror`

```c
void yyerror(const char *s);
```

Bison 在语法错误时调用它。

文件末尾实现：

```c
void yyerror(const char *s) {
    fprintf(stderr, "parse error at line %d: %s\n", yylineno, s);
    exit(1);
}
```

### `yylex`

```c
int yylex(void);
```

来自 lexer。

parser 每次需要下一个 token，就调用：

```c
yylex()
```

## 4. `PatchNode`：回填跳转地址

```c
typedef struct PatchNode {
    int addr;
    struct PatchNode *next;
} PatchNode;
```

`PatchNode` 是一个链表节点，用来记录“现在还不知道目标地址”的跳转指令。

### `addr`

```c
int addr;
```

保存需要回填的 P-code 指令下标。

例如：

```c
int jpc_idx = emit(JPC, 0, 0);
```

这里 `JPC` 的目标地址先写 `0`，等知道真正出口地址后再 patch。

### `next`

```c
struct PatchNode *next;
```

指向下一个需要回填的跳转。

虽然当前多数地方只存一个节点，但用链表可以支持多个待回填地址。

## 5. patch 辅助函数

```c
static PatchNode *make_patch(int addr) {
    PatchNode *p = (PatchNode *)malloc(sizeof(PatchNode));
    p->addr = addr;
    p->next = NULL;
    return p;
}
```

`make_patch` 做三件事：

1. 分配一个 `PatchNode`。
2. 把 `addr` 存进去。
3. 返回节点指针。

```c
static void do_patch(PatchNode *list, int target) {
    for (PatchNode *p = list; p; p = p->next)
        patch(p->addr, target);
}
```

`do_patch` 遍历链表，把每个待回填指令改成 `target`。

这里调用的是 `codegen.c` 的：

```c
patch(addr, target)
```

```c
static void free_patch(PatchNode *list) {
    while (list) {
        PatchNode *next = list->next;
        free(list);
        list = next;
    }
}
```

`free_patch` 释放 patch 链表。

变量含义：

- `list`：当前链表头。
- `next`：先保存下一个节点，避免 `free(list)` 后丢失后续节点。

## 6. AST 辅助结构

parser 文件里有一套小型 AST：

```c
typedef enum {
    AST_NUM,
    AST_ID,
    AST_BIN,
    AST_NEG
} AstKind;
```

它只服务于集合字面量和集合推导式里的算术表达式。

### `AstKind`

```text
AST_NUM  数字
AST_ID   标识符
AST_BIN  二元运算
AST_NEG  一元负号
```

### `ExprAst`

```c
typedef struct ExprAst {
    AstKind kind;
    int value;
    int op;
    char name[64];
    struct ExprAst *left;
    struct ExprAst *right;
} ExprAst;
```

字段含义：

- `kind`：节点种类。
- `value`：数字节点的整数值。
- `op`：二元运算符，例如 `'+'`。
- `name`：标识符名字。
- `left`：左子树。
- `right`：右子树。

### `AstList`

```c
typedef struct AstList {
    ExprAst *expr;
    struct AstList *next;
} AstList;
```

用于保存集合字面量里的表达式列表。

例如：

```l26
{1, x + 2, y}
```

会形成一个 `AstList` 链表。

## 7. AST 构造函数

```c
static ExprAst *ast_new(AstKind kind)
```

创建一个新的 AST 节点。

关键变量：

- `kind`：要创建的节点种类。
- `node`：新分配的 AST 节点。

```c
ExprAst *node = (ExprAst *)calloc(1, sizeof(ExprAst));
```

使用 `calloc`，所以字段初始为 0。

```c
if (!node) { fprintf(stderr, "out of memory\n"); exit(1); }
```

分配失败就报错退出。

```c
node->kind = kind;
```

记录节点种类。

### `ast_num`

```c
static ExprAst *ast_num(int value)
```

创建数字节点。

- `value`：数字值。
- `node->value`：保存这个数字。

### `ast_id`

```c
static ExprAst *ast_id(const char *name)
```

创建标识符节点。

- `name`：变量名。
- `node->name`：节点内部保存的变量名副本。

这里也手动保证：

```c
node->name[63] = '\0';
```

### `ast_bin`

```c
static ExprAst *ast_bin(int op, ExprAst *left, ExprAst *right)
```

创建二元运算节点。

- `op`：运算符。
- `left`：左操作数。
- `right`：右操作数。

### `ast_neg`

```c
static ExprAst *ast_neg(ExprAst *expr)
```

创建一元负号节点。

- `expr`：被取负的表达式。
- `node->left`：保存这个子表达式。

### `ast_free`

```c
static void ast_free(ExprAst *node)
```

递归释放 AST。

逻辑：

```text
如果 node 为空，直接返回
释放 left
释放 right
释放 node 自己
```

## 8. AST 列表函数

```c
static AstList *ast_list_new(ExprAst *expr)
```

创建列表节点。

- `expr`：当前元素表达式。
- `node->expr`：保存这个表达式。

```c
static AstList *ast_list_append(AstList *list, ExprAst *expr)
```

把一个表达式追加到列表末尾。

变量含义：

- `list`：已有链表头。
- `expr`：新表达式。
- `node`：新链表节点。
- `tail`：遍历到链表尾部的指针。

```c
static int ast_list_emit_and_free(AstList *list)
```

逐个生成集合字面量元素的代码，然后释放列表。

变量含义：

- `list`：当前待处理链表。
- `count`：元素数量。
- `next`：释放当前节点前保存下一个节点。

核心逻辑：

```c
if (emit_ast_expr(list->expr) != T_INT)
    type_error("set literal elements must be int");
```

集合字面量里的元素必须是 `int`。

## 9. 语义检查辅助函数

```c
static void type_error(const char *msg)
```

打印类型错误并退出。

- `msg`：错误说明。

```c
fprintf(stderr, "type error at line %d: %s\n", yylineno, msg);
exit(1);
```

### `check_int2`

```c
static void check_int2(VarType t1, VarType t2, const char *op)
```

检查二元运算的两个操作数是不是 `int`。

变量含义：

- `t1`：左操作数类型。
- `t2`：右操作数类型。
- `op`：运算符字符串，用于错误信息。
- `buf`：拼接出来的错误文本。

用于：

```text
+ - * / < > <= >=
```

### `check_bool2`

```c
static void check_bool2(VarType t1, VarType t2, const char *op)
```

检查二元逻辑运算的两个操作数是不是 `bool`。

用于：

```text
&& ||
```

## 10. `emit_ast_expr`

```c
static VarType emit_ast_expr(ExprAst *node)
```

作用：根据 AST 生成表达式 P-code，并返回表达式类型。

这不是普通 `expr` 的主规则，而是集合字面量、集合推导式内部用的算术 AST。

### 参数和返回值

- `node`：要生成代码的 AST 根节点。
- 返回值：表达式类型，通常应该是 `T_INT`。

### `AST_NUM`

```c
emit(LIT, 0, node->value);
return T_INT;
```

数字节点生成：

```text
LIT 0 value
```

表示把整数压栈。

### `AST_ID`

```c
Symbol *s = sym_lookup(node->name);
```

查找变量。

如果没找到，报未声明变量。

```c
int ld = scope_level() - s->level;
```

计算层差。

```c
if (s->type != T_SET) emit(LOD, ld, s->offset);
```

非集合变量直接加载值。

集合变量不在这里压栈，因为集合需要通过地址操作。

### `AST_BIN`

先递归生成左右子表达式：

```c
VarType left = emit_ast_expr(node->left);
VarType right = emit_ast_expr(node->right);
```

再按 `node->op` 生成：

```text
+ -> OPR_ADD
- -> OPR_SUB
* -> OPR_MUL
/ -> OPR_DIV
```

所有这些都要求左右都是 `int`。

### `AST_NEG`

先生成内部表达式：

```c
VarType inner = emit_ast_expr(node->left);
```

再检查类型必须是 `int`，最后生成：

```c
emit(OPR, 0, OPR_NEG);
```

## 11. `%code requires`

```yacc
%code requires {
typedef struct PatchNode PatchNode;
typedef struct ExprAst ExprAst;
typedef struct AstList AstList;
}
```

这一段会进入 `parser.tab.h`。

为什么需要？

因为后面的 `%union` 里写了：

```c
PatchNode *list;
ExprAst *ast;
AstList *alist;
```

`parser.tab.h` 必须知道这些类型名存在。

这里只做前置声明，不暴露结构体字段。

## 12. `%union`：语义值总表

```yacc
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
        int        addr;
        int        jpc_idx;
        int        loop_top;
        int        end_jpc;
        PatchNode *list;
    } ctrl;
    ExprAst *ast;
    AstList *alist;
    int count;
}
```

Bison 的每个 token / 非终结符都可以携带一个语义值。

`%union` 定义所有可能的值类型。

### `ival`

```c
int ival;
```

整数值。

用于：

```text
NUM / TRUE_KW / FALSE_KW
```

### `sval`

```c
char sval[64];
```

字符串值。

用于：

```text
ID
```

### `vtype`

```c
VarType vtype;
```

变量类型。

用于非终结符：

```text
type
```

也就是：

```text
int  -> T_INT
bool -> T_BOOL
set  -> T_SET
```

### `expr`

```c
struct {
    VarType type;
    int     level;
    int     offset;
} expr;
```

普通表达式的语义值。

字段含义：

- `type`：表达式类型。
- `level`：如果表达式代表集合变量，记录层差。
- `offset`：如果表达式代表集合变量，记录偏移。

为什么表达式需要 `level/offset`？

因为集合不是普通栈顶整数，很多集合指令需要知道集合变量的地址。

### `ctrl`

```c
struct {
    int        addr;
    int        jpc_idx;
    int        loop_top;
    int        end_jpc;
    PatchNode *list;
} ctrl;
```

控制流和集合推导式共用的临时信息。

字段含义：

- `addr`：地址字段，`while` 中常当循环起点，comprehension 中常当临时集合偏移。
- `jpc_idx`：条件跳转指令位置，comprehension 中也复用为索引变量偏移。
- `loop_top`：循环开头地址。
- `end_jpc`：循环结束跳转的指令位置。
- `list`：待 patch 的跳转链表。

### `ast`

```c
ExprAst *ast;
```

算术表达式 AST 指针。

用于：

```text
aexpr_ast
```

### `alist`

```c
AstList *alist;
```

AST 链表。

用于：

```text
ast_list
```

### `count`

```c
int count;
```

通用计数字段。

当前文件里保留了这个 union 成员，但主规则里主要使用 `ast_list_emit_and_free` 的局部 `count`。

## 13. token 声明

```yacc
%token <ival> NUM TRUE_KW FALSE_KW
%token <sval> ID
%token INT_KW BOOL_KW SET_KW
%token IF ELSE WHILE
%token READ_KW WRITE_KW
%token ADD_KW REMOVE_KW
%token UNION_KW INTER_KW IN_KW ISEMPTY_KW
%token LE GE EQ_OP NE AND_OP OR_OP
```

这些 token 都来自 `lexer.l`。

### 带值 token

```yacc
%token <ival> NUM TRUE_KW FALSE_KW
```

说明这些 token 使用：

```c
yylval.ival
```

```yacc
%token <sval> ID
```

说明 `ID` 使用：

```c
yylval.sval
```

### 不带值 token

例如：

```yacc
%token INT_KW BOOL_KW SET_KW
```

这些 token 只需要表达“出现了这个词”，不需要额外语义值。

## 14. 非终结符类型

```yacc
%type <expr>  expr
%type <vtype> type
%type <ctrl>  if_head comp_head
%type <ast>   aexpr_ast
%type <alist> ast_list
```

`%type` 给非终结符指定语义值类型。

### `expr`

```yacc
%type <expr> expr
```

说明普通表达式返回：

```text
type / level / offset
```

### `type`

```yacc
%type <vtype> type
```

说明类型语法返回：

```text
T_INT / T_BOOL / T_SET
```

### `if_head`

```yacc
%type <ctrl> if_head
```

说明 `if_head` 会保存控制流回填信息。

### `comp_head`

```yacc
%type <ctrl> comp_head
```

说明集合推导式头部也会保存循环控制信息。

### `aexpr_ast`

```yacc
%type <ast> aexpr_ast
```

说明算术表达式 AST 返回 `ExprAst *`。

### `ast_list`

```yacc
%type <alist> ast_list
```

说明 AST 列表返回 `AstList *`。

## 15. 运算符优先级

```yacc
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
```

越往下优先级越高。

### `NO_ELSE` 和 `ELSE`

```yacc
%nonassoc NO_ELSE
%nonassoc ELSE
```

用于解决经典 dangling else 问题。

也就是：

```l26
if (a)
    if (b) s1;
    else s2;
```

`else` 默认绑定最近的 `if`。

### 逻辑运算

```yacc
%left OR_OP
%left AND_OP
%right '!'
```

含义：

- `||` 左结合。
- `&&` 左结合。
- `!` 右结合，且优先级高于 `&&` / `||`。

### 比较运算

```yacc
%nonassoc '<' '>' LE GE EQ_OP NE
```

比较运算不允许链式结合。

也就是不鼓励：

```l26
a < b < c
```

### 算术运算

```yacc
%left '+' '-'
%left '*' '/'
%right UMINUS
```

含义：

- `*` `/` 优先级高于 `+` `-`。
- 二元 `+` `-` 左结合。
- `UMINUS` 表示一元负号，优先级更高。

### 集合相关

```yacc
%left IN_KW
%left UNION_KW INTER_KW
```

给：

```text
in / union / inter
```

指定优先级和结合性。

## 16. 语法规则区开始

```yacc
%%
```

第一个 `%%` 后面进入 grammar rules。

规则格式：

```yacc
非终结符
    : 产生式1 { 动作 }
    | 产生式2 { 动作 }
    ;
```

动作里的常用符号：

- `$$`：当前规则左边非终结符的语义值。
- `$1`：右边第 1 个符号的语义值。
- `$2`：右边第 2 个符号的语义值。
- `$<类型>n`：显式指定第 n 个符号使用 `%union` 中的哪个字段。
- `$<类型>$`：当前中间动作自己的语义值。

## 17. 顶层规则 `program`

```yacc
program
    : block
        { emit(OPR, 0, OPR_RET); }
    ;
```

整个 L26 程序就是一个 `block`。

当 `block` 编译完成后，生成：

```text
OPR 0 OPR_RET
```

含义：程序结束返回。

所以整体编译顺序是：

```text
lexer 产生 token
parser 识别 block
block 内生成声明、语句 P-code
最后补 OPR_RET
```

## 18. 块 `block`

```yacc
block
    : '{'
        {
            scope_enter();
            $<ival>$ = emit(INT, 0, 0);
        }
      decls
        {
            int sz = scope_frame_size();
            patch($<ival>2, sz > 0 ? sz : 1);
        }
      stmts
      '}'
        {
            int sz = scope_frame_size();
            scope_exit();
            emit(INT, 0, -(sz > 0 ? sz : 1));
        }
    ;
```

block 对应源码：

```l26
{
    declarations
    statements
}
```

### 读到 `{`

```c
scope_enter();
```

进入新作用域。

这会影响：

```text
变量声明记录在哪个 scope
变量查找从哪里开始
scope_level() 的结果
```

```c
$<ival>$ = emit(INT, 0, 0);
```

先生成一条占位的 `INT` 指令。

`INT 0 n` 的作用是分配当前作用域运行时帧空间。

此时还没有读完声明，所以不知道 `n` 是多少，只能先写：

```text
INT 0 0
```

`$<ival>$` 保存这条指令的位置。

### 读完 `decls`

```c
int sz = scope_frame_size();
patch($<ival>2, sz > 0 ? sz : 1);
```

变量含义：

- `sz`：当前作用域变量总宽度。
- `$<ival>2`：前面中间动作保存的 `INT` 指令下标。

为什么 `sz > 0 ? sz : 1`？

即使没有局部变量，也至少分配 1 个 word，让运行时帧结构稳定。

### 读完 `stmts` 和 `}`

```c
int sz = scope_frame_size();
scope_exit();
emit(INT, 0, -(sz > 0 ? sz : 1));
```

退出 block 前先拿到帧大小。

然后：

```c
scope_exit();
```

离开作用域，删除本层符号。

最后生成：

```text
INT 0 -n
```

释放当前 block 的运行时空间。

## 19. 声明列表 `decls`

```yacc
decls
    : /* empty */
    | decls decl
    ;
```

`decls` 是零个或多个声明。

两条产生式含义：

```text
empty       没有声明
decls decl  已有声明后继续接一个声明
```

例如：

```l26
{
    int x;
    bool ok;
}
```

会被归约成：

```text
decls -> decls decl -> decls decl decl -> ...
```

## 20. 单条声明 `decl`

```yacc
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
```

对应源码：

```l26
int x;
bool ok;
set s;
```

### `type ID ';'`

右侧三个符号：

- `$1`：`type` 的语义值，类型是 `VarType`。
- `$2`：`ID` 的语义值，类型是 `char[64]`。
- `';'`：字面量 token，没有额外值。

### `sym_declare`

```c
Symbol *s = sym_declare($2, $1);
```

把变量声明加入当前作用域。

变量含义：

- `$2`：变量名。
- `$1`：变量类型。
- `s`：声明成功后返回的符号表项。

如果同一作用域重复声明，`sym_declare` 返回 `NULL`。

### 重复声明错误

```c
if (!s) {
    fprintf(stderr, "error at line %d: duplicate declaration '%s'\n",
            yylineno, $2);
    exit(1);
}
```

如果声明失败，打印行号和变量名，然后退出。

### 集合变量初始化

```c
if ($1 == T_SET) {
    emit(SET_NEW, scope_level() - s->level, s->offset);
}
```

如果声明的是 `set`，需要运行时初始化集合存储。

变量：

- `scope_level() - s->level`：当前层到变量声明层的层差。
- `s->offset`：集合变量在帧里的偏移。

## 21. 类型 `type`

```yacc
type
    : INT_KW  { $$ = T_INT; }
    | BOOL_KW { $$ = T_BOOL; }
    | SET_KW  { $$ = T_SET; }
    ;
```

`type` 把语法里的关键字转成内部类型枚举。

对应关系：

```text
int  -> T_INT
bool -> T_BOOL
set  -> T_SET
```

这里的 `$$` 类型来自：

```yacc
%type <vtype> type
```

## 22. 语句列表 `stmts`

```yacc
stmts
    : /* empty */
    | stmts stmt
    ;
```

`stmts` 是零个或多个语句。

对应：

```l26
{
    stmt1
    stmt2
    stmt3
}
```

它和 `decls` 结构类似。

## 23. 单条语句 `stmt`

```yacc
stmt
    : assign_stmt
    | if_stmt
    | while_stmt
    | io_stmt
    | block
    | set_op_stmt
    ;
```

当前语言支持六类语句：

```text
assign_stmt  赋值
if_stmt      if / if-else
while_stmt   while 循环
io_stmt      read / write
block        嵌套块
set_op_stmt  add / remove 集合操作
```

注意：`block` 本身也是语句，所以可以嵌套作用域：

```l26
{
    int x;
    {
        int x;
    }
}
```

内层 `x` 可以遮蔽外层 `x`。

## 24. 赋值语句 `assign_stmt`

```yacc
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
```

对应源码：

```l26
x = expr;
```

### 查找左值变量

```c
Symbol *s = sym_lookup($1);
```

- `$1`：左侧变量名。
- `s`：符号表查找结果。

如果找不到，说明变量未声明。

### 类型匹配

```c
if (s->type != $3.type)
```

- `s->type`：左侧变量类型。
- `$3.type`：右侧表达式类型。

赋值要求左右类型一致。

### 层差

```c
int ld = scope_level() - s->level;
```

`ld` 表示从当前作用域访问目标变量需要跨几层。

### 集合赋值

```c
if (s->type == T_SET) {
    emit(SET_COPY, ld, s->offset);
}
```

集合赋值使用 `SET_COPY`。

原因：集合是多 word 结构，不能用普通 `STO` 存一个栈顶值。

### 普通赋值

```c
emit(STO, ld, s->offset);
```

`int` 和 `bool` 使用普通存储指令。

## 25. `if_head`

```yacc
if_head
    : IF '(' expr ')'
        {
            if ($3.type != T_BOOL) type_error("if condition must be bool");
            $$.jpc_idx = emit(JPC, 0, 0);
            $$.list    = make_patch($$.jpc_idx);
        }
    ;
```

`if_head` 单独拆出来，是为了在读完条件后立刻生成条件跳转。

对应源码开头：

```l26
if (condition)
```

### 条件类型

```c
if ($3.type != T_BOOL)
```

`if` 条件必须是 `bool`。

### `JPC`

```c
$$.jpc_idx = emit(JPC, 0, 0);
```

生成条件跳转：

```text
JPC 0 ?
```

含义：如果条件为假，跳到某个地址。

但现在还不知道要跳到哪里，所以先写 `0`。

### patch list

```c
$$.list = make_patch($$.jpc_idx);
```

把这个待修正的 `JPC` 位置保存起来。

## 26. `if_stmt`

```yacc
if_stmt
    : if_head stmt %prec NO_ELSE
        {
            do_patch($1.list, current_addr());
            free_patch($1.list);
        }
    | if_head stmt ELSE
        {
            int jmp_idx = emit(JMP, 0, 0);
            do_patch($1.list, current_addr());
            free_patch($1.list);
            $<ctrl>$.list = make_patch(jmp_idx);
        }
      stmt
        {
            do_patch($<ctrl>4.list, current_addr());
            free_patch($<ctrl>4.list);
        }
    ;
```

### 没有 `else`

```yacc
if_head stmt %prec NO_ELSE
```

流程：

```text
生成 condition
JPC ?        条件假则跳过 then
then stmt
patch JPC 到当前地址
```

动作：

```c
do_patch($1.list, current_addr());
free_patch($1.list);
```

- `$1.list`：`if_head` 保存的 JPC。
- `current_addr()`：then 语句结束后的下一条指令地址。

### 有 `else`

```yacc
if_head stmt ELSE ... stmt
```

流程：

```text
condition
JPC else_start
then stmt
JMP end
else_start:
else stmt
end:
```

读到 `ELSE` 时：

```c
int jmp_idx = emit(JMP, 0, 0);
```

then 执行完后要跳过 else。

然后：

```c
do_patch($1.list, current_addr());
```

把条件为假的 `JPC` patch 到 else 起点。

最后等 else stmt 结束：

```c
do_patch($<ctrl>4.list, current_addr());
```

把 `JMP end` patch 到整个 if-else 后面。

## 27. `while_stmt`

```yacc
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
```

对应源码：

```l26
while (condition)
    stmt
```

### 记录循环起点

```c
$<ctrl>$.addr = current_addr();
```

刚读到 `WHILE` 时，当前地址就是循环条件开始的位置。

这个地址之后用于：

```c
emit(JMP, 0, loop_start);
```

### 条件检查

```c
if ($4.type != T_BOOL)
```

`while` 条件必须是 `bool`。

### 条件假跳出

```c
$<ctrl>$.jpc_idx = emit(JPC, 0, 0);
$<ctrl>$.list = make_patch($<ctrl>$.jpc_idx);
```

条件为假时要跳出循环，但出口地址暂时未知，所以先记录待 patch 位置。

### 循环体结束

```c
emit(JMP, 0, $<ctrl>2.addr);
```

循环体执行完，跳回循环起点。

```c
do_patch($<ctrl>6.list, current_addr());
```

把条件为假的出口 patch 到当前地址，也就是循环后第一条指令。

## 28. I/O 语句 `io_stmt`

```yacc
io_stmt
    : WRITE_KW expr ';'
        { ... }
    | READ_KW ID ';'
        { ... }
    ;
```

支持：

```l26
write expr;
read x;
```

### `write`

```c
if ($2.type == T_SET) {
    if ($2.level >= 0) {
        emit(WRITES, $2.level, $2.offset);
    } else {
        emit(WRITET, 0, 0);
    }
} else {
    emit(WRITE, 0, 0);
}
```

如果写的是普通 `int/bool`：

```text
WRITE
```

如果写的是具名集合变量：

```text
WRITES level offset
```

如果写的是集合表达式结果，例如 union/inter/comprehension 产生的临时集合：

```text
WRITET
```

这里的判断依据：

```text
$2.type   表达式类型
$2.level  集合变量地址状态
$2.offset 集合变量偏移或附加信息
```

### `read`

```c
Symbol *s = sym_lookup($2);
```

先查找目标变量。

```c
if (s->type != T_INT) type_error("read requires int variable");
```

当前语言只允许读入整数变量。

然后生成：

```c
emit(READ, 0, 0);
emit(STO, scope_level() - s->level, s->offset);
```

含义：

```text
READ       从输入读一个整数压栈
STO l a    存到变量地址
```

## 29. 集合操作语句 `set_op_stmt`

```yacc
set_op_stmt
    : ADD_KW ID expr ';'
        { ... }
    | REMOVE_KW ID expr ';'
        { ... }
    ;
```

支持：

```l26
add s x;
remove s x;
```

### `add`

```c
Symbol *s = sym_lookup($2);
```

查找集合变量。

```c
if (!s || s->type != T_SET)
```

左侧必须是已声明的 `set`。

```c
if ($3.type != T_INT)
```

加入集合的元素必须是 `int`。

```c
emit(SET_ADD, scope_level() - s->level, s->offset);
```

生成集合添加指令。

### `remove`

逻辑和 `add` 对称：

```text
目标必须是 set
元素必须是 int
生成 SET_REM
```

## 30. 本阶段主流程图

一个程序：

```l26
{
    int x;
    x = 1;
    write x;
}
```

大致编译流程：

```text
program
  -> block
     -> scope_enter
     -> emit INT 0 0 placeholder
     -> decls
        -> sym_declare("x", T_INT)
     -> patch INT frame_size
     -> stmts
        -> assign_stmt
           -> expr emits LIT 0 1
           -> emit STO ...
        -> io_stmt
           -> expr emits LOD ...
           -> emit WRITE
     -> scope_exit
     -> emit INT 0 -frame_size
  -> emit OPR_RET
```

parser 一边识别语法，一边完成：

```text
符号表维护
类型检查
P-code 生成
跳转地址回填
```

## 31. 本阶段你要记住

1. `parser.y` 是整个编译器的中心。
2. lexer 只返回 token，parser 决定这些 token 如何组成程序。
3. `%union` 定义所有语义值可能的形状。
4. `%token <...>` 给 token 绑定语义值字段。
5. `%type <...>` 给非终结符绑定语义值字段。
6. `block` 负责进入作用域、分配帧空间、退出作用域。
7. `decl` 把变量加入符号表。
8. `assign_stmt` 做未声明检查、类型检查和存储代码生成。
9. `if` / `while` 的核心是先 `emit(JPC, 0, 0)`，后面再 `patch`。
10. parser 当前同时承担语法分析、语义分析和代码生成。

## 下一步

Step 7 建议继续读 `parser.y` 的表达式和集合部分：

1. `expr` 普通表达式如何生成 P-code。
2. `==` / `!=` 对集合为什么有额外语义限制。
3. `{1, 2, 3}` 集合字面量为什么先构建 AST。
4. `ID union ID` / `ID inter ID` 如何操作集合。
5. `{ body | x in s if cond }` 集合推导式如何编译成循环。
