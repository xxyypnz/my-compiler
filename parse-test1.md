# parse-test1.md — test1.l26 全链路深度解析

## 0. 预备知识：先看懂 parser.y 的语法

在追踪代码之前，必须先弄清几个 Bison 特有的概念。

---

### 0.1 `$$`、`$1`、`$2` 是什么

Bison 的每条文法规则形如：

```
左侧符号 : 右侧符号1 右侧符号2 右侧符号3 { 动作 }
```

在动作里：
- `$$` = 这条规则**自己**的语义值（左侧符号的值）
- `$1` = 右侧第1个符号的语义值
- `$2` = 右侧第2个符号的语义值，以此类推

具体例子，`type` 规则：

```bison
type
    : INT_KW  { $$ = T_INT; }   // $$ 就是 type 这个非终结符的值
    | BOOL_KW { $$ = T_BOOL; }
    | SET_KW  { $$ = T_SET; }
    ;
```

`decl` 规则里引用它：

```bison
decl : type ID ';'
       // $1 = type 的 $$（即 T_INT/T_BOOL/T_SET）
       // $2 = ID 的 yylval.sval（标识符名字）
       // $3 = ';'（无值，不用）
```

---

### 0.2 `%union` 和 `%type` 如何保证 C 代码不报错

Bison 里 `$$`、`$1` 等在 C 层面都是同一个 `YYSTYPE` union 的实例，union 里有多个字段。

```c
%union {
    int     ival;          // 给 NUM、TRUE_KW、FALSE_KW、以及 mid-rule 临时存指令地址
    char    sval[64];      // 给 ID 存名字
    VarType vtype;         // 给 type 非终结符
    struct { VarType type; int level; int offset; } expr;  // 给 expr
    struct { int addr; int jpc_idx; PatchNode *list; } ctrl; // 给控制流
    int count;             // 给 expr_list
}
```

如果你写 `$1.type`，Bison 需要知道 `$1` 应该访问 union 的哪个字段。这就是 `%type` 和 `%token` 的作用：

```bison
%token <ival> NUM           // NUM 的 $$ 自动访问 union.ival
%token <sval> ID            // ID 的 $$ 自动访问 union.sval
%type  <expr> expr          // expr 的 $$ 自动访问 union.expr
%type  <vtype> type         // type 的 $$ 自动访问 union.vtype
```

有了这些声明，写 `$1.type` 时 Bison 知道展开成 `$1.expr.type`，C 编译器才不报错。

没有 `<xxx>` 的 token（如 `INT_KW`、`IF`）只做匹配，不取值，写 `$n` 访问它们是未定义行为，所以也不会有人写。

---

### 0.3 中途动作（Mid-rule Action）是什么

Bison 允许动作 `{ }` 出现在规则**中间**，而不只是末尾。

```bison
block
    : '{'
        {                            // ← 这就是 Mid-rule Action，在 '{' 之后立即执行
            scope_enter();
            $<ival>$ = emit(INT, 0, 0);
        }
      decls
        { patch($<ival>2, scope_frame_size()); }   // ← 第二个 Mid-rule Action
      stmts
      '}'
        { ... }
    ;
```

中途动作**本身**也占一个 `$n` 的位置：

| 位置 | 符号 |
|------|------|
| $1 | `'{'` |
| $2 | 第一个中途动作（`$$` 被设为 emit 返回的指令下标） |
| $3 | `decls` |
| $4 | 第二个中途动作 |
| $5 | `stmts` |
| $6 | `'}'` |

所以 `$<ival>2` 就是读取位置2（第一个中途动作）保存的 `ival` 值，也就是那条占位 INT 指令的下标。

`$<ival>$` 是强制指定当前中途动作的 `$$` 使用 union 的 `ival` 字段。必须显式写，否则 Bison 不知道用哪个字段。

---

## 1. 完整 P-Code 预览

先看结果，再逐步解释每条指令从哪里来：

