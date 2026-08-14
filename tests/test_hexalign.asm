; test_hexalign.asm -- hexalign should dynamically pad rsp to 16-byte alignment
;
; Verified from two starting states: already 16-byte aligned, and forced
; off-by-8 with one bare push -- covering both branches of hexalign
; (pad 0 / pad 8). hexalign has no paired "undo" macro -- the space it
; pads gets reclaimed together with everything else by end's
; mov rsp,rbp, so there's nothing here that checks rsp was restored.

%include "asmrt.inc"

section .data
    errAlignedCase1 db "case1: rsp should be 16-byte aligned after hexalign", 0
    errAlignedCase2 db "case2: rsp should be 16-byte aligned after hexalign", 0

section .text
    global entry

proc entry

    ; ---- case 1: the call site is already 16-byte aligned ----
    mov rax, rsp
    and rax, 15
    cmp rax, 0
    je .case1Start
    push 0                 ; if begin left us unaligned, pad once to reach a consistent starting point
.case1Start:

    hexalign
    mov rax, rsp
    and rax, 15
    cmp rax, 0
    sete cl
    movzx rax, cl
    push errAlignedCase1
    push rax
    call assert

    ; ---- case 2: force an "off by 8 bytes" call site (simulating an odd number of pushed arguments) ----
    push 0

    hexalign
    mov rax, rsp
    and rax, 15
    cmp rax, 0
    sete cl
    movzx rax, cl
    push errAlignedCase2
    push rax
    call assert

    mov rax, 0
    end
    ret 24
