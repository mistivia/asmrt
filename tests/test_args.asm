; test_args.asm -- args parameter declaration smoke test

%include "asmrt.inc"

section .data
    err1    db "args p1 mismatch", 0
    err2    db "args p2 mismatch", 0
    err3    db "args p3 mismatch", 0

section .text
    global entry

; sum3(p1, p2, p3) -> rax = p1*100 + p2*10 + p3, to check each param
; landed at the right offset (not just that the sum is right)
sum3:
    ;; args: p1, p2, p3
    %assign N 3
    %assign p1 (16 + (N-1) * 8)
    %assign p2 (16 + (N-2) * 8)
    %assign p3 (16 + (N-3) * 8)
    begin

    mov rax, [rbp + p1]
    cmp rax, 1
    sete al
    movzx rax, al
    push err1
    push rax
    call assert

    mov rax, [rbp + p2]
    cmp rax, 2
    sete al
    movzx rax, al
    push err2
    push rax
    call assert

    mov rax, [rbp + p3]
    cmp rax, 3
    sete al
    movzx rax, al
    push err3
    push rax
    call assert

    mov rax, [rbp + p1]
    imul rax, 100
    mov rcx, [rbp + p2]
    imul rcx, 10
    add rax, rcx
    add rax, [rbp + p3]

    end
    ret 24

entry:
    begin

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
