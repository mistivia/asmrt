; test_fs.asm —— fs_mkdir/fs_stat/fs_rmdir 测试
;
; 目录建在仓库内（相对于 `make test` 的运行目录，即仓库根目录），
; 而不是 /tmp —— 避免 /tmp 里其它用户残留的同名目录导致 mkdir 因
; EEXIST 失败（sticky bit 下，非属主连删都删不掉，只能换地方）。
; fs_rmdir 会在测试结束前自己清理掉这个目录。

%include "asmrt.inc"

section .data
    dir        db "tests/asmrt_test_dir", 0
    err_mkdir  db "fs_mkdir failed", 0
    err_stat   db "fs_stat on created dir failed", 0
    err_rmdir  db "fs_rmdir failed", 0
    err_stat2  db "fs_stat should fail after rmdir", 0

section .bss
    statbuf resb 144

section .text
    global amain

amain:
    begin

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
    end
    ret 24
