; vec.asm -- data structures module, mirroring ckit's cbase/cbase.h
;
; Only the generic vec is implemented so far.  It follows the same
; shape as cbase's struct vec: a growable array whose element type is
; described by a ValueMeta bundle (size/align plus optional
; drop/cmp/eq/hash/copy/move callbacks).  All trait callbacks speak
; the asmrt custom ABI, exactly like sort()'s comparator, so a vec of
; plain int64s can be sorted with the same cmpInt64 used by sort().
;
; Memory management goes through the runtime's memAlloc/memFree/
; memReloc, byte shuffling through memCopy/memMove -- all custom-ABI
; wrappers around libc, so no bare syscalls and no hexalign needed
; here (the wrappers handle their own real-ABI alignment).
;
; Naming follows cbase's vec_* C functions (vecInit/vecWithCapacity/
; vecPush/...), except every asmrt symbol is camelCase (vecInit,
; vecWithCapacity, vecPush, ...).  The exported vecMeta ValueMeta
; describes struct Vec itself, for nested containers (e.g. a vec of
; vecs).

%include "asmrt.inc"

section .data
    global vecMeta
vecMeta:
    dq Vec_size                     ; .size
    dq 8                            ; .align
    dq vecDrop                      ; .drop
    dq vecCmp                       ; .cmp
    dq vecEq                        ; .eq
    dq vecHash                      ; .hash
    dq vecCopy                      ; .copy
    dq vecMove                      ; .move

section .text
    global vecInit
    global vecWithCapacity
    global vecReserve
    global vecPush
    global vecPop
    global vecGet
    global vecSet
    global vecFirst
    global vecLast
    global vecLen
    global vecIsEmpty
    global vecClear
    global vecTruncate
    global vecDrop
    global vecSwapElement
    global vecSwap
    global vecEq
    global vecInsert
    global vecRemove
    global vecAsPtr
    global vecCopy
    global vecMove
    global vecSort
    global vecCmp
    global vecHash
    extern memAlloc
    extern memFree
    extern memReloc
    extern memCopy
    extern memMove
    extern sort

; ---- internal helpers ----

; elemAddr(self, index) -> ptr to element at self->data + index*meta->size
; No call inside, so rax/rbx/rcx are pure scratch for this stretch.
; caller pushes in order: push self; push index
proc elemAddr
    args self, index

    mov rax, [%$self]
    mov rax, [rax + Vec.data]
    mov rbx, [%$self]
    mov rbx, [rbx + Vec.meta]
    mov rbx, [rbx + ValueMeta.size]
    mov rcx, [%$index]
    imul rbx, rcx
    add rax, rbx

    end
    ret 16

; ---- construction / destruction ----

; vecInit(self, meta) -> 0.  Zero the vec and attach the ValueMeta.
proc vecInit
    args self, meta

    mov rax, [%$self]
    mov qword [rax + Vec.data], 0
    mov qword [rax + Vec.len], 0
    mov qword [rax + Vec.capacity], 0
    mov rbx, [%$meta]
    mov [rax + Vec.meta], rbx

    xor rax, rax

    end
    ret 16

; vecWithCapacity(self, meta, capacity) -> 0.  Like vecInit, but
; pre-allocates room for `capacity` elements (data stays NULL when
; capacity is 0, matching cbase).
proc vecWithCapacity
    args self, meta, capacity

    mov rax, [%$self]
    mov qword [rax + Vec.data], 0
    mov qword [rax + Vec.len], 0
    mov qword [rax + Vec.capacity], 0
    mov rbx, [%$meta]
    mov [rax + Vec.meta], rbx

    mov rax, [%$self]
    mov rbx, [%$capacity]
    mov [rax + Vec.capacity], rbx

    cmp rbx, 0
    je .noAlloc

    ; self->data = memAlloc(capacity * meta->size)
    mov rax, [%$meta]
    mov rbx, [rax + ValueMeta.size]
    mov rcx, [%$capacity]
    imul rbx, rcx
    push rbx
    call memAlloc
    mov rbx, [%$self]
    mov [rbx + Vec.data], rax
    jmp .done
