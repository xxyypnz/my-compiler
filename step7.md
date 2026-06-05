# Step 7：`parser.y` 表达式与集合语义

本阶段继续读：

```text
parser.y
```

范围：

```text
expr
comp_head
aexpr_ast
ast_list
yyerror
```

目标：看懂普通表达式、集合表达式、集合字面量、集合推导式如何做类型检查并生成 P-code。

## Step 6 承接

Step 6 已经读完 parser 主干：

```text
program / block / decls / stmts / assign / if / while / io / add / remove
```

但还有几个关键问题没展开：

1. `expr` 的 `type / level / offset` 到底怎么用？
2. 普通算术、比较、逻辑表达式如何生成 P-code？
3. 集合变量为什么不像 `int` 一样直接压栈？
4. `{1, 2, 3}` 为什么先走 `ast_list`？
5. `union/inter/in/isempty` 怎么检查类型？
6. `set == set` 为什么只允许集合变量？
7. `set != set` 为什么被禁止？
8. 集合推导式 `{ body | x in s if cond }` 如何编译成循环？

## 1. `expr` 的语义值约定

`expr` 的类型来自：

```yacc
%type <expr> expr
```

对应 `%union` 里的字段：

```c
struct {
    VarType type;
    int     level;
    int     offset;
} expr;
```

三个字段含义：

- `type`：表达式类型，可能是 `T_INT`、`T_BOOL`、`T_SET`。
- `level`：如果表达式代表集合变量，保存层差。
- `offset`：如果表达式代表集合变量，保存偏移。

普通 `int/bool` 表达式通常设置为：

```c
$$.type = T_INT 或 T_BOOL;
$$.level = 0;
$$.offset = 0;
```

集合表达式有三种状态：

```text
level >= 0   具名集合变量，level/offset 是真实地址
level == -1  集合字面量，结果在 temp_set，offset 临时记录元素数量
level == -2  union/inter/comprehension 的结果在 temp_set
```

这个约定很重要。

PVM 里集合是多 word 结构，不适合像整数一样只压一个值到栈顶，所以 parser 需要携带集合地址或说明结果在 `temp_set`。

## 2. 数字表达式

```yacc
expr
    : NUM
        {
            $$.type = T_INT; $$.level = 0; $$.offset = 0;
            emit(LIT, 0, $1);
        }
```

源码例子：

```l26
123
```

lexer 返回：

```text
NUM
```

并且：

```text
$1 = 123
```

parser 设置：

```text
type = T_INT
```

然后生成：

```text
LIT 0 123
```

作用：把整数 `123` 压入 PVM 栈。

## 3. 布尔常量

```yacc
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
```

源码：

```l26
true
false
```

内部表示：

```text
true  -> 1
false -> 0
```

所以它们也是通过：

```text
LIT 0 1
LIT 0 0
```

压栈。

区别只是类型标记是：

```text
T_BOOL
```

## 4. 标识符表达式

```yacc
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
    }
```

源码例子：

```l26
x
```

### 查符号表

```c
Symbol *s = sym_lookup($1);
```

- `$1`：变量名。
- `s`：符号表项。

如果找不到，说明变量未声明，直接报错退出。

### 计算层差

```c
int ld = scope_level() - s->level;
```

`ld` 是当前作用域到变量声明作用域的距离。

例子：

```l26
{
    int x;      // level 1
    {
        write x;  // 当前 level 2，ld = 2 - 1 = 1
    }
}
```

### 保存表达式信息

```c
$$.type   = s->type;
$$.level  = ld;
$$.offset = s->offset;
```

后续规则可以知道：

```text
这个表达式是什么类型
如果它是集合，它在哪个地址
```

### 非集合变量立即加载

```c
if (s->type != T_SET) {
    emit(LOD, ld, s->offset);
}
```

`int/bool` 可以直接压栈。

集合变量不压栈，只携带地址。

## 5. 算术表达式

```yacc
| expr '+' expr
| expr '-' expr
| expr '*' expr
| expr '/' expr
```

每个二元算术规则结构相同。

以 `+` 为例：

```yacc
| expr '+' expr
    {
        check_int2($1.type, $3.type, "+");
        $$.type = T_INT; $$.level = 0; $$.offset = 0;
        emit(OPR, 0, OPR_ADD);
    }
```

### 类型检查

```c
check_int2($1.type, $3.type, "+");
```

