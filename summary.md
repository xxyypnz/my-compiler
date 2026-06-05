# 项目复盘总览

这个文件是给自己看的，不是展示文档。

用途：隔一段时间忘了项目后，先读这个文件，快速恢复对整个 L26 编译器的全局理解，并知道需要查任何内容时去哪里找。

## 1. L26 编译器的理论链路

这个项目本质上是：

```text
一个小语言 L26
-> 编译成类 P-Code
-> 再由项目内置虚拟机执行
```

整体链路：

```text
源代码 .l26
  |
  v
词法分析 lexer.l
  |
  | 把字符流切成 token
  v
语法分析 parser.y
  |
  | 根据 token 识别程序结构
  | 同时做类型检查、符号表维护、P-Code 生成
  v
P-Code 指令数组 code[]
  |
  v
虚拟机 pvm.c
  |
  | 按指令操作栈、变量帧、集合内存
  v
程序输出
```

更直观一点：

```text
lexer 负责“看见了什么词”
parser 负责“这些词组成什么语法，以及该生成什么代码”
symtab 负责“变量是什么类型，在哪里”
codegen 负责“把指令写进 code[]”
pvm 负责“真正执行 code[]”
main 负责“把这些阶段串起来”
```

## 2. 一次运行实际发生什么

命令：

```bash
./l26c tests/test3.l26
```

大致流程：

```text
main.c
  打开 tests/test3.l26
  调用 yyparse()

parser.y
  需要 token 时调用 yylex()

lexer.l
  从 yyin 读取源码
  返回 INT_KW / ID / NUM / IF / SET_KW 等 token

parser.y
  识别 block、decl、stmt、expr
  声明变量时调用 sym_declare()
  使用变量时调用 sym_lookup()
  归约语法时调用 emit() 生成 P-Code
  if/while 等跳转用 patch() 回填地址

codegen.c
  把所有 P-Code 存入 code[]

main.c
  调用 print_pcode()
  如果不是 -p，就调用 pvm_run()

pvm.c
  从 pc=0 开始执行 code[]
  使用 stack[] 保存变量和临时值
  使用 frame_base[] 管理嵌套作用域
  遇到 WRITE/WRITES 输出结果
```

## 3. L26 当前支持什么

基础类型：

```text
int
bool
set
```

语句：

```text
变量声明
赋值
if / else
while
read
write
嵌套 block
add / remove 集合操作
```

普通表达式：

```text
+  -  *  /
一元负号
<  <=  >  >=  ==  !=
&&  ||  !
true / false
括号
```

集合功能：

```text
集合字面量：{1, 2, 3}
空集合：{}
成员测试：x in s
空集测试：isempty(s)
并集：s1 union s2
交集：s1 inter s2
集合相等：s1 == s2
集合推导式：{ x * 2 | x in s if x > 2 }
```

当前重要限制：

```text
read 只允许 int
set != set 当前不支持
set == set 只允许两个集合变量，不允许临时集合比较
union/inter 当前只支持 ID union ID、ID inter ID
集合最多 200 个元素
```

## 4. 每个核心文件负责什么

### `main.c`

程序入口。

负责命令行参数、打开源码文件、调用 parser、打印 P-Code、启动虚拟机。

### `Makefile`

构建和测试脚本。

负责调用 gcc、flex、bison，生成最终可执行文件 `l26c`，并提供 `make test` 等命令。

### `pcode.h`

编译器和虚拟机之间的“指令协议”。

定义：

```text
指令类型
OPR 子操作码
SET_SIZE / MAX_CODE / MAX_STACK
Instruction 结构
集合双地址编码宏
```

### `codegen.c` / `codegen.h`

P-Code 生成模块。

负责：

```text
维护 code[]
维护 code_len
emit 新指令
patch 跳转地址
打印 P-Code
```

### `symtab.c` / `symtab.h`

符号表和作用域模块。

负责：

```text
进入作用域
退出作用域
声明变量
查找变量
记录变量类型、层级、偏移
计算变量占用宽度
```

### `lexer.l`

Flex 词法分析文件。

负责把源码字符切成 token，并把 `ID`、`NUM` 等值通过 `yylval` 传给 parser。

### `parser.y`

Bison 语法分析文件，也是项目最核心的文件。

负责：

```text
定义语法
接收 token
做类型检查
维护符号表
生成 P-Code
处理 if/while 跳转回填
处理集合语义
```

### `pvm.c` / `pvm.h`

类 P-Code 虚拟机。

负责执行 `code[]`。

内部维护：

