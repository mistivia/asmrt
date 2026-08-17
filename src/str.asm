; str.asm -- simple string operations, custom ABI
;
; Convention: strings are NUL(0)-terminated C-style strings.

%include "asmrt.inc"

section .text
    global strLen
    global strEq

; strLen(s) -> length, excluding the trailing NUL (rax)
strLen:
    ;; args: s
    %assign N 1
    %assign s (16 + (N-1) * 8)
    begin

    ; no call inside the loop, so rbx is just scratch for this stretch of
    ; code -- no need to save/restore it, the caller already assumes it's
    ; clobbered

    mov rbx, [rbp + s]
    xor rax, rax
.loop:
    cmp byte [rbx + rax], 0
    je .done
    inc rax
    jmp .loop
.done:

    end
    ret 8

; strEq(a, b) -> 1 if the two strings are equal, 0 otherwise
strEq:
    ;; args: a, b
    %assign N 2
    %assign a (16 + (N-1) * 8)
    %assign b (16 + (N-2) * 8)
    begin

    ; same as above: no call inside the loop, rbx/rcx are just scratch

    mov rbx, [rbp + a]
    mov rcx, [rbp + b]
.loop:
    mov al, [rbx]
    cmp al, [rcx]
    jne .neq
    test al, al
    je .eq              ; both sides hit NUL at the same time -> equal
    inc rbx
    inc rcx
    jmp .loop
.neq:
    xor rax, rax
    jmp .done
.eq:
    mov rax, 1
.done:

    end
    ret 16