`+` 的左右两侧必须都是 `int`。

如果出现：

```l26
true + 1
```

会报类型错误。

### 代码生成顺序

对于：

```l26
a + b
```

归约前，左右 `expr` 已经分别生成代码：

```text
LOD a
LOD b
```

栈上已有两个操作数。

当前规则只需要再生成：

```text
OPR 0 OPR_ADD
```

PVM 会弹出两个值，相加后把结果压回栈。

### 四种算术对应关系

```text
+ -> OPR_ADD
- -> OPR_SUB
* -> OPR_MUL
/ -> OPR_DIV
```

除法的除零检查不在 parser 做，而是在 PVM 执行 `OPR_DIV` 时做。

## 6. 一元负号

```yacc
| '-' expr %prec UMINUS
    {
        if ($2.type != T_INT) type_error("unary minus requires int");
        $$.type = T_INT; $$.level = 0; $$.offset = 0;
        emit(OPR, 0, OPR_NEG);
    }
```

源码：

```l26
-x
```

`%prec UMINUS` 的作用：告诉 Bison 这里的 `-` 是一元负号，不是二元减法，并使用 `UMINUS` 的优先级。

类型要求：

```text
被取负的表达式必须是 int
```

生成：

```text
OPR 0 OPR_NEG
```

## 7. 比较表达式

```yacc
| expr '<' expr
| expr '>' expr
| expr LE expr
| expr GE expr
```

比较表达式左右都要求 `int`，结果是 `bool`。

对应关系：

```text
<   -> OPR_LT
>   -> OPR_GT
<=  -> OPR_LEQ
>=  -> OPR_GEQ
```

以 `<=` 为例：

```yacc
| expr LE expr
    {
        check_int2($1.type, $3.type, "<=");
        $$.type = T_BOOL; $$.level = 0; $$.offset = 0;
        emit(OPR, 0, OPR_LEQ);
    }
```

源码：

```l26
i <= n
```

生成逻辑：

```text
加载 i
加载 n
OPR_LEQ
```

PVM 把比较结果压栈：

```text
真 -> 1
假 -> 0
```

## 8. 相等 `==`

```yacc
| expr EQ_OP expr
    {
        $$.type = T_BOOL; $$.level = 0; $$.offset = 0;
        if ($1.type == T_SET && $3.type == T_SET) {
            if ($1.level < 0 || $3.level < 0)
                type_error("set equality requires set variables");
            emit(SET_EQL,
                 ENCODE2($1.level, $1.offset),
                 ENCODE2($3.level, $3.offset));
        } else if ($1.type == $3.type) {
            emit(OPR, 0, OPR_EQ);
        } else {
            type_error("'==' operands must have the same type");
        }
    }
```

`==` 分两种情况。

### 普通类型相等

如果两侧类型相同，且不是集合：

```text
int == int
bool == bool
```

生成：

```text
OPR 0 OPR_EQ
```

### 集合相等

如果两侧都是 `T_SET`：

```c
if ($1.level < 0 || $3.level < 0)
    type_error("set equality requires set variables");
```

这条限制很关键。

集合相等只允许：

```l26
s1 == s2
```

不允许：

```l26
s1 == {1, 2}
{1, 2} == {2, 1}
s1 == (s2 union s3)
```

原因：当前 `SET_EQL` 指令需要两个集合变量地址。

集合字面量、`union`、`inter`、comprehension 的结果放在全局 `temp_set`，不是稳定的具名变量地址。为了避免语义不清和临时结果被覆盖，parser 直接限制为集合变量比较。

真正生成的是：

```c
emit(SET_EQL,
     ENCODE2($1.level, $1.offset),
     ENCODE2($3.level, $3.offset));
```

`SET_EQL` 需要两个集合地址。

但 `Instruction` 只有两个整数参数 `l` 和 `a`，所以这里用：

```text
ENCODE2(level, offset)
```

把一对地址编码进一个整数。

## 9. 不等 `!=`

```yacc
| expr NE expr
    {
        if ($1.type != $3.type) type_error("'!=' operands must have the same type");
        if ($1.type == T_SET) type_error("'!=' is not supported for sets");
        $$.type = T_BOOL; $$.level = 0; $$.offset = 0;
        emit(OPR, 0, OPR_NEQ);
    }
```

`!=` 的语义比 `==` 更严格。

### 类型必须一致

