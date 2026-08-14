; test_assert_fail.asm -- when flag is false, assert should print msg and
; terminate the process with exit code -1 (255).
; This is an "expected failure" test case: the Makefile's test target
; treats *_fail-suffixed cases as expecting exit code 255, not 0.

%include "asmrt.inc"

section .data
    msg db "expected failure: intentional assert trip for test harness", 10, 0

section .text
    global amain

amain:
    begin

    push msg
    push 0              ; flag = false -> assert should terminate the process
    call assert

    ; should never reach here; if we do, return a code other than the expected 255
    mov rax, 1
    end
    ret 24
