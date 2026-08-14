; test_local.asm -- local/endlocal shortcut macro smoke test

%include "asmrt.inc"

section .data
    errA    db "local a mismatch", 0
    errB    db "local b mismatch", 0
    errC    db "local c mismatch", 0
    errD    db "local d (struct-sized) mismatch", 0

section .text
    global entry

proc entry
    local a          ; default size 8, at rbp-8
    local b          ; default size 8, at rbp-16
    local c          ; default size 8, at rbp-24
    local d, 16      ; struct-sized, at rbp-40
    endlocal

    mov qword [%$a], 111
    mov qword [%$b], 222
    mov qword [%$c], 333
    mov qword [%$d], 444
    mov qword [%$d + 8], 555

    mov rax, [%$a]
    cmp rax, 111
    sete al
    movzx rax, al
    push errA
    push rax
    call assert

    mov rax, [%$b]
    cmp rax, 222
    sete al
    movzx rax, al
    push errB
    push rax
    call assert

    mov rax, [%$c]
    cmp rax, 333
    sete al
    movzx rax, al
    push errC
    push rax
    call assert

    mov rax, [%$d]
    cmp rax, 444
    jne .fail
    mov rax, [%$d + 8]
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