```c
if ($1.type != $3.type)
```

不允许：

```l26
1 != true
```

### 集合不支持 `!=`

```c
if ($1.type == T_SET) type_error("'!=' is not supported for sets");
```

不允许：

```l26
s1 != s2
```

这是当前项目的明确语义限制。

如果未来要支持，可以生成：

```text
SET_EQL
OPR_NOT
```

但当前实现选择禁止，测试里也覆盖了 `set_ne.l26`。

### 普通不等

对 `int/bool`：

```text
OPR 0 OPR_NEQ
```

## 10. 逻辑表达式

```yacc
| expr AND_OP expr
| expr OR_OP expr
| '!' expr
```

### `&&`

```c
check_bool2($1.type, $3.type, "&&");
$$.type = T_BOOL;
emit(OPR, 0, OPR_AND);
```

左右必须是 `bool`。

### `||`

```c
check_bool2($1.type, $3.type, "||");
$$.type = T_BOOL;
emit(OPR, 0, OPR_OR);
```

左右必须是 `bool`。

### `!`

```c
if ($2.type != T_BOOL) type_error("'!' requires bool");
$$.type = T_BOOL;
emit(OPR, 0, OPR_NOT);
```

操作数必须是 `bool`。

注意：这里没有短路求值。

例如：

```l26
a && b
```

会先计算 `a`，再计算 `b`，最后执行 `OPR_AND`。

## 11. 括号表达式

```yacc
| '(' expr ')'
    { $$ = $2; }
```

括号只改变语法组合方式，不改变表达式本身。

所以直接：

```text
当前表达式语义值 = 括号内部表达式语义值
```

也就是：

```c
$$ = $2;
```

## 12. 集合字面量 `{ e1, e2, ... }`

```yacc
| '{' ast_list '}'
    {
        int count = ast_list_emit_and_free($2);
        $$.type = T_SET; $$.level = -1; $$.offset = count;
        emit(SET_LIT, 0, count);
    }
| '{' '}'
    {
        $$.type = T_SET; $$.level = -1; $$.offset = 0;
        emit(SET_LIT, 0, 0);
    }
```

支持：

```l26
{}
{1, 2, 3}
{x, x + 1}
```

### 为什么用 `ast_list`

普通 `expr` 会边归约边立即 `emit`。

但集合字面量里只允许算术元素，并且需要先把每个元素表达式整理成列表，再统一：

```text
生成元素求值代码
统计元素数量
生成 SET_LIT count
```

所以这里不用普通 `expr`，而是用：

```text
aexpr_ast
ast_list
```

### 非空集合

```c
int count = ast_list_emit_and_free($2);
```

这一步会：

1. 遍历每个元素 AST。
2. 调用 `emit_ast_expr` 生成元素代码。
3. 检查每个元素必须是 `int`。
4. 释放 AST 节点。
5. 返回元素数量。

然后：

```c
emit(SET_LIT, 0, count);
```

PVM 会从栈里弹出 `count` 个整数，放进 `temp_set`。

### 空集合

```c
emit(SET_LIT, 0, 0);
```

生成一个空的临时集合。

### 赋值给集合变量

源码：

```l26
s = {1, 2, 3};
```

流程：

```text
expr 生成 SET_LIT，结果在 temp_set
assign_stmt 发现左侧是 T_SET
emit SET_COPY，把 temp_set 复制到 s
```

## 13. 集合并集 `union`

```yacc
| ID UNION_KW ID
    {
        Symbol *s1 = sym_lookup($1);
        Symbol *s3 = sym_lookup($3);
        ...
        int ld1 = scope_level() - s1->level;
        int ld3 = scope_level() - s3->level;
        emit(SET_UNION, ENCODE2(ld1, s1->offset), ENCODE2(ld3, s3->offset));
        $$.type = T_SET; $$.level = -2; $$.offset = 0;
    }
```

语法只允许：

```l26
ID union ID
```

也就是：

```l26
s1 union s2
```

不支持：

```l26
{1, 2} union s2
s1 union (s2 inter s3)
```

### 类型检查

两边 ID 都必须查得到，并且类型是 `T_SET`。

### 地址编码

```c
ENCODE2(ld1, s1->offset)
ENCODE2(ld3, s3->offset)
```

把两个集合地址分别压缩进 `Instruction.l` 和 `Instruction.a`。

### 结果位置

