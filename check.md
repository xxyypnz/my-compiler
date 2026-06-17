# check.md — 扩展功能一二 现场改题应对

---

## 扩展一：P-Code 可视化 + 单步运行

### 考察点 1：改变 P-Code 的打印格式

**可能的题目：** "把地址从十进制改成十六进制输出" / "每行加一个分隔符" / "OPR 的注释去掉"

**改动位置：** `codegen.c:81–96`，`printf` 格式串

```c
// 原：十进制地址
printf("%4d:  %-10s %6d %6d\n", i, ...);
// 改成十六进制：
printf("%04X:  %-10s %6d %6d\n", i, ...);
```

---

### 考察点 2：单步时显示更多栈内容（不只显示栈顶）

**可能的题目：** "单步时把栈上所有值都打印出来"

**改动位置：** `pvm.c:178–184`，在交互块里加循环

```c
// 原来只打印栈顶 stack[sp-1]
// 改成打印全部：
for (int i = sp - 1; i >= 0; i--)
    printf("  stack[%d]=%d\n", i, stack[i]);
```

---

### 考察点 3：让 `-p` 选项不打印表头，只输出指令

**可能的题目：** "去掉 === Generated P-Code === 这些装饰行"

**改动位置：** `codegen.c:77–79` 和 `codegen.c:97`，删掉 printf 的表头和分隔线

---

### 考察点 4：单步时显示当前帧的所有局部变量值

**可能的题目：** "每步显示当前帧的内存布局"

**改动位置：** `pvm.c:176–185`，在交互块里加：

```c
if (frame_top > 0) {
    int base = frame_base[frame_top - 1];
    for (int i = base; i < sp; i++)
        printf("  mem[%d]=%d\n", i - base, stack[i]);
}
```

---

### 考察点 5：新增 `-v` 参数只打印 P-Code 不运行（与 `-p` 区分）

**改动位置：** `main.c:22–30` 参数解析，增加一个 `else if strcmp "-v"` 分支，逻辑与 `-p` 相同。

---

## 扩展二：集合相等判断

### 考察点 6：改成子集判断（A ⊆ B）而不是相等

**可能的题目：** "把 `==` 改成判断左边是不是右边的子集"

**改动位置：** `pvm.c:105–111`，`set_equal` 函数

```c
// 原来：先比 count，再双向检查
// 改成子集（只需 a 的每个元素都在 b 里，不比 count）：
static int set_subset(int *a, int *b) {
    int ca = a[0];
    for (int i = 1; i <= ca; i++)
        if (!set_contains(b, a[i])) return 0;
    return 1;
}
```

`pvm.c:344` 把 `set_equal` 换成 `set_subset`。

---

### 考察点 7：相等判断的结果改成输出 "true"/"false" 字符串而非 0/1

**可能的题目：** "让集合相等的结果打印 true/false 而不是数字"

这个其实改的不是 `SET_EQL`，而是 `WRITE` 指令，或者在 `io_stmt` 里特判 bool 类型：

**改动位置：** `pvm.c:273–275`

```c
case WRITE:
    // 原：printf("%d\n", pop());
    // 改：
    int v = pop();
    if (v == 0 || v == 1) printf("%s\n", v ? "true" : "false");
    else printf("%d\n", v);
    break;
```

> 注意：这会影响所有 bool 结果输出，不只是 set==，要说明这一点。

---

### 考察点 8：让 set_equal 处理一侧是 temp_set（字面量）的情况

**可能的题目：** "让 `{1,2,3} == s1` 这种写法也能工作"

**问题所在：** 当前 `parser.y:437` 的 set== 分支要求两侧都是命名变量（level≥0），字面量的 level=-1，走不进去。

**改动位置：** `parser.y:437–441`，增加对 level<0 一侧的处理，把 temp_set 地址传进去；或者在 pvm 里为 temp_set 分配一个固定的"虚拟地址"。

> 这道题改动较大，可以告诉助教"当前实现要求两侧都是命名 set 变量，支持字面量需要扩展寻址机制"。

---

### 考察点 9：在 P-Code 打印中，SET_EQL 的格式改为和普通指令一样（不解码）

**可能的题目：** "统一打印格式，SET_EQL 也只打 l 和 a 的原始值"

**改动位置：** `codegen.c:87–92`，把 `SET_EQL` 从第二个 `else if` 里移出，让它走最后的 `else` 分支即可。

```c
// 原：SET_UNION || SET_INTER || SET_EQL 走解码分支
// 改：只让 SET_UNION 和 SET_INTER 解码，SET_EQL 走普通格式
} else if (ins->op == SET_UNION || ins->op == SET_INTER) {
```

---

## 通用应对原则

| 情况 | 策略 |
|------|------|
| 改打印格式 | 只动 `printf` 格式串，逻辑不变，改完立刻重新 `make` |
| 改判断逻辑 | 先找到对应的 C 函数（`set_equal`/`set_contains`），改函数体，不动 emit 和指令结构 |
| 改参数行为 | 只动 `main.c` 的参数解析段（第22–30行），加 `else if` 分支 |
| 改指令输出 | 区分是改编译期打印（`codegen.c`）还是运行期行为（`pvm.c`），不要改错文件 |
| 不确定影响范围 | 先说"这个改动会影响到X，需要同时修改Y"，显示你理解模块关系 |
