# Step 3：P-Code 的保存、回填和打印

本阶段读两个文件：

```text
codegen.h
codegen.c
```

目标：理解 `parser.y` 生成的指令如何被保存到数组里，跳转地址如何回填，最终 P-Code 如何打印出来。

## Step 2 承接

Step 2 中看到 `main.c` 会调用：

```c
print_pcode();
```

也看到 `pcode.h` 里定义了：

```c
Instruction
OpCode
code[MAX_CODE]
code_len
```

本阶段要回答：

1. `code` 和 `code_len` 真正在哪里定义？
2. `emit` 如何追加一条指令？
3. `patch` 为什么只修改 `a` 字段？
4. `current_addr` 为什么返回 `code_len`？
5. `print_pcode` 如何区分普通指令、`OPR` 指令和集合双操作数指令？

## 1. `codegen.h`

`codegen.h` 是对外接口。其他文件只需要包含它，就能调用 P-Code 生成相关函数。

### 头文件保护

```c
#ifndef CODEGEN_H
#define CODEGEN_H
...
#endif
```

作用：避免重复包含。

### 引入 `pcode.h`

```c
#include "pcode.h"
```

因为下面的函数会用到：

```c
OpCode
Instruction
MAX_CODE
```

这些都定义在 `pcode.h`。

### `emit`

```c
int emit(OpCode op, int l, int a);
```

作用：追加一条 P-Code。

参数：

- `op`：指令类型，例如 `LIT`、`LOD`、`JMP`。
- `l`：指令的第一个整数参数。
- `a`：指令的第二个整数参数。

返回值：

- 新指令在 `code[]` 数组中的下标。

为什么要返回下标？

因为 `if`、`while` 这种控制流会先生成未知目标的跳转指令，之后再用 `patch` 回填。

### `patch`

```c
void patch(int idx, int new_a);
```

作用：修改第 `idx` 条指令的 `a` 字段。

参数：

- `idx`：要修改哪条指令。
- `new_a`：新的跳转目标地址。

常用于：

```text
JPC 0 0   先占位
...
patch(jpc_idx, current_addr())
```

### `current_addr`

```c
int current_addr(void);
```

作用：返回下一条即将生成的指令地址。

因为 `code_len` 表示已经有多少条指令，所以：

```text
下一条指令地址 = code_len
```

### `print_pcode`

```c
void print_pcode(void);
```

作用：打印完整 P-Code 表。

这个函数被 `main.c` 调用。

## 2. `codegen.c`

`codegen.c` 是 `codegen.h` 的具体实现。

### 头文件

```c
#include <stdio.h>
#include <stdlib.h>
#include "codegen.h"
```

含义：

- `stdio.h`：使用 `printf`、`fprintf`。
- `stdlib.h`：使用 `exit`。
- `codegen.h`：获得 `Instruction`、`OpCode`、函数声明。

### 全局指令数组

```c
Instruction code[MAX_CODE];
int code_len = 0;
```

这两行是真正定义。

在 `pcode.h` 中只是声明：

```c
extern Instruction code[MAX_CODE];
extern int code_len;
```

变量含义：

- `code`：保存所有 P-Code 指令。
- `MAX_CODE`：数组最大容量，定义在 `pcode.h`，值是 `4096`。
- `code_len`：当前已经生成的指令数量。

例子：

```text
code_len = 0     还没有指令
emit(...)        写入 code[0]，code_len 变成 1
emit(...)        写入 code[1]，code_len 变成 2
```

## 3. `emit`

源码：

```c
int emit(OpCode op, int l, int a) {
    if (code_len >= MAX_CODE) {
        fprintf(stderr, "error: code buffer overflow\n");
        exit(1);
    }
    int idx = code_len++;
    code[idx].op = op;
    code[idx].l  = l;
    code[idx].a  = a;
    return idx;
}
```

### 参数解释

```c
OpCode op
```

指令名，例如：

```text
LIT
LOD
STO
JMP
SET_ADD
```

```c
int l
```

第一个操作数字段。常见含义：

- 层差
- `0`
- 集合双操作数编码的一半

```c
int a
```

第二个操作数字段。常见含义：

- 常量值
- 变量偏移
- 跳转目标
- OPR 子操作编号
- 集合双操作数编码的另一半

### 容量检查

```c
if (code_len >= MAX_CODE)
```

如果指令数量超过 4096，就报错退出。

### 保存下标

```c
int idx = code_len++;
```

这行很关键。

含义：

```text
idx 使用旧的 code_len
code_len 再加 1
```

如果原来：

```text
code_len = 10
```

执行后：

```text
idx = 10
code_len = 11
```

### 写入指令

```c
code[idx].op = op;
code[idx].l  = l;
code[idx].a  = a;
```

把三个字段写进数组。

例子：

```c
emit(LIT, 0, 5);
```

生成：

```text
code[idx].op = LIT
code[idx].l  = 0
code[idx].a  = 5
```

### 返回 `idx`

```c
return idx;
```

用于之后回填。

例子：

```c
int jpc = emit(JPC, 0, 0);
...
patch(jpc, current_addr());
```