```c
$$.type = T_SET;
$$.level = -2;
$$.offset = 0;
```

`level = -2` 表示：

```text
结果在 PVM 的 temp_set 里
```

如果写：

```l26
u = s1 union s2;
```

后续 `assign_stmt` 会用 `SET_COPY` 把 `temp_set` 复制到 `u`。

## 14. 集合交集 `inter`

```yacc
| ID INTER_KW ID
    {
        ...
        emit(SET_INTER, ENCODE2(ld1, s1->offset), ENCODE2(ld3, s3->offset));
        $$.type = T_SET; $$.level = -2; $$.offset = 0;
    }
```

逻辑和 `union` 一样。

区别只是生成：

```text
SET_INTER
```

结果同样放在：

```text
temp_set
```

## 15. 成员测试 `in`

```yacc
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
```

源码：

```l26
3 in s
x + 1 in s
```

左侧必须是 `int`。

右侧必须是集合变量 `ID`。

生成：

```text
SET_IN ld offset
```

PVM 会弹出左侧整数，检查它是否在集合里，然后压入：

```text
1 或 0
```

结果类型是：

```text
T_BOOL
```

## 16. 空集合测试 `isempty`

```yacc
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
```

源码：

```l26
isempty(s)
```

`s` 必须是集合变量。

生成：

```text
SET_EMPTY ld offset
```

PVM 根据集合计数字段判断是否为空。

## 17. 集合推导式总览

```yacc
| '{' aexpr_ast '|' comp_head IF expr '}'
    { ... }
```

源码形式：

```l26
{ body_expr | x in source if filter_expr }
```

例子：

```l26
{ x * 2 | x in s1 if x > 2 }
```

含义：

```text
遍历 s1 中每个元素
把当前元素绑定给 x
如果 x > 2 为真
就把 x * 2 加入结果集合
```

这个语法分两段：

```text
aexpr_ast   body_expr
comp_head   x in source，并生成循环头
expr        filter_expr
```

## 18. `comp_head`

```yacc
comp_head
    : ID IN_KW ID
        { ... }
```

对应：

```l26
x in s1
```

其中：

- `$1`：迭代变量名，例如 `x`。
- `$3`：源集合变量名，例如 `s1`。

### 查找源集合

```c
Symbol *src = sym_lookup($3);
```

源必须存在且是 `T_SET`。

```c
int src_level = src->level;
int src_off   = src->offset;
```

先保存源集合声明层级和偏移。

### 打开推导式作用域

```c
scope_enter();
```

推导式内部有自己的隐藏局部变量，也有迭代变量 `$1`。

进入新作用域后重新计算源集合层差：

```c
int src_ld = scope_level() - src_level;
```

### 分配帧占位

```c
int int_ph = emit(INT, 0, 0);
```

和普通 block 一样，先不知道需要多少空间，所以先占位。

### 声明隐藏变量

```c
Symbol *tmp_sym  = sym_declare("__comp_tmp", T_SET);
Symbol *idx_sym  = sym_declare("__comp_idx", T_INT);
Symbol *iter_sym = sym_declare($1, T_INT);
```

三个变量：

- `__comp_tmp`：推导式结果集合。
- `__comp_idx`：当前遍历下标。
- `$1`：用户写的迭代变量，例如 `x`。

如果迭代变量在当前推导式作用域重复声明，`iter_sym` 会是 `NULL`。

### 回填帧大小

```c
patch(int_ph, scope_frame_size());
```

隐藏变量都声明完后，知道了当前推导式作用域需要多少空间，于是 patch 前面的 `INT`。

### 保存偏移

```c
int tmp_off  = tmp_sym->offset;
int idx_off  = idx_sym->offset;
int iter_off = iter_sym->offset;
```

后续生成代码要访问这些局部变量。

### 初始化结果集合

```c
emit(SET_NEW, 0, tmp_off);
```

`__comp_tmp = {}`。

### 初始化索引

```c
emit(LIT, 0, 0);
emit(STO, 0, idx_off);
```

`__comp_idx = 0`。

### 循环条件

```c
int loop_top = current_addr();
emit(LOD, 0, idx_off);
emit(LOD, src_ld, src_off);
emit(OPR, 0, OPR_LT);
int jpc_end = emit(JPC, 0, 0);
```

集合内存布局中：

```text
base[0] = 元素个数
```

所以：

```c
emit(LOD, src_ld, src_off);
```

