; fs.asm —— 文件系统相关系统调用（stat/fstat、mkdir、rmdir、unlink）的自定义 ABI 封装
;
; 全部直接调用 Linux x86-64 syscall，不依赖 libc。
; 每个函数遵循自定义 ABI：参数压栈传入，返回值在 rax，callee 用 ret N 清栈。
; syscall 会破坏 rcx/r11，但因为调用（含裸 syscall）本来就默认破坏除 rax
; 外的所有寄存器，不需要也不再有寄存器保护宏可用。

%include "asmrt.inc"

section .text
    global fs_stat
    global fs_fstat
    global fs_mkdir
    global fs_rmdir
    global fs_unlink

; fs_stat(path, statbuf) -> result (rax)
fs_stat:
    ;; params
    %define path [rbp+24]
    %define buf  [rbp+16]

    begin

    mov rdi, path
    mov rsi, buf
    mov rax, 4          ; sys_stat
    syscall

    end
    ret 16

; fs_fstat(fd, statbuf) -> result
fs_fstat:
    ;; params
    %define fd  [rbp+24]
    %define buf [rbp+16]

    begin

    mov rdi, fd
    mov rsi, buf
    mov rax, 5          ; sys_fstat
    syscall

    end
    ret 16

; fs_mkdir(path, mode) -> result
fs_mkdir:
    ;; params
    %define path [rbp+24]
    %define mode [rbp+16]

    begin

    mov rdi, path
    mov rsi, mode
    mov rax, 83         ; sys_mkdir
    syscall

    end
    ret 16

; fs_rmdir(path) -> result
fs_rmdir:
    ;; params
    %define path [rbp+16]

    begin

    mov rdi, path
    mov rax, 84         ; sys_rmdir
    syscall

    end
    ret 8

; fs_unlink(path) -> result
fs_unlink:
    ;; params
    %define path [rbp+16]

    begin

    mov rdi, path
    mov rax, 87         ; sys_unlink
    syscall

    end
    ret 8
