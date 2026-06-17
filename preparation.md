# 现场修改预案

这份文档用于助教现场要求“临时改一个功能”时快速定位修改点。

原则：

```text
先判断属于哪个阶段
再改最少文件
最后 make && make test
```

## 0. 快速定位表

```text
新增关键字              lexer.l + parser.y
新增语法结构            parser.y
新增普通运算符          lexer.l + parser.y + pcode.h + pvm.c
新增集合指令            parser.y + pcode.h + pvm.c
只改变类型限制          parser.y
只改变集合运行效果      pvm.c
只改变变量作用域规则    symtab.c/h 或 parser.y 的 scope_enter/exit
只改变打印 P-code       codegen.c
只改变命令行参数        main.c
只改变构建/测试         Makefile
```

现场修改后统一跑：

```bash
make clean
make
make test
```

单独看 P-code：

```bash
./l26c -p tests/testX.l26
```

单步执行：

```bash
./l26c -s tests/testX.l26
```

## 1. 新增一个关键字

例子：新增 `clear` 关键字。

涉及文件：

```text
lexer.l
parser.y
```

### 修改 `lexer.l`

关键字规则要写在 `ID` 规则之前。

```lex
"clear"     { return CLEAR_KW; }
```

位置放在：

```lex
"remove"    { return REMOVE_KW; }
```

附近。

### 修改 `parser.y`

token 区新增：

```yacc
%token CLEAR_KW
```

然后在语句规则里接入。

如果是集合清空语句：

```l26
clear s;
```

可以加到 `set_op_stmt`：

```yacc
| CLEAR_KW ID ';'
    {
        Symbol *s = sym_lookup($2);
        if (!s || s->type != T_SET) {
            fprintf(stderr, "error at line %d: 'clear' requires a set variable\n",
                    yylineno);
            exit(1);
        }
        emit(SET_NEW, scope_level() - s->level, s->offset);
    }
```

这里复用已有 `SET_NEW`，不用改 `pcode.h` 和 `pvm.c`。

### 测试

新增测试：

```l26
{
    set s;
    s = {1, 2};
    clear s;
    write s;
}
```

期望：

```text
{}
```

## 2. 新增取模运算 `%`

例子：

```l26
x = 10 % 3;
```

涉及文件：

```text
lexer.l
parser.y
pcode.h
pvm.c
```

### 修改 `lexer.l`

把 `%` 加入单字符 token 集合：

```lex
[+\-*/%<>!(){};,|=]  { return yytext[0]; }
```

### 修改 `pcode.h`

新增 OPR 子操作码。

当前最大到：

```c
#define OPR_OR   15
```

追加：

```c
#define OPR_MOD  16
```

### 修改 `parser.y`

优先级中把 `%` 放到 `* /` 同级：

```yacc
%left '*' '/' '%'
```

在 `expr` 中加入：

```yacc
| expr '%' expr
    {
        check_int2($1.type, $3.type, "%");
        $$.type = T_INT; $$.level = 0; $$.offset = 0;
        emit(OPR, 0, OPR_MOD);
    }
```

### 修改 `pvm.c`

`opr_names` 追加：

```c
"MOD"
```

并且 `print_instruction` 中：

```c
if (ins->op == OPR && ins->a >= 0 && ins->a <= 16)
```

`OPR` switch 加：

```c
case OPR_MOD:
    b = pop(); a = pop();
    if (b == 0) { fprintf(stderr, "runtime error: modulo by zero\n"); exit(1); }
    push(a % b);
    break;
```

### 测试

```l26
{
    int x;
    x = 10 % 3;
    write x;
}
```

期望：

```text
1
```

## 3. 支持 `set != set`

当前实现明确禁止：

```l26
s1 != s2
```

如果现场要求支持，最小改法只改 `parser.y`。

思路：

```text
s1 != s2
等价于
!(s1 == s2)
```

### 修改 `parser.y`

找到：

```yacc
| expr NE expr
```

把当前动作改成：

```yacc
| expr NE expr
    {
        if ($1.type != $3.type) type_error("'!=' operands must have the same type");
        $$.type = T_BOOL; $$.level = 0; $$.offset = 0;
        if ($1.type == T_SET) {
            if ($1.level < 0 || $3.level < 0)
                type_error("set inequality requires set variables");
            emit(SET_EQL,
                 ENCODE2($1.level, $1.offset),
                 ENCODE2($3.level, $3.offset));
            emit(OPR, 0, OPR_NOT);
        } else {
            emit(OPR, 0, OPR_NEQ);
        }
    }
```

不用改 `pvm.c`，因为已有：

```text
SET_EQL
OPR_NOT
```

### 测试

```l26
{
    set a;
    set b;
    a = {1, 2};
    b = {2, 1};
    if (a != b) { write 1; } else { write 0; }
    b = {1, 3};
    if (a != b) { write 1; } else { write 0; }
}
```