会加载源集合的 count word。

条件是：

```text
__comp_idx < source.count
```

如果为假，`JPC` 跳到推导式循环结束处，但结束地址暂时未知，所以先占位。

### 加载当前元素到迭代变量

```c
emit(LOD, 0, idx_off);
emit(SET_ELEM, src_ld, src_off);
emit(STO, 0, iter_off);
```

含义：

```text
把 __comp_idx 压栈
SET_ELEM 从 source 中取出对应元素
存入迭代变量 x
```

### 返回控制信息

```c
$$.addr     = tmp_off;
$$.jpc_idx  = idx_off;
$$.loop_top = loop_top;
$$.end_jpc  = jpc_end;
$$.list     = NULL;
```

字段复用关系：

- `addr`：保存 `__comp_tmp` 的偏移。
- `jpc_idx`：保存 `__comp_idx` 的偏移。
- `loop_top`：循环开头。
- `end_jpc`：循环结束跳转位置。
- `list`：这里不用。

## 19. 推导式主体动作

```yacc
| '{' aexpr_ast '|' comp_head IF expr '}'
    {
        if ($6.type != T_BOOL) type_error("set comprehension filter must be bool");

        int tmp_off  = $4.addr;
        int idx_off  = $4.jpc_idx;
        int loop_top = $4.loop_top;
        int jpc_end  = $4.end_jpc;
        int jpc_skip = emit(JPC, 0, 0);

        if (emit_ast_expr($2) != T_INT)
            type_error("set comprehension body must be int");
        emit(SET_ADD, 0, tmp_off);
        ast_free($2);

        patch(jpc_skip, current_addr());

        emit(LOD, 0, idx_off);
        emit(LIT, 0, 1);
        emit(OPR, 0, OPR_ADD);
        emit(STO, 0, idx_off);
        emit(JMP, 0, loop_top);

        patch(jpc_end, current_addr());
        emit(SET_UNION, ENCODE2(0, tmp_off), ENCODE2(0, tmp_off));

        int sz = scope_frame_size();
        scope_exit();
        emit(INT, 0, -sz);

        $$.type   = T_SET;
        $$.level  = -2;
        $$.offset = 0;
    }
```

### filter 必须是 bool

```c
if ($6.type != T_BOOL)
```

`if filter_expr` 的过滤条件必须是布尔表达式。

### 取出 `comp_head` 保存的信息

```c
int tmp_off  = $4.addr;
int idx_off  = $4.jpc_idx;
int loop_top = $4.loop_top;
int jpc_end  = $4.end_jpc;
```

`$4` 是 `comp_head` 的语义值。

### filter 为假则跳过 body

```c
int jpc_skip = emit(JPC, 0, 0);
```

当过滤条件为假时，跳过：

```text
计算 body
SET_ADD
```

目标地址之后再 patch。

### 计算 body 并加入结果集合

```c
if (emit_ast_expr($2) != T_INT)
    type_error("set comprehension body must be int");
emit(SET_ADD, 0, tmp_off);
```

body 必须产生整数。

然后把这个整数加入 `__comp_tmp`。

### patch skip

```c
patch(jpc_skip, current_addr());
```

如果 filter 为假，跳到这里继续执行索引自增。

### 索引自增

```c
emit(LOD, 0, idx_off);
emit(LIT, 0, 1);
emit(OPR, 0, OPR_ADD);
emit(STO, 0, idx_off);
```

等价于：

```l26
__comp_idx = __comp_idx + 1;
```

### 跳回循环顶部

```c
emit(JMP, 0, loop_top);
```

继续处理下一个元素。

### patch 循环结束

```c
patch(jpc_end, current_addr());
```

当 `__comp_idx < source.count` 为假时，跳到这里。

### 把结果放进 `temp_set`

```c
emit(SET_UNION, ENCODE2(0, tmp_off), ENCODE2(0, tmp_off));
```

这是一个技巧：

```text
temp_set = __comp_tmp union __comp_tmp
```

结果仍然是 `__comp_tmp`，但通过 `SET_UNION` 统一写入全局 `temp_set`，方便后续 `SET_COPY` 或 `WRITET` 使用。

### 退出推导式作用域

```c
int sz = scope_frame_size();
scope_exit();
emit(INT, 0, -sz);
```

释放隐藏变量和迭代变量所在的运行时帧。