.noAlloc:
.done:
    xor rax, rax

    end
    ret 24

; vecReserve(self, additional) -- ensure capacity for len+additional
; elements, doubling from 4 as cbase does.
proc vecReserve
    args self, additional
    local needed
    local newCap
    endlocal

    mov rax, [%$self]
    mov rax, [rax + Vec.len]
    add rax, [%$additional]
    mov [%$needed], rax

    mov rax, [%$self]
    mov rbx, [rax + Vec.capacity]
    cmp [%$needed], rbx
    jbe .done

    mov rax, [%$self]
    mov rax, [rax + Vec.capacity]
    test rax, rax
    jnz .haveCap
    mov rax, 4
.haveCap:
    mov [%$newCap], rax
.growLoop:
    mov rax, [%$newCap]
    cmp rax, [%$needed]
    jae .grown
    shl qword [%$newCap], 1
    jmp .growLoop
.grown:
    ; self->data = memReloc(self->data, newCap * meta->size)
    mov rax, [%$self]
    mov rax, [rax + Vec.data]
    push rax
    mov rax, [%$self]
    mov rax, [rax + Vec.meta]
    mov rax, [rax + ValueMeta.size]
    mov rbx, [%$newCap]
    imul rax, rbx
    push rax
    call memReloc
    mov rbx, [%$self]
    mov [rbx + Vec.data], rax
    mov rax, [%$newCap]
    mov [rbx + Vec.capacity], rax
.done:

    end
    ret 16

; vecDrop(self) -- drop every element (via meta->drop), free the buffer,
; and reset the vec in place.
proc vecDrop
    args self
    local i
    endlocal

    mov qword [%$i], 0
.loop:
    mov rax, [%$self]
    mov rbx, [rax + Vec.len]
    cmp [%$i], rbx
    jae .freeData
    push [%$self]
    push [%$i]
    call elemAddr
    mov rbx, [%$self]
    mov rbx, [rbx + Vec.meta]
    push rax
    call [rbx + ValueMeta.drop]
    inc qword [%$i]
    jmp .loop
.freeData:
    mov rax, [%$self]
    mov rax, [rax + Vec.data]
    push rax
    call memFree

    mov rax, [%$self]
    mov qword [rax + Vec.data], 0
    mov qword [rax + Vec.len], 0
    mov qword [rax + Vec.capacity], 0

    end
    ret 8

; vecClear(self) -- drop every element and set len to 0, keep buffer.
proc vecClear
    args self
    local i
    endlocal

    mov qword [%$i], 0
.loop:
    mov rax, [%$self]
    mov rbx, [rax + Vec.len]
    cmp [%$i], rbx
    jae .done
    push [%$self]
    push [%$i]
    call elemAddr
    mov rbx, [%$self]
    mov rbx, [rbx + Vec.meta]
    push rax
    call [rbx + ValueMeta.drop]
    inc qword [%$i]
    jmp .loop
.done:
    mov rax, [%$self]
    mov qword [rax + Vec.len], 0

    end
    ret 8

; vecTruncate(self, len) -- drop elements from len onward, shrink len.
proc vecTruncate
    args self, len
    local i
    endlocal

    mov rax, [%$self]
    mov rbx, [rax + Vec.len]
    cmp [%$len], rbx
    jae .setLen

    mov rax, [%$len]
    mov [%$i], rax
.loop:
    mov rax, [%$self]
    mov rbx, [rax + Vec.len]
    cmp [%$i], rbx
    jae .setLen
    push [%$self]
    push [%$i]
    call elemAddr
    mov rbx, [%$self]
    mov rbx, [rbx + Vec.meta]
    push rax
    call [rbx + ValueMeta.drop]
    inc qword [%$i]
    jmp .loop
.setLen:
    mov rax, [%$self]
    mov rbx, [%$len]
    mov [rax + Vec.len], rbx

    end
    ret 16

; ---- element access ----

; vecGet(self, index) -> ptr to element, or NULL if out of bounds
proc vecGet
    args self, index

    mov rax, [%$self]
    mov rbx, [rax + Vec.len]
    cmp [%$index], rbx
    jae .oob

    push [%$self]
    push [%$index]
    call elemAddr
    jmp .done
