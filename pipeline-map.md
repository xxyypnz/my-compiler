# L26 编译器主线流程：文件与行号对照表

> 不含扩展功能（集合相等、集合推导式、单步运行、P-Code可视化）

---

## 一、驱动层 `main.c`

| 事件 | 行号 |
|------|------|
| 参数解析（-s / -p / 文件名） | 22–30 |
| 打开源文件，赋给 `yyin` | 31–35 |
| 调用 `yyparse()`，触发整个编译过程 | 37 |
| 调用 `pvm_run()`，执行生成的 P-Code | 48 |

---

## 二、词法层 `lexer.l`

### 忽略的输入

| 规则 | 行号 |
|------|------|
| 空格 / Tab / 回车 | 16 |
| 换行（`yylineno` 自动累加） | 17 |
| `//` 行注释 | 18 |
| `/* */` 块注释 | 19 |

### 关键字 → Token

| 关键字 | 行号 |
|--------|------|
| `int` | 21 |
| `bool` | 22 |
| `set` | 23 |
| `if` | 24 |
| `else` | 25 |
| `while` | 26 |
| `read` | 27 |
| `write` | 28 |
| `true`（同时写 `yylval.ival=1`） | 29 |
| `false`（同时写 `yylval.ival=0`） | 30 |
| `add` | 31 |
| `remove` | 32 |
| `union` | 33 |
| `inter` | 34 |
| `in` | 35 |
| `isempty` | 36 |

### 标识符 / 数字 / 运算符

| 规则 | 行号 |
|------|------|
| 标识符（写 `yylval.sval`，return `ID`） | 38–42 |
| 整数（写 `yylval.ival`，return `NUM`） | 44–46 |
| 双字符运算符 `<=` `>=` `==` `!=` `&&` `\|\|` | 49–54 |
| 单字符运算符和分隔符 `+ - * / < > ! ( ) { } ; , | =` | 56 |
| 未知字符（报错，不退出） | 58–61 |

---

## 三、语法 + 语义 + 代码生成层 `parser.y`

### 3.1 序言区（C 函数，编译期辅助）

| 内容 | 行号 |
|------|------|
| `PatchNode` 结构体定义 | 16–19 |
| `make_patch(addr)`：创建回填节点 | 21–26 |
| `do_patch(list, target)`：执行回填 | 28–31 |
| `free_patch(list)`：释放回填链表 | 33–39 |
| `type_error(msg)`：语义错误报错并退出 | 44–47 |
| `check_int2(t1,t2,op)`：要求两操作数为 int | 49–55 |
| `check_bool2(t1,t2,op)`：要求两操作数为 bool | 57–63 |

### 3.2 Bison 声明区

| 内容 | 行号 |
|------|------|
| `%glr-parser` | 74 |
| `%union`（定义 yylval 的所有字段） | 79–94 |
| `%token` 声明（含携带值的字段绑定） | 99–106 |
| `%type` 声明（非终结符的语义值字段绑定） | 111–114 |
| 优先级声明（从低到高：`||` → `&&` → `!` → 关系 → `+-` → `*/` → UMINUS → `in` → `union inter`） | 119–130 |

### 3.3 文法规则区

#### 程序结构

| 规则 | 行号 |
|------|------|
| `program → block`（末尾 emit RET） | 136–139 |
| `block → '{' … '}'`（scope_enter、INT占位、patch、scope_exit、INT释放） | 150–167 |
| `decls → ε \| decls decl` | 172–175 |
| `decl → type ID ';'`（sym_declare、set 变量额外 emit SET_NEW） | 177–190 |
| `type → int \| bool \| set` | 192–196 |

#### 语句

| 规则 | 行号 |
|------|------|
| `stmts → ε \| stmts stmt` | 201–204 |
| `stmt`（分发到各子规则） | 206–213 |
| `assign_stmt → ID '=' expr ';'`（sym_lookup、类型检查、emit STO / SET_COPY） | 215–238 |
| `if_stmt`（无 else 分支） | 241–251 |
| `if_stmt`（有 else 分支） | 252–270 |
| `while_stmt`（记录 loop_top、emit JPC 占位、emit JMP、do_patch） | 272–287 |
| `io_stmt → write expr ';'` | 290–304 |
| `io_stmt → read ID ';'` | 305–317 |
| `set_op_stmt → add ID expr ';'` | 320–330 |
| `set_op_stmt → remove ID expr ';'` | 331–342 |

#### 表达式

| 规则 | 行号 |
|------|------|
| `expr → NUM`（emit LIT） | 348–352 |
| `expr → true`（emit LIT 1） | 353–357 |
| `expr → false`（emit LIT 0） | 358–362 |
| `expr → ID`（sym_lookup；int/bool emit LOD；set 不压栈只传地址） | 363–379 |
| `expr → expr + expr` | 380–385 |
| `expr → expr - expr` | 386–391 |
| `expr → expr * expr` | 392–397 |
| `expr → expr / expr` | 398–403 |
| `expr → - expr`（单目负号，%prec UMINUS） | 404–409 |
| `expr → expr < expr` | 410–415 |
| `expr → expr > expr` | 416–421 |
| `expr → expr <= expr` | 422–427 |
| `expr → expr >= expr` | 428–433 |
| `expr → expr == expr`（int/bool 分支；set== 分支为扩展） | 442–443 |
| `expr → expr != expr` | 448–453 |
| `expr → expr && expr` | 454–459 |
| `expr → expr \|\| expr` | 460–465 |
| `expr → ! expr` | 466–471 |
| `expr → ( expr )` | 472–473 |
| `expr → { expr_list }`（集合字面量，emit SET_LIT） | 476–480 |
| `expr → { }`（空集合，emit SET_LIT 0） | 481–485 |
| `expr → ID union ID`（emit SET_UNION） | 488–503 |
| `expr → ID inter ID`（emit SET_INTER） | 507–523 |
| `expr → expr in ID`（emit SET_IN） | 526–536 |
| `expr → isempty ( ID )`（emit SET_EMPTY） | 539–548 |
| `expr_list → expr \| expr_list , expr`（计数，传给 SET_LIT） | 701–706 |

