; mem.asm -- custom-ABI wrappers around libc's malloc/free/realloc
;
; Unlike io.asm/fs.asm, these are real System V ABI calls (not raw
; syscalls), so each one needs hexalign right before the call to keep
; the call site 16-byte aligned. Arguments still go through registers
; per the real ABI (rdi/rsi/...), same as any other real-ABI call made
; from inside this runtime.

%include "asmrt.inc"

section .text
    global memAlloc
    global memFree
    global memReloc
    extern malloc
    extern free
    extern realloc

; memAlloc(size) -> ptr (rax), NULL on failure
memAlloc:
    ;; params
    %define size [rbp+16]

    begin

    hexalign
    mov rdi, size
    call malloc

    end
    ret 8

; memFree(ptr) -> rax is always 0; free() itself returns nothing
memFree:
    ;; params
    %define ptr [rbp+16]

    begin

    hexalign
    mov rdi, ptr
    call free

    mov rax, 0
    end
    ret 8

; memReloc(ptr, size) -> new ptr (rax), NULL on failure (ptr is left untouched by libc on failure)
memReloc:
    ;; params
    %define ptr  [rbp+24]
    %define size [rbp+16]

    begin

    hexalign
    mov rdi, ptr
    mov rsi, size
    call realloc

    end
    ret 16
