; utils.asm -- assorted generic utilities, custom ABI
;
;   sort(base, nmemb, size, cmpFn) -- generic in-place sort over opaque
;     byte blobs, ordered by a custom-ABI comparator (qsort-style,
;     recursive quicksort with Lomuto partition).
;   fnv64(data, dataSize, input) -- FNV-1a 64-bit hash, mirrors
;     ckit/cbase/cbase.h's fnv64.
;
; partition()/swapElems() (sort internals) are not `global` and not
; declared in asmrt.inc -- they're private to this file.
;
; fnv64's FNV_OFFSET_BASIS = 0xcbf29ce484222325, FNV_PRIME = 0x100000001b3.

%include "asmrt.inc"

section .text
    global sort
    global fnv64

; ============================ sort ============================

; sort(base, nmemb, size, cmpFn)
;   base  -- pointer to the first element of the array
;   nmemb -- number of elements
;   size  -- size of one element, in bytes (elements are opaque byte
;            blobs to sort -- it never inspects them itself, only calls
;            cmpFn and swaps raw bytes)
;   cmpFn -- pointer to a custom-ABI comparator cmpFn(a, b), where a/b
;            are pointers to two elements; returns (in rax) a value <0
;            if *a should sort before *b, 0 if equal, >0 if *a should
;            sort after *b -- same contract as libc's qsort comparator,
;            just called through this runtime's own ABI (pushed args,
;            ret N) instead of the real System V one.
;            (Named cmpFn, not cmp, so args's %$cmpFn alias doesn't
;            collide with the x86 `cmp` instruction mnemonic.)
;
; Implementation is recursive quicksort (Lomuto partition, last element
; as pivot). sort() *is* the recursive step -- there's no separate
; "sort a [lo,hi] index range" helper: a sub-array is just another
; (base, nmemb) pair, so recursing means calling sort() again with base
; moved forward by (p+1)*size elements and nmemb shrunk to match, not
; tracking a pair of indices into the original array.
;
; partition()/swapElems() are internal (not `global`) -- nothing outside
; this file calls them directly, so they're not declared in asmrt.inc
; either. Every one of them still follows the same custom ABI as any
; exported function, recursive calls included: the pivot index p, which
; must survive the call to partition(), lives in a `local` slot, never a
; register.
;
; Naive last-element-as-pivot quicksort degrades to O(n) recursion depth
; (and O(n^2) time) on already-sorted or reverse-sorted input -- a known
; limitation of the simplest textbook version, left as-is here in
; keeping with this runtime's teaching/experiment scope over robustness.

; caller pushes in order: push base; push nmemb; push size; push cmpFn
proc sort
    args base, nmemb, size, cmpFn
    local p          ; partition point, returned by partition(); must
                     ; survive the call, so it lives on the stack
    endlocal

    mov rax, [%$nmemb]
    cmp rax, 2
    jl .done                ; 0 or 1 elements -- already sorted, nothing to do

    push [%$base]
    push [%$nmemb]
    push [%$size]
    push [%$cmpFn]
    call partition
    mov [%$p], rax

    ; left part: the p elements before the pivot -- same base, shrunk nmemb
    push [%$base]
    push [%$p]
    push [%$size]
    push [%$cmpFn]
    call sort

    ; right part: everything after the pivot -- base moves past it, nmemb shrinks to match
    mov rax, [%$p]
    inc rax
    imul rax, [%$size]
    add rax, [%$base]
    push rax                  ; new base = base + (p+1)*size

    mov rax, [%$nmemb]
    mov rbx, [%$p]
    inc rbx
    sub rax, rbx
    push rax                  ; new nmemb = nmemb - (p+1)

    push [%$size]
    push [%$cmpFn]
    call sort

.done:
    end
    ret 32

; partition(base, nmemb, size, cmpFn) -> pivot index (rax), 0-based within [0, nmemb)
; Lomuto partition: elem[nmemb-1] is the pivot; on return, everything in
; [0, p) compares < pivot and everything in (p, nmemb) compares >= pivot,
; with the pivot itself now sitting at index p. Same (base, nmemb, size,
; cmpFn) shape as sort() itself -- it always partitions the *whole*
; range it's handed, which is exactly why sort() can recurse by just
; handing it a narrower (base, nmemb) slice instead of extra indices.
; caller pushes in order: push base; push nmemb; push size; push cmpFn
proc partition
    args base, nmemb, size, cmpFn
    local i          ; boundary: [0, i] are known < pivot so far
    local j          ; scan cursor over [0, nmemb-1)
    endlocal

    mov qword [%$i], -1
    mov qword [%$j], 0
