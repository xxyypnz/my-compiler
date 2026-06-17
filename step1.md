# Step 1：项目总览

## 目标

先建立项目地图：知道这个编译器从哪里开始、经过哪些模块、最后如何执行程序。此阶段不逐行抠细节，只抓主链路。

## 一句话理解

这是一个 L26 语言编译器：

```text
源代码 .l26
  -> lexer.l 词法分析
  -> parser.y 语法/语义分析并生成 P-Code
  -> codegen.c 保存和打印 P-Code
  -> pvm.c 执行 P-Code
  -> 输出结果
```

## 最关键文件

| 文件 | 第一阶段只需理解 |
|------|------------------|
| `main.c` | 程序入口：读命令行参数、打开源文件、调用 parser、打印 P-Code、运行虚拟机。 |
| `lexer.l` | 把字符流切成 token，例如 `int`、`ID`、`NUM`、`if`、`+`。 |
| `parser.y` | 项目核心：定义语法规则，做类型检查，维护作用域，生成 P-Code。 |
| `symtab.c/h` | 符号表：记录变量名、类型、作用域层次、运行时偏移。 |
| `codegen.c/h` | P-Code 指令数组：`emit` 发指令，`patch` 回填跳转，`print_pcode` 打印。 |
| `pcode.h` | 指令集定义：有哪些 OpCode、集合大小、OPR 编码。 |
| `pvm.c/h` | 虚拟机：解释执行 P-Code，实现算术、控制流、IO、集合操作。 |
| `Makefile` | 构建和测试入口。 |

## 主流程

### 1. 入口：`main.c`

关键流程：

```text
解析参数
打开 .l26 文件
调用 yyparse()
打印 P-Code
调用 pvm_run()
```

先记住：`main.c` 不负责编译细节，它只是调度。

### 2. 词法：`lexer.l`

作用：把源码文本变成 token。

例子：

```l26
int x;
x = 1 + 2;
```

会被识别成：

```text
INT_KW ID ';' ID '=' NUM '+' NUM ';'
```

### 3. 语法和语义：`parser.y`

这是最重要的文件。

它同时做三件事：

```text
检查语法是否正确
检查类型是否正确
生成 P-Code 指令
```

例子：

```l26
x = 1 + 2;
```

大致生成：

```text
LIT 0 1
LIT 0 2
OPR 0 ADD
STO l offset
```

### 4. 代码生成：`codegen.c`

核心函数：

```c
emit(op, l, a)
patch(idx, target)
print_pcode()
```

理解为：`parser.y` 每识别一个语义动作，就调用 `emit` 往全局指令数组里追加一条 P-Code。

### 5. 虚拟机：`pvm.c`

虚拟机从第 0 条 P-Code 开始解释执行。

常见执行效果：

```text
LIT 0 5     -> 把 5 压栈
LOD l a     -> 读取变量并压栈
STO l a     -> 把栈顶保存到变量
JPC 0 addr  -> 条件为假则跳转
WRITE       -> 输出栈顶
```

## 数据结构总览

### P-Code 指令

定义在 `pcode.h`：

```c
typedef struct {
    OpCode op;
    int l;
    int a;
} Instruction;
```

每条指令都有：

- `op`：指令类型
- `l`：层差或编码参数
- `a`：偏移、常量或跳转地址

### 符号

定义在 `symtab.h`：

```c
name
type
level
offset
```

意思是：变量叫什么、是什么类型、在哪一层作用域、运行时存在栈帧哪里。

### 集合

集合占 201 个整数：

```text
第 0 个：元素个数
第 1-200 个：元素值
```

## 第一阶段阅读顺序

建议按这个顺序读：

```text
1. README.md        了解功能
2. Makefile         了解怎么构建和测试
3. main.c           看程序入口
4. pcode.h          看指令集
5. codegen.c/h      看 P-Code 如何保存
6. symtab.c/h       看变量如何记录
7. lexer.l          看 token 如何产生
8. parser.y         只粗看主规则
9. pvm.c            只粗看执行循环
```

## 第一阶段必须掌握的问题

读完后应该能回答：

1. `./l26c tests/test1.l26` 从入口到输出经历哪些模块？
2. `parser.y` 为什么是项目核心？
3. `emit` 和 `patch` 分别是干什么的？
4. 符号表为什么要记录 `level` 和 `offset`？
5. 虚拟机执行 P-Code 时栈起什么作用？

## 暂时不要深挖

第一阶段先不要细抠：

- Bison 每条产生式的语义动作细节
- 集合推导式的完整生成逻辑
- 每个 P-Code 指令的运行时边界条件
- 错误测试细节

这些放到后续阶段逐行拆。

