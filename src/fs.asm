; fs.asm -- custom-ABI wrappers for filesystem syscalls (stat/fstat, mkdir, rmdir, unlink)
;
; All of these call the Linux x86-64 syscalls directly, no libc dependency.
; Every function follows the custom ABI: arguments pushed on the stack,
; return value in rax, callee cleans the stack with ret N.
; syscall clobbers rcx/r11, but since a call (including a bare syscall)
; already clobbers every register except rax by convention, there's no
; register-protection macro needed or available here.

%include "asmrt.inc"

section .text
    global fsStat
    global fsFstat
    global fsMkdir
    global fsRmdir
    global fsUnlink

; fsStat(path, statBuf) -> result (rax)
fsStat:
    begin
    ;; args: path, buf
    %assign N 2
    %assign path (16 + (N-1) * 8)
    %assign buf (16 + (N-2) * 8)

    mov rdi, [rbp + path]
    mov rsi, [rbp + buf]
    mov rax, 4          ; sys_stat
    syscall

    end
    ret 16

; fsFstat(fd, statBuf) -> result
fsFstat:
    begin
    ;; args: fd, buf
    %assign N 2
    %assign fd (16 + (N-1) * 8)
    %assign buf (16 + (N-2) * 8)

    mov rdi, [rbp + fd]
    mov rsi, [rbp + buf]
    mov rax, 5          ; sys_fstat
    syscall

    end
    ret 16

; fsMkdir(path, mode) -> result
fsMkdir:
    begin
    ;; args: path, mode
    %assign N 2
    %assign path (16 + (N-1) * 8)
    %assign mode (16 + (N-2) * 8)

    mov rdi, [rbp + path]
    mov rsi, [rbp + mode]
    mov rax, 83         ; sys_mkdir
    syscall

    end
    ret 16

; fsRmdir(path) -> result
fsRmdir:
    begin
    ;; args: path
    %assign N 1
    %assign path (16 + (N-1) * 8)

    mov rdi, [rbp + path]
    mov rax, 84         ; sys_rmdir
    syscall

    end
    ret 8

; fsUnlink(path) -> result
fsUnlink:
    begin
    ;; args: path
    %assign N 1
    %assign path (16 + (N-1) * 8)

    mov rdi, [rbp + path]
    mov rax, 87         ; sys_unlink
    syscall

    end
    ret 8
