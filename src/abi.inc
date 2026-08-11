; abi.inc —— 自定义 ABI 支持宏
;
; 约定：
;   - 参数由调用方 push 压栈传入（不用寄存器传参）
;   - 被调用方通过 ret N 清理栈上的参数（N = 参数总字节数）
;   - 返回值统一放在 rax
;   - 除 rax 外，所有寄存器在函数调用前后保持不变
;
; beginfn/endfn：建立栈帧，并保存/恢复函数内部会用到的寄存器
; preccall/postccall：跨越到真实 System V ABI（libc 函数、syscall）前后，
;                      保护本 ABI 依赖“调用不改变寄存器”的寄存器

%ifndef ABI_INC
%define ABI_INC

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

%endif ; ABI_INC
