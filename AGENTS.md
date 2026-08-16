# ASM 开发模式：自定义调用 ABI（stack-based, callee-cleans-stack）

## 核心思想

不使用 System V AMD64 的寄存器传参 ABI，而是自定义一套更简单、心智负担更低的调用约定：

- **参数**：调用方通过 `push` 依次压栈传参，且按参数声明顺序正向 push —— **第一个参数先 push，最后一个参数最后 push**。进入函数后最后一个参数在 `[rbp+16]`（离返回地址最近），第一个参数在最大的偏移处。
- **栈清理**：被调用方（callee）通过 `ret N` 自行清理栈上的参数（类似 stdcall）。`N` = 参数总字节数（不含局部变量）。
- **返回值**：统一放在 `rax`。
- **变量一律落栈**：所有变量——参数还是局部变量——都只以栈上内存单元的形式存在。**寄存器里永远不存变量**，只用来承载一次表达式求值过程中的中间结果，算完立刻写回栈上变量，绝不让一个寄存器的值跨越一次 `call`。
- **调用会破坏所有寄存器**：不管是自定义 ABI 调用还是真实 ABI 调用（如 libc），除 `rax`（返回值）外，其余所有寄存器在 `call` 之后都视为已被破坏。因为变量本来就不放在寄存器里，这条规则不需要任何寄存器保护宏。

## 命名约定

- **变量**（参数、局部变量、全局变量）和**函数名**用 `camelCase`：`msg`、`flag`、`printMsg`、`strLen`。
- **结构体等类型名**用 `CamelCase`（PascalCase）：`Point`、`FileStat`。
- **指针参数/指针返回值在签名注释中以 `p` 前缀命名**：`pVec`、`pMeta`、`pBuf`、`pPath`……（`asmrt.inc` 中每个 `extern` 上方都有带签名的注释，命名一眼能看出哪个参数是地址）。

## begin / end：建帧、收尾，兼管理变量作用域

```asm
%macro begin 0
    %push
    push rbp
    mov  rbp, rsp
    %assign __localSize 0
%endmacro

%macro end 0
    mov  rsp, rbp
    pop  rbp
    %pop
%endmacro
```

`begin` 除了建立标准栈帧，还 `%push` 一个 NASM 预处理器 context，`end` 收尾时 `%pop` 掉它。这是因为**参数、局部变量都通过 context-local 的 `%$name` 别名访问**（而不是普通全局 `%define`）：同一个变量名（`path`、`fd`、`size`……）在不同函数里反复出现是常态，如果用普通 `%define` 定义，NASM 预处理器会在扫描到*下一次*同名声明所在的那一行时，把这行里的裸标识符先展开成上一个函数遗留下来的旧定义（这一步发生在 NASM 识别这是一次宏调用之前），导致声明直接损坏、编译失败。`%$name` 是 context-local 的，`%pop` 时自动失效，不会有这个问题。

**硬性规定：一个函数里 `proc`（内含 `begin`）/`end` 必须各出现且只出现一次**——`%push`/`%pop` 是预处理期指令，按源码文本顺序执行，不看运行时走的是哪条分支。函数内如果有多个提前返回的出口，必须让它们都跳转到同一个 `end` 之前，不能各自各写一个 `end`。

**每个函数体内的顺序固定为：`proc name` → `args`（声明参数）→ `local`...（声明局部变量）→ `endlocal` → 函数体 → `end`。** `args`/`local` 必须写在 `proc`/`begin` 之后，因为 `begin` 是 push context 的地方。

## proc：函数标签 + begin 合并

```asm
%macro proc 1
%1:
    begin
%endmacro
```

`proc funcName` 等价于 `funcName:` 紧跟一行 `begin`，写函数时用这一个宏代替两行。不发 `global`——`global funcName` 仍然按原来的习惯集中写在文件开头的 `section .text` 声明块里。

## args：声明参数

```asm
%macro args 1-*
    %assign %%n %0
    %assign %%i 1
    %rep %0
        %xdefine %[%$ %+ %1] (rbp + 16 + 8*(%%n - %%i))
        %assign %%i %%i+1
    %rotate 1
    %endrep
%endmacro
```

`args a1, a2, ..., an` 按 push 顺序声明参数（`a1` 最先 push，`an` 最后 push、落在 `[rbp+16]`），用到的地方写 `[%$a1]`。**硬性规定：每个参数必须恰好 8 字节**——标量直接传值，结构体只能传指针，不按值展开成多个栈槽。

## local / endlocal：声明局部变量

