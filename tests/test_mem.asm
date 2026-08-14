; test_mem.asm -- memAlloc/memFree/memReloc round-trip test

%include "asmrt.inc"

section .data
    pattern1 dq 0x1122334455667788
    pattern2 dq 0x99AABBCCDDEEFF00

    errAllocNull     db "memAlloc returned null", 0
    errReadback      db "value read back from allocated memory does not match what was written", 0
    errRelocNull     db "memReloc returned null", 0
    errRelocPreserve db "memReloc did not preserve the original content", 0
    errRelocReadback db "value read back from the grown region does not match what was written", 0

section .text
    global amain

amain:
    begin
    ;; local vars
    %define ptr [rbp-8]   ; ptr crosses multiple calls, must live on the stack
    sub rsp, 8

    push 16
    call memAlloc
    mov ptr, rax

    cmp qword ptr, 0
    setne al
    movzx rax, al
    push errAllocNull
    push rax
    call assert

    mov rax, ptr
    mov rbx, [pattern1]
    mov [rax], rbx

    mov rax, ptr
    mov rbx, [rax]
    cmp rbx, [pattern1]
    sete al
    movzx rax, al
    push errReadback
    push rax
    call assert

    push ptr
    push 32
    call memReloc
    mov ptr, rax

    cmp qword ptr, 0
    setne al
    movzx rax, al
    push errRelocNull
    push rax
    call assert

    mov rax, ptr
    mov rbx, [rax]
    cmp rbx, [pattern1]
    sete al
    movzx rax, al
    push errRelocPreserve
    push rax
    call assert

    mov rax, ptr
    mov rbx, [pattern2]
    mov [rax+8], rbx

    mov rax, ptr
    mov rbx, [rax+8]
    cmp rbx, [pattern2]
    sete al
    movzx rax, al
    push errRelocReadback
    push rax
    call assert

    push ptr
    call memFree

    mov rax, 0
    end
    ret 24