.oob:
    xor rax, rax
.done:

    end
    ret 16

; vecFirst(self) -> ptr to first element, or NULL if empty
proc vecFirst
    args self

    mov rax, [%$self]
    cmp qword [rax + Vec.len], 0
    je .empty
    mov rax, [rax + Vec.data]
    jmp .done
.empty:
    xor rax, rax
.done:

    end
    ret 8

; vecLast(self) -> ptr to last element, or NULL if empty
proc vecLast
    args self

    mov rax, [%$self]
    cmp qword [rax + Vec.len], 0
    je .empty
    mov rbx, [rax + Vec.len]
    dec rbx
    push rax
    push rbx
    call elemAddr
    jmp .done
.empty:
    xor rax, rax
.done:

    end
    ret 8

; vecLen(self) -> len
proc vecLen
    args self

    mov rax, [%$self]
    mov rax, [rax + Vec.len]

    end
    ret 8

; vecIsEmpty(self) -> 1 if len == 0, else 0
proc vecIsEmpty
    args self

    mov rax, [%$self]
    cmp qword [rax + Vec.len], 0
    sete al
    movzx rax, al

    end
    ret 8

; vecAsPtr(self) -> raw data pointer (may be NULL)
proc vecAsPtr
    args self

    mov rax, [%$self]
    mov rax, [rax + Vec.data]

    end
    ret 8

; vecSet(self, index, elem, isMove) -- replace element at index: drop
; the old one, copy the new one in (or move when isMove != 0).  No-op
; when index is out of bounds.
proc vecSet
    args self, index, elem, isMove
    local dst
    endlocal

    mov rax, [%$self]
    mov rbx, [rax + Vec.len]
    cmp [%$index], rbx
    jae .done

    push [%$self]
    push [%$index]
    call elemAddr
    mov [%$dst], rax

    mov rax, [%$self]
    mov rax, [rax + Vec.meta]
    push [%$dst]
    call [rax + ValueMeta.drop]

    mov rax, [%$self]
    mov rax, [rax + Vec.meta]
    cmp qword [%$isMove], 0
    jne .moveElem
    push [%$dst]
    push [%$elem]
    call [rax + ValueMeta.copy]
    jmp .done
.moveElem:
    push [%$dst]
    push [%$elem]
    call [rax + ValueMeta.move]
.done:

    end
    ret 32

; ---- push / pop ----

; vecPush(self, elem, isMove) -- append a copy of elem, or move it in
; when isMove != 0.
proc vecPush
    args self, elem, isMove
    local dst
    endlocal

    push [%$self]
    push 1
    call vecReserve

    push [%$self]
    mov rax, [%$self]
    mov rbx, [rax + Vec.len]
    push rbx
    call elemAddr
    mov [%$dst], rax

    mov rax, [%$self]
    mov rax, [rax + Vec.meta]
    cmp qword [%$isMove], 0
    jne .moveElem
    push [%$dst]
    push [%$elem]
    call [rax + ValueMeta.copy]
    jmp .finish
.moveElem:
    push [%$dst]
    push [%$elem]
    call [rax + ValueMeta.move]
.finish:
    mov rax, [%$self]
    inc qword [rax + Vec.len]

    end
    ret 24

; vecPop(self, out) -> 1 if an element was popped, else 0.  When out is
; non-NULL the popped element is copied into *out.  The element slot is
; *not* dropped (ownership moves to the caller), matching cbase.
proc vecPop
    args self, out
    local src
    endlocal

    mov rax, [%$self]
    cmp qword [rax + Vec.len], 0
    je .false

    mov rax, [%$self]
    dec qword [rax + Vec.len]

    cmp qword [%$out], 0
    je .noOut

    push [%$self]
    mov rax, [%$self]
    mov rbx, [rax + Vec.len]
    push rbx
    call elemAddr
    mov [%$src], rax

    push [%$out]
    push [%$src]
    mov rax, [%$self]
    mov rax, [rax + Vec.meta]
    mov rbx, [rax + ValueMeta.size]
    push rbx
    call memCopy
