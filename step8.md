# Step 8：`pvm.c/h` 普通虚拟机执行模型

本阶段读两个文件：

```text
pvm.h
pvm.c
```

但本阶段只读普通虚拟机部分：

```text
stack / sp / pc
frame_base / frame_top
LIT / LOD / STO / INT / JMP / JPC / OPR
READ / WRITE
single-step display
```

集合相关 `SET_*` 指令留到 Step 9。

## Step 7 承接

Step 7 看到 parser 会生成 P-code：

```text
LIT
LOD
STO
INT
JMP
JPC
OPR
READ
WRITE
SET_*
```

现在的问题是：

1. 这些指令真正在哪里执行？
2. `sp` 和 `pc` 分别是什么？
3. `INT 0 n` 为什么能分配局部变量空间？
4. `LOD l a` / `STO l a` 如何找到变量？
5. `JMP` / `JPC` 如何实现控制流？
6. `OPR_ADD` 等子操作码如何运行？
7. 单步模式 `-s` 是怎么打印当前指令的？

## 1. `pvm.h`

```c
#ifndef PVM_H
#define PVM_H

#include "pcode.h"

void pvm_run(int step_mode);  /* step_mode=1: single-step; 0: run */

#endif /* PVM_H */
```

`pvm.h` 很小，只对外暴露一个函数：

```c
void pvm_run(int step_mode);
```

参数：

- `step_mode = 0`：正常运行。
- `step_mode = 1`：单步运行。

`main.c` 里：

```c
pvm_run(step_mode);
```

会调用它执行 parser 生成的全局 `code[]`。

## 2. `pvm.c` 文件开头

```c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "pvm.h"
#include "codegen.h"
```

### `stdio.h`

用于：

```text
printf
fprintf
scanf
fgets
```

PVM 需要读输入、写输出、打印错误和单步信息。

### `stdlib.h`

用于：

```text
exit
qsort
```

### `string.h`

用于：

```text
memset
memcpy
```

本阶段主要用 `memset` 初始化栈。

### `pvm.h`

拿到：

```text
pcode.h
pvm_run 声明
```

### `codegen.h`

PVM 需要访问 code generator 维护的：

```text
code[]
code_len
```

这些定义最终来自 `pcode.h` 和 `codegen.c`。

## 3. PVM 全局状态

```c
static int stack[MAX_STACK];
static int sp;
static int pc;
```

### `stack`

```c
static int stack[MAX_STACK];
```

PVM 的运行时栈。

用途：

```text
保存表达式临时值
保存局部变量
保存集合变量的连续内存
```

`MAX_STACK` 在 `pcode.h`：

```c
#define MAX_STACK 16384
```

### `sp`

```c
static int sp;
```

stack pointer。

约定：

```text
sp 指向下一个可写位置
```

如果当前栈里有 3 个值，占用：

```text
stack[0], stack[1], stack[2]
```

那么：

```text
sp = 3
```

压栈：

```c
stack[sp++] = v;
```

弹栈：

```c
return stack[--sp];
```

### `pc`

```c
static int pc;
```

program counter。

表示下一条要执行的 P-code 指令地址。

执行循环里：

```c
Instruction ins = code[pc++];
```

先取当前指令，再让 `pc` 指向下一条。

跳转指令会直接改写：

```c
pc = ins.a;
```

## 4. 运行时帧

```c
static int frame_base[256];
static int frame_top;
```

parser 的每个 block 会生成：

```text
INT 0 n
...
INT 0 -n
```

PVM 用 `frame_base` 记录每个活跃 block 的起始地址。

### `frame_base`

```c
static int frame_base[256];
```

保存每一层作用域对应的局部变量基址。

例子：

```text
frame_base[0] = 外层 block 的起始 stack 下标
frame_base[1] = 内层 block 的起始 stack 下标
```

### `frame_top`

```c
static int frame_top;
```

活跃 frame 的数量。

如果当前有两个嵌套 block：

```text
frame_top = 2
```

当前 frame 是：

```text
frame_base[frame_top - 1]
```

