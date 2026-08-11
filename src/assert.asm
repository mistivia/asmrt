; assert.asm —— 断言，自定义 ABI
;
; assert(msg, flag)
;   flag 为假（0）时：把以 NUL 结尾的 msg 写到 stderr，然后以退出码 -1 终止进程；
;   flag 为真时：什么也不做，正常返回。
; 直接使用 write/exit 系统调用，不依赖 io.asm，保持独立可用。

%include "asmrt.inc"

section .text
    global assert

; 调用方按顺序 push msg; push flag（第一个参数先 push）
assert:
    beginfn rbx
    %define msg  [rbp+24]
    %define flag [rbp+16]

    cmp qword flag, 0
    jne .ok

    preccall
    mov rbx, msg
    xor rcx, rcx
.strlen_loop:
    cmp byte [rbx + rcx], 0
    je .strlen_done
    inc rcx
    jmp .strlen_loop
.strlen_done:
    mov rdi, 2          ; fd = stderr
    mov rsi, msg
    mov rdx, rcx
    mov rax, 1          ; sys_write
    syscall
    postccall

    mov rdi, -1
    mov rax, 60         ; sys_exit
    syscall             ; 不会返回

.ok:
    endfn rbx
    ret 16
