; test_io.asm -- ioOpen/ioWrite/ioRead/ioClose/ioWriteNum/ioWriteChar
; round-trip test

%include "asmrt.inc"

section .data
    msg         db "hello asmrt io test", 10
    msgLen      equ $ - msg
    path        db "/tmp/asmrt_test_io.txt", 0
    errOpen     db "ioOpen failed", 0
    errWrite    db "ioWrite short write", 0
    errRead     db "ioRead short read", 0
    errContent  db "ioRead content mismatch", 0
    errSeek     db "ioSeek(SEEK_SET, 0) did not return 0", 0

    numPath     db "/tmp/asmrt_test_io_num.txt", 0
    numExpect   db "42,-7,0,A", 10
    numExpectLen equ $ - numExpect
    errNumContent db "ioWriteNum/ioWriteChar content mismatch", 0

section .bss
    readBuf resb 64

section .text
    global entry

entry:
    begin
    ; local variables
    resetOffset
    ; fd needs to survive multiple calls, so it must live on the stack, not just in a register
    decOffset 8
    %assign fd offset
    ; endlocal
    sub rsp, (-offset)

    push path
    push 0x242          ; flags O_RDWR|O_CREAT|O_TRUNC (need to seek back on the same fd and read later)
    push 0x1A4          ; mode 0644
    call ioOpen
    mov [rbp + fd], rax

    cmp qword [rbp + fd], 0
    setge al
    movzx rax, al
    push errOpen
    push rax
    call assert

    push [rbp + fd]
    push msg
    push msgLen
    call ioWrite

    cmp rax, msgLen
    sete al
    movzx rax, al
    push errWrite
    push rax
    call assert

    ; leave fd open, use ioSeek to rewind to the start and read again, to verify seek works
    push [rbp + fd]
    push 0              ; offset
    push 0              ; whence SEEK_SET
    call ioSeek

    cmp rax, 0
    sete al
    movzx rax, al
    push errSeek
    push rax
    call assert

    push [rbp + fd]
    push readBuf
    push msgLen
    call ioRead

    cmp rax, msgLen
    sete al
    movzx rax, al
    push errRead
    push rax
    call assert

    push [rbp + fd]
    call ioClose

    push path
    push 0              ; flags O_RDONLY
    push 0              ; mode (ignored for O_RDONLY)
    call ioOpen
    mov [rbp + fd], rax

    push [rbp + fd]
    push readBuf
    push msgLen
    call ioRead

    cmp rax, msgLen
    sete al
    movzx rax, al
    push errRead
    push rax
    call assert

    push [rbp + fd]
    call ioClose

    xor rcx, rcx
.cmpLoop:
    cmp rcx, msgLen
    je .cmpOk
    mov al, [msg + rcx]
    cmp al, [readBuf + rcx]
    jne .cmpFail
    inc rcx
    jmp .cmpLoop
.cmpFail:
    push errContent
    push 0
    call assert
.cmpOk:

    push path
    call fsUnlink

    ; ioWriteNum/ioWriteChar round trip
    push numPath
    push 0x242          ; flags O_RDWR|O_CREAT|O_TRUNC
    push 0x1A4          ; mode 0644
    call ioOpen
    mov [rbp + fd], rax

    cmp qword [rbp + fd], 0
    setge al
    movzx rax, al
    push errOpen
    push rax
    call assert

    push [rbp + fd]
    push 42
    call ioWriteNum

    push [rbp + fd]
    push ','
    call ioWriteChar

    push [rbp + fd]
    push -7
    call ioWriteNum

    push [rbp + fd]
    push ','
    call ioWriteChar

    push [rbp + fd]
    push 0
    call ioWriteNum

    push [rbp + fd]
    push ','
    call ioWriteChar

    push [rbp + fd]
    push 'A'
    call ioWriteChar

    push [rbp + fd]
    push 10
    call ioWriteChar

    push [rbp + fd]
    push 0              ; offset
    push 0              ; whence SEEK_SET
    call ioSeek

    push [rbp + fd]
    push readBuf
    push numExpectLen
    call ioRead

    cmp rax, numExpectLen
    sete al
    movzx rax, al
    push errRead
    push rax
    call assert

    push [rbp + fd]
    call ioClose

    xor rcx, rcx
.numCmpLoop:
    cmp rcx, numExpectLen
    je .numCmpOk
    mov al, [numExpect + rcx]
    cmp al, [readBuf + rcx]
    jne .numCmpFail
    inc rcx
    jmp .numCmpLoop
.numCmpFail:
    push errNumContent
    push 0
    call assert
.numCmpOk:

    push numPath
    call fsUnlink

    mov rax, 0
    end
    ret 24
