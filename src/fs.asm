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

; fsStat(path, statBuf) -> result
fsStat:
    ; args: path, buf
    argnum 2
    %assign path arg(1)
    %assign buf arg(2)
    begin

    mov rdi, [rbp + path]
    mov rsi, [rbp + buf]
    mov rax, 4          ; sys_stat
    syscall

    end
    ret 16

; fsFstat(fd, statBuf) -> result
fsFstat:
    ; args: fd, buf
    argnum 2
    %assign fd arg(1)
    %assign buf arg(2)
    begin

    mov rdi, [rbp + fd]
    mov rsi, [rbp + buf]
    mov rax, 5          ; sys_fstat
    syscall

    end
    ret 16

; fsMkdir(path, mode) -> result
fsMkdir:
    ; args: path, mode
    argnum 2
    %assign path arg(1)
    %assign mode arg(2)
    begin

    mov rdi, [rbp + path]
    mov rsi, [rbp + mode]
    mov rax, 83         ; sys_mkdir
    syscall

    end
    ret 16

; fsRmdir(path) -> result
fsRmdir:
    argnum 1
    %assign path arg(1)

    begin
    mov rdi, [rbp + path]
    mov rax, 84         ; sys_rmdir
    syscall

    end
    ret 8

; fsUnlink(path) -> result
fsUnlink:
    argnum 1
    %assign path arg(1)

    begin
    mov rdi, [rbp + path]
    mov rax, 87         ; sys_unlink
    syscall

    end
    ret 8
