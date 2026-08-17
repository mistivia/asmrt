; utils.asm -- assorted generic utilities, custom ABI
;
;   sort(base, nmemb, size, cmpFn) -- generic in-place sort over opaque
;     byte blobs, ordered by a custom-ABI comparator (qsort-style,
;     recursive quicksort with Lomuto partition).
;   fnv64(data, dataSize, input) -- FNV-1a 64-bit hash, mirrors
;     ckit/cbase/cbase.h's fnv64.
;
; partition() (sort internals) is not `global` and not
; declared in asmrt.inc -- it's private to this file.
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
;            (Named cmpFn, not cmp, so the cmpFn %assign doesn't
;            collide with the x86 `cmp` instruction mnemonic.)
;
; Implementation is recursive quicksort (Lomuto partition, last element
; as pivot). sort() *is* the recursive step -- there's no separate
; "sort a [lo,hi] index range" helper: a sub-array is just another
; (base, nmemb) pair, so recursing means calling sort() again with base
; moved forward by (p+1)*size elements and nmemb shrunk to match, not
; tracking a pair of indices into the original array.
;
; partition() is internal (not `global`) -- nothing outside this file
; calls it directly, so it's not declared in asmrt.inc either. It still
; follows the same custom ABI as any exported function. The pivot index
; p, which must survive the call to partition(), lives in a stack local,
; never a register.
;
; Naive last-element-as-pivot quicksort degrades to O(n) recursion depth
; (and O(n^2) time) on already-sorted or reverse-sorted input -- a known
; limitation of the simplest textbook version, left as-is here in
; keeping with this runtime's teaching/experiment scope over robustness.

; caller pushes in order: push base; push nmemb; push size; push cmpFn
sort:
    ;; args: base, nmemb, size, cmpFn
    %assign N 4
    %assign base (16 + (N-1) * 8)
    %assign nmemb (16 + (N-2) * 8)
    %assign size (16 + (N-3) * 8)
    %assign cmpFn (16 + (N-4) * 8)
    begin
    ;; local variables
    resetOffset
    ;; partition point, returned by partition(); must
    %assign offset (offset - 8)
    %assign p offset
                     ; survive the call, so it lives on the stack
    ;; endlocal
    sub rsp, (-offset)

    mov rax, [rbp + nmemb]
    cmp rax, 2
    jl .done                ; 0 or 1 elements -- already sorted, nothing to do

    push [rbp + base]
    push [rbp + nmemb]
    push [rbp + size]
    push [rbp + cmpFn]
    call partition
    mov [rbp + p], rax

    ; left part: the p elements before the pivot -- same base, shrunk nmemb
    push [rbp + base]
    push [rbp + p]
    push [rbp + size]
    push [rbp + cmpFn]
    call sort

    ; right part: everything after the pivot -- base moves past it, nmemb shrinks to match
    mov rax, [rbp + p]
    inc rax
    imul rax, [rbp + size]
    add rax, [rbp + base]
    push rax                  ; new base = base + (p+1)*size

    mov rax, [rbp + nmemb]
    mov rbx, [rbp + p]
    inc rbx
    sub rax, rbx
    push rax                  ; new nmemb = nmemb - (p+1)

    push [rbp + size]
    push [rbp + cmpFn]
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
partition:
    ;; args: base, nmemb, size, cmpFn
    %assign N 4
    %assign base (16 + (N-1) * 8)
    %assign nmemb (16 + (N-2) * 8)
    %assign size (16 + (N-3) * 8)
    %assign cmpFn (16 + (N-4) * 8)
    begin
    ;; local variables
    resetOffset
    ;; boundary: [0, i] are known < pivot so far
    %assign offset (offset - 8)
    %assign i offset
    ;; scan cursor over [0, nmemb-1)
    %assign offset (offset - 8)
    %assign j offset
    ;; endlocal
    sub rsp, (-offset)

    mov qword [rbp + i], -1
    mov qword [rbp + j], 0
.loop:
    mov rax, [rbp + j]
    mov rbx, [rbp + nmemb]
    dec rbx
    cmp rax, rbx
    jge .loopDone              ; loop while j < nmemb-1 (pivot itself is excluded)

    ; addr of elem[j] -> 1st cmpFn arg (a), pushed first
    mov rax, [rbp + j]
    imul rax, [rbp + size]
    add rax, [rbp + base]
    push rax

    ; addr of elem[nmemb-1] (the pivot) -> 2nd cmpFn arg (b), pushed last
    mov rax, [rbp + nmemb]
    dec rax
    imul rax, [rbp + size]
    add rax, [rbp + base]
    push rax

    call [rbp + cmpFn]        ; custom-ABI call through the function pointer; cleans its own 16 bytes

    cmp rax, 0
    jge .noSwap                  ; elem[j] >= pivot, leave it where it is

    mov rax, [rbp + i]
    inc rax
    mov [rbp + i], rax                  ; i++

    ; swap elem[i], elem[j]
    mov rax, [rbp + i]
    imul rax, [rbp + size]
    add rax, [rbp + base]
    push rax                       ; addrA = elem[i]

    mov rax, [rbp + j]
    imul rax, [rbp + size]
    add rax, [rbp + base]
    push rax                       ; addrB = elem[j]

    push [rbp + size]
    call memSwap

.noSwap:
    mov rax, [rbp + j]
    inc rax
    mov [rbp + j], rax
    jmp .loop
.loopDone:

    ; final swap: put the pivot (elem[nmemb-1]) right after the < region, at elem[i+1]
    mov rax, [rbp + i]
    inc rax
    mov [rbp + i], rax                  ; i = i + 1, the pivot's final resting index

    mov rax, [rbp + i]
    imul rax, [rbp + size]
    add rax, [rbp + base]
    push rax                       ; addrA = elem[i]

    mov rax, [rbp + nmemb]
    dec rax
    imul rax, [rbp + size]
    add rax, [rbp + base]
    push rax                       ; addrB = elem[nmemb-1]

    push [rbp + size]
    call memSwap

    mov rax, [rbp + i]                  ; return the pivot's final index

    end
    ret 32


; ============================ fnv64 ===========================

; fnv64(data, dataSize, input) -> FNV-1a hash of dataSize bytes at data,
; seeded with input.  Mirrors cbase/cbase.h's fnv64.
; caller pushes in order: push data; push dataSize; push input
fnv64:
    ;; args: data, dataSize, input
    %assign N 3
    %assign data (16 + (N-1) * 8)
    %assign dataSize (16 + (N-2) * 8)
    %assign input (16 + (N-3) * 8)
    begin
    ;; local variables
    resetOffset
    ;; hash 8 bytes
    %assign offset (offset - 8)
    %assign hash offset
    ;; i 8 bytes
    %assign offset (offset - 8)
    %assign i offset
    ;; endlocal
    sub rsp, (-offset)

    mov rax, [rbp + input]
    mov [rbp + hash], rax
    mov qword [rbp + i], 0
.loop:
    mov rax, [rbp + i]
    cmp rax, [rbp + dataSize]
    jae .done

    ; hash *= 0x100000001b3  (too big for an imm32, so via rbx)
    mov rax, [rbp + hash]
    mov rbx, 0x100000001b3
    imul rax, rbx
    mov [rbp + hash], rax

    ; hash ^= data[i]
    mov rax, [rbp + hash]
    mov rbx, [rbp + data]
    mov rcx, [rbp + i]
    movzx rdx, byte [rbx + rcx]
    xor rax, rdx
    mov [rbp + hash], rax

    inc qword [rbp + i]
    jmp .loop
.done:
    mov rax, [rbp + hash]

    end
    ret 24
