; assert.asm -- assertion, custom ABI
;
; assert(string, flag)
;   flag false (0): write the length-prefixed string (a pointer to
;     [8-byte len][data][NUL], see string.asm) to stderr, then terminate
;     the process with exit code -1;
;   flag true: do nothing, return normally.

%include "asmrt.inc"

section .text
    global assert

; caller pushes in order: push msg; push flag (first argument pushed first)
assert:
    ; args: msg, flag
    argnum 2
    %assign msg arg(1)
    %assign flag arg(2)
    begin

    cmp qword [rbp + flag], 0
    jne .ok

    push 2               ; fd = stderr
    push [rbp + msg]     ; msg = the length-prefixed string pointer
    call ioWriteString

    push -1
    call rtExit          ; never returns

.ok:
    end
    ret 16
