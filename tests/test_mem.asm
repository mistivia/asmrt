; test_mem.asm -- memAlloc/memFree/memReloc round-trip test, plus
; memCopy/memMove (a plain non-overlapping copy, and both overlap
; directions of a move).

%include "asmrt.inc"

section .data
    pattern1 dq 0x1122334455667788
    pattern2 dq 0x99AABBCCDDEEFF00

    copySrc  db 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16
    copyLen  equ 16

    ; shiftLeftBuf: memMove(buf, buf+3, 10) -- dest < src, forward copy path
    shiftLeftBuf      db 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16
    shiftLeftExpected db 4,5,6,7,8,9,10,11,12,13
    shiftLen          equ 10

    ; shiftRightBuf: memMove(buf+3, buf, 10) -- dest > src, backward copy path
    shiftRightBuf      db 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16
    shiftRightExpected db 1,2,3,4,5,6,7,8,9,10

    fillExpected db 0xAA,0xAA,0xAA,0xAA,0xAA,0xAA,0xAA,0xAA,0xAA,0xAA,0xAA
    fillLen      equ 11   ; deliberately not a multiple of 8, to exercise the tail loop too

errAllocNull dq (errAllocNull_end - errAllocNull_start)
    errAllocNull_start: db "memAlloc returned null"
    errAllocNull_end: db 0

errReadback dq (errReadback_end - errReadback_start)
    errReadback_start: db "value read back from allocated memory does not match what was written"
    errReadback_end: db 0

errRelocNull dq (errRelocNull_end - errRelocNull_start)
    errRelocNull_start: db "memReloc returned null"
    errRelocNull_end: db 0

errRelocPreserve dq (errRelocPreserve_end - errRelocPreserve_start)
    errRelocPreserve_start: db "memReloc did not preserve the original content"
    errRelocPreserve_end: db 0

errRelocReadback dq (errRelocReadback_end - errRelocReadback_start)
    errRelocReadback_start: db "value read back from the grown region does not match what was written"
    errRelocReadback_end: db 0

errCopy dq (errCopy_end - errCopy_start)
    errCopy_start: db "memCopy did not reproduce the source bytes"
    errCopy_end: db 0

errMoveLeft dq (errMoveLeft_end - errMoveLeft_start)
    errMoveLeft_start: db "memMove (dest < src, forward) produced the wrong bytes"
    errMoveLeft_end: db 0

errMoveRight dq (errMoveRight_end - errMoveRight_start)
    errMoveRight_start: db "memMove (dest > src, backward) produced the wrong bytes"
    errMoveRight_end: db 0

errFill dq (errFill_end - errFill_start)
    errFill_start: db "memFill did not fill every byte with the given value"
    errFill_end: db 0

section .bss
    copyDst resb 16
    fillDst resb 11

section .text
    global entry

; checkRange(a, b, n) -> 1 if a[0..n) == b[0..n) byte for byte, else 0
checkRange:
    argnum 3
    %assign a arg(1)
    %assign b arg(2)
    %assign n arg(3)

    begin
    ; local variables
    resetOffset
    ; k 8 bytes
    decOffset 8
    %assign k offset
    ; endlocal
    sub rsp, (-offset)

    mov qword [rbp + k], 0
.loop:
    mov rax, [rbp + k]
    cmp rax, [rbp + n]
    jge .eq

    mov rbx, [rbp + a]
    mov rcx, [rbp + k]
    mov dl, [rbx + rcx]
    mov rbx, [rbp + b]
    mov rcx, [rbp + k]
    cmp dl, [rbx + rcx]
    jne .neq

    mov rax, [rbp + k]
    inc rax
    mov [rbp + k], rax
    jmp .loop
.eq:
    mov rax, 1
    jmp .done
.neq:
    mov rax, 0
.done:
    end
    ret 24

entry:
    begin
    ; local variables
    resetOffset
    ; ptr crosses multiple calls, must live on the stack
    decOffset 8
    %assign ptr offset
    ; endlocal
    sub rsp, (-offset)

    push 16
    call memAlloc
    mov [rbp + ptr], rax

    cmp qword [rbp + ptr], 0
    setne al
    movzx rax, al
    push errAllocNull
    push rax
    call assert

    mov rax, [rbp + ptr]
    mov rbx, [pattern1]
    mov [rax], rbx

    mov rax, [rbp + ptr]
    mov rbx, [rax]
    cmp rbx, [pattern1]
    sete al
    movzx rax, al
    push errReadback
    push rax
    call assert

    push [rbp + ptr]
    push 32
    call memReloc
    mov [rbp + ptr], rax

    cmp qword [rbp + ptr], 0
    setne al
    movzx rax, al
    push errRelocNull
    push rax
    call assert

    mov rax, [rbp + ptr]
    mov rbx, [rax]
    cmp rbx, [pattern1]
    sete al
    movzx rax, al
    push errRelocPreserve
    push rax
    call assert

    mov rax, [rbp + ptr]
    mov rbx, [pattern2]
    mov [rax+8], rbx

    mov rax, [rbp + ptr]
    mov rbx, [rax+8]
    cmp rbx, [pattern2]
    sete al
    movzx rax, al
    push errRelocReadback
    push rax
    call assert

    push [rbp + ptr]
    call memFree

    ; memCopy(dest, src, n) -- params pushed in declaration order: dest, src, n
    push copyDst
    push copySrc
    push copyLen
    call memCopy

    push copyDst
    push copySrc
    push copyLen
    call checkRange
    push errCopy
    push rax
    call assert

    ; memMove(dest, src, n) -- dest < src here, exercises the forward-copy path
    push shiftLeftBuf
    mov rax, shiftLeftBuf
    add rax, 3
    push rax
    push shiftLen
    call memMove

    push shiftLeftBuf
    push shiftLeftExpected
    push shiftLen
    call checkRange
    push errMoveLeft
    push rax
    call assert

    ; memMove(dest, src, n) -- dest > src here, exercises the backward-copy path
    mov rax, shiftRightBuf
    add rax, 3
    push rax
    push shiftRightBuf
    push shiftLen
    call memMove

    mov rax, shiftRightBuf
    add rax, 3
    push rax
    push shiftRightExpected
    push shiftLen
    call checkRange
    push errMoveRight
    push rax
    call assert

    ; memFill(dest, val, n) -- val's low byte (0xAA) should end up in every one of the n bytes
    push fillDst
    push 0xAA
    push fillLen
    call memFill

    push fillDst
    push fillExpected
    push fillLen
    call checkRange
    push errFill
    push rax
    call assert

    mov rax, 0
    end
    ret 24
