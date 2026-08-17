; test_preasm.asm -- preasm/postasm should save and restore every register exactly
;
; Set every general-purpose register to a distinct known value, then
; after preasm make one custom-ABI call (stringLen, which by convention
; clobbers every register except rax), then postasm, and verify every
; register was restored to exactly what it was before the call.

%include "asmrt.inc"

section .data
probe dq (probe_end - probe_start)
    probe_start: db "x"
    probe_end: db 0

    expRax dq 0x1111111111111111
    expRbx dq 0x2222222222222222
    expRcx dq 0x3333333333333333
    expRdx dq 0x4444444444444444
    expRsi dq 0x5555555555555555
    expRdi dq 0x6666666666666666
    expR8  dq 0x7777777777777777
    expR9  dq 0x8888888888888888
    expR10 dq 0x9999999999999999
    expR11 dq 0xAAAAAAAAAAAAAAAA
    expR12 dq 0xBBBBBBBBBBBBBBBB
    expR13 dq 0xCCCCCCCCCCCCCCCC
    expR14 dq 0xDDDDDDDDDDDDDDDD
    expR15 dq 0xEEEEEEEEEEEEEEEE

errRax dq (errRax_end - errRax_start)
    errRax_start: db "preasm/postasm failed to protect rax"
    errRax_end: db 0

errRbx dq (errRbx_end - errRbx_start)
    errRbx_start: db "preasm/postasm failed to protect rbx"
    errRbx_end: db 0

errRcx dq (errRcx_end - errRcx_start)
    errRcx_start: db "preasm/postasm failed to protect rcx"
    errRcx_end: db 0

errRdx dq (errRdx_end - errRdx_start)
    errRdx_start: db "preasm/postasm failed to protect rdx"
    errRdx_end: db 0

errRsi dq (errRsi_end - errRsi_start)
    errRsi_start: db "preasm/postasm failed to protect rsi"
    errRsi_end: db 0

errRdi dq (errRdi_end - errRdi_start)
    errRdi_start: db "preasm/postasm failed to protect rdi"
    errRdi_end: db 0

errR8 dq (errR8_end - errR8_start)
    errR8_start: db "preasm/postasm failed to protect r8"
    errR8_end: db 0

errR9 dq (errR9_end - errR9_start)
    errR9_start: db "preasm/postasm failed to protect r9"
    errR9_end: db 0

errR10 dq (errR10_end - errR10_start)
    errR10_start: db "preasm/postasm failed to protect r10"
    errR10_end: db 0

errR11 dq (errR11_end - errR11_start)
    errR11_start: db "preasm/postasm failed to protect r11"
    errR11_end: db 0

errR12 dq (errR12_end - errR12_start)
    errR12_start: db "preasm/postasm failed to protect r12"
    errR12_end: db 0

errR13 dq (errR13_end - errR13_start)
    errR13_start: db "preasm/postasm failed to protect r13"
    errR13_end: db 0

errR14 dq (errR14_end - errR14_start)
    errR14_start: db "preasm/postasm failed to protect r14"
    errR14_end: db 0

errR15 dq (errR15_end - errR15_start)
    errR15_start: db "preasm/postasm failed to protect r15"
    errR15_end: db 0

section .bss
    actRax resq 1
    actRbx resq 1
    actRcx resq 1
    actRdx resq 1
    actRsi resq 1
    actRdi resq 1
    actR8  resq 1
    actR9  resq 1
    actR10 resq 1
    actR11 resq 1
    actR12 resq 1
    actR13 resq 1
    actR14 resq 1
    actR15 resq 1

section .text
    global entry

entry:
    begin

    mov rax, [expRax]
    mov rbx, [expRbx]
    mov rcx, [expRcx]
    mov rdx, [expRdx]
    mov rsi, [expRsi]
    mov rdi, [expRdi]
    mov r8,  [expR8]
    mov r9,  [expR9]
    mov r10, [expR10]
    mov r11, [expR11]
    mov r12, [expR12]
    mov r13, [expR13]
    mov r14, [expR14]
    mov r15, [expR15]

    preasm
    push probe
    call stringLen       ; custom-ABI call, rewrites every register to something else
    postasm

    ; move every register to memory right after postasm, before the
    ; upcoming assert calls (themselves register-clobbering calls) wipe
    ; out the values we still need to check
    mov [actRax], rax
    mov [actRbx], rbx
    mov [actRcx], rcx
    mov [actRdx], rdx
    mov [actRsi], rsi
    mov [actRdi], rdi
    mov [actR8],  r8
    mov [actR9],  r9
    mov [actR10], r10
    mov [actR11], r11
    mov [actR12], r12
    mov [actR13], r13
    mov [actR14], r14
    mov [actR15], r15

    mov rax, [actRax]
    cmp rax, [expRax]
    sete al
    movzx rax, al
    push errRax
    push rax
    call assert

    mov rax, [actRbx]
    cmp rax, [expRbx]
    sete al
    movzx rax, al
    push errRbx
    push rax
    call assert

    mov rax, [actRcx]
    cmp rax, [expRcx]
    sete al
    movzx rax, al
    push errRcx
    push rax
    call assert

    mov rax, [actRdx]
    cmp rax, [expRdx]
    sete al
    movzx rax, al
    push errRdx
    push rax
    call assert

    mov rax, [actRsi]
    cmp rax, [expRsi]
    sete al
    movzx rax, al
    push errRsi
    push rax
    call assert

    mov rax, [actRdi]
    cmp rax, [expRdi]
    sete al
    movzx rax, al
    push errRdi
    push rax
    call assert

    mov rax, [actR8]
    cmp rax, [expR8]
    sete al
    movzx rax, al
    push errR8
    push rax
    call assert

    mov rax, [actR9]
    cmp rax, [expR9]
    sete al
    movzx rax, al
    push errR9
    push rax
    call assert

    mov rax, [actR10]
    cmp rax, [expR10]
    sete al
    movzx rax, al
    push errR10
    push rax
    call assert

    mov rax, [actR11]
    cmp rax, [expR11]
    sete al
    movzx rax, al
    push errR11
    push rax
    call assert

    mov rax, [actR12]
    cmp rax, [expR12]
    sete al
    movzx rax, al
    push errR12
    push rax
    call assert

    mov rax, [actR13]
    cmp rax, [expR13]
    sete al
    movzx rax, al
    push errR13
    push rax
    call assert

    mov rax, [actR14]
    cmp rax, [expR14]
    sete al
    movzx rax, al
    push errR14
    push rax
    call assert

    mov rax, [actR15]
    cmp rax, [expR15]
    sete al
    movzx rax, al
    push errR15
    push rax
    call assert

    mov rax, 0
    end
    ret 24