### 返回集合表达式

```c
$$.type   = T_SET;
$$.level  = -2;
$$.offset = 0;
```

说明结果是集合，并且位于 `temp_set`。

## 20. `aexpr_ast`

```yacc
aexpr_ast
    : NUM
        { $$ = ast_num($1); }
    | ID
        { $$ = ast_id($1); }
    | aexpr_ast '+' aexpr_ast
        { $$ = ast_bin('+', $1, $3); }
    | aexpr_ast '-' aexpr_ast
        { $$ = ast_bin('-', $1, $3); }
    | aexpr_ast '*' aexpr_ast
        { $$ = ast_bin('*', $1, $3); }
    | aexpr_ast '/' aexpr_ast
        { $$ = ast_bin('/', $1, $3); }
    | '-' aexpr_ast %prec UMINUS
        { $$ = ast_neg($2); }
    | '(' aexpr_ast ')'
        { $$ = $2; }
    ;
```

`aexpr_ast` 是 arithmetic expression AST。

它只支持：

```text
数字
变量
+ - * /
一元负号
括号
```

不支持：

```text
bool
比较
逻辑
集合运算
```

原因：集合元素和推导式 body 必须是整数表达式。

它不会立即 `emit`，只构造 AST：

```text
ast_num
ast_id
ast_bin
ast_neg
```

真正生成 P-code 的时机是：

```c
emit_ast_expr(...)
```

## 21. `ast_list`

```yacc
ast_list
    : aexpr_ast
        { $$ = ast_list_new($1); }
    | ast_list ',' aexpr_ast
        { $$ = ast_list_append($1, $3); }
    ;
```

用于集合字面量：

```l26
{1, x + 2, y}
```

第一条规则创建链表头。

第二条规则把新元素追加到链表末尾。

最终得到：

```text
AstList -> AstList -> AstList
```

每个节点里有一个 `ExprAst *`。

## 22. `yyerror`

```c
void yyerror(const char *s) {
    fprintf(stderr, "parse error at line %d: %s\n", yylineno, s);
    exit(1);
}
```

Bison 发现语法错误时调用这个函数。

参数：

- `s`：Bison 给出的错误信息。

输出包含：

- `yylineno`：当前行号。
- `s`：语法错误说明。

然后：

```c
exit(1);
```

终止编译。

## 23. 表达式到 P-code 的例子

源码：

```l26
x = 1 + 2 * 3;
```

大致生成：

```text
LIT 0 1
LIT 0 2
LIT 0 3
OPR 0 OPR_MUL
OPR 0 OPR_ADD
STO ...
```

原因：

```text
2 * 3 优先级更高
先乘，再加
```

源码：

```l26
if (x > 0 && true) write x;
```

大致生成：

```text
LOD x
LIT 0 0
OPR_GT
LIT 0 1
OPR_AND
JPC ...
LOD x
WRITE
```

## 24. 集合表达式到 P-code 的例子

源码：

```l26
set s;
s = {1, 2};
```

大致生成：

```text
SET_NEW s
LIT 0 1
LIT 0 2
SET_LIT 0 2
SET_COPY s
```

源码：

```l26
set u;
u = s1 union s2;
```

大致生成：

```text
SET_UNION addr(s1), addr(s2)
SET_COPY addr(u)
```

源码：

```l26
if (3 in s) write 1;
```

大致生成：

```text
LIT 0 3
SET_IN addr(s)
JPC ...
LIT 0 1
WRITE
```

## 25. 本阶段你要记住

1. 普通表达式边归约边生成 P-code。
2. `int/bool` 表达式的值在 PVM 栈顶。
3. 集合表达式不一定压栈，常用 `level/offset` 或 `temp_set` 表示结果位置。
4. `level >= 0` 表示具名集合变量地址。
5. `level < 0` 表示临时集合结果。
6. `set == set` 只允许两个集合变量。
7. `set != set` 当前明确禁止。
8. 集合字面量用 `aexpr_ast/ast_list` 延迟生成元素代码。
9. 集合推导式通过隐藏变量和循环编译实现。
10. parser 在表达式阶段完成类型检查和 P-code 生成。

## 下一步

Step 8 进入 `pvm.c/h`。

先看普通虚拟机执行模型：

```text
stack / sp / pc / frame_base / frame_top
LIT / LOD / STO / INT / JMP / JPC / OPR / READ / WRITE
```
