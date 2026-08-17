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
elemAddr:
    ;; args: self, index
    %assign N 2
    %assign self (16 + (N-1) * 8)
    %assign index (16 + (N-2) * 8)
    begin

    mov rax, [rbp + self]
    mov rax, [rax + Vec_data]
    mov rbx, [rbp + self]
    mov rbx, [rbx + Vec_meta]
    mov rbx, [rbx + ValueMeta_size]
    mov rcx, [rbp + index]
    imul rbx, rcx
    add rax, rbx

    end
    ret 16

; ---- construction / destruction ----

; vecInit(self, meta) -> 0.  Zero the vec and attach the ValueMeta.
vecInit:
    ;; args: self, meta
    %assign N 2
    %assign self (16 + (N-1) * 8)
    %assign meta (16 + (N-2) * 8)
    begin

    mov rax, [rbp + self]
    mov qword [rax + Vec_data], 0
    mov qword [rax + Vec_len], 0
    mov qword [rax + Vec_capacity], 0
    mov rbx, [rbp + meta]
    mov [rax + Vec_meta], rbx

    xor rax, rax

    end
    ret 16

; vecWithCapacity(self, meta, capacity) -> 0.  Like vecInit, but
; pre-allocates room for `capacity` elements (data stays NULL when
; capacity is 0, matching cbase).
vecWithCapacity:
    ;; args: self, meta, capacity
    %assign N 3
    %assign self (16 + (N-1) * 8)
    %assign meta (16 + (N-2) * 8)
    %assign capacity (16 + (N-3) * 8)
    begin

    mov rax, [rbp + self]
    mov qword [rax + Vec_data], 0
    mov qword [rax + Vec_len], 0
    mov qword [rax + Vec_capacity], 0
    mov rbx, [rbp + meta]
    mov [rax + Vec_meta], rbx

    mov rax, [rbp + self]
    mov rbx, [rbp + capacity]
    mov [rax + Vec_capacity], rbx

    cmp rbx, 0
    je .noAlloc

    ; self->data = memAlloc(capacity * meta->size)
    mov rax, [rbp + meta]
    mov rbx, [rax + ValueMeta_size]
    mov rcx, [rbp + capacity]
    imul rbx, rcx
    push rbx
    call memAlloc
    mov rbx, [rbp + self]
    mov [rbx + Vec_data], rax
    jmp .done
.noAlloc:
.done:
    xor rax, rax

    end
    ret 24

; vecReserve(self, additional) -- ensure capacity for len+additional
; elements, doubling from 4 as cbase does.
vecReserve:
    ;; args: self, additional
    %assign N 2
    %assign self (16 + (N-1) * 8)
    %assign additional (16 + (N-2) * 8)
    begin
    ;; local variables
    %assign offset 0
    ;; needed 8 bytes
    %assign offset (offset - 8)
    %assign needed offset
    ;; newCap 8 bytes
    %assign offset (offset - 8)
    %assign newCap offset
    ;; endlocal
    sub rsp, (-offset)

    mov rax, [rbp + self]
    mov rax, [rax + Vec_len]
    add rax, [rbp + additional]
    mov [rbp + needed], rax

    mov rax, [rbp + self]
    mov rbx, [rax + Vec_capacity]
    cmp [rbp + needed], rbx
    jbe .done

    mov rax, [rbp + self]
    mov rax, [rax + Vec_capacity]
    test rax, rax
    jnz .haveCap
    mov rax, 4
.haveCap:
    mov [rbp + newCap], rax
.growLoop:
    mov rax, [rbp + newCap]
    cmp rax, [rbp + needed]
    jae .grown
    shl qword [rbp + newCap], 1
    jmp .growLoop
.grown:
    ; self->data = memReloc(self->data, newCap * meta->size)
    mov rax, [rbp + self]
    mov rax, [rax + Vec_data]
    push rax
    mov rax, [rbp + self]
    mov rax, [rax + Vec_meta]
    mov rax, [rax + ValueMeta_size]
    mov rbx, [rbp + newCap]
    imul rax, rbx
    push rax
    call memReloc
    mov rbx, [rbp + self]
    mov [rbx + Vec_data], rax
    mov rax, [rbp + newCap]
    mov [rbx + Vec_capacity], rax
