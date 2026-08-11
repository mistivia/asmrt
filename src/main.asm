; main.asm —— 运行时入口
;
; main 由 CRT/libc 按标准 System V ABI 调用：
;   rdi = argc, rsi = argv, rdx = envp
; 将三个参数按自定义 ABI 压栈后转调用户提供的 amain（extern，自定义 ABI 实现，
; 内部通过 ret 24 清理这三个参数）。自定义 ABI 按参数声明顺序正向 push，
; 所以 amain 内部 [rbp+16]=envp（最后 push）、[rbp+24]=argv、[rbp+32]=argc（最先 push）。
; amain 的返回值（rax）即作为进程退出码，沿用 __libc_start_main 的约定：
; main 的返回值就是 exit status。
;
; 这里也提供 rt_exit(code)，自定义 ABI 下终止进程的统一入口，运行时其它模块
; （比如 assert.asm）需要退出进程时应该 call rt_exit，不要自己裸写 sys_exit。

%include "asmrt.inc"

section .text
    extern amain
    global main
    global rt_exit

main:
    push rbp
    mov  rbp, rsp

    push rdi            ; argc -> amain 第 1 个参数，最先 push
    push rsi            ; argv -> amain 第 2 个参数
    push rdx            ; envp -> amain 第 3 个参数，最后 push（[rbp+16]）

    call amain           ; 自定义 ABI 调用，amain 内部 ret 24 清栈

    pop rbp
    ret

; rt_exit(code) -> 不返回
; 调用方按顺序 push code
rt_exit:
    beginfn
    %define code [rbp+16]

    mov rdi, code
    mov rax, 60         ; sys_exit
    syscall             ; 不会返回