期望：

```text
0
1
```

注意：如果仍然保留“只允许集合变量比较”，则 `{1} != a` 仍然报错。

## 4. 新增 `size(s)` 返回集合大小

例子：

```l26
write size(s);
```

涉及文件：

```text
lexer.l
parser.y
```

不用新增 PVM 指令。

原因：集合布局中：

```text
base[0] = count
```

而 `LOD ld offset` 正好加载 `base[0]`。

### 修改 `lexer.l`

关键字区新增：

```lex
"size"      { return SIZE_KW; }
```

### 修改 `parser.y`

token 区新增：

```yacc
%token SIZE_KW
```

`expr` 中新增：

```yacc
| SIZE_KW '(' ID ')'
    {
        Symbol *s = sym_lookup($3);
        if (!s || s->type != T_SET) {
            fprintf(stderr, "error at line %d: '%s' is not a set\n", yylineno, $3);
            exit(1);
        }
        emit(LOD, scope_level() - s->level, s->offset);
        $$.type = T_INT; $$.level = 0; $$.offset = 0;
    }
```

### 测试

```l26
{
    set s;
    s = {1, 2, 2, 3};
    write size(s);
}
```

期望：

```text
3
```

## 5. 允许 `read bool`

当前：

```text
read 只允许 int 变量
```

如果现场要求：

```l26
bool b;
read b;
```

最小改法只改 `parser.y`。

### 修改 `parser.y`

找到 `READ_KW ID ';'`：

```c
if (s->type != T_INT) type_error("read requires int variable");
```

改成：

```c
if (s->type != T_INT && s->type != T_BOOL)
    type_error("read requires int or bool variable");
```

后面：

```c
emit(READ, 0, 0);
emit(STO, scope_level() - s->level, s->offset);
```

不用变。

### 说明

PVM 的 `READ` 读的是整数。

所以 bool 输入建议约定：

```text
0 = false
非 0 = true
```

如果助教要求严格只允许 `0/1`，需要新增运行时检查指令或在 `READ` 后插入检查逻辑，这个改动会更大。

## 6. 新增 `print bool` 为 `true/false`

当前：

```l26
write true;
```

输出：

```text
1
```

如果要求输出：

```text
true
false
```

推荐新增 opcode。

涉及文件：

```text
pcode.h
parser.y
pvm.c
codegen.c 可不改，print_pcode 会自动按 opcode 名称表则需要同步
```

### 修改 `pcode.h`

在 `OpCode` 里新增：

```c
WRITEB
```

最好放在 `WRITE` 后：

```c
READ, WRITE, WRITEB, WRITES, WRITET,
```

注意：改 enum 后，`pvm.c` 的 `names[]` 顺序必须同步。

### 修改 `parser.y`

`WRITE_KW expr ';'` 中：

```c
if ($2.type == T_SET) ...
else {
    emit(WRITE, 0, 0);
}
```

改为：

```c
if ($2.type == T_SET) {
    ...
} else if ($2.type == T_BOOL) {
    emit(WRITEB, 0, 0);
} else {
    emit(WRITE, 0, 0);
}
```

### 修改 `pvm.c`

`names[]` 加：

```c
"WRITEB"
```

switch 加：

```c
case WRITEB:
    printf("%s\n", pop() ? "true" : "false");
    break;
```

### 风险

新增 enum 会影响 opcode 数值。

只要 parser 和 PVM 同时重新编译，就没问题。

## 7. 改集合最大容量

当前最大 200 个元素：

```c
#define SET_SIZE 201
```

如果要求改成最多 1000 个元素：

### 修改 `pcode.h`

```c
#define SET_SIZE 1001
```

### 影响

不需要改 parser。

因为：

```c
type_width(T_SET)
```

会使用 `SET_SIZE`。

但要注意：

```text
每个 set 变量占用更多 stack 空间
MAX_STACK 可能也要调大
```

如果测试里集合变量很多，顺便改：

```c
#define MAX_STACK 65536
```

### 测试

写一个超过 200 元素的集合或循环 `add`。

## 8. 新增 `subset` 判断

例子：

```l26
if (a subset b) write 1;
```

涉及文件：

```text
lexer.l
parser.y
pcode.h
pvm.c
```

### 修改 `lexer.l`

```lex
"subset"   { return SUBSET_KW; }
```

### 修改 `pcode.h`

`OpCode` 加：

```c
SET_SUBSET
```

### 修改 `parser.y`

token：

```yacc
%token SUBSET_KW
```

优先级可以和比较放一起：

```yacc
%nonassoc '<' '>' LE GE EQ_OP NE SUBSET_KW
```

`expr` 加：

