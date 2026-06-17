# Step 9：`pvm.c` 集合运行时

本阶段继续读：

```text
pvm.c
pcode.h
```

范围：

```text
SET_SIZE
temp_set
set helpers
WRITES / WRITET
SET_NEW / SET_LIT / SET_ADD / SET_REM
SET_IN / SET_EMPTY
SET_UNION / SET_INTER / SET_COPY / SET_EQL / SET_ELEM
ENCODE2 / DECODE_LD / DECODE_OFF
```

目标：看懂集合在运行时怎么存、怎么查、怎么增删、怎么做并交相等，以及集合推导式如何取元素。

## Step 8 承接

Step 8 已经看懂普通 PVM：

```text
stack / sp / pc / frame_base
LIT / LOD / STO / INT / JMP / JPC / OPR
```

现在剩下集合问题：

1. `set` 为什么占 `201` 个 word？
2. 集合元素放在哪里？
3. `s = {1, 2, 3}` 运行时怎么执行？
4. `add/remove/in/isempty` 怎么实现？
5. `union/inter` 为什么把结果放进 `temp_set`？
6. `SET_EQL` 如何判断两个集合相等？
7. 集合推导式如何用 `SET_ELEM` 取第 `idx` 个元素？

## 1. `SET_SIZE`

`pcode.h` 里：

```c
#define SET_SIZE  201   /* 1 count word + 200 element words */
```

一个集合变量固定占：

```text
201 个 int word
```

布局：

```text
base[0]      元素个数 count
base[1]      第 1 个元素
base[2]      第 2 个元素
...
base[count]  第 count 个元素
```

最多保存：

```text
SET_SIZE - 1 = 200
```

个元素。

## 2. 集合变量的栈布局

源码：

```l26
{
    int x;
    set s;
    bool b;
}
```

符号表 offset 可能是：

```text
x offset = 0，宽度 1
s offset = 1，宽度 201
b offset = 202，宽度 1
```

如果当前 frame base 是 `100`，则：

```text
x      -> stack[100]
s      -> stack[101] 到 stack[301]
b      -> stack[302]
```

集合 `s` 的内部：

```text
stack[101] = count
stack[102] = element 1
stack[103] = element 2
...
```

所以集合的“地址”就是：

```text
base = &stack[frame_base + offset]
```

## 3. `temp_set`

```c
static int temp_set[SET_SIZE];
```

`temp_set` 是全局临时集合缓冲区。

用于保存这些表达式结果：

```text
集合字面量：{1, 2, 3}
并集：s1 union s2
交集：s1 inter s2
集合推导式：{ x * 2 | x in s if x > 2 }
```

为什么需要它？

因为普通表达式结果可以压一个整数到栈顶。

集合结果是 201 个 word，不适合直接作为单个栈值传递。

所以约定：

```text
集合临时结果统一放在 temp_set
```

赋值时：

```text
SET_COPY 把 temp_set 复制到目标集合变量
```

打印临时集合时：

```text
WRITET 打印 temp_set
```

## 4. `set_base`

```c
static int *set_base(int ld, int off) {
    return var_addr(ld, off);
}
```

`set_base` 根据：

```text
层差 ld
偏移 off
```

返回集合变量的基址。

它实际只是调用：

```c
var_addr(ld, off)
```

因为集合变量也从 stack 里分配。

区别在于：返回的地址后面连续 `SET_SIZE` 个 word 都属于这个集合。

## 5. `set_contains`

```c
static int set_contains(int *base, int v) {
    int cnt = base[0];
    for (int i = 1; i <= cnt; i++)
        if (base[i] == v) return 1;
    return 0;
}
```

作用：判断集合里是否有元素 `v`。

参数：

- `base`：集合基址。
- `v`：要查找的元素。

变量：

- `cnt`：元素数量，也就是 `base[0]`。
- `i`：遍历下标，从 `1` 到 `cnt`。

返回：

```text
1  找到了
0  没找到
```

集合不排序，所以查找是线性扫描。

## 6. `set_add_elem`

