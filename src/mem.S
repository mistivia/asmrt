#include "asmrt.inc"

.section .text

.globl memCopy
// memCopy(dest, src, n)
// copy forward
memCopy:
    #define Rdest a0
    #define Rsrc  a1
    #define Rn    a2
    mov t1, Rdest
    begin
10: // while n >= 8
    cmp Rn, 8
    jb 20f
        #define Rt t0
        mov Rt, qword ptr [Rsrc]
        mov qword ptr [Rdest], Rt
        add Rsrc, 8
        add Rdest, 8
        sub Rn, 8
        jmp 10b
20: // while n >= 1
    cmp Rn, 1
    jb 30f
        #define Rtb t0b
        mov Rtb, byte ptr [Rsrc]
        mov byte ptr [Rdest], Rtb
        dec Rn
        inc Rsrc
        inc Rdest
        jmp 20b
30: mov r0, t1
    return

.globl memMove
// memMove(dest, src, n)
memMove:
    #define Rdest a0
    #define Rsrc  a1
    #define Rn    a2
    mov t1, Rdest
    begin
    // if dest <= src
    cmp Rdest, Rsrc
    ja 10f
        call memCopy
        return
10: // endif
    // copy backward
    add Rdest, Rn
    add Rsrc, Rn
20: // while n >= 8
    cmp Rn, 8
    jb 30f
        #define Rt t0
        sub Rsrc, 8
        sub Rdest, 8
        mov Rt, qword ptr [Rsrc]
        mov qword ptr [Rdest], Rt
        sub Rn, 8
        jmp 20b
30: // while n >= 1
    cmp Rn, 1
    jb 40f
        #define Rtb t0b
        dec Rsrc
        dec Rdest
        mov Rtb, byte ptr [Rsrc]
        mov byte ptr [Rdest], Rtb
        dec Rn
        jmp 30b
40: mov r0, t1
    return
