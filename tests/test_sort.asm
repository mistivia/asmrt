; test_sort.asm -- sort() test: one pass with 8-byte elements, one with
; 4-byte elements (proving the element size is actually respected, not
; hardcoded), each with its own custom-ABI comparator.

%include "asmrt.inc"

section .data
    arr64      dq 5, 3, 8, 1, 9, 2, 7, 6, 4, 0
    arr64Len   equ 10

    arr32      dd 3, -1, 2, -5, 0, 42, -42
    arr32Len   equ 7

    errNotSorted64 db "sort() left the int64 array out of order", 0
    errNotSorted32 db "sort() left the int32 array out of order", 0

section .text
    global entry

; cmpInt64(a, b) -> *a - *b, a/b are pointers to int64 elements
cmpInt64:
    begin
    ;; args: a, b
    %assign N 2
    %assign a (16 + (N-1) * 8)
    %assign b (16 + (N-2) * 8)

    mov rax, [rbp + a]
    mov rax, [rax]
    mov rbx, [rbp + b]
    mov rbx, [rbx]
    sub rax, rbx

    end
    ret 16

; cmpInt32(a, b) -> *a - *b (sign-extended to 64 bits), a/b point to int32 elements
cmpInt32:
    begin
    ;; args: a, b
    %assign N 2
    %assign a (16 + (N-1) * 8)
    %assign b (16 + (N-2) * 8)

    mov rax, [rbp + a]
    movsx rax, dword [rax]
    mov rbx, [rbp + b]
    movsx rbx, dword [rbx]
    sub rax, rbx

    end
    ret 16

entry:
    begin
    ;; local variables
    %assign offset 0
    ;; idx 8 bytes
    %assign offset (offset - 8)
    %assign idx offset
    ;; endlocal
    sub rsp, (-offset)

    push arr64
    push arr64Len
    push 8
    push cmpInt64
    call sort

    mov qword [rbp + idx], 0
.check64Loop:
    mov rax, [rbp + idx]
    cmp rax, arr64Len
    jge .check64Done

    mov rbx, [rbp + idx]
    mov rcx, [arr64 + rbx*8]
    cmp rcx, rbx                ; ascending 0..9 -> arr64[i] should equal i
    sete al
    movzx rax, al
    push errNotSorted64
    push rax
    call assert

    mov rax, [rbp + idx]
    inc rax
    mov [rbp + idx], rax
    jmp .check64Loop
.check64Done:

    push arr32
    push arr32Len
    push 4
    push cmpInt32
    call sort

    mov qword [rbp + idx], 0
.check32Loop:
    mov rax, [rbp + idx]
    cmp rax, arr32Len
    jge .check32Done
    cmp rax, 0
    je .check32Next             ; nothing to compare the first element against

    mov rbx, [rbp + idx]
    movsx rcx, dword [arr32 + rbx*4]
    dec rbx
    movsx rdx, dword [arr32 + rbx*4]
    cmp rdx, rcx                ; previous element must be <= current element
    setle al
    movzx rax, al
    push errNotSorted32
    push rax
    call assert

.check32Next:
    mov rax, [rbp + idx]
    inc rax
    mov [rbp + idx], rax
    jmp .check32Loop
.check32Done:

    mov rax, 0
    end
    ret 24