.noOut:
    mov rax, 1
    jmp .done
.false:
    xor rax, rax
.done:

    end
    ret 16

; ---- insert / remove ----

; vecInsert(self, index, elem, isMove) -- insert elem at index
; (0..len inclusive).  isMove != 0 moves elem in (ValueMeta.move),
; otherwise a copy is made (ValueMeta.copy).  No-op when index > len.
proc vecInsert
    args self, index, elem, isMove
    local dst
    local shiftDst
    endlocal

    mov rax, [%$self]
    mov rbx, [rax + Vec.len]
    cmp [%$index], rbx
    ja .done

    push [%$self]
    push 1
    call vecReserve

    mov rax, [%$self]
    mov rbx, [rax + Vec.len]
    cmp [%$index], rbx
    jae .noShift

    ; shift [index, len) up one slot: memMove(data+(index+1)*size, data+index*size, (len-index)*size)
    mov rbx, [%$index]
    inc rbx
    push [%$self]
    push rbx
    call elemAddr
    mov [%$shiftDst], rax

    push [%$self]
    push [%$index]
    call elemAddr
    mov rbx, rax                ; src

    mov rax, [%$self]
    mov rax, [rax + Vec.meta]
    mov rdx, [rax + ValueMeta.size]
    mov rax, [%$self]
    mov rax, [rax + Vec.len]
    sub rax, [%$index]
    imul rax, rdx               ; n bytes

    push [%$shiftDst]
    push rbx
    push rax
    call memMove
.noShift:
    push [%$self]
    push [%$index]
    call elemAddr
    mov [%$dst], rax

    mov rax, [%$self]
    mov rax, [rax + Vec.meta]
    cmp qword [%$isMove], 0
    jne .moveElem
    push [%$dst]
    push [%$elem]
    call [rax + ValueMeta.copy]
    jmp .finish
.moveElem:
    push [%$dst]
    push [%$elem]
    call [rax + ValueMeta.move]
.finish:
    mov rax, [%$self]
    inc qword [rax + Vec.len]
.done:

    end
    ret 32

; vecRemove(self, index, out) -- remove the element at index, shifting
; the tail down.  When out is non-NULL, copy the removed element into
; *out first (ownership moves to the caller; the slot is not dropped),
; matching cbase.  No-op when index >= len.
proc vecRemove
    args self, index, out
    local removed
    endlocal

    mov rax, [%$self]
    mov rbx, [rax + Vec.len]
    cmp [%$index], rbx
    jae .done

    cmp qword [%$out], 0
    je .noOut
    push [%$self]
    push [%$index]
    call elemAddr
    mov [%$removed], rax
    mov rax, [%$self]
    mov rax, [rax + Vec.meta]
    mov rbx, [rax + ValueMeta.size]
    push [%$out]
    push [%$removed]
    push rbx
    call memCopy
.noOut:
    mov rax, [%$self]
    mov rax, [rax + Vec.len]
    dec rax
    cmp [%$index], rax
    jae .noShift

    ; dest = elemAddr(self, index)
    push [%$self]
    push [%$index]
    call elemAddr
    mov [%$removed], rax

    ; src = elemAddr(self, index+1)
    mov rbx, [%$index]
    inc rbx
    push [%$self]
    push rbx
    call elemAddr

    ; n = size * (len - index - 1)
    mov rdx, [%$self]
    mov rdx, [rdx + Vec.meta]
    mov rdx, [rdx + ValueMeta.size]
    mov rcx, [%$self]
    mov rcx, [rcx + Vec.len]
    sub rcx, [%$index]
    dec rcx
    imul rdx, rcx

    push [%$removed]
    push rax
    push rdx
    call memMove
.noShift:
    mov rax, [%$self]
    dec qword [rax + Vec.len]
.done:

    end
    ret 24

; ---- swap / reorder ----

