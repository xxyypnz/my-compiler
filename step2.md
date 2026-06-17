# Step 2：入口、构建与指令模型

本阶段读三个文件：

```text
main.c
Makefile
pcode.h
```

目标：看懂程序如何启动、如何构建、P-Code 指令长什么样。

## Step 1 留下的问题

### 1. `./l26c tests/test1.l26` 从入口到输出经历哪些模块？

```text
main.c
  -> yyparse()
  -> lexer.l 提供 token
  -> parser.y 检查语法/语义并生成 P-Code
  -> codegen.c 打印 P-Code
  -> pvm.c 执行 P-Code
  -> 输出结果
```

### 2. `parser.y` 为什么是项目核心？

因为它同时负责：

```text
语法规则
类型检查
符号表操作
P-Code 生成
跳转地址回填
```

### 3. `emit` 和 `patch` 分别是干什么的？

- `emit(op, l, a)`：追加一条 P-Code。
- `patch(idx, target)`：修改之前生成的跳转指令目标地址。

### 4. 符号表为什么要记录 `level` 和 `offset`？

- `level`：变量在哪一层作用域。
- `offset`：变量在该层运行时栈帧里的位置。

虚拟机靠 `(level difference, offset)` 找变量。

### 5. 虚拟机执行 P-Code 时栈起什么作用？

栈保存：

- 表达式中间值
- 局部变量
- 块作用域的运行时帧
- 集合变量的连续内存块

## 1. `main.c`

`main.c` 是程序入口，只负责调度，不负责具体编译逻辑。

### 头文件

```c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "codegen.h"
#include "pvm.h"
```

含义：

- `stdio.h`：使用 `FILE`、`fopen`、`fprintf`、`printf`。
- `stdlib.h`：使用 `exit`。
- `string.h`：使用 `strcmp`。
- `codegen.h`：使用 `print_pcode()`。
- `pvm.h`：使用 `pvm_run()`。

### 外部变量和函数

```c
extern FILE *yyin;
extern int yyparse(void);
```

这两个来自 Flex/Bison：

- `yyin`：词法分析器读取的输入文件。
- `yyparse()`：Bison 生成的语法分析入口。

也就是说：

```c
yyin = fopen(filename, "r");
yyparse();
```

等价于“让 parser 从这个源文件开始编译”。

### `usage`

```c
static void usage(const char *prog)
```

参数：

- `prog`：程序名，通常是 `argv[0]`。

作用：

```text
打印用法
退出程序
```

输出内容：

```text
Usage: ./l26c [-s] [-p] <source.l26>
-s single-step mode
-p print P-Code only
```

`static` 表示这个函数只在 `main.c` 内部使用。

### `main`

```c
int main(int argc, char *argv[])
```

参数：

- `argc`：命令行参数数量。
- `argv`：命令行参数数组。

例如：

```bash
./l26c -s tests/test1.l26
```

对应：

```text
argc = 3
argv[0] = "./l26c"
argv[1] = "-s"
argv[2] = "tests/test1.l26"
```

### 三个局部变量

```c
int step_mode  = 0;
int print_only = 0;
const char *filename = NULL;
```

含义：

- `step_mode`：是否单步运行。`0` 表示否，`1` 表示是。
- `print_only`：是否只打印 P-Code 不执行。`0` 表示否，`1` 表示是。
- `filename`：源文件路径。

### 参数解析循环

```c
for (int i = 1; i < argc; i++)
```

从 `argv[1]` 开始读，因为 `argv[0]` 是程序名。

判断逻辑：

```c
if (strcmp(argv[i], "-s") == 0)
    step_mode = 1;
else if (strcmp(argv[i], "-p") == 0)
    print_only = 1;
else if (argv[i][0] == '-')
    usage(argv[0]);
else
    filename = argv[i];
```

解释：

- 遇到 `-s`：开启单步模式。
- 遇到 `-p`：只打印 P-Code。
- 遇到其他 `-xxx`：非法参数。
- 否则认为它是源文件名。

### 检查文件名

```c
if (!filename) usage(argv[0]);
```

如果没有源文件，就打印用法并退出。

### 打开源文件

```c
yyin = fopen(filename, "r");
```

把源文件打开，并交给 Flex/Bison 使用。

如果失败：

```c
fprintf(stderr, "error: cannot open '%s'\n", filename);
return 1;
```

`return 1` 表示程序异常结束。

### 调用 parser

```c
if (yyparse() != 0) {
    fclose(yyin);
    return 1;
}
```

`yyparse()` 会完成：

```text
词法分析
语法分析
类型检查
P-Code 生成
```

