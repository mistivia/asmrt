#include "asmrt.inc"

.section .text

.globl memCopy
// memCopy(dest, src, n)
// copy forward
memCopy:
    #define Rdest a0
    #define Rsrc  a1
    #define Rn    a2

    #define Rt0   t0
    #define Rt1   t1
    #define Rt2   a3
    #define Rt3   a4
    mov r0, Rdest
    begin
10: // align dest to 8 bytes
    test Rdest, 7
    jz 20f
    cmp Rn, 1
    jb 20f
        mov t0b, byte ptr [Rsrc]
        mov byte ptr [Rdest], t0b
        dec Rn
        inc Rsrc
        inc Rdest
        jmp 10b
20: // while n >= 32
    cmp Rn, 32
    jb 30f
        mov Rt0, qword ptr [Rsrc]
        mov Rt1, qword ptr [Rsrc + 8]
        mov Rt2, qword ptr [Rsrc + 16]
        mov Rt3, qword ptr [Rsrc + 24]
        mov qword ptr [Rdest], Rt0
        mov qword ptr [Rdest + 8], Rt1
        mov qword ptr [Rdest + 16], Rt2
        mov qword ptr [Rdest + 24], Rt3
        add Rsrc, 32
        add Rdest, 32
        sub Rn, 32
        jmp 20b
30: // while n >= 8
    cmp Rn, 8
    jb 40f
        mov Rt0, qword ptr [Rsrc]
        mov qword ptr [Rdest], Rt0
        add Rsrc, 8
        add Rdest, 8
        sub Rn, 8
        jmp 30b
40: // while n >= 1
    cmp Rn, 1
    jb 50f
        mov t0b, byte ptr [Rsrc]
        mov byte ptr [Rdest], t0b
        dec Rn
        inc Rsrc
        inc Rdest
        jmp 40b
50:
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
20: // align the end of dest to 8 bytes
    test Rdest, 7
    jz 30f
    cmp Rn, 1
    jb 30f
        dec Rsrc
        dec Rdest
        mov t0b, byte ptr [Rsrc]
        mov byte ptr [Rdest], t0b
        dec Rn
        jmp 20b
30: // while n >= 8
    cmp Rn, 8
    jb 40f
        #define Rt t0
        sub Rsrc, 8
        sub Rdest, 8
        mov Rt, qword ptr [Rsrc]
        mov qword ptr [Rdest], Rt
        sub Rn, 8
        jmp 30b
40: // while n >= 1
    cmp Rn, 1
    jb 50f
        #define Rtb t0b
        dec Rsrc
        dec Rdest
        mov Rtb, byte ptr [Rsrc]
        mov byte ptr [Rdest], Rtb
        dec Rn
        jmp 40b
50: mov r0, t1
    return

.globl memFill
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
10: // align dest to 8 bytes
    test Rdest, 7
    jz 20f
    cmp Rn, 1
    jb 20f
        mov byte ptr [Rdest], Rvalb
        inc Rdest
        dec Rn
        jmp 10b
20: // while n >= 8
    cmp Rn, 8
    jb 30f
        mov qword ptr [Rdest], Rval
        add Rdest, 8
        sub Rn, 8
        jmp 20b
30: // end
    // while n >= 1
    cmp Rn, 1
    jb 40f
        mov byte ptr [Rdest], Rvalb
        inc Rdest
        dec Rn
        jmp 30b
40: // end
    mov r0, t1
    return

.globl memSwap
// memSwap(pa, pb, n)
memSwap:
    #define Rpa a0
    #define Rpb a1
    #define Rn  a2
    begin
    // if pa == pb
    cmp Rpa, Rpb
    jne 0f
        mov r0, 0
        return
0:  // if |pa - pb| < n
    mov t0, Rpa
    sub t0, Rpb
    mov t1, t0
    neg t1
    cmp t0, 0
    cmovl t0, t1
    cmp t0, Rn
    jae 10f
        mov r0, -1
        return
10: // endif
    // align pa to 8 bytes
    test Rpa, 7
    jz 20f
    cmp Rn, 1
    jb 20f
        mov t0b, byte ptr [Rpa]
        mov t1b, byte ptr [Rpb]
        mov byte ptr [Rpa], t1b
        mov byte ptr [Rpb], t0b
        dec Rn
        inc Rpa
        inc Rpb
        jmp 10b
20:
    // while n >= 8
    cmp Rn, 8
    jl 30f
        mov t0, qword ptr [Rpa]
        mov t1, qword ptr [Rpb]
        mov qword ptr [Rpa], t1
        mov qword ptr [Rpb], t0
        sub Rn, 8
        add Rpa, 8
        add Rpb, 8
        jmp 20b
30: // end
    // while n >= 1
    cmp Rn, 1
    jl 40f
        mov t0b, byte ptr [Rpa]
        mov t1b, byte ptr [Rpb]
        mov byte ptr [Rpa], t1b
        mov byte ptr [Rpb], t0b
        dec Rn
        inc Rpa
        inc Rpb
        jmp 30b
40: // end
    mov r0, 0
    return