```text
stack[]
sp
pc
frame_base[]
frame_top
temp_set
```

执行普通指令、控制流、I/O、集合运行时操作。

## 5. 当前目录结构

```text
.
├── Makefile
├── README.md
├── GUIDE.md
├── REQUIREMENT.md
├── main.c
├── pcode.h
├── codegen.c
├── codegen.h
├── symtab.c
├── symtab.h
├── lexer.l
├── parser.y
├── pvm.c
├── pvm.h
├── tests/
│   ├── test1.l26
│   ├── test2.l26
│   ├── test3.l26
│   ├── test4.l26
│   ├── test5.l26
│   └── errors/
├── docs/
│   ├── 设计说明.md
│   ├── 设计说明.pdf
│   ├── 测试结果.md
│   ├── 测试结果截图.svg
│   └── 完整测试记录.txt
├── scripts/
│   ├── run_error_tests.sh
│   └── generate_submission_assets.py
├── submission/
│   ├── 提交说明.md
│   ├── 程序/
│   └── 文档/
├── step1.md ... step10.md
├── preparation.md
└── summary.md
```

生成文件也可能出现在根目录：

```text
l26c
lexer.c
parser.tab.c
parser.tab.h
*.o
```

这些是构建产物，不是手写源码。

## 6. 怎么构建和运行

构建：

```bash
make
```

清理：

```bash
make clean
```

运行一个程序：

```bash
./l26c tests/test1.l26
```

只打印 P-Code，不执行：

```bash
./l26c -p tests/test1.l26
```

单步执行：

```bash
./l26c -s tests/test1.l26
```

运行正确测试：

```bash
make test
```

运行错误测试：

```bash
make test-errors
```

运行全部测试：

```bash
make test-all
```

## 7. 测试文件分别看什么

```text
tests/test1.l26
  int、read/write、while、if/else、算术、比较
  示例：阶乘

tests/test2.l26
  set 基础操作
  包括 add/remove/in/union/inter/isempty/write set

tests/test3.l26
  嵌套作用域和变量遮蔽
  重点看 level、offset、frame_base

tests/test4.l26
  加分项
  set equality 和 set comprehension

tests/test5.l26
  综合测试
  bool、逻辑表达式、while、set、comprehension、inter

tests/errors/
  错误测试
  覆盖重复声明、未声明变量、类型错误、非法 read、非法 set 操作、除零、set != set 等
```

## 8. 文档各自作用

### 展示/提交相关

```text
README.md
  项目介绍、构建运行、语言文法、设计概述、测试结果

GUIDE.md
  使用说明

REQUIREMENT.md
  需求或作业要求整理

docs/设计说明.md
  更正式的设计说明

docs/测试结果.md
  测试输出记录

docs/完整测试记录.txt
  更完整的测试日志

submission/
  提交打包目录
```

### 自己学习源码用

```text
step1.md
  项目总览和阅读路线

step2.md
  main.c + Makefile + pcode.h

step3.md
  codegen.c/h

step4.md
  symtab.c/h

step5.md
  lexer.l

step6.md
  parser.y 总览、语义值、主干语句、控制流

step7.md
  parser.y 表达式与集合语义

step8.md
  pvm.c/h 普通虚拟机执行模型

step9.md
  pvm.c 集合运行时

step10.md
  端到端串联整个项目

preparation.md
  助教现场要求改功能时的预案

summary.md
  当前这个总索引，忘了项目时先看
```

## 9. 忘了以后应该怎么重新进入项目

最快路径：

```text
1. 先读 summary.md
2. 跑 make test，确认项目当前是通的
3. 用 ./l26c -p tests/test3.l26 看一遍 P-Code
4. 如果忘了整体链路，读 step10.md
5. 如果忘了某个文件，按 step2-step9 查
6. 如果要现场改代码，读 preparation.md
```

推荐复习顺序：

```text
summary.md
step10.md
step2.md
step5.md
step6.md
step7.md
step8.md
step9.md
preparation.md
```

如果只剩 10 分钟：

```text
summary.md
preparation.md
tests/test3.l26
tests/test4.l26
```

## 10. 常见问题应该去哪找

### 构建失败

先看：

```text
Makefile
```

再看 bison/flex 生成文件：

```text
parser.y
lexer.l
```

### token 不识别

看：

```text
lexer.l
```

关键词要在 `ID` 规则之前。

### 语法不接受

看：

```text
parser.y
```

重点查：

```text
%token
%type
优先级声明
grammar rules
```

### 类型检查不对

看：

```text
parser.y
```

重点查：

