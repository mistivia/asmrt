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
    ;; args: msg, flag
    argnum 2
    %assign msg arg(1)
    %assign flag arg(2)
    begin

    cmp qword [rbp + flag], 0
    jne .ok

    push [rbp + msg]
    call strLen          ; rax = strlen(msg); msg is a stack argument, still readable after the call

    push 2               ; fd = stderr
    push [rbp + msg]     ; buf = msg
    push rax             ; count = strlen(msg)
    call ioWrite

    push -1
    call rtExit          ; never returns

.ok:
    end
    ret 16
