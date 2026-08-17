; test_fs.asm -- fsMkdir/fsStat/fsRmdir test
;
; The directory is created inside the repo (relative to the working
; directory `make test` runs from, i.e. the repo root) rather than /tmp --
; this avoids mkdir failing with EEXIST because of a leftover directory
; of the same name from another user in /tmp (under the sticky bit, a
; non-owner can't even remove it, so the only fix is to use a different
; location). fsRmdir cleans this directory up before the test ends.

%include "asmrt.inc"

section .data
    dir db "tests/asmrt_test_dir", 0

errMkdir dq (errMkdir_end - errMkdir_start)
    errMkdir_start: db "fsMkdir failed"
    errMkdir_end: db 0

errStat dq (errStat_end - errStat_start)
    errStat_start: db "fsStat on created dir failed"
    errStat_end: db 0

errRmdir dq (errRmdir_end - errRmdir_start)
    errRmdir_start: db "fsRmdir failed"
    errRmdir_end: db 0

errStat2 dq (errStat2_end - errStat2_start)
    errStat2_start: db "fsStat should fail after rmdir"
    errStat2_end: db 0

section .bss
    statBuf resb 144

section .text
    global entry

entry:
    begin

    push dir
    push 0x1ED          ; mode 0755
    call fsMkdir

    cmp rax, 0
    setge al
    movzx rax, al
    push errMkdir
    push rax
    call assert

    push dir
    push statBuf
    call fsStat

    cmp rax, 0
    sete al
    movzx rax, al
    push errStat
    push rax
    call assert

    push dir
    call fsRmdir

    cmp rax, 0
    sete al
    movzx rax, al
    push errRmdir
    push rax
    call assert

    push dir
    push statBuf
    call fsStat         ; the directory is gone now, this should fail (return negative)

    cmp rax, 0
    setl al
    movzx rax, al
    push errStat2
    push rax
    call assert

    mov rax, 0
    end
    ret 24