```text
assign_stmt
if_head
while_stmt
io_stmt
set_op_stmt
expr
comp_head
```

### 变量作用域不对

看：

```text
symtab.c
parser.y 的 block / comp_head
```

关注：

```text
scope_enter
scope_exit
sym_declare
sym_lookup
level
offset
```

### P-Code 生成不对

看：

```text
parser.y
codegen.c
```

关注：

```text
emit
patch
current_addr
```

### 程序运行结果不对

先用：

```bash
./l26c -p 文件.l26
```

看 P-Code。

如果 P-Code 已经错，查 `parser.y`。

如果 P-Code 对但运行错，查 `pvm.c`。

### 集合相关错误

优先看：

```text
parser.y 的集合表达式规则
pvm.c 的 SET_* 指令
pcode.h 的 SET_SIZE 和 ENCODE2
```

## 11. 关键概念速记

### token

lexer 识别出的最小语法单位。

例子：

```text
INT_KW
ID
NUM
IF
SET_KW
LE
EQ_OP
```

### yylval

lexer 给 parser 传 token 附加值的变量。

```text
NUM 使用 yylval.ival
ID 使用 yylval.sval
```

### VarType

变量类型：

```text
T_INT
T_BOOL
T_SET
```

### level / offset

符号表记录变量运行时位置。

```text
level  变量声明在哪一层作用域
offset 变量在该 frame 里的偏移
```

parser 生成代码时计算：

```text
ld = 当前 level - 变量 level
```

PVM 执行时用：

```text
frame_base[frame_top - 1 - ld] + offset
```

找到变量地址。

### P-Code

中间代码。

每条指令结构：

```c
op, l, a
```

### INT 指令

不是 int 类型。

它负责运行时分配/释放 frame：

```text
INT 0 n    分配 n 个 word
INT 0 -n   释放 n 个 word
```

### JPC

条件跳转。

```text
弹出栈顶
如果为 0，就跳到目标地址
```

### patch

先生成未知目标的跳转：

```text
JPC 0 0
```

等知道目标地址后再改：

```text
JPC 0 target
```

### 集合内存布局

每个 set 占 201 个 int：

```text
base[0] = count
base[1..count] = elements
```

最多 200 个元素。

### temp_set

集合临时结果缓冲。

这些结果都会放进去：

```text
集合字面量
union
inter
comprehension
```

赋值时用 `SET_COPY` 复制到目标集合变量。

## 12. 现场解释项目时的最短版本

可以这样说：

```text
这个项目用 Flex/Bison 实现了 L26 小语言编译器。
lexer.l 把源码切成 token，parser.y 识别语法并做类型检查，同时调用 symtab 管理作用域和变量地址，调用 codegen 生成类 P-Code。
生成的 P-Code 存在全局 code[] 里，main.c 打印后交给 pvm.c 执行。
PVM 是栈式虚拟机，用 stack[] 存变量和临时值，用 frame_base[] 支持嵌套作用域。
set 类型在运行时固定占 201 个 word，第 0 个 word 是元素个数，后面是元素。
集合字面量、并集、交集和推导式的临时结果统一放在 temp_set，再通过 SET_COPY 写回变量。
```

## 13. 如果要修改功能，先看这里

最可能现场被要求改的功能，以及入口：

```text
新增关键字
  lexer.l 加规则
  parser.y 加 %token 和语法

新增普通运算符
  lexer.l
  parser.y
  pcode.h
  pvm.c

新增集合操作
  parser.y
  pcode.h
  pvm.c

修改类型限制
  parser.y

修改集合输出或运行时行为
  pvm.c

修改命令行参数
  main.c

修改测试
  Makefile
  tests/
  scripts/run_error_tests.sh
```

详细预案在：

```text
preparation.md
```

## 14. 现在最重要的几个文件

如果时间很少，只记这几个：

```text
parser.y
  最大、最核心。语法、类型检查、代码生成都在这里。

pvm.c
  运行结果是否正确主要看这里。

symtab.c
  变量作用域、遮蔽、level/offset 看这里。

pcode.h
  parser 和 pvm 的共同协议。

lexer.l
  token 和关键字看这里。
```

## 15. 项目闭环确认

当前主线文档已经覆盖完整流程：

```text
step1  总览
step2  main / Makefile / pcode
step3  codegen
step4  symtab
step5  lexer
step6  parser 主干
step7  parser 表达式和集合
step8  PVM 普通执行
step9  PVM 集合运行时
step10 端到端串联
```

读完 `summary.md` 后，如果还想完全恢复细节，就按上面顺序回看对应 step。
