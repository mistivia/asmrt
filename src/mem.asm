; mem.asm -- custom-ABI wrappers around libc's malloc/free/realloc, plus
; a couple of memcpy/memmove-alikes implemented natively.
;
; memAlloc/memFree/memReloc are real System V ABI calls (not raw
; syscalls), so each one needs hexalign right before the call to keep
; the call site 16-byte aligned. Arguments still go through registers
; per the real ABI (rdi/rsi/...), same as any other real-ABI call made
; from inside this runtime.
;
; memCopy/memMove/memFill don't call into libc at all -- copying/filling
; bytes doesn't need an allocator, so they're written directly in the
; custom ABI, the same way str.asm implements strLen/strEq itself
; instead of wrapping libc's. copyForward (the shared
; 8-bytes-at-a-time-then-a-tail loop used by both memCopy and memMove's
; non-overlapping case) is internal, not `global` -- same pattern as
; sort.asm's swapElems helper.

%include "asmrt.inc"

section .text
    global memAlloc
    global memFree
    global memReloc
    global memCopy
    global memMove
    global memFill
    extern malloc
    extern free
    extern realloc

; memAlloc(size) -> ptr (rax), NULL on failure
proc memAlloc
    args size

    hexalign
    mov rdi, [%$size]
    call malloc

    end
    ret 8

; memFree(ptr) -> rax is always 0; free() itself returns nothing
proc memFree
    args ptr

    hexalign
    mov rdi, [%$ptr]
    call free

    mov rax, 0
    end
    ret 8

; memReloc(ptr, size) -> new ptr (rax), NULL on failure (ptr is left untouched by libc on failure)
proc memReloc
    args ptr, size

    hexalign
    mov rdi, [%$ptr]
    mov rsi, [%$size]
    call realloc

    end
    ret 16

; memCopy(dest, src, n) -> dest (rax)
; Copies n bytes from src to dest. Assumes the two regions don't
; overlap -- for possibly-overlapping regions use memMove instead.
; caller pushes in order: push dest; push src; push n
proc memCopy
    args dest, src, n

    push [%$dest]
    push [%$src]
    push [%$n]
    call copyForward

    end
    ret 24

; memMove(dest, src, n) -> dest (rax)
; Like memCopy, but safe when the two regions overlap: copies forward
; (low to high address) when dest <= src, backward (high to low) when
; dest > src, so a byte is never overwritten before it's read.
; caller pushes in order: push dest; push src; push n
proc memMove
    args dest, src, n

    mov rax, [%$dest]
    mov rbx, [%$src]
    cmp rax, rbx
    jbe .forward

    ; backward: walk down from the high end, 8 bytes at a time, so every
    ; write lands behind the next not-yet-read source byte. What's left
    ; once fewer than 8 bytes remain is the low-address tail, which no
    ; earlier chunk in this loop has touched -- copy that forward, order
    ; doesn't matter for those last few bytes. No call happens inside
    ; either loop, so rax/rbx/rcx/r8/al are pure scratch throughout.
    mov rbx, [%$dest]
    mov rcx, [%$src]
    mov r8, [%$n]
.backQwordLoop:
    cmp r8, 8
    jl .backByteLoop
    sub r8, 8
    mov rax, [rcx + r8]
    mov [rbx + r8], rax
    jmp .backQwordLoop
.backByteLoop:
    cmp r8, 0
    jle .backDone
    dec r8
    mov al, [rcx + r8]
    mov [rbx + r8], al
    jmp .backByteLoop
.backDone:
    mov rax, [%$dest]
    jmp .exit

.forward:
    push [%$dest]
    push [%$src]
    push [%$n]
    call copyForward     ; already returns dest in rax

.exit:
    end
    ret 24

; memFill(dest, val, n) -> dest (rax)
; Fills n bytes at dest with the low byte of val -- same low-byte-only
; contract as libc's memset. Broadcasts that byte across all 8 bytes of
; a qword once up front (the classic shift-or trick), then stores 8
; bytes at a time while at least 8 remain, falling back to a
; byte-at-a-time tail for the rest (n isn't guaranteed to be a multiple
; of 8) -- same chunking as copyForward/swapElems. No call happens in
; either loop, so rax/rbx/r8/r10 are pure scratch throughout.
; caller pushes in order: push dest; push val; push n
proc memFill
    args dest, val, n

    mov rax, [%$val]
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

    mov rbx, [%$dest]
    xor r8, r8
.qwordLoop:
    mov rax, [%$n]
    sub rax, r8
    cmp rax, 8
    jl .byteLoop
    mov [rbx + r8], r10
    add r8, 8
    jmp .qwordLoop
.byteLoop:
    cmp r8, [%$n]
    jge .done
    mov [rbx + r8], r10b
    inc r8
    jmp .byteLoop
.done:
    mov rax, [%$dest]

    end
    ret 24

; copyForward(dest, src, n) -> dest (rax) -- internal helper shared by
; memCopy and memMove's non-overlapping case. Moves 8 bytes at a time
; while at least 8 remain, then a byte-at-a-time tail for whatever's
; left (n isn't guaranteed to be a multiple of 8). No call happens
; inside either loop, so rax/rbx/rcx/r8 are pure scratch throughout.
; caller pushes in order: push dest; push src; push n
proc copyForward
    args dest, src, n

    mov rbx, [%$dest]
    mov rcx, [%$src]
    xor r8, r8
.qwordLoop:
    mov rax, [%$n]
    sub rax, r8
    cmp rax, 8
    jl .byteLoop
    mov rax, [rcx + r8]
    mov [rbx + r8], rax
    add r8, 8
    jmp .qwordLoop
.byteLoop:
    cmp r8, [%$n]
    jge .done
    mov al, [rcx + r8]
    mov [rbx + r8], al
    inc r8
    jmp .byteLoop
.done:
    mov rax, [%$dest]

    end
    ret 24