.done:

    end
    ret 16

; vecDrop(self) -- drop every element (via meta->drop), free the buffer,
; and reset the vec in place.
vecDrop:
    ;; args: self
    %assign N 1
    %assign self (16 + (N-1) * 8)
    begin

    ;; local variables
    %assign offset 0
    ;; i 8 bytes
    %assign offset (offset - 8)
    %assign i offset
    ;; endlocal
    sub rsp, (-offset)

    mov qword [rbp + i], 0
.loop:
    mov rax, [rbp + self]
    mov rbx, [rax + Vec_len]
    cmp [rbp + i], rbx
    jae .freeData
    push [rbp + self]
    push [rbp + i]
    call elemAddr
    mov rbx, [rbp + self]
    mov rbx, [rbx + Vec_meta]
    push rax
    call [rbx + ValueMeta_drop]
    inc qword [rbp + i]
    jmp .loop
.freeData:
    mov rax, [rbp + self]
    mov rax, [rax + Vec_data]
    push rax
    call memFree

    mov rax, [rbp + self]
    mov qword [rax + Vec_data], 0
    mov qword [rax + Vec_len], 0
    mov qword [rax + Vec_capacity], 0

    end
    ret 8

; vecClear(self) -- drop every element and set len to 0, keep buffer.
vecClear:
    begin

    ;; args: self
    %assign N 1
    %assign self (16 + (N-1) * 8)

    ;; local variables
    %assign offset 0
    ;; i 8 bytes
    %assign offset (offset - 8)
    %assign i offset
    ;; endlocal
    sub rsp, (-offset)

    mov qword [rbp + i], 0
.loop:
    mov rax, [rbp + self]
    mov rbx, [rax + Vec_len]
    cmp [rbp + i], rbx
    jae .done
    push [rbp + self]
    push [rbp + i]
    call elemAddr
    mov rbx, [rbp + self]
    mov rbx, [rbx + Vec_meta]
    push rax
    call [rbx + ValueMeta_drop]
    inc qword [rbp + i]
    jmp .loop
.done:
    mov rax, [rbp + self]
    mov qword [rax + Vec_len], 0

    end
    ret 8

; vecTruncate(self, len) -- drop elements from len onward, shrink len.
vecTruncate:
    begin

    ;; args: self, len
    %assign N 2
    %assign self (16 + (N-1) * 8)
    %assign len (16 + (N-2) * 8)

    ;; local variables
    %assign offset 0
    ;; i 8 bytes
    %assign offset (offset - 8)
    %assign i offset
    ;; endlocal
    sub rsp, (-offset)

    mov rax, [rbp + self]
    mov rbx, [rax + Vec_len]
    cmp [rbp + len], rbx
    jae .setLen

    mov rax, [rbp + len]
    mov [rbp + i], rax
.loop:
    mov rax, [rbp + self]
    mov rbx, [rax + Vec_len]
    cmp [rbp + i], rbx
    jae .setLen
    push [rbp + self]
    push [rbp + i]
    call elemAddr
    mov rbx, [rbp + self]
    mov rbx, [rbx + Vec_meta]
    push rax
    call [rbx + ValueMeta_drop]
    inc qword [rbp + i]
    jmp .loop
.setLen:
    mov rax, [rbp + self]
    mov rbx, [rbp + len]
    mov [rax + Vec_len], rbx

    end
    ret 16

; ---- element access ----

; vecGet(self, index) -> ptr to element, or NULL if out of bounds
vecGet:
    ;; args: self, index
    %assign N 2
    %assign self (16 + (N-1) * 8)
    %assign index (16 + (N-2) * 8)
    begin

    mov rax, [rbp + self]
    mov rbx, [rax + Vec_len]
    cmp [rbp + index], rbx
    jae .oob

    push [rbp + self]
    push [rbp + index]
    call elemAddr
    jmp .done
.oob:
    xor rax, rax
.done:

    end
    ret 16