## 4. `patch`

源码：

```c
void patch(int idx, int new_a) {
    code[idx].a = new_a;
}
```

参数：

- `idx`：指令下标。
- `new_a`：新的 `a` 字段。

为什么只改 `a`？

因为跳转指令格式是：

```text
JMP 0 target
JPC 0 target
```

目标地址放在 `a` 字段里。

例子：

```text
10: JPC 0 0
```

后来发现 false 分支应跳到 25：

```c
patch(10, 25);
```

变成：

```text
10: JPC 0 25
```

## 5. `current_addr`

源码：

```c
int current_addr(void) {
    return code_len;
}
```

含义：返回下一条指令地址。

为什么不是 `code_len - 1`？

因为：

- `code_len - 1` 是最后一条已生成指令。
- `code_len` 是下一条即将生成指令。

在回填跳转时，我们通常要跳到“接下来这里”，所以用 `code_len`。

## 6. `opcode_name`

源码形式：

```c
static const char *opcode_name(OpCode op)
```

作用：把枚举值转成人能读懂的字符串。

例子：

```text
LIT -> "LIT"
LOD -> "LOD"
SET_ADD -> "SET_ADD"
```

参数：

- `op`：一个 `OpCode` 枚举值。

返回值：

- 对应的字符串。

`static` 表示只在 `codegen.c` 内部使用。

默认分支：

```c
default: return "???";
```

如果遇到未知指令，就打印 `???`。

## 7. `opr_name`

源码形式：

```c
static const char *opr_name(int n)
```

作用：把 `OPR` 的子操作编号转成人能读懂的名字。

例子：

```text
OPR_ADD -> "ADD"
OPR_SUB -> "SUB"
OPR_EQ  -> "EQ"
```

参数：

- `n`：`OPR` 指令的 `a` 字段。

例子：

```text
OPR 0 2
```

因为 `2` 是 `OPR_ADD`，所以打印时附加：

```text
; ADD
```

默认分支：

```c
default: return "?";
```

## 8. `print_pcode`

源码开头：

```c
void print_pcode(void) {
    printf("\n=== Generated P-Code ===\n");
    printf("%-6s %-10s %6s %6s\n", "Addr", "Op", "L", "A");
    printf("-------------------------------\n");
```

作用：打印标题和表头。

表头含义：

- `Addr`：指令地址，也就是数组下标。
- `Op`：操作码名称。
- `L`：第一个参数。
- `A`：第二个参数。

### 遍历所有指令

```c
for (int i = 0; i < code_len; i++)
```

变量：

- `i`：当前指令地址。
- `code_len`：总指令数。

### 当前指令指针

```c
Instruction *ins = &code[i];
```

`ins` 指向当前指令。

之后可以写：

```c
ins->op
ins->l
ins->a
```

等价于：

```c
code[i].op
code[i].l
code[i].a
```

## 9. 三种打印分支

### 分支 1：`OPR`

```c
if (ins->op == OPR)
```

打印格式：

```c
printf("%4d:  %-10s %6d %6d  ; %s\n",
       i, opcode_name(ins->op), ins->l, ins->a,
       opr_name(ins->a));
```

特点：最后多打印一个注释。

例子：

```text
18:  OPR             0      2  ; ADD
```

### 分支 2：双集合操作

```c
else if (ins->op == SET_UNION || ins->op == SET_INTER || ins->op == SET_EQL)
```

这些指令涉及两个集合地址。

原始字段是：

```text
ins->l = ENCODE2(ld1, off1)
ins->a = ENCODE2(ld2, off2)
```

打印时拆开：

```c
DECODE_LD(ins->l)
DECODE_OFF(ins->l)
DECODE_LD(ins->a)
DECODE_OFF(ins->a)
```

例子：

```text
47: SET_UNION ld1=0 off1=0 ld2=0 off2=201
```

这样比直接打印两个大整数更容易读。

### 分支 3：普通指令

```c
else
```

普通打印：

```text
地址: 指令名 L A
```

例子：

```text
0:  INT             0      3
1:  READ            0      0
2:  STO             0      0
```

## 10. 控制流回填例子

以 `if` 为例：

```l26
if (x > 0) {
    write x;
}
```

生成时大致是：

```text
LOD ...
LIT 0 0
OPR 0 GT
JPC 0 0      先不知道跳到哪里
...
write body
...
```

此时记录：

```c
int jpc_idx = emit(JPC, 0, 0);
```

等 body 生成完：

```c
patch(jpc_idx, current_addr());
```

把 `JPC 0 0` 改成：

```text
JPC 0 body_end
```

## 11. 本阶段你要记住

`codegen.c` 只有四个对外能力：

```text
emit          追加指令
patch         回填跳转目标
current_addr  获取下一条指令地址
print_pcode   打印指令表
```

核心数据只有两个：

```text
code      指令数组
code_len  当前指令数量
```

下一阶段建议读：

```text
symtab.h
symtab.c
```

因为 `parser.y` 生成 `LOD/STO/SET_*` 时，需要符号表告诉它变量的 `type`、`level`、`offset`。