; vecSwapElement(self, a, b) -- byte-swap two elements via a temporary
; buffer of meta->size bytes.  No-op for out-of-bounds or a == b.
proc vecSwapElement
    args self, a, b
    local tmp
    local pa
    local pb
    local size
    endlocal

    mov rax, [%$a]
    cmp rax, [%$b]
    je .done
    mov rax, [%$self]
    mov rbx, [rax + Vec.len]
    cmp [%$a], rbx
    jae .done
    cmp [%$b], rbx
    jae .done

    mov rax, [%$self]
    mov rax, [rax + Vec.meta]
    mov rax, [rax + ValueMeta.size]
    mov [%$size], rax
    push rax
    call memAlloc
    mov [%$tmp], rax

    push [%$self]
    push [%$a]
    call elemAddr
    mov [%$pa], rax

    push [%$self]
    push [%$b]
    call elemAddr
    mov [%$pb], rax

    push [%$tmp]
    push [%$pa]
    push [%$size]
    call memCopy
    push [%$pa]
    push [%$pb]
    push [%$size]
    call memCopy
    push [%$pb]
    push [%$tmp]
    push [%$size]
    call memCopy

    push [%$tmp]
    call memFree
.done:

    end
    ret 24

; vecSwap(a, b) -- swap two whole vec headers (32 bytes each).
proc vecSwap
    args a, b
    local tmpVec, 32
    endlocal

    lea rax, [%$tmpVec]
    push rax
    push [%$a]
    push 32
    call memCopy

    push [%$a]
    push [%$b]
    push 32
    call memCopy

    push [%$b]
    lea rax, [%$tmpVec]
    push rax
    push 32
    call memCopy

    end
    ret 16

; vecSort(self) -- sort the elements in place using the runtime's
; sort() with meta->cmp as the comparator (same custom-ABI callback
; contract sort() expects).
proc vecSort
    args self

    mov rax, [%$self]
    cmp qword [rax + Vec.len], 1
    jbe .done

    mov rax, [%$self]
    mov rax, [rax + Vec.data]
    push rax
    mov rax, [%$self]
    mov rax, [rax + Vec.len]
    push rax
    mov rax, [%$self]
    mov rax, [rax + Vec.meta]
    mov rax, [rax + ValueMeta.size]
    push rax
    mov rax, [%$self]
    mov rax, [rax + Vec.meta]
    mov rax, [rax + ValueMeta.cmp]
    push rax
    call sort
.done:

    end
    ret 8

; ---- whole-vec operations ----

; vecCopy(dst, src) -- deep copy src into dst.  No-op when dst == src.
; dst is re-initialized with src's meta and capacity == src->len.
proc vecCopy
    args dst, src
    local i
    local srcElem
    local dstElem
    endlocal

    mov rax, [%$dst]
    cmp rax, [%$src]
    je .done

    mov rax, [%$src]
    mov rax, [rax + Vec.meta]
    push [%$dst]
    push rax
    mov rax, [%$src]
    mov rax, [rax + Vec.len]
    push rax
    call vecWithCapacity

    mov qword [%$i], 0
.loop:
    mov rax, [%$src]
    mov rbx, [rax + Vec.len]
    cmp [%$i], rbx
    jae .setLen

    push [%$src]
    push [%$i]
    call elemAddr
    mov [%$srcElem], rax

    push [%$dst]
    push [%$i]
    call elemAddr
    mov [%$dstElem], rax

    mov rax, [%$dst]
    mov rax, [rax + Vec.meta]
    push [%$dstElem]
    push [%$srcElem]
    call [rax + ValueMeta.copy]

    inc qword [%$i]
    jmp .loop
.setLen:
    mov rax, [%$dst]
    mov rbx, [%$src]
    mov rbx, [rbx + Vec.len]
    mov [rax + Vec.len], rbx
.done:

    end
    ret 16

; vecMove(dst, src) -- transfer ownership of src's buffer to dst and
; reset src.  No-op when dst == src.
proc vecMove
    args dst, src

    mov rax, [%$dst]
    cmp rax, [%$src]
    je .done

    mov rbx, [%$src]
    mov rax, [%$dst]
    mov rcx, [rbx + Vec.data]
    mov [rax + Vec.data], rcx
    mov rcx, [rbx + Vec.len]
    mov [rax + Vec.len], rcx
    mov rcx, [rbx + Vec.capacity]
    mov [rax + Vec.capacity], rcx
    mov rcx, [rbx + Vec.meta]
    mov [rax + Vec.meta], rcx

    mov qword [rbx + Vec.data], 0
    mov qword [rbx + Vec.len], 0
    mov qword [rbx + Vec.capacity], 0
    mov qword [rbx + Vec.meta], 0
