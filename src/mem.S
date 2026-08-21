#include "asmrt.inc"

.section .text

.globl memCopy
/* copyForward(dest, src, n) */
memCopy:
    #define Rdest a0
    #define Rsrc  a1
    #define Rn    a2
    mov t1, Rdest
    begin
.LqwordLoop:
    /* while n >= 8 */
    cmp Rn, 8
    jb .LbyteLoop
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
    jb .Ldone
        #define Rtb t0b
        mov Rtb, byte ptr [Rsrc]
        mov byte ptr [Rdest], Rtb
        dec Rn
        inc Rsrc
        inc Rdest
        jmp .LbyteLoop
.Ldone:
    mov r0, t1
    return

.globl memMove
/* memMove(dest, src, n) */
memMove:
    #define Rdest a0
    #define Rsrc  a1
    #define Rn    a2
    mov t1, Rdest
    begin
    /* if dest <= src */
    cmp Rdest, Rsrc
    jbe .LcallForward
    /* else: copy backward */
    add Rdest, Rn
    add Rsrc, Rn
.LqwordLoop2:
    /* while n >= 8 */
    cmp Rn, 8
    jb .LbyteLoop2
        #define Rt t0
        sub Rsrc, 8
        sub Rdest, 8
        mov Rt, qword ptr [Rsrc]
        mov qword ptr [Rdest], Rt
        sub Rn, 8
        jmp .LqwordLoop2
.LbyteLoop2:
    /* while n >= 1 */
    cmp Rn, 1
    jb .Ldone2
        #define Rtb t0b
        dec Rsrc
        dec Rdest
        mov Rtb, byte ptr [Rsrc]
        mov byte ptr [Rdest], Rtb
        dec Rn
        jmp .LbyteLoop2
.Ldone2:
    mov r0, t1
    return
.LcallForward:
    call memCopy
    return
