# ASM 开发模式：自定义调用 ABI（stack-based, callee-cleans-stack）

## 核心思想

不使用 System V AMD64 的寄存器传参 ABI，而是自定义一套更简单、心智负担更低的调用约定：

- **参数**：调用方通过 `push` 依次压栈传参，且按参数声明顺序正向 push —— **第一个参数先 push，最后一个参数最后 push**。进入函数后最后一个参数在 `[rbp+16]`（离返回地址最近），第一个参数在最大的偏移处。
- **栈清理**：被调用方（callee）通过 `ret N` 自行清理栈上的参数（类似 stdcall）。`N` = 参数总字节数（不含局部变量）。
- **返回值**：统一放在 `rax`。
- **变量一律落栈**：所有变量——参数还是局部变量——都只以栈上内存单元的形式存在。**寄存器里永远不存变量**，只用来承载一次表达式求值过程中的中间结果，算完立刻写回栈上变量，绝不让一个寄存器的值跨越一次 `call`。
- **调用会破坏所有寄存器**：不管是自定义 ABI 调用还是真实 ABI 调用（如 libc），除 `rax`（返回值）外，其余所有寄存器在 `call` 之后都视为已被破坏。因为变量本来就不放在寄存器里，这条规则不需要任何寄存器保护宏。

## 命名约定

- **变量**（参数、局部变量、全局变量）和**函数名**用 `camelCase`：`msg`、`flag`、`printMsg`、`stringLen`。
- **结构体等类型名**用 `CamelCase`（PascalCase）：`Point`、`FileStat`。
- **指针参数/指针返回值在签名注释中以 `p` 前缀命名**：`pVec`、`pMeta`、`pBuf`、`pPath`……（`asmrt.inc` 中每个 `extern` 上方都有带签名的注释，命名一眼能看出哪个参数是地址）。

## begin / end：建帧、收尾

```asm
%macro begin 0
    push rbp
    mov  rbp, rsp
%endmacro

%macro end 0
    mov  rsp, rbp
    pop  rbp
%endmacro
```

`begin` 建立栈帧。

**硬性规定：一个函数里 `begin`/`end` 必须各出现且只出现一次**。函数内如果有多个提前返回的出口，必须让它们都跳转到同一个 `end` 之前，不能各自各写一个 `end`。

**每个函数体内的顺序固定为：`name:` → 声明参数 → `begin` → 声明局部变量→ `endlocal` → 函数体 → `end`。** 没有参数的函数直接 `name:` -> `begin` 开始。

## 声明参数

参数必须是8 byte，如果需要用结构体，那用指针。

假设有N个参数，第i个参数的偏移是 16 + (N-i) * 8

例如，对于f(x, y, z):

```asm
; args: x, y, z
argnum 3
%assign x arg(1)
%assign y arg(2)
%assign z arg(3)
```

## 结构

例如，对于下面的struct：

```c
struct Sample {
    int32_t x, y;
    int64_t z;
}
```

这样实现：

```asm
; struct Sample
resetOffset

%assign Sample_x offset
incOffset 4

%assign Sample_y offset
incOffset 4

%assign Sample_z offset
incOffset 8

%assign sizeof_Sample offset
```

`Sample_x`/`Sample_y`/`Sample_z` 是字段偏移，`Sample_size` 是整个结构体的字节数。

**硬性规定不变：`Type_size` 必须是 8 的整数倍。** 字段本身凑不满时手动补一个padding:

```asm
; struct Tiny
resetOffset

%assign Tiny_x offset
incOffset 4

incOffset 4 ; padding
%assign sizeof_Tiny offset
```

跨模块共享的结构体（如 `ValueMeta`、`Vec`）统一声明在 `asmrt.inc` 的
"shared struct definitions" 段，而不放在某个 `.asm` 模块里——这样任何
`%include "asmrt.inc"` 的模块都能直接用结构体名和字段偏移。

## 声明局部变量

例如栈上有变量 i64 x，和Sample s

```asm
; local variables
resetOffset
; int64_t x
decOffset 8
%assign x offset
; Sample s
decOffset Sample_size
%assign s offset
; endlocal
sub rsp, (-offset)
```

## hexalign：真实 ABI 调用点的动态栈对齐

```asm
%macro hexalign 0
    mov  rax, rsp
    and  rax, 8          ; rsp 已 16 字节对齐时为 0，否则（差 8 字节）为 8
    sub  rsp, rax
%endmacro
```

调用真实 ABI 函数（libc、系统调用等）之前放一句 `hexalign`，运行时按需垫 8 字节，不需要手算参数/局部变量个数的奇偶性，也不需要配对的"撤销"宏——垫的空间随 `end` 的 `mov rsp, rbp` 一并归还。按*调用点*放，不是按函数放：一个函数有几处真实 ABI 调用，每处前面都要放。

## preasm / postasm：C 回调场景下的全寄存器保护宏


