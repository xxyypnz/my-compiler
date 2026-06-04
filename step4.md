# Step 4：符号表与作用域

本阶段读两个文件：

```text
symtab.h
symtab.c
```

目标：理解变量如何被记录，作用域如何进入/退出，`level` 和 `offset` 如何算出来。

## Step 3 承接

Step 3 看到 `emit(LOD, l, a)`、`emit(STO, l, a)` 需要两个关键参数：

```text
l = 层差
a = 偏移
```

这两个参数从哪里来？

答案：来自符号表。

本阶段要回答：

1. 一个变量声明后会保存哪些信息？
2. 为什么同名变量在内层可以遮蔽外层？
3. 同一作用域内重复声明如何被发现？
4. `level` 表示什么？
5. `offset` 表示什么？
6. `set` 为什么占 201 个 word？

## 1. `symtab.h`

`symtab.h` 定义符号表对外可见的数据结构和函数。

### 头文件保护

```c
#ifndef SYMTAB_H
#define SYMTAB_H
...
#endif
```

作用：避免重复包含。

### 引入 `pcode.h`

```c
#include "pcode.h"
```

原因：`type_width()` 需要用到 `SET_SIZE`。

`SET_SIZE` 定义在 `pcode.h`：

```c
#define SET_SIZE 201
```

## 2. `VarType`

```c
typedef enum { T_INT, T_BOOL, T_SET } VarType;
```

`VarType` 表示 L26 里的变量类型。

三个值：

- `T_INT`：整数类型，对应源码里的 `int`。
- `T_BOOL`：布尔类型，对应源码里的 `bool`。
- `T_SET`：集合类型，对应源码里的 `set`。

例子：

```l26
int x;
bool ok;
set s;
```

符号表里分别记录为：

```text
x  -> T_INT
ok -> T_BOOL
s  -> T_SET
```

## 3. `Symbol`

```c
typedef struct Symbol {
    char          name[64];
    VarType       type;
    int           level;
    int           offset;
    struct Symbol *next;
} Symbol;
```

`Symbol` 表示一个变量。

### `name`

```c
char name[64];
```

变量名，最多保存 63 个字符，最后 1 个字符留给 `'\0'`。

例子：

```l26
int count;
```

则：

```text
name = "count"
```

### `type`

```c
VarType type;
```

变量类型。

例子：

```l26
set s;
```

则：

```text
type = T_SET
```

### `level`

```c
int level;
```

变量声明时所在的嵌套层级。

约定：

```text
最外层 block = 1
再嵌套一层 = 2
再嵌套一层 = 3
```

例子：

```l26
{
    int x;      // level = 1
    {
        int y;  // level = 2
    }
}
```

### `offset`

```c
int offset;
```

变量在当前作用域运行时帧里的偏移。

例子：

```l26
{
    int a;   // offset = 0, 宽度 1
    bool b;  // offset = 1, 宽度 1
    set s;   // offset = 2, 宽度 201
}
```

### `next`

```c
struct Symbol *next;
```

指向同一作用域里的下一个变量。

当前作用域的变量用链表保存：

```text
head -> symbol3 -> symbol2 -> symbol1 -> NULL
```

新声明的变量插到链表头部。

## 4. `Scope`

```c
typedef struct Scope {
    Symbol      *head;
    int          frame_size;
    int          base_offset;
    struct Scope *parent;
} Scope;
```

`Scope` 表示一个块作用域。

### `head`

```c
Symbol *head;
```

当前作用域内变量链表的头指针。

如果当前作用域没有变量：

```text
head = NULL
```

### `frame_size`

```c
int frame_size;
```

当前作用域已经分配了多少 word。

例子：

```l26
{
    int a;   // frame_size 从 0 变成 1
    bool b;  // frame_size 从 1 变成 2
    set s;   // frame_size 从 2 变成 203
}
```

### `base_offset`

```c
int base_offset;
```

当前实现里固定为 `0`。

历史上它可以表示累计偏移，但现在虚拟机采用“每个块一个栈帧”，所以变量只需要本帧内 offset。

### `parent`

```c
struct Scope *parent;
```

指向外层作用域。

例子：

```text
当前内层 scope -> parent -> 外层 scope -> parent -> NULL
```

## 5. `symtab.c`

`symtab.c` 实现符号表操作。

### 头文件

```c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "symtab.h"
```

含义：

- `stdio.h`：错误输出。
- `stdlib.h`：`malloc`、`free`、`exit`。
- `string.h`：`strcmp`、`strncpy`。
- `symtab.h`：结构和函数声明。

## 6. `current_scope`

```c
static Scope *current_scope = NULL;
```

含义：当前正在编译的作用域。

初始状态：

```text
current_scope = NULL
```

当进入最外层 `{}`：

```text
current_scope -> level 1 scope
```

进入内层 `{}`：

```text
current_scope -> level 2 scope -> parent -> level 1 scope
```

`static` 表示它只在 `symtab.c` 内部可见。

## 7. `type_width`

```c
int type_width(VarType t) {
    return (t == T_SET) ? SET_SIZE : 1;
}
```

参数：

- `t`：变量类型。

返回值：

- `T_INT`：1
- `T_BOOL`：1
- `T_SET`：201

为什么集合是 201？

```text
1 个 word 保存元素个数
200 个 word 保存元素
```

## 8. `scope_enter`

```c
void scope_enter(void)
```

作用：进入一个新的块作用域。

核心步骤：

```c
Scope *s = malloc(sizeof(Scope));
```

