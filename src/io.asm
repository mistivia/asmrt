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
    global io_seek

; io_open(path, flags, mode) -> fd
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

; io_read(fd, buf, count) -> bytes read
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

; io_write(fd, buf, count) -> bytes written
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

; io_seek(fd, offset, whence) -> 新的文件偏移量 (rax)
; whence: 0 = SEEK_SET, 1 = SEEK_CUR, 2 = SEEK_END
io_seek:
    beginfn
    %define fd     [rbp+32]
    %define offset [rbp+24]
    %define whence [rbp+16]

    preccall
    mov rdi, fd
    mov rsi, offset
    mov rdx, whence
    mov rax, 8          ; sys_lseek
    syscall
    postccall

    endfn
    ret 24