; vecFirst(self) -> ptr to first element, or NULL if empty
vecFirst:
    ;; args: self
    %assign N 1
    %assign self (16 + (N-1) * 8)
    begin

    mov rax, [rbp + self]
    cmp qword [rax + Vec_len], 0
    je .empty
    mov rax, [rax + Vec_data]
    jmp .done
.empty:
    xor rax, rax
.done:

    end
    ret 8

; vecLast(self) -> ptr to last element, or NULL if empty
vecLast:
    ;; args: self
    %assign N 1
    %assign self (16 + (N-1) * 8)
    begin

    mov rax, [rbp + self]
    cmp qword [rax + Vec_len], 0
    je .empty
    mov rbx, [rax + Vec_len]
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
vecLen:
    ;; args: self
    %assign N 1
    %assign self (16 + (N-1) * 8)
    begin

    mov rax, [rbp + self]
    mov rax, [rax + Vec_len]

    end
    ret 8

; vecIsEmpty(self) -> 1 if len == 0, else 0
vecIsEmpty:
    ;; args: self
    %assign N 1
    %assign self (16 + (N-1) * 8)
    begin

    mov rax, [rbp + self]
    cmp qword [rax + Vec_len], 0
    sete al
    movzx rax, al

    end
    ret 8

; vecAsPtr(self) -> raw data pointer (may be NULL)
vecAsPtr:
    ;; args: self
    %assign N 1
    %assign self (16 + (N-1) * 8)
    begin

    mov rax, [rbp + self]
    mov rax, [rax + Vec_data]

    end
    ret 8

; vecSet(self, index, elem, isMove) -- replace element at index: drop
; the old one, copy the new one in (or move when isMove != 0).  No-op
; when index is out of bounds.
vecSet:
    ;; args: self, index, elem, isMove
    %assign N 4
    %assign self (16 + (N-1) * 8)
    %assign index (16 + (N-2) * 8)
    %assign elem (16 + (N-3) * 8)
    %assign isMove (16 + (N-4) * 8)
    begin
    ;; local variables
    %assign offset 0
    ;; dst 8 bytes
    %assign offset (offset - 8)
    %assign dst offset
    ;; endlocal
    sub rsp, (-offset)

    mov rax, [rbp + self]
    mov rbx, [rax + Vec_len]
    cmp [rbp + index], rbx
    jae .done

    push [rbp + self]
    push [rbp + index]
    call elemAddr
    mov [rbp + dst], rax

    mov rax, [rbp + self]
    mov rax, [rax + Vec_meta]
    push [rbp + dst]
    call [rax + ValueMeta_drop]

    mov rax, [rbp + self]
    mov rax, [rax + Vec_meta]
    cmp qword [rbp + isMove], 0
    jne .moveElem
    push [rbp + dst]
    push [rbp + elem]
    call [rax + ValueMeta_copy]
    jmp .done
.moveElem:
    push [rbp + dst]
    push [rbp + elem]
    call [rax + ValueMeta_move]
.done:

    end
    ret 32

; ---- push / pop ----

; vecPush(self, elem, isMove) -- append a copy of elem, or move it in
; when isMove != 0.
vecPush:
    ;; args: self, elem, isMove
    %assign N 3
    %assign self (16 + (N-1) * 8)
    %assign elem (16 + (N-2) * 8)
    %assign isMove (16 + (N-3) * 8)
    begin
    ;; local variables
    %assign offset 0
    ;; dst 8 bytes
    %assign offset (offset - 8)
    %assign dst offset
    ;; endlocal
    sub rsp, (-offset)

    push [rbp + self]
    push 1
    call vecReserve

    push [rbp + self]
    mov rax, [rbp + self]
    mov rbx, [rax + Vec_len]
    push rbx
    call elemAddr
    mov [rbp + dst], rax

    mov rax, [rbp + self]
    mov rax, [rax + Vec_meta]
    cmp qword [rbp + isMove], 0
    jne .moveElem
    push [rbp + dst]
    push [rbp + elem]
    call [rax + ValueMeta_copy]
    jmp .finish
.moveElem:
    push [rbp + dst]
    push [rbp + elem]
    call [rax + ValueMeta_move]
.finish:
    mov rax, [rbp + self]
    inc qword [rax + Vec_len]

    end
    ret 24

