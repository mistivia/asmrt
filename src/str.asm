; str.asm —— 简单字符串操作，自定义 ABI
;
; 约定：字符串均为以 NUL(0) 结尾的 C 风格字符串。

%include "asmrt.inc"

section .text
    global str_len
    global str_eq

; str_len(s) -> 长度，不含结尾 NUL (rax)
str_len:
    beginfn rbx
    %define s [rbp+16]

    mov rbx, s
    xor rax, rax
.loop:
    cmp byte [rbx + rax], 0
    je .done
    inc rax
    jmp .loop
.done:

    endfn rbx
    ret 8
%undef s

; str_eq(a, b) -> 1 表示两个字符串相等，0 表示不相等
; 调用方按顺序 push a; push b（第一个参数先 push）
str_eq:
    beginfn rbx, rcx
    %define a [rbp+24]
    %define b [rbp+16]

    mov rbx, a
    mov rcx, b
.loop:
    mov al, [rbx]
    cmp al, [rcx]
    jne .neq
    test al, al
    je .eq              ; 两边同时遇到 NUL，说明相等
    inc rbx
    inc rcx
    jmp .loop
.neq:
    xor rax, rax
    jmp .done
.eq:
    mov rax, 1
.done:

    endfn rbx, rcx
    ret 16
%undef a
%undef b