```
地址   指令      L    A     含义
─────────────────────────────────────────────────────────
  0:  INT      0    3      分配外层 block 的 3 个字（n/result/i）
  1:  READ     0    0      读整数压栈
  2:  STO      0    0      n = 栈顶，offset=0
  3:  LIT      0    1      压栈常数 1
  4:  STO      0    1      result = 1，offset=1
  5:  LIT      0    1      压栈常数 1
  6:  STO      0    2      i = 1，offset=2
──── while 条件（loop_top = 7）────
  7:  LOD      0    2      load i
  8:  LOD      0    0      load n
  9:  OPR      0   12      i <= n（OPR_LEQ）
 10:  JPC      0   22      条件假跳到 loop_end（回填后）
──── while 体（无局部变量的 block）────
 11:  INT      0    0      while 体 block 入口（分配0字，仅建帧）
 12:  LOD      1    1      load result（ld=1：跨1层到外层帧）
 13:  LOD      1    2      load i（ld=1）
 14:  OPR      0    4      result * i（OPR_MUL）
 15:  STO      1    1      result = result * i
 16:  LOD      1    2      load i
 17:  LIT      0    1      压栈 1
 18:  OPR      0    2      i + 1（OPR_ADD）
 19:  STO      1    2      i = i + 1
 20:  INT      0    0      while 体 block 出口（释放0字，退帧）
 21:  JMP      0    7      跳回 loop_top
──── loop_end = 22 ────
 22:  LOD      0    1      load result（用于 write）
 23:  WRITE    0    0      输出 result
──── if 条件 ────
 24:  LOD      0    1      load result（用于比较）
 25:  LIT      0  100      压栈 100
 26:  OPR      0   11      result > 100（OPR_GT）
 27:  JPC      0   33      条件假跳到 else_start（回填后）
──── then 体 ────
 28:  INT      0    0      then block 入口
 29:  LIT      0    1      压栈 1
 30:  WRITE    0    0      输出 1
 31:  INT      0    0      then block 出口
 32:  JMP      0   37      跳过 else（回填后）
──── else_start = 33 ────
 33:  INT      0    0      else block 入口
 34:  LIT      0    0      压栈 0
 35:  WRITE    0    0      输出 0
 36:  INT      0    0      else block 出口
──── after_else = 37 ────
 37:  INT      0   -3      外层 block 出口，释放 3 个字
 38:  OPR      0    0      RET，程序结束
```

---

## 2. 逐行追踪

### 2.1 外层 `{`（第4行）

**Lexer：** 返回 token `'{'`，`yylval` 无内容（符号字符无附带数据）。

**Parser 规则触发：** `block : '{'` 之后立刻执行第一个 Mid-rule Action：

```c
scope_enter();                      // symtab：创建新作用域，level=1，frame_size=0
$<ival>$ = emit(INT, 0, 0);        // codegen：emit 占位指令，返回下标 0，存入 $2
```

**Symtab 状态：**

```
current_scope:
    level       = 1
    frame_size  = 0       ← 还不知道要分配多少
    base_offset = 0
```

**P-Code 产物：**
```
0: INT 0 0    ← 占位，将在 decls 结束后 patch
```

---

### 2.2 `int n;`（第5行）

**Lexer 依次返回：**

| Token | yylval 内容 |
|-------|------------|
| `INT_KW` | 无（纯匹配） |
| `ID` | `yylval.sval = "n"` |
| `';'` | 无 |

**Parser 规则触发：**

第一步，`type → INT_KW`：

```c
$$ = T_INT;   // type 的语义值是 T_INT，存入 union.vtype
```

第二步，`decl → type ID ';'`（$1=T_INT，$2="n"）：

```c
Symbol *s = sym_declare("n", T_INT);
// symtab：在 current_scope 链头插入 Symbol{name="n", type=T_INT, level=1, offset=0}
// current_scope->frame_size += type_width(T_INT) = 1   →   frame_size = 1

// T_INT 不是 T_SET，不 emit SET_NEW
```

**Symtab 状态变化：**

```
Symbol: name="n"  type=T_INT  level=1  offset=0
current_scope->frame_size = 1
```

**P-Code 产物：** 无（声明本身不生成运行时指令，只更新符号表）。

---

### 2.3 `int result;`（第6行）

与 `int n;` 完全对称：

```c
sym_declare("result", T_INT);
// offset = base_offset + frame_size = 0 + 1 = 1
// frame_size = 2
```

**Symtab 状态：**

```
Symbol: name="result"  type=T_INT  level=1  offset=1
current_scope->frame_size = 2
```

