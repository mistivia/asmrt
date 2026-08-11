; test_fs.asm —— fs_mkdir/fs_stat/fs_rmdir 测试

%include "asmrt.inc"

section .data
    dir        db "/tmp/asmrt_test_dir", 0
    err_mkdir  db "fs_mkdir failed", 0
    err_stat   db "fs_stat on created dir failed", 0
    err_rmdir  db "fs_rmdir failed", 0
    err_stat2  db "fs_stat should fail after rmdir", 0

section .bss
    statbuf resb 144

section .text
    global amain

amain:
    beginfn rbx

    push dir
    push 0x1ED          ; mode 0755
    call fs_mkdir

    cmp rax, 0
    setge al
    movzx rax, al
    push err_mkdir
    push rax
    call assert

    push dir
    push statbuf
    call fs_stat

    cmp rax, 0
    sete al
    movzx rax, al
    push err_stat
    push rax
    call assert

    push dir
    call fs_rmdir

    cmp rax, 0
    sete al
    movzx rax, al
    push err_rmdir
    push rax
    call assert

    push dir
    push statbuf
    call fs_stat        ; 目录已删，这次应该失败（返回负数）

    cmp rax, 0
    setl al
    movzx rax, al
    push err_stat2
    push rax
    call assert

    mov rax, 0
    endfn rbx
    ret 24
