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
;   - 除 rax 外，所有寄存器在函数调用前后保持不变
;
; beginfn/endfn：建立栈帧，并保存/恢复函数内部会用到的寄存器
; preccall/postccall：跨越到真实 System V ABI（libc 函数、syscall）前后，
;                      保护本 ABI 依赖“调用不改变寄存器”的寄存器

%ifndef ASMRT_INC
%define ASMRT_INC

; ---- 自定义 ABI 支持宏 ----

%macro preccall 0
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11
%endmacro

%macro postccall 0
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
%endmacro

%macro beginfn 0-*
    push rbp
    mov  rbp, rsp
%rep %0
    push %1
    %rotate 1
%endrep
%endmacro

%macro endfn 0-*
%rep %0
    %rotate -1
    pop %1
%endrep
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
