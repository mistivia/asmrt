; mem.asm -- custom-ABI wrappers around libc's malloc/free/realloc, plus
; a couple of memcpy/memmove-alikes implemented natively.
;
; memAlloc/memFree/memReloc are real System V ABI calls (not raw
; syscalls), so each one needs hexalign right before the call to keep
; the call site 16-byte aligned. Arguments still go through registers
; per the real ABI (rdi/rsi/...), same as any other real-ABI call made
; from inside this runtime.
;
; memCopy/memMove/memFill/memSwap don't call into libc at all --
; copying/filling/swapping bytes doesn't need an allocator, so they're
; written directly in the custom ABI, the same way string.asm implements
; stringLen/stringEq itself instead of wrapping libc's. copyForward (the
; shared 8-bytes-at-a-time-then-a-tail loop used by both memCopy and
; memMove's non-overlapping case) is internal, not `global`, while
; memSwap is the public byte-swap helper shared with utils.asm's sort.

%include "asmrt.inc"

section .text
    global memFill
    global memSwap

; memFill(dest, val, n) -> dest
; Fills n bytes at dest with the low byte of val -- same low-byte-only
; contract as libc's memset. Broadcasts that byte across all 8 bytes of
; a qword once up front (the classic shift-or trick), then stores 8
; bytes at a time while at least 8 remain, falling back to a
; byte-at-a-time tail for the rest (n isn't guaranteed to be a multiple
; of 8) -- same chunking as copyForward/memSwap. No call happens in
; either loop, so rax/rbx/r8/r10 are pure scratch throughout.
; caller pushes in order: push dest; push val; push n
memFill:
    argnum 3
    %assign dest arg(1)
    %assign val  arg(2)
    %assign n    arg(3)

    begin
    mov rax, [rbp + val]
    and rax, 0xFF
    mov r10, rax
    shl r10, 8
    or  r10, rax
    mov rax, r10
    shl r10, 16
    or  r10, rax
    mov rax, r10
    shl r10, 32
    or  r10, rax          ; r10 = val's low byte broadcast across all 8 bytes

    mov rbx, [rbp + dest]
    xor r8, r8
.qwordLoop:
    mov rax, [rbp + n]
    sub rax, r8
    cmp rax, 8
    jl .byteLoop
    mov [rbx + r8], r10
    add r8, 8
    jmp .qwordLoop
.byteLoop:
    cmp r8, [rbp + n]
    jge .done
    mov [rbx + r8], r10b
    inc r8
    jmp .byteLoop
.done:
    mov rax, [rbp + dest]
    end
    ret 24

; memSwap(addrA, addrB, size) -- swap `size` bytes between addrA/addrB.
; Moves 8 bytes at a time while at least 8 remain, then falls back to a
; byte-at-a-time tail for whatever's left (size isn't guaranteed to be a
; multiple of 8 -- e.g. a 4-byte int32 element). No call happens inside
; either loop, so rax/rbx/rcx/rdx/r8/r9b are pure scratch for that
; stretch, same as stringEq's loop in string.asm.
; caller pushes in order: push addrA; push addrB; push size
memSwap:
    argnum 3
    %assign addrA arg(1)
    %assign addrB arg(2)
    %assign size  arg(3)

    begin
    mov rbx, [rbp + addrA]
    mov rcx, [rbp + addrB]
    xor r8, r8
.qwordLoop:
    mov rax, [rbp + size]
    sub rax, r8
    cmp rax, 8
    jl .byteLoop
    mov rax, [rbx + r8]
    mov rdx, [rcx + r8]
    mov [rbx + r8], rdx
    mov [rcx + r8], rax
    add r8, 8
    jmp .qwordLoop
.byteLoop:
    cmp r8, [rbp + size]
    jge .done
    mov al,  [rbx + r8]
    mov r9b, [rcx + r8]
    mov [rbx + r8], r9b
    mov [rcx + r8], al
    inc r8
    jmp .byteLoop
.done:
    end
    ret 24