## 5. `temp_set`

```c
static int temp_set[SET_SIZE];
```

这是集合临时结果缓冲区。

用于：

```text
集合字面量
union
inter
comprehension
```

本阶段只记住它存在，具体布局和指令到 Step 9 再讲。

## 6. `get_frame_base`

```c
static int get_frame_base(int ld) {
    int idx = frame_top - 1 - ld;
    if (idx < 0) {
        fprintf(stderr, "runtime error: invalid level difference %d\n", ld);
        exit(1);
    }
    return frame_base[idx];
}
```

作用：根据层差 `ld` 找到目标 frame 的基址。

### `ld`

```c
int ld
```

level difference。

parser 生成：

```c
ld = scope_level() - s->level;
```

含义：

```text
ld = 0  当前作用域
ld = 1  外层作用域
ld = 2  再外一层
```

### `idx`

```c
int idx = frame_top - 1 - ld;
```

当前 frame 下标是：

```text
frame_top - 1
```

所以往外找 `ld` 层就是：

```text
frame_top - 1 - ld
```

### 错误检查

```c
if (idx < 0)
```

如果层差超过现有 frame 数量，说明生成代码或运行状态有问题。

## 7. `var_addr`

```c
static int *var_addr(int ld, int off) {
    return &stack[get_frame_base(ld) + off];
}
```

作用：根据：

```text
层差 ld
偏移 off
```

找到变量实际地址。

公式：

```text
变量地址 = stack[目标 frame 基址 + offset]
```

例子：

```text
当前 frame base = 100
变量 offset = 3
变量地址 = &stack[103]
```

## 8. `set_base`

```c
static int *set_base(int ld, int off) {
    return var_addr(ld, off);
}
```

集合变量也是存在 stack 里的局部变量区域。

区别是：

```text
int/bool 占 1 个 word
set 占 SET_SIZE 个 word
```

所以集合基址同样通过 `var_addr` 取得。

集合细节 Step 9 再讲。

## 9. `push`

```c
static void push(int v) {
    if (sp >= MAX_STACK) { fprintf(stderr, "runtime error: stack overflow\n"); exit(1); }
    stack[sp++] = v;
}
```

压栈函数。

参数：

- `v`：要压入的整数。

逻辑：

1. 检查是否超过 `MAX_STACK`。
2. 写入 `stack[sp]`。
3. `sp++`。

## 10. `pop`

```c
static int pop(void) {
    if (sp <= 0) { fprintf(stderr, "runtime error: stack underflow\n"); exit(1); }
    return stack[--sp];
}
```

弹栈函数。

逻辑：

1. 如果 `sp <= 0`，说明栈空，报错。
2. 先 `--sp`。
3. 返回栈顶值。

例子：

```text
sp = 3
pop 后 sp = 2
返回 stack[2]
```

## 11. 单步模式指令名

```c
static const char *opr_names[] = {
    "RET","NEG","ADD","SUB","MUL","DIV","?","EQ",
    "NEQ","LT","GEQ","GT","LEQ","NOT","AND","OR"
};
```

`OPR` 指令的 `a` 字段表示子操作码。

例如：

```text
OPR 0 2 -> ADD
OPR 0 9 -> LT
```

`opr_names` 用来在单步模式打印更友好的名字。

## 12. `print_instruction`

```c
static void print_instruction(int addr)
```

作用：打印 `code[addr]` 这条指令。

### 取指令

```c
Instruction *ins = &code[addr];
```

- `addr`：指令地址。
- `ins`：指向该指令的指针。

### 普通 opcode 名称

```c
const char *names[] = {
    "LIT","LOD","STO","INT","JMP","JPC","OPR",
    "READ","WRITE","WRITES","WRITET",
    "SET_NEW","SET_LIT","SET_ADD","SET_REM",
    "SET_IN","SET_EMPTY","SET_UNION","SET_INTER","SET_COPY",
    "SET_EQL","SET_ELEM"
};
```

这张表把 `OpCode` 枚举值映射成字符串。

### `nm`

