; test_io.asm —— io_open/io_write/io_read/io_close 往返测试

%include "asmrt.inc"

section .data
    msg         db "hello asmrt io test", 10
    msg_len     equ $ - msg
    path        db "/tmp/asmrt_test_io.txt", 0
    err_open    db "io_open failed", 0
    err_write   db "io_write short write", 0
    err_read    db "io_read short read", 0
    err_content db "io_read content mismatch", 0

section .bss
    readbuf resb 64

section .text
    global amain

amain:
    beginfn rbx

    push path
    push 0x241          ; flags O_WRONLY|O_CREAT|O_TRUNC
    push 0x1A4          ; mode 0644
    call io_open
    mov rbx, rax

    cmp rbx, 0
    setge al
    movzx rax, al
    push err_open
    push rax
    call assert

    push rbx
    push msg
    push msg_len
    call io_write

    cmp rax, msg_len
    sete al
    movzx rax, al
    push err_write
    push rax
    call assert

    push rbx
    call io_close

    push path
    push 0              ; flags O_RDONLY
    push 0              ; mode (O_RDONLY 时忽略)
    call io_open
    mov rbx, rax

    push rbx
    push readbuf
    push msg_len
    call io_read

    cmp rax, msg_len
    sete al
    movzx rax, al
    push err_read
    push rax
    call assert

    push rbx
    call io_close

    xor rcx, rcx
.cmp_loop:
    cmp rcx, msg_len
    je .cmp_ok
    mov al, [msg + rcx]
    cmp al, [readbuf + rcx]
    jne .cmp_fail
    inc rcx
    jmp .cmp_loop
.cmp_fail:
    push err_content
    push 0
    call assert
.cmp_ok:

    push path
    call fs_unlink

    mov rax, 0
    endfn rbx
    ret 24
