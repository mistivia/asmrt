/**
 * assert.asm -- assertion
 * assert(flag, string)
 *   flag false (0): write the length-prefixed string (a pointer to
 *     [8-byte len][data][NUL], see string.asm) to stderr, then terminate
 *     the process with exit code -1;
 *   flag true: do nothing, return normally.
 */

#include "asmrt.inc"

.section .text

.global assertTrue

assertTrue:
    #define Rflag a0
    #define Rmsg  a1
    begin
    cmp Rflag, 0
    jne .Lok

    mov a0, 2 /* stderr */
    call ioWriteString

    /* exit(-1) */
    mov a0, -1
    mov r0, 93
    syscall    
.Lok:
    mov r0, 0
    return
