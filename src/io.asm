; io.asm —— 文件打开/关闭/读写的自定义 ABI 封装
;
; 全部直接调用 Linux x86-64 syscall，不依赖 libc。
; 每个函数遵循自定义 ABI：参数压栈传入，返回值在 rax，callee 用 ret N 清栈。
; syscall 会破坏 rcx/r11，但因为调用（含裸 syscall）本来就默认破坏除 rax
; 外的所有寄存器，不需要也不再有寄存器保护宏可用。

%include "asmrt.inc"

section .text
    global io_open
    global io_close
    global io_read
    global io_write
    global io_seek

; io_open(path, flags, mode) -> fd
io_open:
    ;; params
    %define path  [rbp+32]
    %define flags [rbp+24]
    %define mode  [rbp+16]

    begin

    mov rdi, path
    mov rsi, flags
    mov rdx, mode
    mov rax, 2          ; sys_open
    syscall

    end
    ret 24

; io_close(fd) -> result (rax)
io_close:
    ;; params
    %define fd [rbp+16]

    begin

    mov rdi, fd
    mov rax, 3          ; sys_close
    syscall

    end
    ret 8

; io_read(fd, buf, count) -> bytes read
io_read:
    ;; params
    %define fd    [rbp+32]
    %define buf   [rbp+24]
    %define count [rbp+16]

    begin

    mov rdi, fd
    mov rsi, buf
    mov rdx, count
    mov rax, 0          ; sys_read
    syscall

    end
    ret 24

; io_write(fd, buf, count) -> bytes written
io_write:
    ;; params
    %define fd    [rbp+32]
    %define buf   [rbp+24]
    %define count [rbp+16]

    begin

    mov rdi, fd
    mov rsi, buf
    mov rdx, count
    mov rax, 1          ; sys_write
    syscall

    end
    ret 24

; io_seek(fd, offset, whence) -> 新的文件偏移量 (rax)
; whence: 0 = SEEK_SET, 1 = SEEK_CUR, 2 = SEEK_END
io_seek:
    ;; params
    %define fd     [rbp+32]
    %define offset [rbp+24]
    %define whence [rbp+16]

    begin

    mov rdi, fd
    mov rsi, offset
    mov rdx, whence
    mov rax, 8          ; sys_lseek
    syscall

    end
    ret 24