```yacc
| ID SUBSET_KW ID
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
        emit(SET_SUBSET, ENCODE2(ld1, s1->offset), ENCODE2(ld3, s3->offset));
        $$.type = T_BOOL; $$.level = 0; $$.offset = 0;
    }
```

### 修改 `pvm.c`

新增 helper：

```c
static int set_subset(int *a, int *b) {
    int ca = a[0];
    for (int i = 1; i <= ca; i++)
        if (!set_contains(b, a[i])) return 0;
    return 1;
}
```

`names[]` 加：

```c
"SET_SUBSET"
```

switch 加：

```c
case SET_SUBSET: {
    int *a = set_base(DECODE_LD(ins.l), DECODE_OFF(ins.l));
    int *b = set_base(DECODE_LD(ins.a), DECODE_OFF(ins.a));
    push(set_subset(a, b) ? 1 : 0);
    break;
}
```

`print_instruction` 中双集合地址判断也加：

```c
ins->op == SET_SUBSET
```

## 9. 新增 `for` 循环

例子：

```l26
for (i = 1; i <= 10; i = i + 1) {
    write i;
}
```

涉及文件：

```text
lexer.l
parser.y
```

不需要新增 PVM 指令，因为可以翻译成 while。

### 修改 `lexer.l`

```lex
"for"       { return FOR; }
```

### 修改 `parser.y`

token：

```yacc
%token FOR
```

问题：现有 `assign_stmt` 带 `;`，for 头里不方便复用。

建议新增一个不带分号的赋值规则：

```yacc
assign_core
    : ID '=' expr
        {
            Symbol *s = sym_lookup($1);
            if (!s) {
                fprintf(stderr, "error at line %d: undeclared variable '%s'\n",
                        yylineno, $1);
                exit(1);
            }
            if (s->type != $3.type) type_error("type mismatch in assignment");
            int ld = scope_level() - s->level;
            if (s->type == T_SET) emit(SET_COPY, ld, s->offset);
            else emit(STO, ld, s->offset);
        }
    ;
```

然后：

```yacc
assign_stmt
    : assign_core ';'
    ;
```

`stmt` 加：

```yacc
| for_stmt
```

`for_stmt` 的难点是第三段 `i = i + 1` 应该在循环体之后执行，但 parser 读到它时会立即 emit。

所以现场不推荐临时做完整 C 风格 for。

低风险替代语法：

```l26
for (init; cond) stmt
```

或直接告诉助教：当前编译器是一遍归约即时生成代码，完整 `for(init;cond;post)` 需要延迟 `post` 代码，最好先引入小型代码缓存。

如果必须做，方案是：

```text
给 codegen 增加临时 code buffer
解析 post 时写入 buffer
stmt 结束后再 append buffer
```

这不是现场五分钟改动。

## 10. 新增 `do while`

比 `for` 更适合现场修改。

源码：

```l26
do stmt while (expr);
```

涉及文件：

```text
lexer.l
parser.y
```

### 修改 `lexer.l`

```lex
"do"        { return DO; }
```

### 修改 `parser.y`

token：

```yacc
%token DO
```

`stmt` 加：

```yacc
| do_while_stmt
```

新增：

```yacc
do_while_stmt
    : DO
        { $<ctrl>$.addr = current_addr(); }
      stmt WHILE '(' expr ')' ';'
        {
            if ($6.type != T_BOOL) type_error("do-while condition must be bool");
            int jpc_end = emit(JPC, 0, 0);
            emit(JMP, 0, $<ctrl>2.addr);
            patch(jpc_end, current_addr());
        }
    ;
```

注意：这里的逻辑是：

```text
执行 stmt
计算条件
如果条件 false，JPC 到结束
否则 JMP 回开头
```

也可以反过来用 `OPR_NOT` 后 `JPC`。

## 11. 改 `write` 支持多个表达式

例子：

```l26
write x, y, z;
```

涉及文件：

```text
parser.y
```

lexer 已经支持 `,`。

### 修改思路

新增：

```yacc
write_list
    : expr
        {
            if ($1.type == T_SET) {
                if ($1.level >= 0) emit(WRITES, $1.level, $1.offset);
                else emit(WRITET, 0, 0);
            } else {
                emit(WRITE, 0, 0);
            }
        }
    | write_list ',' expr
        {
            if ($3.type == T_SET) {
                if ($3.level >= 0) emit(WRITES, $3.level, $3.offset);
                else emit(WRITET, 0, 0);
            } else {
                emit(WRITE, 0, 0);
            }
        }
    ;
```

然后把：

```yacc
WRITE_KW expr ';'
```

改成：

```yacc
WRITE_KW write_list ';'
```

需要给 `write_list` 加 `%type` 吗？

不需要，如果它不传语义值。

### 风险

这会和集合字面量里的逗号无直接冲突，因为集合字面量在 `{ ... }` 内。

## 12. 改 `set` 输出格式

当前：

```text
{1, 2, 3}
```