---

### 2.4 `int i;`（第7行）

```c
sym_declare("i", T_INT);
// offset = 0 + 2 = 2
// frame_size = 3
```

**Symtab 状态：**

```
Symbol: name="i"  type=T_INT  level=1  offset=2
current_scope->frame_size = 3
```

---

### 2.5 decls 结束，回填 INT 指令

`decls` 规则结束后，block 规则的**第二个 Mid-rule Action** 立刻触发：

```c
patch($<ival>2, scope_frame_size());
// $<ival>2 = 0（第一个 Mid-rule Action 存的占位指令下标）
// scope_frame_size() = 3（n + result + i 各占 1 字）
// 效果：code[0].a = 3
```

**P-Code 变化：**

```
0: INT 0 0   →   INT 0 3    ← 现在知道要分配 3 个字了
```

此时运行时的栈分布将是：

```
stack[0] = n
stack[1] = result
stack[2] = i
```

---

### 2.6 `read n;`（第9行）

**Lexer：**

| Token | yylval |
|-------|--------|
| `READ_KW` | 无 |
| `ID` | `sval = "n"` |
| `';'` | 无 |

**Parser 规则：** `io_stmt → READ_KW ID ';'`（$2 = "n"）：

```c
Symbol *s = sym_lookup("n");
// symtab：从当前作用域向上找，找到 {level=1, offset=0}
// 类型检查：T_INT ✓

int ld = scope_level() - s->level;   // 1 - 1 = 0（同一层，层差为0）

emit(READ, 0, 0);    // 从 stdin 读整数，压栈
emit(STO, 0, 0);     // 弹栈顶，存到 frame_base[当前帧] + 0 = stack[0]
```

**P-Code 产物：**
```
1: READ  0  0
2: STO   0  0
```

**运行时效果（以输入 n=5 为例）：**
```
READ  → 压栈 5，sp=4
STO   → stack[0] = 5，sp=3
```

---

### 2.7 `result = 1;`（第10行）

**Lexer：**

| Token | yylval |
|-------|--------|
| `ID` | `sval = "result"` |
| `'='` | 无 |
| `NUM` | `ival = 1` |
| `';'` | 无 |

**Parser 规则：** 先内后外，先归约 `expr → NUM`，再归约 `assign_stmt → ID '=' expr ';'`。

**Step 1：** `expr → NUM`（$1 = 1）：

```c
$$.type   = T_INT;
$$.level  = 0;      // 不是 set，level/offset 无意义，填0
$$.offset = 0;
emit(LIT, 0, $1);   // LIT 0 1：把常数 1 压栈
```

**Step 2：** `assign_stmt → ID '=' expr ';'`（$1="result"，$3=expr 的语义值）：

```c
Symbol *s = sym_lookup("result");   // {level=1, offset=1}
// 类型检查：s->type(T_INT) == $3.type(T_INT) ✓

int ld = scope_level() - s->level = 1 - 1 = 0;

// T_INT，用 STO
emit(STO, 0, 1);    // 弹栈顶，存到 stack[frame_base[0] + 1] = stack[1]
```

**P-Code 产物：**
```
3: LIT  0  1
4: STO  0  1
```

---

### 2.8 `i = 1;`（第11行）

与上完全对称，`sym_lookup("i")` → offset=2：

```
5: LIT  0  1
6: STO  0  2
```

---

## 3. while 循环——回填专题详解

这是最复杂的部分，分四个阶段。

```bison
while_stmt
    : WHILE
        { $<ctrl>$.addr = current_addr(); }   // 位置 $2：记录 loop_top
      '(' expr ')'
        {                                      // 位置 $6：条件结束后
            $<ctrl>$.jpc_idx = emit(JPC, 0, 0);
            $<ctrl>$.list    = make_patch($<ctrl>$.jpc_idx);
        }
      stmt
        {                                      // 最终动作
            emit(JMP, 0, $<ctrl>2.addr);
            do_patch($<ctrl>6.list, current_addr());
        }
    ;
```

### 阶段1：WHILE token 之后立刻记录 loop_top

**Lexer：** 返回 `WHILE`。

**Parser Mid-rule Action（位置 $2）：**

