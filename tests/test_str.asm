; test_str.asm -- strLen/strEq test

%include "asmrt.inc"

section .data
    s1        db "hello", 0
    s1Len     equ $ - s1 - 1
    empty     db 0
    s2        db "hello", 0
    s3        db "world", 0
    s4        db "hell", 0     ; prefix of s1, different length

    errLen       db "strLen(s1) != 5", 0
    errLenEmpty  db "strLen(empty) != 0", 0
    errEqSame    db "strEq(s1, s2) should be equal", 0
    errEqDiff    db "strEq(s1, s3) should not be equal", 0
    errEqPrefix  db "strEq(s1, s4) should not be equal (different length)", 0
    errEqSelf    db "strEq(s1, s1) should be equal", 0

section .text
    global entry

proc entry

    push s1
    call strLen
    cmp rax, s1Len
    sete al
    movzx rax, al
    push errLen
    push rax
    call assert

    push empty
    call strLen
    cmp rax, 0
    sete al
    movzx rax, al
    push errLenEmpty
    push rax
    call assert

    push s1
    push s2
    call strEq
    push errEqSame
    push rax
    call assert

    push s1
    push s3
    call strEq
    xor rax, 1
    push errEqDiff
    push rax
    call assert

    push s1
    push s4
    call strEq
    xor rax, 1
    push errEqPrefix
    push rax
    call assert

    push s1
    push s1
    call strEq
    push errEqSelf
    push rax
    call assert

    mov rax, 0
    end
    ret 24
