; test_assert_fail.asm —— flag 为假时 assert 应打印 msg 并以退出码 -1(255) 终止进程
; 这是一个"预期失败"的测试：Makefile 的 test 目标会把 *_fail 结尾的用例
; 期望退出码当作 255，而不是 0。

%include "abi.inc"

section .data
    msg db "expected failure: intentional assert trip for test harness", 10, 0

section .text
    extern assert
    global amain

amain:
    beginfn rbx

    push msg
    push 0              ; flag = false -> assert 应该终止进程
    call assert

    ; 不应该执行到这里；如果执行到了，返回一个不同于期望值 255 的退出码
    mov rax, 1
    endfn rbx
    ret 24