; vecPop(self, out) -> 1 if an element was popped, else 0.  When out is
; non-NULL the popped element is copied into *out.  The element slot is
; *not* dropped (ownership moves to the caller), matching cbase.
vecPop:
    ;; args: self, out
    %assign N 2
    %assign self (16 + (N-1) * 8)
    %assign out (16 + (N-2) * 8)
    begin
    ;; local variables
    %assign offset 0
    ;; src 8 bytes
    %assign offset (offset - 8)
    %assign src offset
    ;; endlocal
    sub rsp, (-offset)

    mov rax, [rbp + self]
    cmp qword [rax + Vec_len], 0
    je .false

    mov rax, [rbp + self]
    dec qword [rax + Vec_len]

    cmp qword [rbp + out], 0
    je .noOut

    push [rbp + self]
    mov rax, [rbp + self]
    mov rbx, [rax + Vec_len]
    push rbx
    call elemAddr
    mov [rbp + src], rax

    push [rbp + out]
    push [rbp + src]
    mov rax, [rbp + self]
    mov rax, [rax + Vec_meta]
    mov rbx, [rax + ValueMeta_size]
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
; (0..len inclusive).  isMove != 0 moves elem in (ValueMeta_move),
; otherwise a copy is made (ValueMeta_copy).  No-op when index > len.
vecInsert:
    ;; args: self, index, elem, isMove
    %assign N 4
    %assign self (16 + (N-1) * 8)
    %assign index (16 + (N-2) * 8)
    %assign elem (16 + (N-3) * 8)
    %assign isMove (16 + (N-4) * 8)
    begin
    ;; local variables
    %assign offset 0
    ;; dst 8 bytes
    %assign offset (offset - 8)
    %assign dst offset
    ;; shiftDst 8 bytes
    %assign offset (offset - 8)
    %assign shiftDst offset
    ;; endlocal
    sub rsp, (-offset)

    mov rax, [rbp + self]
    mov rbx, [rax + Vec_len]
    cmp [rbp + index], rbx
    ja .done

    push [rbp + self]
    push 1
    call vecReserve

    mov rax, [rbp + self]
    mov rbx, [rax + Vec_len]
    cmp [rbp + index], rbx
    jae .noShift

    ; shift [index, len) up one slot: memMove(data+(index+1)*size, data+index*size, (len-index)*size)
    mov rbx, [rbp + index]
    inc rbx
    push [rbp + self]
    push rbx
    call elemAddr
    mov [rbp + shiftDst], rax

    push [rbp + self]
    push [rbp + index]
    call elemAddr
    mov rbx, rax                ; src

    mov rax, [rbp + self]
    mov rax, [rax + Vec_meta]
    mov rdx, [rax + ValueMeta_size]
    mov rax, [rbp + self]
    mov rax, [rax + Vec_len]
    sub rax, [rbp + index]
    imul rax, rdx               ; n bytes

    push [rbp + shiftDst]
    push rbx
    push rax
    call memMove
.noShift:
    push [rbp + self]
    push [rbp + index]
    call elemAddr
    mov [rbp + dst], rax

    mov rax, [rbp + self]
    mov rax, [rax + Vec_meta]
    cmp qword [rbp + isMove], 0
    jne .moveElem
    push [rbp + dst]
    push [rbp + elem]
    call [rax + ValueMeta_copy]
    jmp .finish
.moveElem:
    push [rbp + dst]
    push [rbp + elem]
    call [rax + ValueMeta_move]
.finish:
    mov rax, [rbp + self]
    inc qword [rax + Vec_len]
.done:

    end
    ret 32

