#include "asmrt.inc"

.section .text

.globl assertTrue

assertTrue:
    #define Rflag a0
    #define Rmsg  a1
    begin
    // if flag == 0
    cmp Rflag, 0
    jne 10f
        mov a0, 2 // stderr
        call ioWriteString
        // exit(-1)
        mov a0, -1
        mov r0, 93
        syscall
10: // else
        mov r0, 0
        return
    // endif
