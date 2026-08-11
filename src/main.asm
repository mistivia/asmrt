; main.asm —— 运行时入口
;
; main 由 CRT/libc 按标准 System V ABI 调用：
;   rdi = argc, rsi = argv, rdx = envp
; 将三个参数按自定义 ABI 压栈后转调用户提供的 amain（extern，自定义 ABI 实现，
; 内部通过 ret 24 清理这三个参数）。自定义 ABI 按参数声明顺序正向 push，
; 所以 amain 内部 [rbp+16]=envp（最后 push）、[rbp+24]=argv、[rbp+32]=argc（最先 push）。
; amain 的返回值（rax）即作为进程退出码，沿用 __libc_start_main 的约定：
; main 的返回值就是 exit status。

section .text
    extern amain
    global main

main:
    push rbp
    mov  rbp, rsp

    push rdi            ; argc -> amain 第 1 个参数，最先 push
    push rsi            ; argv -> amain 第 2 个参数
    push rdx            ; envp -> amain 第 3 个参数，最后 push（[rbp+16]）

    call amain           ; 自定义 ABI 调用，amain 内部 ret 24 清栈

    pop rbp
    ret