; vecRemove(self, index, out) -- remove the element at index, shifting
; the tail down.  When out is non-NULL, copy the removed element into
; *out first (ownership moves to the caller; the slot is not dropped),
; matching cbase.  No-op when index >= len.
vecRemove:
    ;; args: self, index, out
    %assign N 3
    %assign self (16 + (N-1) * 8)
    %assign index (16 + (N-2) * 8)
    %assign out (16 + (N-3) * 8)
    begin
    ;; local variables
    %assign offset 0
    ;; removed 8 bytes
    %assign offset (offset - 8)
    %assign removed offset
    ;; endlocal
    sub rsp, (-offset)

    mov rax, [rbp + self]
    mov rbx, [rax + Vec_len]
    cmp [rbp + index], rbx
    jae .done

    cmp qword [rbp + out], 0
    je .noOut
    push [rbp + self]
    push [rbp + index]
    call elemAddr
    mov [rbp + removed], rax
    mov rax, [rbp + self]
    mov rax, [rax + Vec_meta]
    mov rbx, [rax + ValueMeta_size]
    push [rbp + out]
    push [rbp + removed]
    push rbx
    call memCopy
.noOut:
    mov rax, [rbp + self]
    mov rax, [rax + Vec_len]
    dec rax
    cmp [rbp + index], rax
    jae .noShift

    ; dest = elemAddr(self, index)
    push [rbp + self]
    push [rbp + index]
    call elemAddr
    mov [rbp + removed], rax

    ; src = elemAddr(self, index+1)
    mov rbx, [rbp + index]
    inc rbx
    push [rbp + self]
    push rbx
    call elemAddr

    ; n = size * (len - index - 1)
    mov rdx, [rbp + self]
    mov rdx, [rdx + Vec_meta]
    mov rdx, [rdx + ValueMeta_size]
    mov rcx, [rbp + self]
    mov rcx, [rcx + Vec_len]
    sub rcx, [rbp + index]
    dec rcx
    imul rdx, rcx

    push [rbp + removed]
    push rax
    push rdx
    call memMove
.noShift:
    mov rax, [rbp + self]
    dec qword [rax + Vec_len]
.done:

    end
    ret 24

; ---- swap / reorder ----

; vecSwapElement(self, a, b) -- byte-swap two elements via memSwap.
; No temporary buffer or heap allocation needed.  No-op for
; out-of-bounds or a == b.
vecSwapElement:
    ;; args: self, a, b
    %assign N 3
    %assign self (16 + (N-1) * 8)
    %assign a (16 + (N-2) * 8)
    %assign b (16 + (N-3) * 8)
    begin
    ;; local variables
    %assign offset 0
    ;; pa 8 bytes
    %assign offset (offset - 8)
    %assign pa offset
    ;; pb 8 bytes
    %assign offset (offset - 8)
    %assign pb offset
    ;; size 8 bytes
    %assign offset (offset - 8)
    %assign size offset
    ;; endlocal
    sub rsp, (-offset)

    mov rax, [rbp + a]
    cmp rax, [rbp + b]
    je .done
    mov rax, [rbp + self]
    mov rbx, [rax + Vec_len]
    cmp [rbp + a], rbx
    jae .done
    cmp [rbp + b], rbx
    jae .done

    mov rax, [rbp + self]
    mov rax, [rax + Vec_meta]
    mov rax, [rax + ValueMeta_size]
    mov [rbp + size], rax

    push [rbp + self]
    push [rbp + a]
    call elemAddr
    mov [rbp + pa], rax

    push [rbp + self]
    push [rbp + b]
    call elemAddr
    mov [rbp + pb], rax

    push [rbp + pa]
    push [rbp + pb]
    push [rbp + size]
    call memSwap
.done:

    end
    ret 24

; vecSwap(a, b) -- swap two whole vec headers (32 bytes each).
vecSwap:
    ;; args: a, b
    %assign N 2
    %assign a (16 + (N-1) * 8)
    %assign b (16 + (N-2) * 8)
    begin
    ;; local variables
    %assign offset 0
    ;; tmpVec 32 bytes
    %assign offset (offset - 32)
    %assign tmpVec offset
    ;; endlocal
    sub rsp, (-offset)

    lea rax, [rbp + tmpVec]
    push rax
    push [rbp + a]
    push 32
    call memCopy

    push [rbp + a]
    push [rbp + b]
    push 32
    call memCopy

    push [rbp + b]
    lea rax, [rbp + tmpVec]
    push rax
    push 32
    call memCopy

    end
    ret 16

