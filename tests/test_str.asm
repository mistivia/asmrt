; test_str.asm —— str_len/str_eq 测试

%include "asmrt.inc"

section .data
    s1        db "hello", 0
    s1_len    equ $ - s1 - 1
    empty     db 0
    s2        db "hello", 0
    s3        db "world", 0
    s4        db "hell", 0     ; s1 的前缀，长度不同

    err_len       db "str_len(s1) != 5", 0
    err_len_empty db "str_len(empty) != 0", 0
    err_eq_same   db "str_eq(s1, s2) 应该相等", 0
    err_eq_diff   db "str_eq(s1, s3) 不应该相等", 0
    err_eq_prefix db "str_eq(s1, s4) 不应该相等（长度不同）", 0
    err_eq_self   db "str_eq(s1, s1) 应该相等", 0

section .text
    global amain

amain:
    beginfn rbx

    push s1
    call str_len
    cmp rax, s1_len
    sete al
    movzx rax, al
    push err_len
    push rax
    call assert

    push empty
    call str_len
    cmp rax, 0
    sete al
    movzx rax, al
    push err_len_empty
    push rax
    call assert

    push s1
    push s2
    call str_eq
    push err_eq_same
    push rax
    call assert

    push s1
    push s3
    call str_eq
    xor rax, 1
    push err_eq_diff
    push rax
    call assert

    push s1
    push s4
    call str_eq
    xor rax, 1
    push err_eq_prefix
    push rax
    call assert

    push s1
    push s1
    call str_eq
    push err_eq_self
    push rax
    call assert

    mov rax, 0
    endfn rbx
    ret 24