如果返回非 0，说明编译失败。

### 打印 P-Code

```c
print_pcode();
```

这个函数来自 `codegen.c`，会打印所有已生成指令。

### `-p` 模式

```c
if (print_only) return 0;
```

如果用户用了 `-p`，到这里就结束，不执行虚拟机。

### 执行虚拟机

```c
printf("=== Running ===\n");
pvm_run(step_mode);
printf("=== Done ===\n");
```

- `pvm_run(0)`：普通执行。
- `pvm_run(1)`：单步执行。

## 2. `Makefile`

`Makefile` 描述怎么从源码生成 `l26c`。

### 变量

```make
CC = gcc
```

编译器是 `gcc`。

```make
CFLAGS = -Wall -Wno-unused-function -g
```

编译参数：

- `-Wall`：打开常见 warning。
- `-Wno-unused-function`：忽略未使用函数 warning。
- `-g`：保留调试信息。

```make
TARGET = l26c
```

最终可执行文件名。

```make
SRCS = symtab.c codegen.c pvm.c main.c
```

手写 C 源文件列表。

```make
OBJS = $(SRCS:.c=.o) lexer.o parser.o
```

目标文件列表。

`$(SRCS:.c=.o)` 的意思是：

```text
symtab.c -> symtab.o
codegen.c -> codegen.o
pvm.c -> pvm.o
main.c -> main.o
```

再加上：

```text
lexer.o
parser.o
```

### 伪目标

```make
.PHONY: all clean test test-errors test-all
```

这些不是文件名，而是命令入口。

### 默认目标

```make
all: $(TARGET)
```

运行：

```bash
make
```

等价于构建 `l26c`。

### 链接目标

```make
$(TARGET): $(OBJS)
    $(CC) $(CFLAGS) -o $@ $^
```

变量：

- `$@`：当前目标，即 `l26c`。
- `$^`：所有依赖，即所有 `.o` 文件。

最终命令类似：

```bash
gcc -Wall -Wno-unused-function -g -o l26c symtab.o codegen.o pvm.o main.o lexer.o parser.o
```

### 生成 parser

```make
parser.tab.c parser.tab.h: parser.y
    bison -d -Wcounterexamples -o parser.tab.c parser.y
```

含义：

- 输入：`parser.y`
- 输出：`parser.tab.c` 和 `parser.tab.h`

参数：

- `-d`：生成头文件 `parser.tab.h`。
- `-Wcounterexamples`：如果有文法冲突，打印反例。
- `-o parser.tab.c`：指定输出 C 文件名。

### 生成 lexer

```make
lexer.c: lexer.l parser.tab.h
    flex -o lexer.c lexer.l
```

含义：

- 输入：`lexer.l`
- 输出：`lexer.c`
- 依赖 `parser.tab.h`，因为 lexer 需要 token 定义。

### 编译 lexer 和 parser

```make
lexer.o: lexer.c
    $(CC) $(CFLAGS) -c lexer.c -o lexer.o
```

```make
parser.o: parser.tab.c
    $(CC) $(CFLAGS) -c parser.tab.c -o parser.o
```

`-c` 表示只编译成 `.o`，不链接。

### 通用 C 编译规则

```make
%.o: %.c
    $(CC) $(CFLAGS) -c $< -o $@
```

变量：

- `$<`：第一个依赖文件，例如 `main.c`。
- `$@`：目标文件，例如 `main.o`。

### 清理

```make
clean:
    rm -f *.o lexer.c parser.tab.c parser.tab.h $(TARGET)
```

删除：

- `.o` 文件
- Flex 生成的 `lexer.c`
- Bison 生成的 `parser.tab.c/parser.tab.h`
- 可执行文件 `l26c`

### 正向测试

```make
test: all
```

表示测试前先确保 `l26c` 已构建。

`test1` 需要输入，所以用：

```make
printf "5\n" | ./$(TARGET) tests/test1.l26
```

后面依次运行 `test2` 到 `test5`。

### 负向测试

```make
test-errors: all
    ./scripts/run_error_tests.sh
```

运行错误用例，要求它们按预期失败。

### 完整测试

```make
test-all: test test-errors
```

先跑正向测试，再跑负向测试。

## 3. `pcode.h`

`pcode.h` 定义整个项目的指令模型。

### 头文件保护

```c
#ifndef PCODE_H
#define PCODE_H
...
#endif
```

作用：防止同一个头文件被重复包含。

### 常量

```c
#define SET_SIZE 201
```

集合占 201 个 `int`：

```text
1 个 count
200 个元素
```

```c
#define MAX_CODE 4096
```