; vecSort(self) -- sort the elements in place using the runtime's
; sort() with meta->cmp as the comparator (same custom-ABI callback
; contract sort() expects).
vecSort:
    ;; args: self
    %assign N 1
    %assign self (16 + (N-1) * 8)
    begin

    mov rax, [rbp + self]
    cmp qword [rax + Vec_len], 1
    jbe .done

    mov rax, [rbp + self]
    mov rax, [rax + Vec_data]
    push rax
    mov rax, [rbp + self]
    mov rax, [rax + Vec_len]
    push rax
    mov rax, [rbp + self]
    mov rax, [rax + Vec_meta]
    mov rax, [rax + ValueMeta_size]
    push rax
    mov rax, [rbp + self]
    mov rax, [rax + Vec_meta]
    mov rax, [rax + ValueMeta_cmp]
    push rax
    call sort
.done:

    end
    ret 8

; ---- whole-vec operations ----

; vecCopy(dst, src) -- deep copy src into dst.  No-op when dst == src.
; dst is re-initialized with src's meta and capacity == src->len.
vecCopy:
    ;; args: dst, src
    %assign N 2
    %assign dst (16 + (N-1) * 8)
    %assign src (16 + (N-2) * 8)
    begin
    ;; local variables
    %assign offset 0
    ;; i 8 bytes
    %assign offset (offset - 8)
    %assign i offset
    ;; srcElem 8 bytes
    %assign offset (offset - 8)
    %assign srcElem offset
    ;; dstElem 8 bytes
    %assign offset (offset - 8)
    %assign dstElem offset
    ;; endlocal
    sub rsp, (-offset)

    mov rax, [rbp + dst]
    cmp rax, [rbp + src]
    je .done

    mov rax, [rbp + src]
    mov rax, [rax + Vec_meta]
    push [rbp + dst]
    push rax
    mov rax, [rbp + src]
    mov rax, [rax + Vec_len]
    push rax
    call vecWithCapacity

    mov qword [rbp + i], 0
.loop:
    mov rax, [rbp + src]
    mov rbx, [rax + Vec_len]
    cmp [rbp + i], rbx
    jae .setLen

    push [rbp + src]
    push [rbp + i]
    call elemAddr
    mov [rbp + srcElem], rax

    push [rbp + dst]
    push [rbp + i]
    call elemAddr
    mov [rbp + dstElem], rax

    mov rax, [rbp + dst]
    mov rax, [rax + Vec_meta]
    push [rbp + dstElem]
    push [rbp + srcElem]
    call [rax + ValueMeta_copy]

    inc qword [rbp + i]
    jmp .loop
.setLen:
    mov rax, [rbp + dst]
    mov rbx, [rbp + src]
    mov rbx, [rbx + Vec_len]
    mov [rax + Vec_len], rbx
.done:

    end
    ret 16

; vecMove(dst, src) -- transfer ownership of src's buffer to dst and
; reset src.  No-op when dst == src.
vecMove:
    ;; args: dst, src
    %assign N 2
    %assign dst (16 + (N-1) * 8)
    %assign src (16 + (N-2) * 8)
    begin

    mov rax, [rbp + dst]
    cmp rax, [rbp + src]
    je .done

    mov rbx, [rbp + src]
    mov rax, [rbp + dst]
    mov rcx, [rbx + Vec_data]
    mov [rax + Vec_data], rcx
    mov rcx, [rbx + Vec_len]
    mov [rax + Vec_len], rcx
    mov rcx, [rbx + Vec_capacity]
    mov [rax + Vec_capacity], rcx
    mov rcx, [rbx + Vec_meta]
    mov [rax + Vec_meta], rcx

    mov qword [rbx + Vec_data], 0
    mov qword [rbx + Vec_len], 0
    mov qword [rbx + Vec_capacity], 0
    mov qword [rbx + Vec_meta], 0
.done:

    end
    ret 16

; ---- comparisons / hashing ----