```c
$<ctrl>$.addr = current_addr();   // current_addr() = 7（下一条将要 emit 的地址）
```

此时还没有 emit 任何条件指令，所以 7 就是"条件判断的第一条指令地址"，即 loop_top。

---

### 阶段2：解析条件 `(i <= n)`

**Lexer 依次返回：** `'('`、`ID("i")`、`LE`、`ID("n")`、`')'`

**解析 `expr → ID`（即 i）：**

```c
Symbol *s = sym_lookup("i");   // {level=1, offset=2}
int ld = scope_level() - s->level = 1 - 1 = 0;

$$.type = T_INT;  $$.level = 0;  $$.offset = 2;
emit(LOD, 0, 2);   // 把 i 的值压栈
```

**解析 `expr → ID`（即 n）：**

```c
sym_lookup("n") → {level=1, offset=0}
emit(LOD, 0, 0);   // 把 n 的值压栈
```

**解析 `expr → expr LE expr`：**

```c
check_int2($1.type, $3.type, "<=");   // 两边都是 T_INT ✓
$$.type = T_BOOL;
emit(OPR, 0, OPR_LEQ);   // 弹出两个值，压入（i<=n）的结果 0 或 1
```

**P-Code（地址7-9）：**
```
7: LOD  0  2      ← load i
8: LOD  0  0      ← load n
9: OPR  0  12     ← i <= n，结果压栈
```

---

### 阶段3：条件结束后，emit JPC 占位（位置 $6 的 Mid-rule Action）

```c
$<ctrl>$.jpc_idx = emit(JPC, 0, 0);
// 此时不知道 loop_end 在哪里，先用 0 占位
// emit 返回该指令下标 = 10
// jpc_idx = 10

$<ctrl>$.list = make_patch(10);
// 创建一个 PatchNode{addr=10}，记录"将来要回填地址10"
```

**P-Code（地址10）：**
```
10: JPC  0  0     ← 占位，将来回填为 loop_end
```

**当前状态：**
```
$2.addr    = 7   ← loop_top
$6.jpc_idx = 10  ← 待回填的 JPC 指令下标
$6.list    = PatchNode{addr=10}
```

---

### 阶段4：解析 while 体（嵌套 block）

while 体 `{ result = result * i; i = i + 1; }` 是一个 `stmt → block`。

**block 入口：**

```c
scope_enter();     // level=2，base_offset=3，frame_size=0
emit(INT, 0, 0);   // 占位，地址11；decls 为空所以 patch 为 INT 0 0
```

**解析 `result = result * i;`：**

```c
// expr → ID(result)：
sym_lookup("result") → {level=1, offset=1}
ld = scope_level() - s->level = 2 - 1 = 1   // ← 现在是 level 2，变量在 level 1，层差=1
emit(LOD, 1, 1);   // 跨1帧取 result

// expr → ID(i)：
sym_lookup("i") → {level=1, offset=2}
ld = 2 - 1 = 1
emit(LOD, 1, 2);   // 跨1帧取 i

// expr → expr '*' expr
emit(OPR, 0, OPR_MUL);   // result * i

// assign_stmt：sym_lookup("result"), ld=1
emit(STO, 1, 1);   // 跨1帧写 result
```

> **层差（ld）的含义：** ld=0 表示在当前帧找变量；ld=1 表示去父帧找。PVM 的实现是 `frame_base[frame_top - 1 - ld]`。这里 while 体在 level=2，result 在 level=1，ld=1，PVM 会找 frame_base[0]（外层帧基址=0），然后 stack[0+1]=stack[1]=result。

**解析 `i = i + 1;`：**

```c
emit(LOD, 1, 2);   // load i（ld=1，跨帧）
emit(LIT, 0, 1);   // push 1
emit(OPR, 0, OPR_ADD);
emit(STO, 1, 2);   // store i
```

**block 出口：**

```c
sz = scope_frame_size() = 0;   // while 体没有局部变量
scope_exit();                   // level 回到 1
emit(INT, 0, -0);               // emit(INT, 0, 0)：归还 0 字
```

