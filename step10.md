# Step 10：端到端串联整个项目

本阶段不再读单个文件，而是把整个项目连起来。

目标：看懂一个 `.l26` 程序如何经过：

```text
源码
-> lexer
-> parser
-> symtab
-> codegen
-> P-code
-> PVM
-> 输出
```

到这里，项目主线就讲完了。

## Step 9 承接

Step 9 读完 PVM 集合运行时后，所有核心文件都已经覆盖：

```text
main.c
Makefile
pcode.h
codegen.c/h
symtab.c/h
lexer.l
parser.y
pvm.c/h
```

最后还要回答：

1. 一次运行从 `main` 开始如何流过所有模块？
2. token、符号表、P-code、运行时栈之间如何衔接？
3. 一个有嵌套作用域和集合的程序如何完整执行？
4. 当前测试文件分别覆盖哪些语言能力？
5. 读完这些 step 后，应该能独立定位哪类问题？

## 1. 项目文件职责总表

```text
Makefile      定义构建、测试、清理规则
main.c        命令行入口，打开源码，调用 yyparse，打印/执行 P-code
pcode.h       定义指令、操作码、栈大小、集合大小
codegen.h/c   维护 code[]，提供 emit/patch/print_pcode
symtab.h/c    维护作用域和变量符号表
lexer.l       把字符流切成 token
parser.y      语法分析、类型检查、符号表操作、P-code 生成
pvm.h/c       执行 P-code
tests/        正确和错误测试用例
docs/         设计说明和测试记录
```

最核心的依赖方向：

```text
main
  -> yyparse
      -> yylex
      -> symtab
      -> codegen
  -> print_pcode
  -> pvm_run
      -> code[]
```

## 2. 一次运行从命令开始

命令：

```bash
./l26c tests/test3.l26
```

`main.c` 处理参数：

```text
-s  单步执行
-p  只打印 P-code，不运行
```

然后：

```c
yyin = fopen(filename, "r");
yyparse();
print_pcode();
pvm_run(step_mode);
```

所以完整阶段是：

```text
打开源码文件
调用 parser
parser 自动调用 lexer
parser 生成 P-code
打印 P-code
PVM 执行 P-code
```

## 3. lexer 阶段

源码片段：

```l26
{
    int x;
    set s;
    x = 10;
    s = {1, 2};
}
```

`lexer.l` 输出 token 流：

```text
'{'
INT_KW ID ';'
SET_KW ID ';'
ID '=' NUM ';'
ID '=' '{' NUM ',' NUM '}' ';'
'}'
```

其中带语义值的 token：

```text
ID("x")
ID("s")
NUM(10)
NUM(1)
NUM(2)
```

这些值通过：

```text
yylval.sval
yylval.ival
```

传给 `parser.y`。

## 4. parser 阶段

parser 从顶层开始：

```yacc
program : block
```

block 进入时：

```text
scope_enter
emit INT 0 0 placeholder
```

声明阶段：

```l26
int x;
set s;
```

会执行：

```text
sym_declare("x", T_INT)
sym_declare("s", T_SET)
emit SET_NEW addr(s)
```

声明结束后：

```text
patch INT frame_size
```

语句阶段：

```l26
x = 10;
s = {1, 2};
```

会执行：

```text
NUM -> emit LIT 0 10
assign -> emit STO addr(x)

set literal -> emit LIT 0 1, LIT 0 2, SET_LIT 0 2
set assign -> emit SET_COPY addr(s)
```

block 退出时：

```text
scope_exit
emit INT 0 -frame_size
```

program 结束：

```text
emit OPR 0 OPR_RET
```

## 5. 符号表变化

以：

```l26
{
    int x;
    set s;
}
```

为例。

进入外层 block：

```text
level = 1
frame_size = 0
```

声明 `x`：

```text
name = "x"
type = T_INT
level = 1
offset = 0
width = 1
frame_size = 1
```

声明 `s`：

```text
name = "s"
type = T_SET
level = 1
offset = 1
width = 201
frame_size = 202
```

退出 block：

```text
scope_exit
删除本层符号
回到父作用域
```

## 6. P-code 生成结果示例

对 `tests/test3.l26`，只打印 P-code：

```bash
./l26c -p tests/test3.l26
```

关键输出是：

```text
0   INT       0    202
1   SET_NEW   0      1
2   LIT       0     10
3   STO       0      0
4   LIT       0      1
5   LIT       0      2
6   SET_LIT   0      2
7   SET_COPY  0      1
8   INT       0    201
9   SET_NEW   0      0
10  LIT       0      5
11  LIT       0      6
12  SET_LIT   0      2
13  SET_COPY  0      0
14  LIT       0      7
15  SET_ADD   0      0
16  WRITES    0      0
17  WRITES    1      1
18  INT       0   -201
19  LOD       0      0
20  WRITE     0      0
21  INT       0   -202
22  OPR       0      0
```

这段程序测试嵌套作用域和变量遮蔽。

## 7. 解释 `test3.l26`

源码核心：

