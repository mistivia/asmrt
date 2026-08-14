; main.asm -- runtime entry point
;
; main is called by the CRT/libc using the standard System V ABI:
;   rdi = argc, rsi = argv, rdx = envp
; It pushes the three arguments onto the stack using the custom ABI and
; forwards to the user-supplied amain (extern, custom-ABI implementation,
; cleans up its three arguments internally with ret 24). The custom ABI
; pushes arguments in declaration order, so inside amain [rbp+16]=envp
; (pushed last), [rbp+24]=argv, [rbp+32]=argc (pushed first).
; amain's return value (rax) becomes the process exit code, following the
; __libc_start_main convention that main's return value is the exit
; status.
;
; This file also provides rtExit(code), the single place under the
; custom ABI to terminate the process; other runtime modules (e.g.
; assert.asm) should call rtExit instead of issuing a bare sys_exit.

%include "asmrt.inc"

section .text
    extern amain
    global main
    global rtExit

main:
    begin

    push rdi            ; argc -> amain's 1st argument, pushed first
    push rsi            ; argv -> amain's 2nd argument
    push rdx            ; envp -> amain's 3rd argument, pushed last ([rbp+16])

    call amain           ; custom-ABI call; amain cleans the stack with ret 24

    end
    ret

; rtExit(code) -> does not return
; Caller pushes code
rtExit:
    ;; params
    %define code [rbp+16]

    begin

    mov rdi, code
    mov rax, 60         ; sys_exit
    syscall             ; never returns
