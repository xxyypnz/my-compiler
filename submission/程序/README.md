# L26 编译器

基于 Flex/Bison 实现的 L26 语言编译器，生成类 P-Code 指令并在内置虚拟机上运行。

---

## 构建与运行

**环境要求**：gcc、flex、bison、make（Linux/WSL）

```bash
make
./l26c <源文件.l26>       # 编译并运行
./l26c -s <源文件.l26>    # 单步调试模式
./l26c -p <源文件.l26>    # 仅打印 P-Code
make test                  # 运行所有测试
```

---

## L26 语言文法

```
<program>    ::= <block>
<block>      ::= "{" <decls> <stmts> "}"
<decls>      ::= { <decl> }
<decl>       ::= <type> <ID> ";"
<type>       ::= "int" | "bool" | "set"

<stmts>      ::= { <stmt> }
<stmt>       ::= <assign_stmt> | <if_stmt> | <while_stmt>
               | <io_stmt> | <block> | <set_op_stmt>

<assign_stmt> ::= <ID> "=" <expr> ";"
<if_stmt>     ::= "if" "(" <bexpr> ")" <stmt> [ "else" <stmt> ]
<while_stmt>  ::= "while" "(" <bexpr> ")" <stmt>
<io_stmt>     ::= "write" <expr> ";" | "read" <ID> ";"
<set_op_stmt> ::= "add" <ID> <aexpr> ";" | "remove" <ID> <aexpr> ";"

<expr>        ::= <aexpr> | <bexpr> | <set_expr>

<aexpr>  ::= <aterm> { ("+" | "-") <aterm> }
<aterm>  ::= <afactor> { ("*" | "/") <afactor> }
<afactor>::= <ID> | NUM | "(" <aexpr> ")"

<bexpr>  ::= <bterm> { "||" <bterm> }
<bterm>  ::= <bfactor> { "&&" <bfactor> }
<bfactor>::= "true" | "false" | "!" <bfactor> | "(" <bexpr> ")"
           | <rel> | <set_test>

<rel>    ::= <aexpr> ("<" | "<=" | ">" | ">=" | "==" | "!=") <aexpr>

<set_expr>  ::= "{" [ <aexpr> { "," <aexpr> } ] "}"
              | <ID> "union" <ID>
              | <ID> "inter" <ID>

<set_test>  ::= <aexpr> "in" <ID>
              | "isempty" "(" <ID> ")"

(* 加分项扩展 *)
<rel>       ::= <ID> "==" <ID>   (* 集合相等，当两侧均为 set 类型 *)
<set_expr>  ::= "{" <aexpr> "|" <ID> "in" <ID> "if" <bexpr> "}"  (* 集合推导式 *)
```

---

## 编译器设计

### 整体架构

```
源程序(.l26)
    │
    ▼
[Flex 词法分析] lexer.l
    │  token 流
    ▼
[Bison 语法分析 + 语义动作] parser.y
    ├── 符号表管理 symtab.c  （嵌套作用域、变量查找）
    ├── 类型检查
    └── P-Code 生成 codegen.c
    │
    ▼
P-Code 指令序列
    │
    ▼
[类 P-Code 虚拟机] pvm.c → 运行输出
```

### 符号表

采用链式作用域栈。每进入一个 `{ }` 块调用 `scope_enter()`，退出时调用 `scope_exit()`。变量查找从当前作用域向外逐层搜索，支持内层变量遮蔽外层同名变量。

每个符号记录：变量名、类型（int/bool/set）、层次（level）、偏移（offset）。

内存占用：`int`/`bool` 占 1 个字，`set` 占 201 个字（1 个计数字 + 200 个元素字）。

### P-Code 指令集

**标准指令：**

| 指令 | 操作数 | 说明 |
|------|--------|------|
| `LIT 0 n` | — | 将常数 n 压栈 |
| `LOD l a` | 层差 l，偏移 a | 将变量值压栈 |
| `STO l a` | 层差 l，偏移 a | 将栈顶值存入变量 |
| `INT 0 n` | n>0 分配，n<0 释放 | 调整栈帧大小 |
| `JMP 0 a` | 目标地址 a | 无条件跳转 |
| `JPC 0 a` | 目标地址 a | 栈顶为 0 时跳转 |
| `OPR 0 n` | 运算编码 n | 算术/逻辑运算 |

