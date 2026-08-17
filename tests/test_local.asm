; test_local.asm -- local variable declaration smoke test

%include "asmrt.inc"

section .data
errA dq (errA_end - errA_start)
    errA_start: db "local a mismatch"
    errA_end: db 0

errB dq (errB_end - errB_start)
    errB_start: db "local b mismatch"
    errB_end: db 0

errC dq (errC_end - errC_start)
    errC_start: db "local c mismatch"
    errC_end: db 0

errD dq (errD_end - errD_start)
    errD_start: db "local d (struct-sized) mismatch"
    errD_end: db 0

section .text
    global entry

entry:
    begin
    ; local variables
    resetOffset
    ; default size 8, at rbp-8
    decOffset 8
    %assign a offset
    ; default size 8, at rbp-16
    decOffset 8
    %assign b offset
    ; default size 8, at rbp-24
    decOffset 8
    %assign c offset
    ; struct-sized, at rbp-40
    decOffset 16)
    %assign d offset
    ; endlocal
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