C 代码把一个函数指针注册为回调（如 `qsort` 的比较函数），回调内部要转调自定义 ABI 函数时，用这一对宏包住 `call`：

```asm
myCallback:
    preasm
    ; ... 按自定义 ABI 规则 push 参数 ...
    call someAsmrtFunc
    postasm
    ; 需要用到 someAsmrtFunc 的返回值的话，必须在 postasm 之前
    ; 把 rax 存到内存里——postasm 会把 rax 也恢复成调用前的值
    ret
```

## 完整示例（递归 fibo + 调用真实 ABI 的 printf）

```asm
entry:
    begin
    push 10
    call fibo
    push rax
    call printNum
    end
    ret 24

fibo:
    ; args: x
    argnum 1
    %assign x arg(1)

    begin
    resetOffset
    ; int64_t acc
    decOffset 8
    %assign acc offset

    sub rsp, (-offset)

    mov rax, [rbp + x]
    cmp rax, 2
    jg .calc
    mov rax, 1
    jmp .end
.calc:
    mov rax, [rbp + x]
    sub rax, 1
    push rax
    call fibo               ; 调用之后除 rax 外所有寄存器视为已破坏
    mov [rbp + acc], rax    ; 立刻把结果存回栈上的局部变量，不留在寄存器里

    mov rax, [rbp + x]
    sub rax, 2
    push rax
    call fibo
    add rax, [rbp + acc]    ; acc 是栈上变量，不受两次调用之间寄存器被破坏的影响
.end:
    end
    ret 8

printNum:
    ; args x
    argnum 1
    %assign x arg(1)
    begin
    ; 没有局部变量，不需要 endlocal——对齐交给下面的 hexalign 动态处理
    hexalign ; align to 16 byte before calling C function
    mov rdi, printMsg
    mov rsi, [rbp + x]
    xor rax, rax         ; printf 是变参函数，rax 需清零表示 0 个向量寄存器参数
    call printf
    end
    ret 8
```

## 项目布局

```
src/asmrt.inc   共享头文件：ABI 宏 + 公共结构体定义 + 所有运行时函数的 extern 声明
src/main.asm    进程入口（main -> entry）、rtExit
src/assert.asm  assert(string, flag)——失败时向 stderr 写长度前缀字符串
src/io.asm      文件 I/O syscalls（ioOpen/ioClose/ioRead/ioWrite/ioSeek/...）
src/fs.asm      文件系统 syscalls（fsStat/fsFstat/fsMkdir/fsRmdir/fsUnlink）
src/mem.asm     malloc/free/realloc 包装 + 原生 memcpy/memmove/memset 类似物
src/string.asm  长度前缀字符串模块（stringLen/stringFromCStr/stringSplit/...）
src/utils.asm   通用工具：sort（qsort 风格递归快速排序）+ fnv64（FNV-1a 64 位哈希）
src/vec.asm     vector数据结构模块（vec）
src/list.asm    双向链表数据结构模块（list）
tests/          每个模块一个 test_*.asm，`make test` 编译并运行
```

每个运行时 `.asm` 文件只需 `%include "asmrt.inc"`——ABI 宏、公共结构体
以及所有运行时函数的 `extern` 声明都由它统一提供，调用方不需要手写
`extern` 行。

## 构建与测试

- `make`：nasm 汇编 `src/*.asm` 为 `build/*.o`，再 `ar rcs` 打包成
  `build/libasmrt.a`。
- `make test`：汇编 `tests/test_*.asm`，与 `libasmrt.a` 链接后逐个运行；
  退出码 0 为通过，`*_fail` 测试期望 255。每个测试文件导出
  `global entry`（无参数、custom ABI、`ret 24`），由 `main.asm` 的
  `main` push argc/argv/envp 后调用，entry 的返回值即进程退出码。
- `make install PREFIX=/usr/local`：把 `libasmrt.a` 装到 `$(PREFIX)/lib`，
  `asmrt.inc` 装到 `$(PREFIX)/include/nasm`。
- **注意**：Makefile 已将 `asmrt.inc` 列入每个 `.o` 的依赖，修改
  `.inc` 后 `make` 会自动重新编译受影响的模块。

## 数据结构约定

`ValueMeta` 的 6 个 trait 回调（`drop`/`cmp`/`eq`/`hash`/`copy`/`move`）
全部是**自定义 ABI 函数**：参数 push 传，返回值在 rax、callee 用 `ret N` 清栈。

## Vector模块（vec.asm）

实现"值语义 + trait 回调"的通用动态数组。

```
vecInit, vecWithCapacity, vecReserve, vecPush,
vecPop, vecGet, vecSet, vecFirst, vecLast, vecLen,
vecIsEmpty, vecClear, vecTruncate, vecDrop, vecSwapElement, vecSwap,
vecEq, vecInsert, vecRemove, vecAsPtr, vecCopy, vecMove,
vecSort, vecCmp, vecHash, vecMeta
```