**扩展指令（集合与 I/O）：**

| 指令 | 说明 |
|------|------|
| `READ` | 从标准输入读整数，压栈 |
| `WRITE` | 弹出栈顶整数，输出 |
| `WRITES l a` | 输出 (l,a) 处的集合 |
| `WRITET` | 输出全局临时集合 |
| `SET_NEW l a` | 初始化 (l,a) 处集合为空 |
| `SET_LIT 0 n` | 弹出 n 个整数，构造集合存入临时缓冲 |
| `SET_ADD l a` | 弹出整数，添加到 (l,a) 处集合 |
| `SET_REM l a` | 弹出整数，从 (l,a) 处集合删除 |
| `SET_IN l a` | 弹出整数，检查是否在集合中，压 0/1 |
| `SET_EMPTY l a` | 检查集合是否为空，压 0/1 |
| `SET_UNION l1a1 l2a2` | 计算两集合并集，存入临时缓冲 |
| `SET_INTER l1a1 l2a2` | 计算两集合交集，存入临时缓冲 |
| `SET_COPY l a` | 将临时缓冲复制到 (l,a) 处集合 |
| `SET_EQL l1a1 l2a2` | 判断两集合相等，压 0/1（加分项） |
| `SET_ELEM l a` | 弹出索引 i，压集合第 i 个元素 |

两集合指令的操作数编码：`l = ld1*10000 + off1`，`a = ld2*10000 + off2`。

### 虚拟机

使用平坦整数数组作为运行时栈，配合帧栈（`frame_base[]`）追踪每个嵌套块的基地址。`INT 0 n`（n>0）压入新帧，`INT 0 -n` 弹出帧。集合变量直接存储在栈帧内，通过 `(层差, 偏移)` 寻址。

---

## 加分项说明

### 1. P-Code 可视化 + 单步运行

每次编译后自动打印完整 P-Code 列表（地址、指令名、操作数、OPR 子操作注释）。

`-s` 参数启用单步模式：每条指令执行前显示指令内容和当前栈顶，等待用户输入（Enter 单步，r 连续，q 退出）。

### 2. 集合相等判断

语法：`s1 == s2`（两侧均为 set 类型变量）

编译为 `SET_EQL` 指令，运行时比较两集合元素是否完全相同（顺序无关），结果压栈（1=相等，0=不等）。

### 3. 集合推导式

语法：`{ expr | x in S if bexpr }`

编译为对源集合 S 的遍历循环：对每个满足过滤条件 `bexpr` 的元素 x，计算 `expr` 并加入结果集合。迭代变量 x 仅在推导式内部有效（独立作用域）。

---

## 代码结构

| 文件 | 说明 |
|------|------|
| `pcode.h` | 指令集枚举、常量定义 |
| `symtab.h/c` | 符号表，嵌套作用域管理 |
| `codegen.h/c` | P-Code 指令生成与打印 |
| `lexer.l` | Flex 词法规则 |
| `parser.y` | Bison 语法规则 + 全部语义动作 |
| `pvm.h/c` | 类 P-Code 虚拟机 |
| `main.c` | 入口，命令行参数处理 |
| `Makefile` | 构建脚本 |
| `tests/` | 5 个测试用例 |

---

## 测试结果

### test1.l26 — 阶乘（输入 5）
```
120
1
```

### test2.l26 — 集合操作
```
{1, 2, 3}
1
0
{1, 2, 3, 4, 5}
{3}
0
1
```

### test3.l26 — 嵌套作用域与变量遮蔽
```
{5, 6, 7}
{1, 2}
10
```

### test4.l26 — 加分项：集合相等 + 集合推导式
```
1
0
{6, 8, 10}
```

### test5.l26 — 综合测试
```
55
1
{2, 4, 6, 8, 10}
{1, 3, 5, 7, 9}
```
