# ASM 开发模式：自定义调用 ABI（stack-based, callee-cleans-stack）

## 核心思想

不使用 System V AMD64 的寄存器传参 ABI，而是自定义一套更简单、心智负担更低的调用约定：

- **参数**：调用方通过 `push` 依次压栈传参（而非放入 rdi/rsi/rdx/...），且按参数声明顺序正向 push —— **第一个参数先 push，最后一个参数最后 push**。因此进入函数后 `[rbp+16]` 对应的是*最后一个参数*（最靠近返回地址），第一个参数反而在最大的偏移处（详见「参数访问约定」）。
- **栈清理**：被调用方（callee）通过 `ret N` 自行清理栈上的参数（类似 stdcall，而非 cdecl）。`N` = 参数总字节数。
- **返回值**：统一放在 `rax`。
- **寄存器保护**：除 `rax` 外，其余寄存器默认视为"调用后不变"（callee-saved），函数内部用到的寄存器自己负责保存/恢复，调用方因此不用担心内部实现细节，写递归/复杂逻辑更省心。

这套约定只在"自定义 ABI 函数互相调用"时有效；一旦要调用外部真正 ABI（如 libc 的 `printf`）的函数，就必须显式保护自定义 ABI 依赖的寄存器不被真实 ABI 调用破坏。

## 四个宏

### 1. `beginfn` / `endfn`：变长寄存器帧宏

```asm
%macro beginfn 1-*
    push rbp
    mov  rbp, rsp
%rep %0
    push %1
    %rotate 1
%endrep
%endmacro

%macro endfn 1-*
%rep %0
    %rotate -1
    pop %1
%endrep
    pop  rbp
%endmacro
```

- 利用 NASM 的可变参数宏（`1-*`、`%0`、`%rep`/`%rotate`）实现"传入几个寄存器名，就 push/pop 几个"。
- `beginfn rbp` 建立标准栈帧后，紧接着把调用列表中的寄存器逐个压栈（用作函数内的局部保存）。
- `endfn` 以相反顺序弹出，最后恢复 `rbp`。
- 用法示例：`beginfn rcx`（`fibo` 函数）表示该函数内部会用 `rcx` 存中间结果，进入时保存、退出时恢复，从而使 `rcx` 在这个自定义 ABI 下对调用者也是"安全"的。
- `print_num` 里的 `beginfn rbp` 则是另一种用法：额外 push 一次 `rbp` 本身，不是为了保存寄存器，而是用来凑够 16 字节栈对齐。因为进入函数时已经有 `push rbp`（帧指针）+ `call` 压入的返回地址，栈偏移是不对齐的；`beginfn` 的可变参数列表每传入一个寄存器就多 push 8 字节，所以传 `rbp` 只是借用它当"占位寄存器"再压一次栈，把栈调整到 16 字节对齐，以满足之后 `call printf` 时 System V ABI 对调用点栈对齐的要求。`endfn rbp` 对应地多弹出一次，抵消这次占位 push。

### 2. `preccall` / `postccall`：跨真实 ABI 调用的寄存器保护

```asm
%macro preccall
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11
%endmacro

%macro postccall
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
%endmacro
```

- 这几个寄存器在 System V ABI 里是 caller-saved（调用后可能被破坏），但在这套自定义 ABI 里被当作"全程保留"。
- 所以每次要调用外部真实 ABI 函数（`extern printf` 等）时，先 `preccall` 把这些寄存器备份，调用结束后 `postccall` 恢复，保证自定义 ABI 的"寄存器不变"假设不被外部调用破坏。

## 参数访问约定

调用方按参数声明顺序正向 push：`f(p1, p2, ..., pn)` 对应 `push p1; push p2; ...; push pn; call f`。
进入函数、`beginfn` 建立好帧后，栈布局固定为：

```
[rbp + 0]                旧 rbp
[rbp + 8]                返回地址（call 压入）
[rbp + 16]                pn      （最后一个参数，最后 push，离返回地址最近）
[rbp + 24]                p(n-1)
...
[rbp + 16 + 8*(n-1)]       p1      （第一个参数，最先 push，离返回地址最远）
```

也就是说，参数偏移要**从最后一个参数往前数**：最后一个参数固定在 `[rbp+16]`，往前每多一个参数偏移 +8，第一个参数在最大偏移处。用 `%define` 给参数取别名时按这个顺序分配，函数体内直接写别名即可读取，可读性接近高级语言。

示例（`assert(msg, flag)`，2 个参数）：

```asm
; 调用方：第一个参数先 push
push msg
push flag
call assert

; assert 内部：
%define msg  [rbp + 24]   ; 第 1 个参数，最先 push
%define flag [rbp + 16]   ; 第 2 个参数，最后 push，离返回地址最近
```

单参数函数（如下面例子里的 `fibo`、`print_num`）不受这次调整影响 —— 只有一个参数时，"先 push" 和"后 push"是同一次 push，恒定落在 `[rbp+16]`。

## 完整调用示例（递归 fibo）

```asm
main:
    push rbp
    mov rbp, rsp

    push 10          ; 传参：压栈
    call fibo
    push rax         ; fibo 返回值在 rax，作为参数传给 print_num
    call print_num
    ...

fibo:
    beginfn rcx      ; 建帧 + 保存 rcx（内部要用它存中间结果）
    %define x [rbp + 16]

    mov rax, x
    cmp rax, 2
    jg .calc
    mov rax, 1
    jmp .end
.calc:
    mov rax, x
    sub rax, 1
    push rax
    call fibo        ; 递归调用，无需担心 rcx 被破坏（自定义 ABI 保证）
    mov rcx, rax      ; 安全地把结果存进 rcx

    mov rax, x
    sub rax, 2
    push rax
    call fibo
    add rax, rcx     ; rcx 在两次调用之间始终有效
.end:
    endfn rcx        ; 恢复 rcx + rbp
    ret 8            ; 清理调用方压入的 1 个 8 字节参数

print_num:
    %define x [rbp + 16]
    beginfn rbp

    mov rdi, print_msg   ; 按真实 System V ABI 准备 printf 的参数
    mov rsi, x
    xor rax, rax         ; printf 是变参函数，rax 需清零表示 0 个向量寄存器参数
    preccall              ; 保护自定义 ABI 的寄存器
    call printf
    postccall              ; 恢复

    endfn rbp
    ret 8
```

## 这个模式解决的问题

写手工汇编时最烦的两件事：

1. 每个函数都要小心翼翼记住"我用了哪个寄存器、要不要保存"——`beginfn`/`endfn` 把这个过程宏化、声明式化。
2. 递归/多层调用时，寄存器会在调用链上被不同层覆写，容易出 bug——自定义 ABI 直接规定"调用不改变除 rax 外的寄存器"，把这个负担从"程序员记忆"转移到"宏机械保存/恢复"，只有在跨到外部真实 ABI 边界时才需要 `preccall`/`postccall` 显式处理。

## 适用场景与局限

- 适合纯自研代码内部（函数间互相调用只走这套约定），能显著降低手写递归/多参数函数时的心智负担。
- 边界清晰：一旦调用外部库（libc、系统调用等使用标准 ABI 的代码），必须用 `preccall`/`postccall` 显式转换约定，且传参需按真实 ABI 放入寄存器（如例中 `mov rdi, ...` / `mov rsi, ...`）。
- 代价：栈操作（push/pop、rbp 帧）比寄存器传参多，性能不如标准 ABI，仅适合教学/实验/减少心智负担优先于性能的场景。


# 你的任务

基于这套自定义ABI，开发一个nasm用的汇编runtime，封装一些常用函数和系统调用。