**P-Code（地址11-20）：**
```
11: INT  0   0    ← while 体 block 入口（0 字，仅建帧边界）
12: LOD  1   1    ← load result（ld=1 跨帧）
13: LOD  1   2    ← load i（ld=1 跨帧）
14: OPR  0   4    ← MUL
15: STO  1   1    ← result = result * i
16: LOD  1   2    ← load i
17: LIT  0   1
18: OPR  0   2    ← ADD
19: STO  1   2    ← i = i + 1
20: INT  0   0    ← while 体 block 出口（0 字）
```

---

### 阶段5：while_stmt 最终动作——完成回填

while 体 `stmt` 解析完毕，触发 while_stmt 的最终动作：

```c
emit(JMP, 0, $<ctrl>2.addr);
// $<ctrl>2.addr = 7（loop_top）
// 生成：JMP 0 7   ← 无条件跳回条件判断

do_patch($<ctrl>6.list, current_addr());
// current_addr() = 22（JMP 之后的下一个空位 = loop_end）
// 遍历 PatchNode 链表：patch(10, 22)
// 效果：code[10].a = 22

free_patch($<ctrl>6.list);   // 释放链表内存
```

**P-Code（地址21）：**
```
21: JMP  0   7
```

**回填结果：**
```
10: JPC  0   0   →   JPC  0  22    ← 条件假时跳到 loop_end(22)
21: JMP  0   7                     ← 无条件跳回 loop_top(7)
```

**完整 while 回填示意图：**

```
地址  指令
 7: LOD i          ← loop_top（while_stmt $2 在此记录 current_addr=7）
 8: LOD n
 9: OPR LEQ
10: JPC 0 [???]   ← 先 emit 占位，jpc_idx=10 存入 PatchNode
11: INT 0 0        ← while 体开始
...（体内指令）
20: INT 0 0        ← while 体结束
21: JMP 0 7        ← 跳回 loop_top（最终动作 emit，用 $2.addr=7）
22:                ← current_addr()=22，do_patch(10, 22) 填回 JPC
```

---

## 4. `write result;`（第18行）

**Lexer：** `WRITE_KW`，然后 `ID("result")`，然后 `';'`

**Parser：** 先归约 `expr → ID`，再归约 `io_stmt → WRITE_KW expr ';'`

**`expr → ID(result)`：**

```c
sym_lookup("result") → {type=T_INT, level=1, offset=1}
ld = 1 - 1 = 0
$$.type = T_INT;  $$.level = 0;  $$.offset = 1;
emit(LOD, 0, 1);   // 把 result 的值压栈
```

**`io_stmt` 动作：**

```c
if ($2.type == T_SET) { ... }    // 不是 set
else {
    emit(WRITE, 0, 0);           // 弹栈顶整数，打印
}
```

**P-Code（地址22-23）：**
```
22: LOD   0  1
23: WRITE 0  0
```

---

## 5. `if (result > 100)` ——回填再次出现

```bison
if_stmt
    : IF '(' expr ')'
        {                           // 位置 $5：emit JPC 占位
            jpc_idx = emit(JPC, 0, 0);
            list    = make_patch(jpc_idx);
        }
      stmt                          // then 体
        {                           // 位置 $7：then 结束
            jmp_idx = emit(JMP, 0, 0);          // 跳过 else
            do_patch($5.list, current_addr());   // 回填 JPC → else_start
            $7.list = make_patch(jmp_idx);
        }
      ELSE stmt                     // else 体
        {                           // 最终动作
            do_patch($7.list, current_addr());   // 回填 JMP → after_else
        }
```

### 解析条件 `result > 100`

```c
// expr → ID(result)
sym_lookup("result") → {level=1, offset=1}, ld=0
emit(LOD, 0, 1);     // code[24]

// expr → NUM(100)
emit(LIT, 0, 100);   // code[25]

// expr → expr '>' expr
check_int2(T_INT, T_INT, ">");
$$.type = T_BOOL;
emit(OPR, 0, OPR_GT);   // code[26]
```

### 位置 $5 的 Mid-rule Action

```c
$<ctrl>$.jpc_idx = emit(JPC, 0, 0);   // code[27]，jpc_idx=27
$<ctrl>$.list    = make_patch(27);
```

```
27: JPC  0  0    ← 占位
```

### then 体 `{ write 1; }`（stmt → block）

```
28: INT  0  0    ← then block 入口
29: LIT  0  1
30: WRITE 0  0
31: INT  0  0    ← then block 出口
```

