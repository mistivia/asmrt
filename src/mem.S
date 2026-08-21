#include "asmrt.inc"

.section .text

/* copyForward(dest, src, n) */
copyForward:
    #define Rdest a0
    #define Rsrc  a1
    #define Rn    a2
    begin
.LqwordLoop:
    /* while n >= 8 */
    cmp Rn, 8
    jl .LbyteLoop
        #define Rt t0
        mov Rt, qword ptr [Rsrc]
        mov qword ptr [Rdest], Rt
        add Rsrc, 8
        add Rdest, 8
        sub Rn, 8
        jmp .LqwordLoop
.LbyteLoop:
    /* while n >= 1 */
    cmp Rn, 1
    jl .Ldone
        #define Rtb t0b
        mov Rtb, byte ptr [Rsrc]
        mov byte ptr [Rdest], Rtb
        dec Rn
        inc Rsrc
        inc Rdest
        jmp .LbyteLoop
.Ldone:
    mov r0, Rdest
    return

