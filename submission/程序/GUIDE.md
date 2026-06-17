# GUIDE — L26 编译器个人操作手册

## 环境要求

- WSL (Ubuntu) 或 Linux
- `gcc`, `flex`, `bison`, `make`

安装（Ubuntu/WSL）：
```bash
sudo apt update && sudo apt install -y gcc flex bison make
```

---

## 构建

```bash
cd /mnt/c/2026-06-01/compile   # 或你的实际路径
make
```

成功后生成可执行文件 `l26c`。

清理重建：
```bash
make clean && make
```

---

## 运行方式

```bash
./l26c <源文件.l26>          # 编译并运行，自动打印 P-Code
./l26c -s <源文件.l26>       # 单步模式（每步按 Enter，r=连续运行，q=退出）
./l26c -p <源文件.l26>       # 只打印 P-Code，不执行
```

---

## 运行所有测试

```bash
make test
```

或逐个运行：
```bash
echo "5" | ./l26c tests/test1.l26    # test1 需要输入，这里输入 5
./l26c tests/test2.l26
./l26c tests/test3.l26
./l26c tests/test4.l26
./l26c tests/test5.l26
```

---

## 各测试预期输出

### test1.l26 — 阶乘 + if/else（输入 5）
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

### test3.l26 — 嵌套作用域与遮蔽
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

---

## 单步模式说明

运行 `./l26c -s tests/test1.l26` 后，每条 P-Code 指令执行前会显示：

```
  [   3] LOD         0   0
  sp=5    stack top: 3  [Enter=step  r=run  q=quit]
```

- **Enter** — 执行当前指令，显示下一条
- **r** — 切换到连续运行模式
- **q** — 退出

---

## P-Code 输出格式

每次运行都会先打印完整 P-Code 列表，例如：

```
=== Generated P-Code ===
Addr   Op           L      A
-------------------------------
   0:  INT          0      2
   1:  LIT          0      1
   2:  STO          0      0
   3:  LOD          0      0
   4:  LIT          0     10
   5:  OPR          0      9   ; LT
   6:  JPC          0     11
   7:  LOD          0      0
   8:  WRITE        0      0
   9:  INT          0     -2
  10:  OPR          0      0   ; RET
================================
```

---

## 加分项演示

### 集合相等（test4.l26）
```l26
if (s1 == s2) { write 1; } else { write 0; }
```
两个集合元素完全相同（顺序无关）时输出 1。

### 集合推导式（test4.l26）
```l26
result = { x * 2 | x in s1 if x > 2 };
```
对 s1 中每个满足 `x > 2` 的元素，计算 `x * 2`，构成新集合。

---

## 文件结构

```
compile/
├── pcode.h          指令集定义
├── symtab.h/c       符号表（嵌套作用域）
├── codegen.h/c      P-Code 生成
├── lexer.l          Flex 词法规则
├── parser.y         Bison 语法 + 语义动作
├── pvm.h/c          P-Code 虚拟机
├── main.c           入口
├── Makefile
└── tests/
    ├── test1.l26    阶乘 + 控制流
    ├── test2.l26    集合操作
    ├── test3.l26    嵌套作用域
    ├── test4.l26    加分项
    └── test5.l26    综合测试
```

---

## 常见问题

**bison 报 shift/reduce 冲突**
正常，dangling-else 冲突由 `%nonassoc NO_ELSE / ELSE` 解决，其余冲突数应为 0。

**flex 报 `yylineno` 重定义**
lexer.l 里已有 `%option yylineno`，parser.y 里的 `extern int yylineno` 声明不会冲突。

**运行时 "invalid level difference"**
说明 LOD/STO 的层差计算有误，检查 scope_level() 调用时机。

**集合输出顺序**
集合元素按升序排列输出（`print_set` 内部 qsort），与插入顺序无关。
