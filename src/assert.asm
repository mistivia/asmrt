; assert.asm —— 断言，自定义 ABI
;
; assert(msg, flag)
;   flag 为假（0）时：把以 NUL 结尾的 msg 写到 stderr，然后以退出码 -1 终止进程；
;   flag 为真时：什么也不做，正常返回。
; 长度计算复用 str.asm 的 str_len，写 stderr 复用 io.asm 的 io_write；
; 退出进程没有现成的封装，直接用 sys_exit。

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

    mov rbx, msg

    push msg
    call str_len        ; rax = strlen(msg)

    push 2               ; fd = stderr
    push rbx              ; buf = msg
    push rax               ; count = strlen(msg)
    call io_write

    mov rdi, -1
    mov rax, 60           ; sys_exit
    syscall              ; 不会返回

.ok:
    endfn rbx
    ret 16