```c
const char *nm = (ins->op <= SET_ELEM) ? names[ins->op] : "???";
```

如果 opcode 合法，就取名称。

否则显示：

```text
???
```

### 打印 `OPR`

```c
if (ins->op == OPR && ins->a >= 0 && ins->a <= 15)
```

如果是 `OPR`，额外打印子操作名称。

### 打印双集合地址指令

```c
else if (ins->op == SET_UNION || ins->op == SET_INTER || ins->op == SET_EQL)
```

这些指令的 `l/a` 字段里编码了两个集合地址，所以单步打印时会解码。

本阶段先知道这是为了调试方便即可。

## 13. `pvm_run` 初始化

```c
void pvm_run(int step_mode) {
    pc        = 0;
    sp        = 0;
    frame_top = 0;
    memset(stack, 0, sizeof(stack));
```

执行开始前：

- `pc = 0`：从第 0 条 P-code 开始。
- `sp = 0`：运行时栈为空。
- `frame_top = 0`：还没有活跃 frame。
- `memset(stack, 0, sizeof(stack))`：清空栈内存。

参数：

- `step_mode`：是否单步运行。

## 14. 主执行循环

```c
while (1) {
    if (pc < 0 || pc >= code_len) {
        fprintf(stderr, "runtime error: pc=%d out of range\n", pc);
        break;
    }
    ...
    Instruction ins = code[pc++];
    switch (ins.op) {
        ...
    }
}
```

PVM 一直循环取指令执行。

### PC 越界检查

```c
if (pc < 0 || pc >= code_len)
```

如果 `pc` 不在 `[0, code_len)` 范围内，说明跳转地址错误或程序没有正常 `RET`。

### 取指令

```c
Instruction ins = code[pc++];
```

执行前：

```text
pc 指向当前指令
```

执行后：

```text
pc 默认指向下一条
```

如果当前指令是 `JMP/JPC`，会覆盖这个默认值。

## 15. 单步交互

```c
if (step_mode) {
    print_instruction(pc);
    printf("\n  sp=%-4d  stack top: %s  [Enter=step  r=run  q=quit] ",
           sp, sp > 0 ? "" : "(empty)");
    if (sp > 0) printf("%d  ", stack[sp - 1]);
    char buf[16];
    if (!fgets(buf, sizeof(buf), stdin)) break;
    if (buf[0] == 'q') break;
    if (buf[0] == 'r') step_mode = 0;
}
```

如果用户用：

```bash
./l26c -s tests/test1.l26
```

就进入单步模式。

每一步会显示：

```text
当前指令
sp
栈顶值
```

输入：

- Enter：执行一步。
- `r`：切换成连续运行。
- `q`：退出。

## 16. `LIT`

```c
case LIT:
    push(ins.a);
    break;
```

指令格式：

```text
LIT 0 a
```

作用：把常量 `a` 压栈。

例子：

```text
LIT 0 5
```

执行后：

```text
stack top = 5
```

## 17. `LOD`

```c
case LOD:
    push(*var_addr(ins.l, ins.a));
    break;
```

指令格式：

```text
LOD l a
```

作用：加载变量值到栈顶。

步骤：

1. `var_addr(ins.l, ins.a)` 找到变量地址。
2. `*var_addr(...)` 取出变量值。
3. `push(...)` 压栈。

用于：

```l26
write x;
y = x + 1;
```

## 18. `STO`

```c
case STO:
    *var_addr(ins.l, ins.a) = pop();
    break;
```

指令格式：

```text
STO l a
```

作用：弹出栈顶值，存入变量。

步骤：

1. `pop()` 取出表达式结果。
2. `var_addr(ins.l, ins.a)` 找到变量地址。
3. 写入该地址。

用于：

```l26
x = 10;
```

大致指令：

```text
LIT 0 10
STO 0 offset(x)
```

## 19. `INT`

