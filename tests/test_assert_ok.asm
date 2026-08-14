; test_assert_ok.asm -- when flag is true, assert should return directly, no print, no exit

%include "asmrt.inc"

section .data
    msg db "this should never be printed", 10, 0

section .text
    global entry

proc entry

    push msg
    push 1              ; flag = true
    call assert

    mov rax, 0
    end
    ret 24
