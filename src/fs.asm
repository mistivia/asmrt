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
proc fsStat
    args path, buf

    mov rdi, [%$path]
    mov rsi, [%$buf]
    mov rax, 4          ; sys_stat
    syscall

    end
    ret 16

; fsFstat(fd, statBuf) -> result
proc fsFstat
    args fd, buf

    mov rdi, [%$fd]
    mov rsi, [%$buf]
    mov rax, 5          ; sys_fstat
    syscall

    end
    ret 16

; fsMkdir(path, mode) -> result
proc fsMkdir
    args path, mode

    mov rdi, [%$path]
    mov rsi, [%$mode]
    mov rax, 83         ; sys_mkdir
    syscall

    end
    ret 16

; fsRmdir(path) -> result
proc fsRmdir
    args path

    mov rdi, [%$path]
    mov rax, 84         ; sys_rmdir
    syscall

    end
    ret 8

; fsUnlink(path) -> result
proc fsUnlink
    args path

    mov rdi, [%$path]
    mov rax, 87         ; sys_unlink
    syscall

    end
    ret 8