```l26
{
    int x;
    set s;
    x = 10;
    s = {1, 2};

    {
        set x;
        x = {5, 6};
        add x 7;
        write x;
        write s;
    }

    write x;
}
```

外层：

```text
x 是 int，offset 0
s 是 set，offset 1
frame_size = 202
```

内层：

```text
set x 遮蔽外层 int x
内层 x 是 set，offset 0
frame_size = 201
```

所以：

```text
WRITES 0 0
```

打印内层集合 `x`。

```text
WRITES 1 1
```

打印外层集合 `s`。

这里 `1` 是层差：

```text
从内层访问外层
```

内层退出后：

```text
LOD 0 0
WRITE
```

访问的是外层 `int x`，值仍然是 `10`。

## 8. PVM 执行这段 P-code

先执行：

```text
INT 0 202
```

创建外层 frame。

然后：

```text
SET_NEW 0 1
```

初始化外层 `s`。

```text
LIT 0 10
STO 0 0
```

把 `10` 存进外层 `x`。

```text
LIT 0 1
LIT 0 2
SET_LIT 0 2
SET_COPY 0 1
```

构造 `{1, 2}` 到 `temp_set`，再复制给外层 `s`。

进入内层：

```text
INT 0 201
SET_NEW 0 0
```

创建内层 frame，初始化内层集合 `x`。

```text
LIT 0 5
LIT 0 6
SET_LIT 0 2
SET_COPY 0 0
LIT 0 7
SET_ADD 0 0
```

内层 `x` 变成：

```text
{5, 6, 7}
```

然后：

```text
WRITES 0 0
```

打印内层 `x`。

```text
WRITES 1 1
```

打印外层 `s`。

退出内层：

```text
INT 0 -201
```

最后：

```text
LOD 0 0
WRITE
```

打印外层 `x = 10`。

## 9. 各模块如何交接数据

### lexer 到 parser

通过：

```text
return TOKEN
yylval
```

交接。

例子：

```text
lexer: ID("x")
parser: $1 或 $2 读取 "x"
```

### parser 到 symtab

通过：

```text
sym_declare
sym_lookup
scope_enter
scope_exit
```

交接。

parser 负责决定什么时候声明、什么时候查找。

symtab 负责回答变量的：

```text
type / level / offset
```

### parser 到 codegen

通过：

```text
emit
patch
current_addr
```

交接。

parser 每归约一部分语法，就生成对应 P-code。

### codegen 到 PVM

通过全局：

```text
code[]
code_len
```

交接。

`codegen.c` 写入，`pvm.c` 读取执行。

### parser 到 PVM 的间接约定

parser 和 PVM 之间还有很多语义约定。

例如：

```text
LIT 把常量压栈
STO 从栈顶取值存变量
JPC 弹出 bool，0 表示假
SET_LIT 把栈顶 n 个 int 变成 temp_set
SET_COPY 把 temp_set 复制到目标集合
```

这些约定必须两边一致。

## 10. 正确测试覆盖

### `tests/test1.l26`

覆盖：

```text
int 变量
read/write
while
if/else
算术表达式
比较表达式
```

核心场景：计算阶乘。

### `tests/test2.l26`

覆盖：

```text
set 声明
集合字面量
write set
in
add
remove
union
inter
isempty
```

核心场景：集合基本操作。

### `tests/test3.l26`

覆盖：

```text
嵌套 block
变量遮蔽
跨层访问变量
set 和 int 同名但不同作用域
```

核心场景：符号表和 frame 层差。

### `tests/test4.l26`

覆盖：

```text
set equality
set comprehension
集合相等忽略顺序
```

核心场景：

```l26
s1 == s2
{ x*2 | x in s1 if x > 2 }
```

### `tests/test5.l26`

覆盖：

```text
综合压力测试
bool 变量
逻辑表达式
while + set add
comprehension
inter
```

核心场景：多种语言特性组合使用。

## 11. 错误测试覆盖

`tests/errors/` 里是负向测试。

### `duplicate_decl.l26`

覆盖：

```text
同一作用域重复声明
```

对应：

```text
sym_declare 返回 NULL
```

### `undeclared_var.l26`

覆盖：

```text
使用未声明变量
```

对应：

```text
sym_lookup 返回 NULL
```

### `type_mismatch_assign.l26`

覆盖：

```text
赋值左右类型不一致
```

对应：

```text
assign_stmt 中 s->type != expr.type
```

### `read_set.l26`

覆盖：

```text
read 只能读 int 变量
```

对应：

```text
read requires int variable
```

### `add_non_set.l26`

覆盖：

```text
add 的目标必须是 set 变量
```

### `division_by_zero.l26`

覆盖：

```text
运行时除零错误
```

对应：

```text
PVM 的 OPR_DIV
```

### `set_literal_eq.l26`

覆盖：

```text
集合相等只允许集合变量
```

不允许：

```l26
s == {1, 2}
```

### `set_ne.l26`

覆盖：

```text
set != set 不支持
```

对应：

```text
'!=' is not supported for sets
```