#### 错误处理

| 内容 | 行号 |
|------|------|
| `yyerror()`（语法错误回调，打印行号后 exit） | 710–713 |

---

## 四、符号表层 `symtab.c`

| 函数 | 行号 |
|------|------|
| `type_width(t)`：int/bool 返回 1，set 返回 201 | 8–10 |
| `scope_enter()`：创建新 Scope 帧，链入作用域栈 | 12–22 |
| `scope_exit()`：释放当前 Scope 及其所有 Symbol | 24–35 |
| `scope_level()`：统计当前作用域栈深度 | 37–42 |
| `scope_frame_size()`：当前 Scope 已分配的字数 | 44–46 |
| `scope_total_size()` | 48–52 |
| `sym_declare(name, type)`：在当前 Scope 注册变量，分配 offset | 54–70 |
| `sym_lookup(name)`：从当前 Scope 向上逐层查找变量 | 73–78 |

---

## 五、代码发射层 `codegen.c`

| 函数 | 行号 |
|------|------|
| `code[]` 数组和 `code_len` 定义 | 5–6 |
| `emit(op, l, a)`：追加一条指令，返回其下标 | 8–18 |
| `patch(idx, new_a)`：回填指令的 `a` 字段 | 20–22 |
| `current_addr()`：返回下一条指令的地址（=`code_len`） | 24–26 |

---

## 六、虚拟机层 `pvm.c`

### 6.1 运行时数据结构

| 内容 | 行号 |
|------|------|
| `stack[]`、`sp`、`pc` | 7–9 |
| `frame_base[]`、`frame_top` | 12–13 |
| `temp_set[]`（set 运算的全局临时缓冲） | 16 |

### 6.2 内部辅助函数

| 函数 | 行号 |
|------|------|
| `get_frame_base(ld)`：按层差找帧基址 | 22–30 |
| `var_addr(ld, off)`：变量地址 = 帧基址 + 偏移 | 32–34 |
| `set_base(ld, off)`：set 变量首地址（同 var_addr） | 36–38 |
| `push(v)` | 40–43 |
| `pop()` | 45–49 |
| `set_contains(base, v)` | 55–59 |
| `set_add_elem(base, v)`（去重插入） | 61–72 |
| `set_rem_elem(base, v)`（移除，平移填坑） | 73–84 |
| `set_copy(dst, src)` | 86–88 |
| `set_union(dst, a, b)` | 90–96 |
| `set_inter(dst, a, b)` | 98–103 |
| `print_set(base)`（排序后打印） | 117–128 |

### 6.3 主执行循环入口

| 内容 | 行号 |
|------|------|
| `pvm_run()` 函数，初始化 pc/sp/frame_top | 164–169 |
| 主循环 `while(1)` | 170 |
| 取指 `ins = code[pc++]` | 187 |
| `switch(ins.op)` | 189 |

### 6.4 基础指令实现

| 指令 | 行号 |
|------|------|
| `LIT` | 191–193 |
| `LOD` | 195–197 |
| `STO` | 199–201 |
| `INT`（≥0 建帧分配 / <0 退帧释放） | 203–221 |
| `JMP` | 223–225 |
| `JPC`（弹栈顶，为 0 则跳转） | 227–229 |
| `OPR` 分发 switch | 231–261 |
| — `OPR_RET`（return，程序结束） | 234–235 |
| — `OPR_NEG` | 236–238 |
| — `OPR_ADD` | 239 |
| — `OPR_SUB` | 240 |
| — `OPR_MUL` | 241 |
| — `OPR_DIV`（含除零检查） | 242–246 |
| — `OPR_EQ` | 247 |
| — `OPR_NEQ` | 248 |
| — `OPR_LT` | 249 |
| — `OPR_GEQ` | 250 |
| — `OPR_GT` | 251 |
| — `OPR_LEQ` | 252 |
| — `OPR_NOT` | 253 |
| — `OPR_AND` | 254 |
| — `OPR_OR` | 255 |
| `READ`（scanf，结果压栈） | 263–270 |
| `WRITE`（pop 打印整数） | 273–275 |

### 6.5 Set 指令实现

| 指令 | 行号 |
|------|------|
| `WRITES`（按地址打印命名 set） | 277–280 |
| `WRITET`（打印 temp_set） | 282–285 |
| `SET_NEW`（清零 201 字） | 287–289 |
| `SET_LIT`（弹 n 个 int，去重放入 temp_set） | 291–299 |
| `SET_ADD`（弹栈顶，加入指定 set） | 301–305 |
| `SET_REM`（弹栈顶，从指定 set 删除） | 307–311 |
| `SET_IN`（弹栈顶，检查成员，压 0/1） | 313–317 |
| `SET_EMPTY`（检查 count==0，压 0/1） | 319–321 |
| `SET_UNION`（结果写入 temp_set） | 323–328 |
| `SET_INTER`（结果写入 temp_set） | 330–335 |
| `SET_COPY`（从 temp_set 拷贝到指定 set） | 337–339 |