.loop:
    mov rax, [%$j]
    mov rbx, [%$nmemb]
    dec rbx
    cmp rax, rbx
    jge .loopDone              ; loop while j < nmemb-1 (pivot itself is excluded)

    ; addr of elem[j] -> 1st cmpFn arg (a), pushed first
    mov rax, [%$j]
    imul rax, [%$size]
    add rax, [%$base]
    push rax

    ; addr of elem[nmemb-1] (the pivot) -> 2nd cmpFn arg (b), pushed last
    mov rax, [%$nmemb]
    dec rax
    imul rax, [%$size]
    add rax, [%$base]
    push rax

    call [%$cmpFn]        ; custom-ABI call through the function pointer; cleans its own 16 bytes

    cmp rax, 0
    jge .noSwap                  ; elem[j] >= pivot, leave it where it is

    mov rax, [%$i]
    inc rax
    mov [%$i], rax                  ; i++

    ; swap elem[i], elem[j]
    mov rax, [%$i]
    imul rax, [%$size]
    add rax, [%$base]
    push rax                       ; addrA = elem[i]

    mov rax, [%$j]
    imul rax, [%$size]
    add rax, [%$base]
    push rax                       ; addrB = elem[j]

    push [%$size]
    call swapElems

.noSwap:
    mov rax, [%$j]
    inc rax
    mov [%$j], rax
    jmp .loop
.loopDone:

    ; final swap: put the pivot (elem[nmemb-1]) right after the < region, at elem[i+1]
    mov rax, [%$i]
    inc rax
    mov [%$i], rax                  ; i = i + 1, the pivot's final resting index

    mov rax, [%$i]
    imul rax, [%$size]
    add rax, [%$base]
    push rax                       ; addrA = elem[i]

    mov rax, [%$nmemb]
    dec rax
    imul rax, [%$size]
    add rax, [%$base]
    push rax                       ; addrB = elem[nmemb-1]

    push [%$size]
    call swapElems

    mov rax, [%$i]                  ; return the pivot's final index

    end
    ret 32

; swapElems(addrA, addrB, size) -- swap `size` bytes between addrA/addrB.
; Moves 8 bytes at a time while at least 8 remain, then falls back to a
; byte-at-a-time tail for whatever's left (size isn't guaranteed to be a
; multiple of 8 -- e.g. a 4-byte int32 element). No call happens inside
; either loop, so rax/rbx/rcx/rdx/r8/r9b are pure scratch for that
; stretch, same as strEq's loop in str.asm.
; caller pushes in order: push addrA; push addrB; push size
proc swapElems
    args addrA, addrB, size

    mov rbx, [%$addrA]
    mov rcx, [%$addrB]
    xor r8, r8
.qwordLoop:
    mov rax, [%$size]
    sub rax, r8
    cmp rax, 8
    jl .byteLoop           ; fewer than 8 bytes left -- finish those one at a time
    mov rax, [rbx + r8]
    mov rdx, [rcx + r8]
    mov [rbx + r8], rdx
    mov [rcx + r8], rax
    add r8, 8
    jmp .qwordLoop
.byteLoop:
    cmp r8, [%$size]
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

; ============================ fnv64 ===========================

; fnv64(data, dataSize, input) -> FNV-1a hash of dataSize bytes at data,
; seeded with input.  Mirrors cbase/cbase.h's fnv64.
; caller pushes in order: push data; push dataSize; push input
proc fnv64
    args data, dataSize, input
    local hash
    local i
    endlocal

    mov rax, [%$input]
    mov [%$hash], rax
    mov qword [%$i], 0
.loop:
    mov rax, [%$i]
    cmp rax, [%$dataSize]
    jae .done

    ; hash *= 0x100000001b3  (too big for an imm32, so via rbx)
    mov rax, [%$hash]
    mov rbx, 0x100000001b3
    imul rax, rbx
    mov [%$hash], rax

    ; hash ^= data[i]
    mov rax, [%$hash]
    mov rbx, [%$data]
    mov rcx, [%$i]
    movzx rdx, byte [rbx + rcx]
    xor rax, rdx
    mov [%$hash], rax

    inc qword [%$i]
    jmp .loop
.done:
    mov rax, [%$hash]

    end
    ret 24
