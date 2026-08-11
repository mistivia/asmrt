; test_assert_ok.asm —— flag 为真时 assert 应直接返回，不打印、不退出

%include "asmrt.inc"

section .data
    msg db "this should never be printed", 10, 0

section .text
    global amain

amain:
    beginfn rbx

    push msg
    push 1              ; flag = true
    call assert

    mov rax, 0
    endfn rbx
    ret 24
