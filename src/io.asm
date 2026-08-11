; io.asm —— 文件打开/关闭/读写的自定义 ABI 封装
;
; 全部直接调用 Linux x86-64 syscall，不依赖 libc。
; 每个函数遵循自定义 ABI：参数压栈传入，返回值在 rax，callee 用 ret N 清栈。
; syscall 指令本身会破坏 rcx/r11，且需要把参数搬进 rdi/rsi/rdx，
; 所以用 preccall/postccall 包裹，保证“调用不改变寄存器”的约定对调用方成立。

%include "asmrt.inc"

section .text
    global io_open
    global io_close
    global io_read
    global io_write

; io_open(path, flags, mode) -> fd (rax)
; 调用方按顺序 push path; push flags; push mode（第一个参数先 push）
io_open:
    beginfn
    %define path  [rbp+32]
    %define flags [rbp+24]
    %define mode  [rbp+16]

    preccall
    mov rdi, path
    mov rsi, flags
    mov rdx, mode
    mov rax, 2          ; sys_open
    syscall
    postccall

    endfn
    ret 24
%undef path
%undef flags
%undef mode

; io_close(fd) -> result (rax)
io_close:
    beginfn
    %define fd [rbp+16]

    preccall
    mov rdi, fd
    mov rax, 3          ; sys_close
    syscall
    postccall

    endfn
    ret 8
%undef fd

; io_read(fd, buf, count) -> bytes read (rax)
; 调用方按顺序 push fd; push buf; push count（第一个参数先 push）
io_read:
    beginfn
    %define fd    [rbp+32]
    %define buf   [rbp+24]
    %define count [rbp+16]

    preccall
    mov rdi, fd
    mov rsi, buf
    mov rdx, count
    mov rax, 0          ; sys_read
    syscall
    postccall

    endfn
    ret 24
%undef fd
%undef buf
%undef count

; io_write(fd, buf, count) -> bytes written (rax)
; 调用方按顺序 push fd; push buf; push count（第一个参数先 push）
io_write:
    beginfn
    %define fd    [rbp+32]
    %define buf   [rbp+24]
    %define count [rbp+16]

    preccall
    mov rdi, fd
    mov rsi, buf
    mov rdx, count
    mov rax, 1          ; sys_write
    syscall
    postccall

    endfn
    ret 24
%undef fd
%undef buf
%undef count
