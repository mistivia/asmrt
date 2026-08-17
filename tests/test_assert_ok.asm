; test_assert_ok.asm -- when flag is true, assert should return directly, no print, no exit

%include "asmrt.inc"

section .data
msg dq (msg_end - msg_start)
    msg_start: db "this should never be printed", 10
    msg_end: db 0

section .text
    global entry

entry:
    begin

    push msg
    push 1              ; flag = true
    call assert

    mov rax, 0
    end
    ret 24
