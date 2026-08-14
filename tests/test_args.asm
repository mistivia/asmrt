; test_args.asm -- args shortcut macro smoke test

%include "asmrt.inc"

section .data
    err1    db "args p1 mismatch", 0
    err2    db "args p2 mismatch", 0
    err3    db "args p3 mismatch", 0

section .text
    global entry

; sum3(p1, p2, p3) -> rax = p1*100 + p2*10 + p3, to check each param
; landed at the right offset (not just that the sum is right)
proc sum3
    args p1, p2, p3

    mov rax, [%$p1]
    cmp rax, 1
    sete al
    movzx rax, al
    push err1
    push rax
    call assert

    mov rax, [%$p2]
    cmp rax, 2
    sete al
    movzx rax, al
    push err2
    push rax
    call assert

    mov rax, [%$p3]
    cmp rax, 3
    sete al
    movzx rax, al
    push err3
    push rax
    call assert

    mov rax, [%$p1]
    imul rax, 100
    mov rcx, [%$p2]
    imul rcx, 10
    add rax, rcx
    add rax, [%$p3]

    end
    ret 24

proc entry

    push 1
    push 2
    push 3
    call sum3

    cmp rax, 123
    jne .fail
    mov rax, 0
    jmp .done
.fail:
    mov rax, 1
.done:

    end
    ret 24