```c
static void set_add_elem(int *base, int v) {
    if (set_contains(base, v)) return;
    int cnt = base[0];
    if (cnt >= SET_SIZE - 1) {
        fprintf(stderr, "runtime error: set overflow (max %d elements)\n", SET_SIZE - 1);
        exit(1);
    }
    base[cnt + 1] = v;
    base[0]++;
}
```

作用：向集合加入元素。

### 去重

```c
if (set_contains(base, v)) return;
```

集合不允许重复元素。

如果元素已经存在，直接返回。

### 容量检查

```c
if (cnt >= SET_SIZE - 1)
```

最多只能放 200 个元素。

超过就运行时报错。

### 插入

```c
base[cnt + 1] = v;
base[0]++;
```

把新元素放在当前最后一个元素之后，然后元素数量加 1。

## 7. `set_rem_elem`

```c
static void set_rem_elem(int *base, int v) {
    int cnt = base[0];
    for (int i = 1; i <= cnt; i++) {
        if (base[i] == v) {
            for (int j = i; j < cnt; j++) base[j] = base[j + 1];
            base[0]--;
            return;
        }
    }
}
```

作用：从集合删除元素。

### 查找元素

```c
for (int i = 1; i <= cnt; i++)
```

从第一个元素扫到最后一个。

### 左移覆盖

```c
for (int j = i; j < cnt; j++) base[j] = base[j + 1];
```

找到后，把后面的元素整体左移一格。

例子：

```text
{1, 2, 3}
删除 2
```

内部数组从：

```text
base[0]=3, base[1]=1, base[2]=2, base[3]=3
```

变成：

```text
base[0]=2, base[1]=1, base[2]=3
```

### 不存在则不做事

如果元素没找到，函数直接结束。

所以：

```l26
remove s 99;
```

如果 `99` 不在 `s` 中，是 no-op。

## 8. `set_copy`

```c
static void set_copy(int *dst, int *src) {
    memcpy(dst, src, SET_SIZE * sizeof(int));
}
```

作用：复制整个集合。

参数：

- `dst`：目标集合基址。
- `src`：源集合基址。

复制长度：

```text
SET_SIZE * sizeof(int)
```

也就是包括 count word 和所有元素 word。

用于：

```text
SET_COPY
```

## 9. `set_union`

```c
static void set_union(int *dst, int *a, int *b) {
    memset(dst, 0, SET_SIZE * sizeof(int));
    int ca = a[0];
    for (int i = 1; i <= ca; i++) set_add_elem(dst, a[i]);
    int cb = b[0];
    for (int i = 1; i <= cb; i++) set_add_elem(dst, b[i]);
}
```

作用：

```text
dst = a ∪ b
```

步骤：

1. 清空 `dst`。
2. 把 `a` 的所有元素加入 `dst`。
3. 把 `b` 的所有元素加入 `dst`。

因为 `set_add_elem` 自动去重，所以并集不会有重复元素。

## 10. `set_inter`

```c
static void set_inter(int *dst, int *a, int *b) {
    memset(dst, 0, SET_SIZE * sizeof(int));
    int ca = a[0];
    for (int i = 1; i <= ca; i++)
        if (set_contains(b, a[i])) set_add_elem(dst, a[i]);
}
```

作用：

```text
dst = a ∩ b
```

步骤：

1. 清空 `dst`。
2. 遍历 `a`。
3. 如果 `a[i]` 也在 `b` 中，就加入 `dst`。

## 11. `set_equal`

```c
static int set_equal(int *a, int *b) {
    if (a[0] != b[0]) return 0;
    int ca = a[0];
    for (int i = 1; i <= ca; i++)
        if (!set_contains(b, a[i])) return 0;
    return 1;
}
```

作用：判断两个集合是否相等。

集合相等不要求内部顺序一致。

### 数量先相等

```c
if (a[0] != b[0]) return 0;
```

元素个数不同，集合一定不相等。

### 元素逐个检查

```c
for (int i = 1; i <= ca; i++)
    if (!set_contains(b, a[i])) return 0;
```

只要 `a` 中有一个元素不在 `b` 中，就不相等。

如果数量相同，且 `a` 的每个元素都在 `b` 中，则两个集合相等。

## 12. `print_set`

```c
static int cmp_int(const void *x, const void *y) {
    return *(int *)x - *(int *)y;
}
```