最多生成 4096 条 P-Code。

```c
#define MAX_STACK 16384
```

虚拟机运行栈最大 16384 个整数。

### `OpCode`

```c
typedef enum {
    LIT = 0, LOD, STO, INT, JMP, JPC, OPR,
    READ, WRITE, WRITES, WRITET,
    SET_NEW, SET_LIT, SET_ADD, SET_REM,
    SET_IN, SET_EMPTY, SET_UNION, SET_INTER, SET_COPY,
    SET_EQL, SET_ELEM
} OpCode;
```

`OpCode` 是指令类型。

基础指令：

- `LIT`：压入常量。
- `LOD`：读取变量。
- `STO`：保存变量。
- `INT`：分配或释放栈帧。
- `JMP`：无条件跳转。
- `JPC`：条件跳转。
- `OPR`：算术、关系、逻辑操作。

IO 指令：

- `READ`：读整数。
- `WRITE`：输出整数或 bool。
- `WRITES`：输出集合变量。
- `WRITET`：输出临时集合。

集合指令：

- `SET_NEW`：初始化空集合。
- `SET_LIT`：构造集合字面量。
- `SET_ADD`：添加元素。
- `SET_REM`：删除元素。
- `SET_IN`：成员判断。
- `SET_EMPTY`：空集判断。
- `SET_UNION`：并集。
- `SET_INTER`：交集。
- `SET_COPY`：复制临时集合到变量。
- `SET_EQL`：集合相等。
- `SET_ELEM`：按索引取集合元素。

### `Instruction`

```c
typedef struct {
    OpCode op;
    int l;
    int a;
} Instruction;
```

每条 P-Code 指令由三个字段组成：

- `op`：操作码。
- `l`：层差，或集合双操作数编码的一部分。
- `a`：地址、偏移、常量、跳转目标或另一个编码参数。

例子：

```text
LIT 0 5
```

表示：

```text
op = LIT
l = 0
a = 5
```

例子：

```text
LOD 1 3
```

表示读取外层 1 层、偏移 3 的变量。

### OPR 子操作

```c
#define OPR_RET 0
#define OPR_NEG 1
#define OPR_ADD 2
...
```

`OPR` 是一个大类，具体运算由 `a` 字段决定。

例如：

```text
OPR 0 2
```

因为：

```c
#define OPR_ADD 2
```

所以表示加法。

常见编码：

- `OPR_RET`：返回，结束程序。
- `OPR_NEG`：取负。
- `OPR_ADD`：加法。
- `OPR_SUB`：减法。
- `OPR_MUL`：乘法。
- `OPR_DIV`：除法。
- `OPR_EQ`：相等。
- `OPR_NEQ`：不等。
- `OPR_LT`：小于。
- `OPR_GEQ`：大于等于。
- `OPR_GT`：大于。
- `OPR_LEQ`：小于等于。
- `OPR_NOT`：逻辑非。
- `OPR_AND`：逻辑与。
- `OPR_OR`：逻辑或。

### 双集合操作编码

```c
#define ENCODE2(ld, off) ((ld) * 10000 + (off))
#define DECODE_LD(enc)   ((enc) / 10000)
#define DECODE_OFF(enc)  ((enc) % 10000)
```

问题：`Instruction` 只有 `l` 和 `a` 两个整数，但 `SET_UNION` 需要两个集合地址：

```text
集合1: ld1, off1
集合2: ld2, off2
```

解决方式：

```text
l = ENCODE2(ld1, off1)
a = ENCODE2(ld2, off2)
```

运行时再拆开：

```text
ld  = DECODE_LD(encoded)
off = DECODE_OFF(encoded)
```

例子：

```c
ENCODE2(1, 203) = 10203
```

拆回：

```c
DECODE_LD(10203)  = 1
DECODE_OFF(10203) = 203
```

### 全局 P-Code 数组声明

```c
extern Instruction code[MAX_CODE];
extern int code_len;
```

含义：

- `code`：全局 P-Code 指令数组。
- `code_len`：当前已经生成多少条指令。

这里用 `extern`，说明变量不是在 `pcode.h` 里真正创建的。

真正定义在 `codegen.c`：

```c
Instruction code[MAX_CODE];
int code_len = 0;
```

## 本阶段小结

现在你应该能看懂：

```text
main.c     决定程序如何启动
Makefile   决定项目如何构建和测试
pcode.h    决定 P-Code 的数据格式
```

下一阶段建议读：

```text
codegen.c + codegen.h
```

因为它们直接使用 `pcode.h`，负责真正保存、回填和打印指令。