```asm
%macro local 1-2 8
    %assign __localSize __localSize + %2
    %assign %[%$ %+ %1 %+ _offset] (-__localSize)
    %xdefine %[%$ %+ %1] (rbp + %[%$ %+ %1 %+ _offset])
%endmacro

%macro endlocal 0
    sub rsp, __localSize
%endmacro
```

`local name[, size]`（`size` 缺省 8）按声明顺序累加偏移，用到的地方写 `[%$name]`；最后一个 `local` 之后调用一次 `endlocal`，补上 `sub rsp, N`。**硬性规定：`size` 必须是 8 的整数倍**（结构体大小同样必须是 8 的倍数，见下面 struc 一节），这样 `endlocal` 算出来的 `N` 自动就是 8 的整数倍，不需要额外取整。

## 结构体：直接用 NASM 的 struc/endstruc

不再手写 `%assign Type_field (...)` 链，直接用 NASM 自带的结构体宏：

```asm
struc Sample                ; int32 x; int32 y; int64 z;
    .x: resd 1
    .y: resd 1
    .z: resq 1
endstruc                    ; Sample_size = 4+4+8 = 16，已经是 8 的整数倍，不用 padding
```

`Sample.x`/`Sample.y`/`Sample.z` 是字段偏移，`Sample_size` 是整个结构体的字节数。访问字段：`[%$c + Sample.y]`（`%$c` 是 `local`/`args` 声明的、指向该结构体实例的地址）或 `[somePtr + Sample.y]`（`somePtr` 是指向堆/全局实例的指针）。

**硬性规定不变：`Type_size` 必须是 8 的整数倍。** 字段本身凑不满时手动补一个 `resX` padding 字段：

```asm
struc Tiny                  ; int32 x;
    .x: resd 1
    resd 1                  ; 4 字节实际数据凑不满 8，补 4 字节 padding
endstruc                    ; Tiny_size = 4+4 = 8
```

跨模块共享的结构体（如 `ValueMeta`、`Vec`）统一声明在 `asmrt.inc` 的
"shared struct definitions" 段，而不放在某个 `.asm` 模块里——这样任何
`%include "asmrt.inc"` 的模块都能直接用结构体名和字段偏移。`struc` 的
字段布局必须保持 8 的整数倍（见上），`Type_size` 同样必须是 8 的倍数。

## hexalign：真实 ABI 调用点的动态栈对齐

```asm
%macro hexalign 0
    mov  rax, rsp
    and  rax, 8          ; rsp 已 16 字节对齐时为 0，否则（差 8 字节）为 8
    sub  rsp, rax
%endmacro
```

调用真实 ABI 函数（libc、系统调用等）之前放一句 `hexalign`，运行时按需垫 8 字节，不需要手算参数/局部变量个数的奇偶性，也不需要配对的"撤销"宏——垫的空间随 `end` 的 `mov rsp, rbp` 一并归还。按*调用点*放，不是按函数放：一个函数有几处真实 ABI 调用，每处前面都要放。

## preasmcall / postasmcall：C 回调场景下的全寄存器保护宏

```asm
%macro preasmcall 0
    push rax
    push rbx
    push rcx
    push rdx
    push rbp
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15
    sub  rsp, 8   ; 15 个寄存器是奇数个，补一个占位槽凑够 16 字节对齐
%endmacro

%macro postasmcall 0
    add  rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rbp
    pop rdx
    pop rcx
    pop rbx
    pop rax
%endmacro
```

C 代码把一个函数指针注册为回调（如 `qsort` 的比较函数），回调内部要转调自定义 ABI 函数时，用这一对宏包住 `call`：

```asm
myCallback:
    preasmcall
    ; ... 按自定义 ABI 规则 push 参数 ...
    call someAsmrtFunc
    postasmcall
    ; 需要用到 someAsmrtFunc 的返回值的话，必须在 postasmcall 之前
    ; 把 rax 存到内存里——postasmcall 会把 rax 也恢复成调用前的值
    ret
```

保护范围包含 `rax`（连同调用结果一起被恢复，需要的话提前存走）和 `rbp`——因此 `preasmcall`/`postasmcall` 之间不能通过 `[%$name]` 访问当前函数自己的参数/局部变量，这段区间 `rbp` 的语义不受保证。

## 完整示例（递归 fibo + 调用真实 ABI 的 printf）