`cmp_int` 是 `qsort` 的比较函数。

```c
static void print_set(int *base) {
    int cnt = base[0];
    int tmp[SET_SIZE - 1];
    for (int i = 0; i < cnt; i++) tmp[i] = base[i + 1];
    qsort(tmp, cnt, sizeof(int), cmp_int);
    printf("{");
    for (int i = 0; i < cnt; i++) {
        if (i) printf(", ");
        printf("%d", tmp[i]);
    }
    printf("}");
}
```

作用：打印集合。

### 为什么复制到 `tmp`

```c
int tmp[SET_SIZE - 1];
for (int i = 0; i < cnt; i++) tmp[i] = base[i + 1];
```

打印前把元素复制出来。

这样排序不会改变集合真实存储顺序。

### 为什么排序

```c
qsort(tmp, cnt, sizeof(int), cmp_int);
```

集合本身无序。

为了输出稳定、测试容易比较，打印时按升序输出。

例子：

```text
内部可能是 {5, 1, 3}
打印为 {1, 3, 5}
```

## 13. `WRITES`

```c
case WRITES:
    print_set(set_base(ins.l, ins.a));
    printf("\n");
    break;
```

指令格式：

```text
WRITES ld offset
```

作用：打印具名集合变量。

parser 在：

```l26
write s;
```

如果 `s` 是集合变量，会生成：

```text
WRITES ld offset
```

PVM 先通过：

```c
set_base(ins.l, ins.a)
```

找到集合地址，再调用 `print_set`。

## 14. `WRITET`

```c
case WRITET:
    print_set(temp_set);
    printf("\n");
    break;
```

指令格式：

```text
WRITET 0 0
```

作用：打印临时集合结果。

用于：

```l26
write s1 union s2;
write {1, 2, 3};
```

这些表达式结果在：

```text
temp_set
```

所以不能用 `WRITES`。

## 15. `SET_NEW`

```c
case SET_NEW:
    memset(set_base(ins.l, ins.a), 0, SET_SIZE * sizeof(int));
    break;
```

指令格式：

```text
SET_NEW ld offset
```

作用：初始化集合变量为空集合。

把整个集合区域清零：

```text
base[0] = 0
base[1..200] = 0
```

parser 在声明集合变量时生成：

```l26
set s;
```

对应：

```text
SET_NEW addr(s)
```

## 16. `SET_LIT`

```c
case SET_LIT: {
    int elems[SET_SIZE - 1];
    int n = ins.a;
    for (int i = n - 1; i >= 0; i--) elems[i] = pop();
    memset(temp_set, 0, SET_SIZE * sizeof(int));
    for (int i = 0; i < n; i++) set_add_elem(temp_set, elems[i]);
    break;
}
```

指令格式：

```text
SET_LIT 0 n
```

作用：把栈顶的 `n` 个整数组成集合，放进 `temp_set`。

### `n`

```c
int n = ins.a;
```

集合字面量元素个数。

### 为什么倒序弹栈

parser 对：

```l26
{1, 2, 3}
```

会先生成：

```text
LIT 0 1
LIT 0 2
LIT 0 3
SET_LIT 0 3
```

执行到 `SET_LIT` 时，栈顶顺序是：

```text
top -> 3, 2, 1
```

所以代码：

```c
for (int i = n - 1; i >= 0; i--) elems[i] = pop();
```

把它还原成：

```text
elems[0] = 1
elems[1] = 2
elems[2] = 3
```

### 构造 `temp_set`

```c
memset(temp_set, 0, SET_SIZE * sizeof(int));
for (int i = 0; i < n; i++) set_add_elem(temp_set, elems[i]);
```

先清空临时集合，再逐个加入元素。

`set_add_elem` 会自动去重。

## 17. `SET_ADD`

```c
case SET_ADD: {
    int v = pop();
    set_add_elem(set_base(ins.l, ins.a), v);
    break;
}
```

指令格式：

```text
SET_ADD ld offset
```

作用：把栈顶整数加入集合变量。

parser 对：

```l26
add s expr;
```

会先生成 `expr` 的代码，把元素值压栈，再生成：

```text
SET_ADD addr(s)
```

## 18. `SET_REM`