如果要求输出：

```text
[1,2,3]
```

只改 `pvm.c` 的 `print_set`。

位置：

```c
static void print_set(int *base)
```

把：

```c
printf("{");
...
if (i) printf(", ");
...
printf("}");
```

改成：

```c
printf("[");
...
if (i) printf(",");
...
printf("]");
```

不影响 parser、P-code、集合存储。

## 13. 改集合打印不排序

当前 `print_set` 会：

```c
qsort(tmp, cnt, sizeof(int), cmp_int);
```

如果要求按插入顺序输出，删除 `qsort` 这行即可。

风险：测试预期输出可能要改。

## 14. 新增注释语法

当前支持：

```text
// line comment
/* block comment */
```

如果要求支持 Python 风格 `# comment`，只改 `lexer.l`：

```lex
"#"[^\n]*          { /* hash line comment */ }
```

放在注释规则附近。

## 15. 新增小于等于等 token 时的原则

如果新增多字符运算符，例如：

```text
=>  -> ARROW
<=  -> LE
```

一定放在单字符规则之前。

原因：

```lex
[+\-*/<>!(){};,|=]  { return yytext[0]; }
```

会吃掉单字符。

Flex 虽然优先最长匹配，但多字符 token 必须有单独规则才能返回专门 token。

## 16. 修改类型检查规则

大多数类型限制都在 `parser.y`。

常见位置：

```text
assign_stmt     赋值左右类型一致
if_head         if 条件必须 bool
while_stmt      while 条件必须 bool
io_stmt         read/write
set_op_stmt     add/remove
expr            运算符类型规则
comp_head       推导式源必须 set
```

如果助教要求“允许某个类型组合”，优先只改 parser。

例如允许 `int == bool`：

```yacc
| expr EQ_OP expr
```

中当前要求：

```c
$1.type == $3.type
```

可以放宽。

但要能解释清楚运行时语义：

```text
bool 在本项目里就是 0/1
```

## 17. 遇到 Bison warning 怎么处理

如果修改 `parser.y` 后出现 conflict：

```bash
bison -d -Wcounterexamples -o parser.tab.c parser.y
```

重点看：

```text
shift/reduce
reduce/reduce
```

常用修复手段：

1. 给运算符加优先级。
2. 把容易冲突的语法拆成更具体的非终结符。
3. 避免两个规则都能识别同一段 token。
4. 对 dangling else 使用 `%prec NO_ELSE`。

表达式冲突优先改：

```yacc
%left
%right
%nonassoc
```

语句冲突优先改：

```text
stmt 分类
中间非终结符
```

## 18. 现场修改后最小自测模板

新增功能后建议建临时文件：

```bash
tmp_feature.l26
```

先看 P-code：

```bash
./l26c -p tmp_feature.l26
```

再运行：

```bash
./l26c tmp_feature.l26
```

最后跑全量：

```bash
make test
```

如果是错误语义，测试方式：

```bash
./l26c tmp_error.l26
echo $?
```

期望：

```text
返回码非 0
stderr 有明确错误
```

## 19. 最容易被问到的解释

### 为什么集合变量不直接压栈？

因为 `int/bool` 是一个 word，集合是 201 个 word。

普通表达式结果可以压栈，集合表达式要么携带地址，要么放进 `temp_set`。

### 为什么 `set == set` 要限制为变量？

当前 `SET_EQL` 需要两个稳定集合地址。

集合字面量、union、inter、comprehension 都写入同一个 `temp_set`，不能安全同时表示两个临时集合。

### 为什么 `union/inter` 只支持 `ID union ID`？

这是为了简化运行时地址编码。

当前指令 `SET_UNION/SET_INTER` 接收两个集合变量地址，不接收任意集合表达式。

### 为什么 `for(init;cond;post)` 不适合现场快速加？

parser 当前是一遍归约即时生成代码。

`post` 出现在循环体之前被解析，但运行时应该在循环体之后执行。

要正确实现需要缓存 `post` 的 P-code 或调整语法设计。

### 为什么 block 为空也分配 1 个 word？

parser 中：

```c
sz > 0 ? sz : 1
```

让每个运行时 frame 都有稳定空间，避免空 frame 带来的边界问题。

## 20. 最安全的现场改动优先级

如果助教让自由加一个小功能，优先选：

```text
1. clear s;        只加关键字和 parser，复用 SET_NEW
2. size(s)         只加关键字和 parser，复用 LOD
3. set != set      只改 parser，复用 SET_EQL + OPR_NOT
4. # 注释          只改 lexer.l
5. 改集合输出格式  只改 pvm.c
```

不建议现场主动选择：

```text
完整 for(init;cond;post)
任意集合表达式嵌套 union/inter
两个临时集合直接比较
短路 && / ||
函数调用
数组
```

这些都需要更大范围的代码生成设计。
