; assert.asm -- assertion, custom ABI
;
; assert(msg, flag)
;   flag false (0): write the NUL-terminated msg to stderr, then
;     terminate the process with exit code -1;
;   flag true: do nothing, return normally.

%include "asmrt.inc"

section .text
    global assert

; caller pushes in order: push msg; push flag (first argument pushed first)
assert:
    ;; params
    %define msg  (rbp+24)
    %define flag (rbp+16)

    begin
    ; no locals needed here

    cmp qword [flag], 0
    jne .ok

    push [msg]
    call strLen          ; rax = strlen(msg); msg is a stack argument, still readable after the call

    push 2               ; fd = stderr
    push [msg]           ; buf = msg
    push rax             ; count = strlen(msg)
    call ioWrite

    push -1
    call rtExit          ; never returns

.ok:
    end
    ret 16