; vecEq(a, b) -> 1 if both vecs have the same length and every pair of
; elements compares equal via a's meta->eq, else 0.
vecEq:
    ;; args: a, b
    %assign N 2
    %assign a (16 + (N-1) * 8)
    %assign b (16 + (N-2) * 8)
    begin
    ;; local variables
    %assign offset 0
    ;; i 8 bytes
    %assign offset (offset - 8)
    %assign i offset
    ;; ea 8 bytes
    %assign offset (offset - 8)
    %assign ea offset
    ;; eb 8 bytes
    %assign offset (offset - 8)
    %assign eb offset
    ;; endlocal
    sub rsp, (-offset)

    mov rax, [rbp + a]
    mov rbx, [rbp + b]
    mov rcx, [rax + Vec_len]
    cmp rcx, [rbx + Vec_len]
    jne .notEq

    mov qword [rbp + i], 0
.loop:
    mov rax, [rbp + a]
    mov rbx, [rax + Vec_len]
    cmp [rbp + i], rbx
    jae .eq

    push [rbp + a]
    push [rbp + i]
    call elemAddr
    mov [rbp + ea], rax

    push [rbp + b]
    push [rbp + i]
    call elemAddr
    mov [rbp + eb], rax

    mov rax, [rbp + a]
    mov rax, [rax + Vec_meta]
    push [rbp + ea]
    push [rbp + eb]
    call [rax + ValueMeta_eq]
    test rax, rax
    jz .notEq

    inc qword [rbp + i]
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
vecCmp:
    ;; args: a, b
    %assign N 2
    %assign a (16 + (N-1) * 8)
    %assign b (16 + (N-2) * 8)
    begin
    ;; local variables
    %assign offset 0
    ;; minLen 8 bytes
    %assign offset (offset - 8)
    %assign minLen offset
    ;; i 8 bytes
    %assign offset (offset - 8)
    %assign i offset
    ;; ea 8 bytes
    %assign offset (offset - 8)
    %assign ea offset
    ;; eb 8 bytes
    %assign offset (offset - 8)
    %assign eb offset
    ;; endlocal
    sub rsp, (-offset)

    mov rax, [rbp + a]
    mov rbx, [rbp + b]
    mov rax, [rax + Vec_len]
    mov rbx, [rbx + Vec_len]
    cmp rax, rbx
    jbe .aIsMin
    mov rax, rbx
.aIsMin:
    mov [rbp + minLen], rax

    mov qword [rbp + i], 0
.loop:
    mov rax, [rbp + i]
    cmp rax, [rbp + minLen]
    jae .compareLens

    push [rbp + a]
    push [rbp + i]
    call elemAddr
    mov [rbp + ea], rax

    push [rbp + b]
    push [rbp + i]
    call elemAddr
    mov [rbp + eb], rax

    mov rax, [rbp + a]
    mov rax, [rax + Vec_meta]
    push [rbp + ea]
    push [rbp + eb]
    call [rax + ValueMeta_cmp]
    test rax, rax
    jnz .done

    inc qword [rbp + i]
    jmp .loop
.compareLens:
    mov rax, [rbp + a]
    mov rbx, [rbp + b]
    mov rax, [rax + Vec_len]
    mov rbx, [rbx + Vec_len]
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
vecHash:
    ;; args: self
    %assign N 1
    %assign self (16 + (N-1) * 8)
    begin
    ;; local variables
    %assign offset 0
    ;; hash 8 bytes
    %assign offset (offset - 8)
    %assign hash offset
    ;; i 8 bytes
    %assign offset (offset - 8)
    %assign i offset
    ;; elemHash 8 bytes
    %assign offset (offset - 8)
    %assign elemHash offset
    ;; endlocal
    sub rsp, (-offset)

    mov rax, 0xcbf29ce484222325
    mov [rbp + hash], rax

    mov qword [rbp + i], 0
.loop:
    mov rax, [rbp + self]
    mov rbx, [rax + Vec_len]
    cmp [rbp + i], rbx
    jae .done

    push [rbp + self]
    push [rbp + i]
    call elemAddr
    mov rbx, [rbp + self]
    mov rbx, [rbx + Vec_meta]
    push rax
    call [rbx + ValueMeta_hash]
    mov [rbp + elemHash], rax

    lea rax, [rbp + elemHash]
    push rax
    push 8
    push [rbp + hash]
    call fnv64
    mov [rbp + hash], rax

    inc qword [rbp + i]
    jmp .loop
.done:
    mov rax, [rbp + hash]

    end
    ret 8
