#include "asmrt.inc"

.section .text

.globl memCopy
// memCopy(dest, src, n)
// copy forward
memCopy:
    // args
    #define Rdest a0
    #define Rsrc  a1
    #define Rn    a2
    // vars
    #define Rt0   t0
    #define Rt1   t1
    #define Rt2   a3
    #define Rt3   a4
    mov r0, Rdest
    begin
1:  // while dest % 8 != 0 and n >= 1
    test Rdest, 7
    jz 2f
    cmp Rn, 1
    jb 2f
        mov t0b, byte ptr [Rsrc]
        mov byte ptr [Rdest], t0b
        dec Rn
        inc Rsrc
        inc Rdest
        jmp 1b
    // endloop
2:  // while n >= 32
    cmp Rn, 32
    jb 3f
        mov Rt0, qword ptr [Rsrc]
        mov Rt1, qword ptr [Rsrc + 8]
        mov Rt2, qword ptr [Rsrc + 16]
        mov Rt3, qword ptr [Rsrc + 24]
        mov qword ptr [Rdest],      Rt0
        mov qword ptr [Rdest + 8],  Rt1
        mov qword ptr [Rdest + 16], Rt2
        mov qword ptr [Rdest + 24], Rt3
        add Rsrc, 32
        add Rdest, 32
        sub Rn, 32
        jmp 2b
    // endloop
3:  // while n >= 8
    cmp Rn, 8
    jb 4f
        mov Rt0, qword ptr [Rsrc]
        mov qword ptr [Rdest], Rt0
        add Rsrc, 8
        add Rdest, 8
        sub Rn, 8
        jmp 3b
4:  // endloop
    // while n >= 1
    cmp Rn, 1
    jb 5f
        mov t0b, byte ptr [Rsrc]
        mov byte ptr [Rdest], t0b
        dec Rn
        inc Rsrc
        inc Rdest
        jmp 4b
5:  // endloop
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
    ja 1f
        call memCopy
        return
1:  // endif
    // copy backward
    add Rdest, Rn
    add Rsrc, Rn
2:  // while dest not aligned to 8 and n >= 1
    test Rdest, 7
    jz 3f
    cmp Rn, 1
    jb 3f
        dec Rsrc
        dec Rdest
        mov t0b, byte ptr [Rsrc]
        mov byte ptr [Rdest], t0b
        dec Rn
        jmp 2b
    // endloop
3:  // while n >= 8
    cmp Rn, 8
    jb 4f
        #define Rt t0
        sub Rsrc, 8
        sub Rdest, 8
        mov Rt, qword ptr [Rsrc]
        mov qword ptr [Rdest], Rt
        sub Rn, 8
        jmp 3b
    // endloop
4:  // while n >= 1
    cmp Rn, 1
    jb 5f
        #define Rtb t0b
        dec Rsrc
        dec Rdest
        mov Rtb, byte ptr [Rsrc]
        mov byte ptr [Rdest], Rtb
        dec Rn
        jmp 4b
    // endloop
5:  mov r0, t1
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
1:  // while dest not aligned to 8 bytes and n >= 1
    test Rdest, 7
    jz 2f
    cmp Rn, 1
    jb 2f
        mov byte ptr [Rdest], Rvalb
        inc Rdest
        dec Rn
        jmp 1b
    // endloop
2:  // while n >= 8
    cmp Rn, 8
    jb 3f
        mov qword ptr [Rdest], Rval
        add Rdest, 8
        sub Rn, 8
        jmp 2b
3:  // endloop
    // while n >= 1
    cmp Rn, 1
    jb 4f
        mov byte ptr [Rdest], Rvalb
        inc Rdest
        dec Rn
        jmp 3b
4:  // endloop
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
    jne 5f
        mov r0, 0
        return
    // endif
5:  // if |pa - pb| < n
    mov t0, Rpa
    sub t0, Rpb
    mov t1, t0
    neg t1
    cmp t0, 0
    cmovl t0, t1
    cmp t0, Rn
    jae 1f
        mov r0, -1
        return
1:  // endif
    // while pa not aligned to 8 bytes and n >= 1
    test Rpa, 7
    jz 2f
    cmp Rn, 1
    jb 2f
        mov t0b, byte ptr [Rpa]
        mov t1b, byte ptr [Rpb]
        mov byte ptr [Rpa], t1b
        mov byte ptr [Rpb], t0b
        dec Rn
        inc Rpa
        inc Rpb
        jmp 1b
2:  // endloop
    // while n >= 8
    cmp Rn, 8
    jl 3f
        mov t0, qword ptr [Rpa]
        mov t1, qword ptr [Rpb]
        mov qword ptr [Rpa], t1
        mov qword ptr [Rpb], t0
        sub Rn, 8
        add Rpa, 8
        add Rpb, 8
        jmp 2b
3:  // endloop
    // while n >= 1
    cmp Rn, 1
    jl 4f
        mov t0b, byte ptr [Rpa]
        mov t1b, byte ptr [Rpb]
        mov byte ptr [Rpa], t1b
        mov byte ptr [Rpb], t0b
        dec Rn
        inc Rpa
        inc Rpb
        jmp 3b
4:  // end
    mov r0, 0
    return