```c
case INT:
    if (ins.a >= 0) {
        if (frame_top >= 256) {
            fprintf(stderr, "runtime error: frame stack overflow\n");
            exit(1);
        }
        frame_base[frame_top++] = sp;
        sp += ins.a;
        if (sp > MAX_STACK) {
            fprintf(stderr, "runtime error: stack overflow\n");
            exit(1);
        }
    } else {
        sp -= (-ins.a);
        frame_top--;
    }
    break;
```

`INT` 在这里不是整数类型，而是“调整栈空间”的指令。

### 分配空间

```text
INT 0 n
```

当 `n >= 0`：

```c
frame_base[frame_top++] = sp;
sp += n;
```

含义：

1. 当前 `sp` 是新 frame 的起点。
2. 保存到 `frame_base`。
3. `sp += n` 预留 `n` 个 word。

例子：

```text
INT 0 3
```

会给当前 block 分配 3 个 word。

### 释放空间

```text
INT 0 -n
```

当 `n < 0`：

```c
sp -= (-ins.a);
frame_top--;
```

含义：

```text
释放当前 frame 的 n 个 word
弹出一个 frame 记录
```

### 和 `block` 对应

parser 中每个 block：

```text
进入时 emit INT 0 n
退出时 emit INT 0 -n
```

PVM 运行时就建立和销毁局部变量空间。

## 20. `JMP`

```c
case JMP:
    pc = ins.a;
    break;
```

指令格式：

```text
JMP 0 target
```

无条件跳转到 `target`。

用于：

```text
while 循环回到开头
if-else then 分支结束后跳过 else
```

## 21. `JPC`

```c
case JPC:
    if (pop() == 0) pc = ins.a;
    break;
```

指令格式：

```text
JPC 0 target
```

含义：

```text
弹出栈顶条件
如果条件为 0，跳到 target
否则继续执行下一条
```

`0` 表示假，非 `0` 表示真。

用于：

```text
if 条件为假跳过 then
while 条件为假跳出循环
comprehension 条件为假跳过 body
```

## 22. `OPR`

```c
case OPR: {
    int b, a;
    switch (ins.a) {
        ...
    }
    break;
}
```

`OPR` 是一组算术、比较、逻辑操作。

真正操作由：

```text
ins.a
```

决定。

局部变量：

- `b`：通常保存右操作数。
- `a`：除法中保存左操作数。

## 23. `OPR_RET`

```c
case OPR_RET:
    return;
```

程序结束。

parser 顶层规则：

```c
emit(OPR, 0, OPR_RET);
```

PVM 执行到这里就从 `pvm_run` 返回。

## 24. 一元运算

```c
case OPR_NEG:
    stack[sp - 1] = -stack[sp - 1];
    break;
```

一元负号直接修改栈顶值。

```c
case OPR_NOT:
    push(pop() == 0 ? 1 : 0);
    break;
```

逻辑非：

```text
0 -> 1
非 0 -> 0
```

## 25. 算术二元运算

```c
case OPR_ADD: b = pop(); push(pop() + b); break;
case OPR_SUB: b = pop(); push(pop() - b); break;
case OPR_MUL: b = pop(); push(pop() * b); break;
```

栈机执行二元运算的模式：

```text
先 pop 右操作数 b
再 pop 左操作数
计算
push 结果
```

减法必须注意顺序：

```text
left - right
```

所以写成：

```c
b = pop();
push(pop() - b);
```

## 26. 除法

```c
case OPR_DIV:
    b = pop(); a = pop();
    if (b == 0) { fprintf(stderr, "runtime error: division by zero\n"); exit(1); }
    push(a / b);
    break;
```

除法需要额外检查：

```text
除数不能为 0
```

这里的：

- `a`：左操作数。
- `b`：右操作数，也就是除数。

如果 `b == 0`，运行时报错。

## 27. 相等和比较

```c
case OPR_EQ:  b = pop(); push(pop() == b ? 1 : 0); break;
case OPR_NEQ: b = pop(); push(pop() != b ? 1 : 0); break;
case OPR_LT:  b = pop(); push(pop() <  b ? 1 : 0); break;
case OPR_GEQ: b = pop(); push(pop() >= b ? 1 : 0); break;
case OPR_GT:  b = pop(); push(pop() >  b ? 1 : 0); break;
case OPR_LEQ: b = pop(); push(pop() <= b ? 1 : 0); break;
```

