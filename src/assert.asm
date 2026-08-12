; assert.asm —— 断言，自定义 ABI
;
; assert(msg, flag)
;   flag 为假（0）时：把以 NUL 结尾的 msg 写到 stderr，然后以退出码 -1 终止进程；
;   flag 为真时：什么也不做，正常返回。

%include "asmrt.inc"

section .text
    global assert

; 调用方按顺序 push msg; push flag（第一个参数先 push）
assert:
    ;; params
    %define msg  [rbp+24]
    %define flag [rbp+16]

    begin
    ; n=2(偶) + L'=0(偶) 已对齐，无局部变量，不需要 sub rsp

    cmp qword flag, 0
    jne .ok

    push msg
    call str_len        ; rax = strlen(msg)；msg 是栈上参数，调用后仍可直接再读

    push 2               ; fd = stderr
    push msg              ; buf = msg
    push rax               ; count = strlen(msg)
    call io_write

    push -1
    call rt_exit          ; 不会返回

.ok:
    end
    ret 16
