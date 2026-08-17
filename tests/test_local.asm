; test_local.asm -- local variable declaration smoke test

%include "asmrt.inc"

section .data
    errA    db "local a mismatch", 0
    errB    db "local b mismatch", 0
    errC    db "local c mismatch", 0
    errD    db "local d (struct-sized) mismatch", 0

section .text
    global entry

entry:
    begin
    ;; local variables
    resetOffset
    ;; default size 8, at rbp-8
    %assign offset (offset - 8)
    %assign a offset
    ;; default size 8, at rbp-16
    %assign offset (offset - 8)
    %assign b offset
    ;; default size 8, at rbp-24
    %assign offset (offset - 8)
    %assign c offset
    ;; struct-sized, at rbp-40
    %assign offset (offset - 16)
    %assign d offset
    ;; endlocal
    sub rsp, (-offset)

    mov qword [rbp + a], 111
    mov qword [rbp + b], 222
    mov qword [rbp + c], 333
    mov qword [rbp + d], 444
    mov qword [rbp + d + 8], 555

    mov rax, [rbp + a]
    cmp rax, 111
    sete al
    movzx rax, al
    push errA
    push rax
    call assert

    mov rax, [rbp + b]
    cmp rax, 222
    sete al
    movzx rax, al
    push errB
    push rax
    call assert

    mov rax, [rbp + c]
    cmp rax, 333
    sete al
    movzx rax, al
    push errC
    push rax
    call assert

    mov rax, [rbp + d]
    cmp rax, 444
    jne .fail
    mov rax, [rbp + d + 8]
    cmp rax, 555
    jne .fail
    mov rax, 1
    jmp .dok
.fail:
    xor rax, rax
.dok:
    push errD
    push rax
    call assert

    mov rax, 0
    end
    ret 24
