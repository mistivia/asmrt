; fs.asm —— 文件系统相关系统调用（stat/fstat、mkdir、rmdir、unlink）的自定义 ABI 封装
;
; 全部直接调用 Linux x86-64 syscall，不依赖 libc。
; 每个函数遵循自定义 ABI：参数压栈传入，返回值在 rax，callee 用 ret N 清栈。

%include "asmrt.inc"

section .text
    global fs_stat
    global fs_fstat
    global fs_mkdir
    global fs_rmdir
    global fs_unlink

; fs_stat(path, statbuf) -> result (rax)
fs_stat:
    beginfn
    %define path [rbp+24]
    %define buf  [rbp+16]

    preccall
    mov rdi, path
    mov rsi, buf
    mov rax, 4          ; sys_stat
    syscall
    postccall

    endfn
    ret 16

; fs_fstat(fd, statbuf) -> result
fs_fstat:
    beginfn
    %define fd  [rbp+24]
    %define buf [rbp+16]

    preccall
    mov rdi, fd
    mov rsi, buf
    mov rax, 5          ; sys_fstat
    syscall
    postccall

    endfn
    ret 16

; fs_mkdir(path, mode) -> result
fs_mkdir:
    beginfn
    %define path [rbp+24]
    %define mode [rbp+16]

    preccall
    mov rdi, path
    mov rsi, mode
    mov rax, 83         ; sys_mkdir
    syscall
    postccall

    endfn
    ret 16

; fs_rmdir(path) -> result
fs_rmdir:
    beginfn
    %define path [rbp+16]

    preccall
    mov rdi, path
    mov rax, 84         ; sys_rmdir
    syscall
    postccall

    endfn
    ret 8

; fs_unlink(path) -> result
fs_unlink:
    beginfn
    %define path [rbp+16]

    preccall
    mov rdi, path
    mov rax, 87         ; sys_unlink
    syscall
    postccall

    endfn
    ret 8