.done:

    end
    ret 16

; ---- comparisons / hashing ----

; vecEq(a, b) -> 1 if both vecs have the same length and every pair of
; elements compares equal via a's meta->eq, else 0.
proc vecEq
    args a, b
    local i
    local ea
    local eb
    endlocal

    mov rax, [%$a]
    mov rbx, [%$b]
    mov rcx, [rax + Vec.len]
    cmp rcx, [rbx + Vec.len]
    jne .notEq

    mov qword [%$i], 0
.loop:
    mov rax, [%$a]
    mov rbx, [rax + Vec.len]
    cmp [%$i], rbx
    jae .eq

    push [%$a]
    push [%$i]
    call elemAddr
    mov [%$ea], rax

    push [%$b]
    push [%$i]
    call elemAddr
    mov [%$eb], rax

    mov rax, [%$a]
    mov rax, [rax + Vec.meta]
    push [%$ea]
    push [%$eb]
    call [rax + ValueMeta.eq]
    test rax, rax
    jz .notEq

    inc qword [%$i]
    jmp .loop
.eq:
    mov rax, 1
    jmp .done
.notEq:
    xor rax, rax
.done:

    end
    ret 16

; vecCmp(a, b) -> lexicographic order: -1/0/1.  Elements are compared
; with a's meta->cmp; shorter vec is less when all shared elements tie.
proc vecCmp
    args a, b
    local minLen
    local i
    local ea
    local eb
    endlocal

    mov rax, [%$a]
    mov rbx, [%$b]
    mov rax, [rax + Vec.len]
    mov rbx, [rbx + Vec.len]
    cmp rax, rbx
    jbe .aIsMin
    mov rax, rbx
.aIsMin:
    mov [%$minLen], rax

    mov qword [%$i], 0
.loop:
    mov rax, [%$i]
    cmp rax, [%$minLen]
    jae .compareLens

    push [%$a]
    push [%$i]
    call elemAddr
    mov [%$ea], rax

    push [%$b]
    push [%$i]
    call elemAddr
    mov [%$eb], rax

    mov rax, [%$a]
    mov rax, [rax + Vec.meta]
    push [%$ea]
    push [%$eb]
    call [rax + ValueMeta.cmp]
    test rax, rax
    jnz .done

    inc qword [%$i]
    jmp .loop
.compareLens:
    mov rax, [%$a]
    mov rbx, [%$b]
    mov rax, [rax + Vec.len]
    mov rbx, [rbx + Vec.len]
    cmp rax, rbx
    jl .less
    jg .greater
    xor rax, rax
    jmp .done
.less:
    mov rax, -1
    jmp .done
.greater:
    mov rax, 1
.done:

    end
    ret 16

; vecHash(self) -> deterministic FNV-1a hash over the element hashes:
; each element's meta->hash is folded through fnv64, exactly like
; cbase's vec_hash.
proc vecHash
    args self
    local hash
    local i
    local elemHash
    endlocal

    mov rax, 0xcbf29ce484222325
    mov [%$hash], rax

    mov qword [%$i], 0
.loop:
    mov rax, [%$self]
    mov rbx, [rax + Vec.len]
    cmp [%$i], rbx
    jae .done

    push [%$self]
    push [%$i]
    call elemAddr
    mov rbx, [%$self]
    mov rbx, [rbx + Vec.meta]
    push rax
    call [rbx + ValueMeta.hash]
    mov [%$elemHash], rax

    lea rax, [%$elemHash]
    push rax
    push 8
    push [%$hash]
    call fnv64
    mov [%$hash], rax

    inc qword [%$i]
    jmp .loop
.done:
    mov rax, [%$hash]

    end
    ret 8