比较结果统一压入：

```text
真 -> 1
假 -> 0
```

这些结果可继续用于：

```text
if
while
&&
||
!
```

## 28. 逻辑二元运算

```c
case OPR_AND: b = pop(); push(pop() & b); break;
case OPR_OR:  b = pop(); push(pop() | b); break;
```

这里使用按位运算：

```text
&
|
```

因为 parser 已经保证布尔值通常是 `0/1`，所以结果仍然符合布尔含义。

注意：不是短路求值。

## 29. 未知 `OPR`

```c
default:
    fprintf(stderr, "runtime error: unknown OPR %d\n", ins.a);
    exit(1);
```

如果 `ins.a` 不是已知子操作码，PVM 报运行时错误。

## 30. `READ`

```c
case READ: {
    int v;
    if (scanf("%d", &v) != 1) {
        fprintf(stderr, "runtime error: read failed\n");
        exit(1);
    }
    push(v);
    break;
}
```

指令格式：

```text
READ 0 0
```

作用：

1. 从标准输入读一个整数。
2. 压入栈顶。

parser 对：

```l26
read x;
```

生成：

```text
READ
STO addr(x)
```

所以 `READ` 本身只负责读入并压栈。

## 31. `WRITE`

```c
case WRITE:
    printf("%d\n", pop());
    break;
```

指令格式：

```text
WRITE 0 0
```

作用：

1. 弹出栈顶值。
2. 按整数打印。
3. 输出换行。

用于：

```l26
write x + 1;
```

表达式先把结果压栈，`WRITE` 再弹出打印。

## 32. 一个普通程序的执行过程

源码：

```l26
{
    int x;
    x = 2 + 3;
    write x;
}
```

大致 P-code：

```text
0 INT   0 1
1 LIT   0 2
2 LIT   0 3
3 OPR   0 OPR_ADD
4 STO   0 0
5 LOD   0 0
6 WRITE 0 0
7 INT   0 -1
8 OPR   0 OPR_RET
```

运行过程：

```text
INT 0 1       创建 frame，给 x 分配 1 word
LIT 0 2       压入 2
LIT 0 3       压入 3
OPR_ADD       弹出 2 和 3，压入 5
STO 0 0       把 5 存入 x
LOD 0 0       加载 x，压入 5
WRITE         打印 5
INT 0 -1      释放 frame
OPR_RET       结束
```

## 33. 嵌套作用域例子

源码：

```l26
{
    int x;
    x = 10;
    {
        int y;
        y = x + 1;
        write y;
    }
}
```

访问 `y`：

```text
ld = 0
```

因为 `y` 在当前 frame。

访问外层 `x`：

```text
ld = 1
```

PVM 用：

```c
get_frame_base(1)
```

找到外层 frame，然后加上 `x` 的 offset。

这就是 `scope_level()` 和 `frame_base[]` 的运行时对应关系。

## 34. 本阶段你要记住

1. PVM 执行的是全局 `code[]`。
2. `pc` 指向下一条指令。
3. `sp` 指向栈中下一个空位。
4. `push/pop` 管理表达式临时值。
5. `INT 0 n` 创建运行时 frame。
6. `INT 0 -n` 释放运行时 frame。
7. `frame_base[]` 让 `LOD/STO` 可以访问外层变量。
8. `LOD` 加载变量，`STO` 存储变量。
9. `JMP/JPC` 实现控制流。
10. `OPR` 执行算术、比较和逻辑。
11. `READ/WRITE` 通过栈和标准输入输出交互。

## 下一步

Step 9 继续读 `pvm.c` 的集合运行时：

```text
set memory layout
set_contains / set_add_elem / set_rem_elem
SET_NEW / SET_LIT / SET_ADD / SET_REM
SET_IN / SET_EMPTY / SET_UNION / SET_INTER / SET_COPY
SET_EQL / SET_ELEM
WRITES / WRITET
```
