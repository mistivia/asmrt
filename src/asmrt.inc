; asmrt.inc —— asmrt 运行时统一头文件
;
; 包含自定义 ABI 支持宏，以及运行时对外提供的全部函数的 extern 声明。
; 任何用到 asmrt 的文件（包括运行时自身的实现文件）只需要
; %include "asmrt.inc" 即可，不用再逐个手写 extern。
; （NASM 允许一个符号在同一文件里既 extern 又 global + 定义，
;  此时以本文件的定义为准，所以实现文件包含本文件是安全的。）
;
; 自定义 ABI 约定：
;   - 参数由调用方 push 压栈传入（不用寄存器传参），按参数声明顺序
;     正向 push（第一个参数先 push）
;   - 被调用方通过 ret N 清理栈上的参数（N = 参数总字节数）
;   - 返回值统一放在 rax
;   - 除 rax 外，一次调用（自定义 ABI 的 call、真实 ABI 的 call、裸
;     syscall）之后，其余所有寄存器一律视为已被破坏。因此变量一律
;     落栈：参数和局部变量都以 [rbp+N] / [rbp-N] 的形式通过 %define
;     起别名访问，寄存器只用来承载一次表达式求值过程中的中间结果，
;     绝不让寄存器里的值跨越一次 call。
;
; begin/end：建立/收尾标准栈帧。
;   begin = push rbp; mov rbp, rsp
;   end   = mov rsp, rbp; pop rbp
;   局部变量的 sub rsp, N 写在 begin 之后、函数体之前，N 的取值要按
;   16 字节对齐规则手算（参数个数 + 实际分配的局部变量槽位数之和必须
;   为偶数，不够则多垫一个占位槽），详见 AGENTS.md。
;
; 因为"调用会破坏所有寄存器"这条假设本来就统一适用于自定义 ABI 调用、
; 真实 System V ABI 调用（如 libc 函数）和裸 syscall，所以不再需要任何
; 寄存器保护宏（原来的 preccall/postccall 已删除）。

%ifndef ASMRT_INC
%define ASMRT_INC

; ---- 自定义 ABI 支持宏 ----

%macro begin 0
    push rbp
    mov  rbp, rsp
%endmacro

%macro end 0
    mov  rsp, rbp
    pop  rbp
%endmacro

; ---- 运行时导出符号 ----

; main.asm
extern rt_exit

; io.asm
extern io_open
extern io_close
extern io_read
extern io_write
extern io_seek

; fs.asm
extern fs_stat
extern fs_fstat
extern fs_mkdir
extern fs_rmdir
extern fs_unlink

; assert.asm
extern assert

; str.asm
extern str_len
extern str_eq

%endif ; ASMRT_INC