分配一个新 `Scope`。

```c
s->head = NULL;
```

新作用域一开始没有变量。

```c
s->frame_size = 0;
```

新作用域一开始没有分配任何 word。

```c
s->base_offset = 0;
```

当前实现不使用累计偏移。

```c
s->parent = current_scope;
```

新作用域的父作用域是原来的当前作用域。

```c
current_scope = s;
```

把新作用域设为当前作用域。

## 9. `scope_exit`

```c
void scope_exit(void)
```

作用：退出当前作用域，并释放当前作用域里的所有符号。

如果当前没有作用域：

```c
if (!current_scope) return;
```

逐个释放变量：

```c
Symbol *sym = current_scope->head;
while (sym) {
    Symbol *next = sym->next;
    free(sym);
    sym = next;
}
```

保存父作用域：

```c
Scope *parent = current_scope->parent;
```

释放当前作用域：

```c
free(current_scope);
```

回到父作用域：

```c
current_scope = parent;
```

## 10. `scope_level`

```c
int scope_level(void)
```

作用：计算当前嵌套层级。

实现：

```c
int level = 0;
Scope *s = current_scope;
while (s) {
    level++;
    s = s->parent;
}
return level;
```

意思是：从当前作用域一路往父作用域数，数到 `NULL`。

例子：

```text
level 3 -> level 2 -> level 1 -> NULL
```

返回 `3`。

## 11. `scope_frame_size`

```c
int scope_frame_size(void) {
    return current_scope ? current_scope->frame_size : 0;
}
```

作用：返回当前作用域已经分配的 word 数。

用途：`parser.y` 在块结束时需要知道：

```text
INT 0 n
```

中的 `n` 应该是多少。

## 12. `scope_total_size`

```c
int scope_total_size(void) {
    return current_scope ? current_scope->frame_size : 0;
}
```

当前实现里它和 `scope_frame_size()` 一样。

保留这个函数主要是接口完整性。

## 13. `sym_declare`

```c
Symbol *sym_declare(const char *name, VarType type)
```

作用：在当前作用域声明一个变量。

参数：

- `name`：变量名。
- `type`：变量类型。

返回值：

- 成功：返回新建的 `Symbol *`。
- 失败：返回 `NULL`。

失败场景：

```c
if (!current_scope) return NULL;
```

没有当前作用域，不能声明变量。

### 重复声明检查

```c
for (Symbol *s = current_scope->head; s; s = s->next)
    if (strcmp(s->name, name) == 0) return NULL;
```

只检查当前作用域。

所以这样非法：

```l26
{
    int x;
    bool x;
}
```

但这样合法：

```l26
{
    int x;
    {
        bool x;
    }
}
```

因为内层 `x` 遮蔽外层 `x`。

### 创建 Symbol

```c
Symbol *sym = malloc(sizeof(Symbol));
```

分配变量记录。

```c
strncpy(sym->name, name, 63);
sym->name[63] = '\0';
```

复制变量名，并保证字符串结尾安全。

```c
sym->type = type;
```

保存变量类型。

```c
sym->level = scope_level();
```

保存变量所在作用域层级。

```c
sym->offset = current_scope->frame_size;
```

当前帧已经用了多少 word，新变量就从这个 offset 开始。

```c
current_scope->frame_size += type_width(type);
```

声明变量后，当前帧大小增加变量宽度。

例子：

```l26
int a;   // offset = 0, frame_size += 1
set s;   // offset = 1, frame_size += 201
bool b;  // offset = 202, frame_size += 1
```

### 插入链表

```c
sym->next = current_scope->head;
current_scope->head = sym;
```

新变量插入当前作用域变量链表头部。

## 14. `sym_lookup`

```c
Symbol *sym_lookup(const char *name)
```

作用：查找变量。

参数：

- `name`：变量名。

返回值：

- 找到：返回 `Symbol *`。
- 没找到：返回 `NULL`。

查找逻辑：

```c
for (Scope *sc = current_scope; sc; sc = sc->parent)
    for (Symbol *s = sc->head; s; s = s->next)
        if (strcmp(s->name, name) == 0) return s;
return NULL;
```

解释：

1. 先查当前作用域。
2. 当前作用域找不到，再查父作用域。
3. 一直查到最外层。
4. 都没有则返回 `NULL`。

这就是变量遮蔽的原因。

例子：

```l26
{
    int x;
    {
        bool x;
        x = true;
    }
}
```

内层查 `x` 时，先找到 `bool x`，不会继续找外层 `int x`。

## 15. 和 P-Code 的关系

符号表最终服务于 P-Code 地址生成。

如果当前层级是 2，变量声明层级是 1：

```text
ld = scope_level() - sym->level = 2 - 1 = 1
```

然后生成：

```c
emit(LOD, ld, sym->offset);
```

或：

```c
emit(STO, ld, sym->offset);
```

虚拟机执行时用：

```text
当前帧向外找 ld 层
在那一层帧里找 offset
```

## 16. 本阶段你要记住

符号表解决三个问题：

```text
变量是否存在
变量是什么类型
变量运行时在哪里
```

核心数据：

```text
current_scope 当前作用域
Scope         一个块作用域
Symbol        一个变量
```

核心函数：

```text
scope_enter   进入块
scope_exit    退出块
sym_declare   声明变量
sym_lookup    查找变量
type_width    计算变量占多少 word
```

下一阶段建议读：

```text
lexer.l
```

因为 parser 要靠 lexer 提供 token，读懂 token 后再进入 `parser.y` 会轻松很多。

