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

// memFill(dest, val, n)
memFill:
    #define Rdest a0
    #define Rval  a1
    #define Rn    a2
    #define Rvalb a1b
    mov t1, Rdest
    begin
    // expand val to 8 bytes
    and Rval, 0xff
    mov t0, Rval
    shl t0, 8
    or t0, Rval
    mov Rval, t0
    shl t0, 16
    or t0, Rval
    mov Rval, t0
    shl t0, 32
    or t0, Rval
    mov Rval, t0
10: // while n >= 8
    cmp Rn, 8
    jb 20f
        mov qword ptr [Rdest], Rval
        add Rdest, 8
        sub Rn, 8
        jmp 10b
20: // end
    // while n >= 1
    cmp Rn, 1
    jb 30f
        mov byte ptr [Rdest], Rvalb
        inc Rdest
        dec Rn
        jmp 20b
30: // end
    mov r0, t1
    return