```c
case SET_REM: {
    int v = pop();
    set_rem_elem(set_base(ins.l, ins.a), v);
    break;
}
```

指令格式：

```text
SET_REM ld offset
```

作用：从集合变量中删除栈顶整数。

如果元素不存在，`set_rem_elem` 什么也不做。

## 19. `SET_IN`

```c
case SET_IN: {
    int v = pop();
    push(set_contains(set_base(ins.l, ins.a), v) ? 1 : 0);
    break;
}
```

指令格式：

```text
SET_IN ld offset
```

作用：判断栈顶整数是否属于集合。

步骤：

1. `pop()` 取出待检查元素。
2. `set_contains` 判断是否存在。
3. 把结果压栈：

```text
存在 -> 1
不存在 -> 0
```

源码：

```l26
if (3 in s) ...
```

`SET_IN` 的结果可以直接给 `JPC` 使用。

## 20. `SET_EMPTY`

```c
case SET_EMPTY:
    push(set_base(ins.l, ins.a)[0] == 0 ? 1 : 0);
    break;
```

指令格式：

```text
SET_EMPTY ld offset
```

作用：判断集合是否为空。

只需要看：

```text
base[0]
```

也就是元素个数。

如果为 0，压入 `1`，否则压入 `0`。

## 21. 双集合地址编码

`pcode.h` 里：

```c
#define ENCODE2(ld, off)       ((ld) * 10000 + (off))
#define DECODE_LD(enc)         ((enc) / 10000)
#define DECODE_OFF(enc)        ((enc) % 10000)
```

有些集合指令需要两个集合地址：

```text
SET_UNION
SET_INTER
SET_EQL
```

但 `Instruction` 只有：

```c
OpCode op;
int l;
int a;
```

所以 parser 把一个地址对：

```text
(ld, offset)
```

编码成一个整数。

例子：

```text
ld = 1
offset = 202
ENCODE2 = 1 * 10000 + 202 = 10202
```

解码：

```text
DECODE_LD(10202) = 1
DECODE_OFF(10202) = 202
```

## 22. `SET_UNION`

```c
case SET_UNION: {
    int *a = set_base(DECODE_LD(ins.l), DECODE_OFF(ins.l));
    int *b = set_base(DECODE_LD(ins.a), DECODE_OFF(ins.a));
    set_union(temp_set, a, b);
    break;
}
```

指令格式：

```text
SET_UNION encoded_addr1 encoded_addr2
```

作用：

```text
temp_set = set1 ∪ set2
```

步骤：

1. 解码第一个集合地址。
2. 解码第二个集合地址。
3. 找到两个集合基址。
4. 调用 `set_union(temp_set, a, b)`。

结果放在：

```text
temp_set
```

## 23. `SET_INTER`

```c
case SET_INTER: {
    int *a = set_base(DECODE_LD(ins.l), DECODE_OFF(ins.l));
    int *b = set_base(DECODE_LD(ins.a), DECODE_OFF(ins.a));
    set_inter(temp_set, a, b);
    break;
}
```

作用：

```text
temp_set = set1 ∩ set2
```

和 `SET_UNION` 结构相同，只是调用：

```c
set_inter(...)
```

## 24. `SET_COPY`

```c
case SET_COPY:
    set_copy(set_base(ins.l, ins.a), temp_set);
    break;
```

指令格式：

```text
SET_COPY ld offset
```

作用：

```text
目标集合变量 = temp_set
```

用于集合赋值。

例子：

```l26
s = {1, 2, 3};
u = s1 union s2;
```

前一条表达式会把结果放进 `temp_set`。

赋值语句最后生成：

```text
SET_COPY addr(target)
```

把临时结果复制到目标变量。

## 25. `SET_EQL`

```c
case SET_EQL: {
    int *a = set_base(DECODE_LD(ins.l), DECODE_OFF(ins.l));
    int *b = set_base(DECODE_LD(ins.a), DECODE_OFF(ins.a));
    push(set_equal(a, b) ? 1 : 0);
    break;
}
```

指令格式：

```text
SET_EQL encoded_addr1 encoded_addr2
```

作用：判断两个集合变量是否相等。

结果：

```text
相等 -> 压入 1
不等 -> 压入 0
```