### 位置 $7 的 Mid-rule Action（then 结束、else 开始前）

```c
int jmp_idx = emit(JMP, 0, 0);         // code[32]，跳过 else，占位
do_patch($<ctrl>5.list, current_addr());
// current_addr() = 33（JMP 之后的下一个空位 = else_start）
// patch(27, 33)：code[27].a = 33

$<ctrl>$.list = make_patch(32);         // 记录 JMP 待回填
```

```
32: JMP  0  0    ← 占位，将回填为 after_else
```

### else 体 `{ write 0; }`

```
33: INT  0  0    ← else block 入口（此时 code[27] 已被回填为 JPC 0 33）
34: LIT  0  0
35: WRITE 0  0
36: INT  0  0    ← else block 出口
```

### 最终动作（else 结束后）

```c
do_patch($<ctrl>7.list, current_addr());
// current_addr() = 37（after_else）
// patch(32, 37)：code[32].a = 37
```

### if-else 回填示意图

```
27: JPC 0 [???]  ← emit 时地址未知，先填0；后来 patch → 33
28-31: (then 体)
32: JMP 0 [???]  ← emit 时 after_else 未知，先填0；后来 patch → 37
33-36: (else 体)   ← code[27] 在 then 结束时被回填到这里
37:                ← code[32] 在 else 结束时被回填到这里
```

---

## 6. 外层 block 关闭 `}`

```c
int sz = scope_frame_size();   // = 3（n、result、i 共 3 字）
scope_exit();                  // 弹出 level=1 的作用域，销毁所有 Symbol
emit(INT, 0, -3);              // code[37]：归还 3 个字
```

```
37: INT  0  -3
```

---

## 7. program 规则收尾

```bison
program : block { emit(OPR, 0, OPR_RET); }
```

```c
emit(OPR, 0, OPR_RET);   // code[38]
```

```
38: OPR  0   0    ← RET
```

PVM 执行到 OPR_RET 时，`pvm_run()` 直接 `return`，程序结束。

---

## 8. 符号表最终状态（外层 block 内）

| 变量 | type | level | offset | 栈地址 |
|------|------|-------|--------|--------|
| n | T_INT | 1 | 0 | stack[0] |
| result | T_INT | 1 | 1 | stack[1] |
| i | T_INT | 1 | 2 | stack[2] |

scope_exit() 后这三个 Symbol 被 free，但 stack 里的值还在（INT 0 -3 会让 sp 回退3位，从逻辑上释放）。

---

## 9. 运行时内存快照（n=5 时的关键时刻）

**循环开始前：**
```
stack[0]=5(n)  stack[1]=1(result)  stack[2]=1(i)   sp=3
```

**第3次迭代（i=3, result=2）执行 result * i 时，栈的瞬态：**
```
stack[0]=5  stack[1]=2  stack[2]=3   sp=3
LOD 1 1 → push 2,  sp=4
LOD 1 2 → push 3,  sp=5
OPR MUL → pop 3, pop 2, push 6,  sp=4
STO 1 1 → pop 6 → stack[1]=6,  sp=3
```

**循环结束后（i=6 > n=5，JPC 跳走）：**
```
stack[0]=5  stack[1]=120  stack[2]=6   sp=3
```

**write result 输出 120，if(120 > 100) 为真，write 1，最终输出：**
```
120
1
```

---

## 10. 总结：三次回填对照表

| 回填对象 | emit 时地址 | 回填时机 | 回填值 | 含义 |
|---------|------------|---------|-------|------|
| while JPC（code[10]） | 10 | while 体 stmt 结束后 | 22 | 条件假跳到 loop_end |
| if JPC（code[27]） | 27 | then 体结束后 | 33 | 条件假跳到 else_start |
| if JMP（code[32]） | 32 | else 体结束后 | 37 | then 执行完跳过 else |

**回填的本质：** Bison 自底向上解析，读到 `while` 关键字时还没生成循环体，所以不可能知道 loop_end 在哪。`make_patch` 记住"坑的位置"，`do_patch` 在"知道答案"的时刻填回去。`current_addr()` 永远返回"下一条待 emit 指令的地址"，即"刚刚结束的位置"，这正是跳转目标所需的值。