`fnv64` 哈希函数与 `sort` 一起放在 `utils.asm` 模块（vecHash 内部通过
extern 调用它）。

约定：

- vec 的内存分配/释放/扩容走 `memAlloc`/`memFree`/`memReloc`，字节搬运走
  `memCopy`/`memMove`——这些包装内部已处理真实 ABI 与栈对齐，vec 自身
  不需要 `hexalign`。
- `vecMeta` 是 `.data` 里的一个 `ValueMeta` 实例，描述 `Vec` 自身
  （`size = Vec_size`，`cmp = vecCmp` ...），供嵌套容器（vec of vec）使用。
- 内部 helper（如 `elemAddr`）非 `global`，也不出现在 `asmrt.inc` 的
  extern 声明里；只有公共 API 才导出。

## List模块（list.asm）

与 vec 同样的"值语义 + trait 回调"模型的双向链表。`listMeta` 描述
`struct List` 自身，供嵌套容器使用。

```
listInit, listDrop, listClear,
listCopy, listMove, listSwap,
listInsertBefore, listInsertAfter, listRemove, listSet,
listBegin, listLast, listEnd, listNext, listPrev, listGet,
listLen, listIsEmpty,
listPushBack, listPushFront, listPopBack, listPopFront,
listEq, listCmp, listHash, listMeta
```

约定：

- list 的节点分配/释放走 `memAlloc`/`memFree`，字节搬运走 `memSwap`，
  不需要 `hexalign`。
- `listMeta` 是 `.data` 里的一个 `ValueMeta` 实例，描述 `List` 自身，
  供嵌套容器（list of list）使用。
- 所有插入/替换接口带 `isMove` 参数：`isMove != 0` 走 `ValueMeta.move`，
  否则 `ValueMeta.copy`。
- 内部 helper（如 `newNode`、`nodeData`）非 `global`，也不在
  `asmrt.inc` 的 extern 声明里。

## 字符串模块（string.asm）

字符串就是一个指针（8 字节），指向带长度前缀的缓冲区：

```
string -> [ 8-byte len ][ data bytes ... ][ NUL ]
```

`len` 统计字符数，**不包含**末尾的 NUL。字面量这样写：

```
s1 dq (s1_end - s1_start)
s1_start: db "hello"
s1_end: db 0
```

堆字符串是一次 `8 + len + 1` 字节的分配，由 `stringFromCStr`/
`stringFromRaw`/... 创建，用 `stringDrop` 释放。

**string 指针就是值本身**：`stringMeta` 的 objsize = 8，vec/list<string>
每个元素直接存一个 string 指针。容器的 ValueMeta 回调收到的是**元素地址**
（指向容器内那个 8 字节槽）——`stringEq`/`stringCmp`/`stringCopy`/
`stringMove`/`stringDrop`/`stringSlotHash` 都是这个约定：先解引用一次拿到
string，再操作。

```
stringLen, stringEq, stringCmp,
stringInit, stringFromCStr, stringFromRaw,
stringCopy, stringMove, stringDrop,
stringCStr, stringAt, stringHash, stringSlotHash,
stringSubstring, stringConcat,
stringStartsWith, stringEndsWith, stringFind, stringCount,
stringLower, stringUpper, stringCapitalize,
stringStrip, stringLStrip, stringRStrip,
stringRemovePrefix, stringRemoveSuffix,
stringSplit, stringSplitLines, stringJoin,
stringMeta
```

约定：

- 堆字符串分配/释放走 `memAlloc`/`memFree`，字节搬运走 `memCopy`，
  不需要 `hexalign`。
- **构造/变换函数不取 out 指针**：`stringFromRaw`、`stringSubstring`、
  `stringConcat`、`stringLower/Upper/Capitalize`、`stringStrip`
  系列、`stringRemovePrefix/Suffix`、`stringJoin` 全部在 `rax` 返回
  新字符串（符合自定义 ABI 的返回值约定），没有 `pOut` 之类二重指针。
- 只有 `stringSplit`/`stringSplitLines` 需要调用方传入 `pVec` 来存放
  切出的元素。
- `ioWriteString(fd, string)` 一次 sys_write 输出整个长度前缀字符串。
- `assert` 接受长度前缀字符串，失败时经 `ioWriteString` 写 stderr。

## 注意事项

- x86-64 没有 `push imm64`。需要压入 64 位立即数时先 `mov rax, imm64`
  再 `push rax`。

## 适用场景与局限

- 适合纯自研代码内部（函数间互相调用只走这套约定），把"要不要保存寄存器"这个问题直接消灭。
- 一旦调用外部库（libc、系统调用等标准 ABI 代码），按真实 ABI 把参数放进对应寄存器即可，不需要额外的寄存器保护；调用点前放一句 `hexalign` 处理栈对齐。
- 代价：所有变量读写都要走一次内存访问（`[rbp + name]`），比全寄存器分配慢很多；仅适合教学/实验/把心智负担降到最低优先于性能的场景。