```asm
proc main

    push 10
    call fibo
    push rax
    call printNum
    ...

proc fibo
    args x
    local acc        ; 存第一次递归调用的结果，8 字节
    endlocal

    mov rax, [%$x]
    cmp rax, 2
    jg .calc
    mov rax, 1
    jmp .end
.calc:
    mov rax, [%$x]
    sub rax, 1
    push rax
    call fibo        ; 调用之后除 rax 外所有寄存器视为已破坏
    mov [%$acc], rax    ; 立刻把结果存回栈上的局部变量，不留在寄存器里

    mov rax, [%$x]
    sub rax, 2
    push rax
    call fibo
    add rax, [%$acc]    ; acc 是栈上变量，不受两次调用之间寄存器被破坏的影响
.end:
    end
    ret 8

proc printNum
    args x
    ; 没有局部变量，不需要 endlocal——对齐交给下面的 hexalign 动态处理

    hexalign
    mov rdi, printMsg
    mov rsi, [%$x]
    xor rax, rax         ; printf 是变参函数，rax 需清零表示 0 个向量寄存器参数
    call printf

    end
    ret 8
```

## 项目布局

```
src/asmrt.inc   共享头文件：ABI 宏 + 公共 struc + 所有运行时函数的 extern 声明
src/main.asm    进程入口（main -> entry）、rtExit
src/assert.asm  assert(msg, flag)
src/io.asm      文件 I/O syscalls（ioOpen/ioClose/ioRead/ioWrite/ioSeek/...）
src/fs.asm      文件系统 syscalls（fsStat/fsFstat/fsMkdir/fsRmdir/fsUnlink）
src/mem.asm     malloc/free/realloc 包装 + 原生 memcpy/memmove/memset 类似物
src/str.asm     NUL 结尾字符串辅助（strLen/strEq）
src/utils.asm   通用工具：sort（qsort 风格递归快速排序）+ fnv64（FNV-1a 64 位哈希）
src/ds.asm      数据结构模块（vec，镜像 ckit/cbase/cbase.h）
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
- **注意**：Makefile 没有把 `asmrt.inc` 列入依赖。修改 `.inc` 后必须
  `make clean && make`，否则会得到 "Nothing to be done"。

## 数据结构模块（ds.asm）

镜像 ckit/cbase/cbase.h 的 `struct vec` / `struct value_meta`，实现
"值语义 + trait 回调"的通用动态数组。导出符号命名沿用 cbase 的
`vec_*`，但按本仓库约定写成 camelCase：

```
vecInit, vecWithCapacity, vecReserve, vecPushCp, vecPushMv,
vecPop, vecGet, vecSetCp, vecSetMv, vecFirst, vecLast, vecLen,
vecIsEmpty, vecClear, vecTruncate, vecDrop, vecSwapElement, vecSwap,
vecEq, vecInsertCp, vecInsertMv, vecRemove, vecAsPtr, vecCopy, vecMove,
vecSort, vecCmp, vecHash, vecMeta
```

`fnv64` 哈希函数与 `sort` 一起放在 `utils.asm` 模块（vecHash 内部通过
extern 调用它）。

约定：

- `ValueMeta` 的 6 个 trait 回调（`drop`/`cmp`/`eq`/`hash`/`copy`/`move`）
  全部是**自定义 ABI 函数**，签名与 sort 的比较器一致：参数 push 传、
  返回值在 rax、callee 用 `ret N` 清栈。
- vec 的内存分配/释放/扩容走 `memAlloc`/`memFree`/`memReloc`，字节搬运走
  `memCopy`/`memMove`——这些包装内部已处理真实 ABI 与栈对齐，vec 自身
  不需要 `hexalign`。
- `vecMeta` 是 `.data` 里的一个 `ValueMeta` 实例，描述 `Vec` 自身
  （`size = Vec_size`，`cmp = vecCmp` ...），供嵌套容器（vec of vec）使用。
- 内部 helper（如 `elemAddr`）非 `global`，也不出现在 `asmrt.inc` 的
  extern 声明里；只有公共 API 才导出。

## 注意事项

- x86-64 没有 `push imm64`。需要压入 64 位立即数时先 `mov rax, imm64`
  再 `push rax`。

## 适用场景与局限

- 适合纯自研代码内部（函数间互相调用只走这套约定），把"要不要保存寄存器"这个问题直接消灭。
- 一旦调用外部库（libc、系统调用等标准 ABI 代码），按真实 ABI 把参数放进对应寄存器即可，不需要额外的寄存器保护；调用点前放一句 `hexalign` 处理栈对齐。
- 代价：所有变量读写都要走一次内存访问（`[%$name]`），比全寄存器分配慢很多；仅适合教学/实验/把心智负担降到最低优先于性能的场景。
