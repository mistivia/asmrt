; io.asm -- custom-ABI wrappers for opening/closing/reading/writing files
;
; All of these call the Linux x86-64 syscalls directly, no libc dependency.
; Every function follows the custom ABI: arguments pushed on the stack,
; return value in rax, callee cleans the stack with ret N.
; syscall clobbers rcx/r11, but since a call (including a bare syscall)
; already clobbers every register except rax by convention, there's no
; register-protection macro needed or available here.

%include "asmrt.inc"

section .text
    global ioOpen
    global ioClose
    global ioRead
    global ioWrite
    global ioSeek

; ioOpen(path, flags, mode) -> fd
ioOpen:
    ;; params
    %define path  (rbp+32)
    %define flags (rbp+24)
    %define mode  (rbp+16)

    begin

    mov rdi, [path]
    mov rsi, [flags]
    mov rdx, [mode]
    mov rax, 2          ; sys_open
    syscall

    end
    ret 24

; ioClose(fd) -> result (rax)
ioClose:
    ;; params
    %define fd (rbp+16)

    begin

    mov rdi, [fd]
    mov rax, 3          ; sys_close
    syscall

    end
    ret 8

; ioRead(fd, buf, count) -> bytes read
ioRead:
    ;; params
    %define fd    (rbp+32)
    %define buf   (rbp+24)
    %define count (rbp+16)

    begin

    mov rdi, [fd]
    mov rsi, [buf]
    mov rdx, [count]
    mov rax, 0          ; sys_read
    syscall

    end
    ret 24

; ioWrite(fd, buf, count) -> bytes written
ioWrite:
    ;; params
    %define fd    (rbp+32)
    %define buf   (rbp+24)
    %define count (rbp+16)

    begin

    mov rdi, [fd]
    mov rsi, [buf]
    mov rdx, [count]
    mov rax, 1          ; sys_write
    syscall

    end
    ret 24

; ioSeek(fd, offset, whence) -> new file offset (rax)
; whence: 0 = SEEK_SET, 1 = SEEK_CUR, 2 = SEEK_END
ioSeek:
    ;; params
    %define fd     (rbp+32)
    %define offset (rbp+24)
    %define whence (rbp+16)

    begin

    mov rdi, [fd]
    mov rsi, [offset]
    mov rdx, [whence]
    mov rax, 8          ; sys_lseek
    syscall

    end
    ret 24