parser 已经限制：

```text
SET_EQL 只用于两个集合变量
```

所以 PVM 这里可以直接按两个地址执行。

## 26. `SET_ELEM`

```c
case SET_ELEM: {
    int idx = pop();
    int *base = set_base(ins.l, ins.a);
    int cnt = base[0];
    if (idx < 0 || idx >= cnt) {
        fprintf(stderr, "runtime error: set index %d out of range (size=%d)\n", idx, cnt);
        exit(1);
    }
    push(base[idx + 1]);
    break;
}
```

指令格式：

```text
SET_ELEM ld offset
```

作用：按下标取集合元素。

用于集合推导式。

### 输入

栈顶必须是：

```text
idx
```

也就是要取第几个元素。

### 边界检查

```c
if (idx < 0 || idx >= cnt)
```

集合有效下标范围：

```text
0 到 cnt - 1
```

注意：集合内部元素从 `base[1]` 开始存。

### 取元素

```c
push(base[idx + 1]);
```

如果 `idx = 0`，取：

```text
base[1]
```

如果 `idx = 1`，取：

```text
base[2]
```

## 27. 集合赋值完整例子

源码：

```l26
{
    set s;
    s = {1, 2, 2, 3};
    write s;
}
```

大致 P-code：

```text
INT 0 201
SET_NEW 0 0
LIT 0 1
LIT 0 2
LIT 0 2
LIT 0 3
SET_LIT 0 4
SET_COPY 0 0
WRITES 0 0
INT 0 -201
OPR 0 OPR_RET
```

运行效果：

```text
SET_LIT 生成 temp_set = {1, 2, 3}
SET_COPY 把 temp_set 复制到 s
WRITES 打印 s
```

重复的 `2` 会被 `set_add_elem` 去掉。

## 28. 并集完整例子

源码：

```l26
{
    set a;
    set b;
    set u;
    a = {1, 2};
    b = {2, 3};
    u = a union b;
    write u;
}
```

关键指令：

```text
SET_UNION addr(a), addr(b)
SET_COPY addr(u)
WRITES addr(u)
```

运行效果：

```text
temp_set = {1, 2, 3}
u = temp_set
打印 {1, 2, 3}
```

## 29. 成员测试例子

源码：

```l26
if (3 in s) {
    write 1;
}
```

关键指令：

```text
LIT 0 3
SET_IN addr(s)
JPC else_or_end
LIT 0 1
WRITE
```

`SET_IN` 把结果压成 `1/0`，后面的 `JPC` 使用这个布尔值。

## 30. 集合推导式里的 `SET_ELEM`

源码：

```l26
result = { x * 2 | x in s if x > 2 };
```

推导式循环中有一段：

```text
LOD idx
SET_ELEM addr(s)
STO iter(x)
```

含义：

```text
取出 s[idx]
存到迭代变量 x
```

然后 filter 和 body 就可以像普通变量一样使用 `x`。

## 31. 集合输出为什么稳定

集合内部插入顺序可能取决于程序执行顺序。

但 `print_set` 会排序后输出。

所以：

```l26
s1 = {5, 4, 3, 2, 1};
write s1;
```

输出是：

```text
{1, 2, 3, 4, 5}
```

这也让测试输出更稳定。

## 32. 本阶段你要记住

1. 集合变量固定占 `SET_SIZE = 201` 个 word。
2. `base[0]` 是元素个数。
3. `base[1..count]` 是元素值。
4. 集合自动去重。
5. `temp_set` 保存集合表达式的临时结果。
6. `SET_LIT` 从栈顶弹出元素并构造 `temp_set`。
7. `SET_COPY` 把 `temp_set` 复制到集合变量。
8. `SET_UNION/SET_INTER` 的结果也放入 `temp_set`。
9. `SET_EQL` 比较两个集合变量并压入布尔值。
10. `SET_ELEM` 用于集合推导式按下标取元素。
11. `WRITES` 打印集合变量，`WRITET` 打印临时集合。

## 下一步

Step 10 做端到端串联。

用一个完整 L26 程序看：

```text
源码
-> lexer token
-> parser 归约
-> symtab 变化
-> P-code 生成
-> PVM 执行
-> 输出
```