## 12. 构建和测试链路

构建：

```bash
make
```

主要步骤：

```text
编译 symtab.c
编译 codegen.c
编译 pvm.c
编译 main.c
bison 生成 parser.tab.c/parser.tab.h
flex 生成 lexer.c
编译 lexer.c
编译 parser.tab.c
链接 l26c
```

测试：

```bash
make test
```

一般会跑：

```text
tests/test*.l26
tests/errors/*.l26
```

正确测试期望成功运行并输出预期结果。

错误测试期望失败，并给出对应错误。

## 13. 从 bug 定位到文件

如果 token 不认识：

```text
看 lexer.l
```

如果语法不接受：

```text
看 parser.y 的 grammar rules 和优先级
```

如果类型错误不对：

```text
看 parser.y 的语义动作
```

如果变量作用域、遮蔽、offset 错：

```text
看 symtab.c/h
```

如果 P-code 地址或 patch 错：

```text
看 parser.y 的 emit/patch 位置
看 codegen.c 的 patch/current_addr
```

如果运行时栈、跳转、变量读写错：

```text
看 pvm.c 的普通指令
```

如果集合结果错：

```text
看 parser.y 的集合表达式生成
看 pvm.c 的 SET_* 指令
```

如果构建、测试命令错：

```text
看 Makefile
```

## 14. 你现在应该能独立追踪的例子

### 普通赋值

源码：

```l26
x = 1 + 2;
```

你应该能追踪：

```text
lexer: ID '=' NUM '+' NUM ';'
parser: assign_stmt + expr
symtab: 查找 x
codegen: LIT, LIT, OPR_ADD, STO
pvm: 压栈、相加、存变量
```

### 条件语句

源码：

```l26
if (x > 0) write x;
```

你应该能追踪：

```text
expr 生成比较结果
if_head 生成 JPC 占位
then stmt 生成 WRITE
patch JPC 到 if 结束地址
PVM 根据栈顶 bool 决定是否跳转
```

### 集合赋值

源码：

```l26
s = {1, 2, 3};
```

你应该能追踪：

```text
ast_list 构建元素 AST
emit_ast_expr 生成 LIT
SET_LIT 构造 temp_set
SET_COPY 复制到 s
```

### 集合相等

源码：

```l26
if (s1 == s2) write 1;
```

你应该能追踪：

```text
expr ID 保存集合地址
EQ_OP 检查两侧都是集合变量
SET_EQL 生成布尔值
JPC 使用布尔值控制分支
```

### 集合推导式

源码：

```l26
result = { x * 2 | x in s if x > 2 };
```

你应该能追踪：

```text
comp_head 打开隐藏作用域
__comp_tmp 保存结果
__comp_idx 保存索引
x 保存当前元素
SET_ELEM 取 s[idx]
filter false 时 JPC 跳过 body
body true 时 SET_ADD 加入结果
SET_UNION tmp,tmp 把结果放进 temp_set
SET_COPY 复制给 result
```

## 15. 全项目主线图

```text
Makefile
  |
  | builds
  v
l26c
  |
  v
main.c
  |
  | yyparse()
  v
parser.y  <--- yylex() <--- lexer.l
  |
  | sym_declare / sym_lookup
  v
symtab.c
  |
  | emit / patch
  v
codegen.c ----> code[]
  |
  | print_pcode()
  v
P-code listing
  |
  | pvm_run()
  v
pvm.c
  |
  v
program output
```

## 16. 学完后的阅读顺序

如果之后重新读源码，建议按这个顺序快速过一遍：

```text
1. main.c        入口
2. pcode.h       指令定义
3. codegen.c     code[] 如何生成
4. symtab.c      变量地址如何来
5. lexer.l       token 如何来
6. parser.y      token 如何变成 P-code
7. pvm.c         P-code 如何执行
8. tests/        功能如何验证
```

这个顺序和 Step 1 到 Step 10 基本一致。

## 17. 本阶段你要记住

1. 这个项目是一个完整小编译器加虚拟机。
2. lexer 只负责识别 token。
3. parser 是语法分析、类型检查、代码生成中心。
4. symtab 负责把变量名变成 `type/level/offset`。
5. codegen 负责维护 P-code 数组。
6. pcode.h 是 parser 和 PVM 的共同协议。
7. PVM 负责按协议执行指令。
8. 集合依赖固定内存布局和 `temp_set`。
9. 测试用例覆盖了普通语言特性、集合特性、bonus 和错误语义。
10. 调 bug 时先判断问题发生在哪个阶段，再去对应文件。

## 18. 到这里已经讲完的内容

```text
Step 1   项目总览
Step 2   main.c / Makefile / pcode.h
Step 3   codegen.c/h
Step 4   symtab.c/h
Step 5   lexer.l
Step 6   parser.y 总览和主干语句
Step 7   parser.y 表达式与集合语义
Step 8   pvm.c/h 普通虚拟机执行模型
Step 9   pvm.c 集合运行时
Step 10  端到端串联
```

主线已经完整闭环。
