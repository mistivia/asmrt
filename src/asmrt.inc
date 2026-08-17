; asmrt.inc -- shared header for the asmrt runtime
;
; Custom ABI: caller pushes args in declaration order (last-pushed arg
; lands at [rbp+16]); callee cleans its own args with ret N; return value
; in rax; every register but rax is clobbered by any call (custom-ABI,
; real-ABI, or bare syscall) -- so no variable ever lives in a register
; across a call, only on the stack.
;
; Params and locals are declared with args/local and accessed as
; context-local %$name aliases (NASM %push/%pop), e.g. [%$fd], [%$flag].
; Using %$ instead of a plain global %define means the same name can be
; reused in different functions in the same file without colliding --
; a plain %define would otherwise leak for the rest of the file and get
; pre-expanded (and corrupted) the next time that name is declared.
;
; Required order in every function: proc name -> args -> local... ->
; endlocal -> body -> end. (args/local must come after proc/begin
; because begin is what pushes the context %$ names live in.)

%ifndef ASMRT_INC
%define ASMRT_INC

; ---- custom ABI support macros ----

%macro begin 0
    %push
    push rbp
    mov  rbp, rsp
    %assign __localSize 0
%endmacro

%macro end 0
    mov  rsp, rbp
    pop  rbp
    %pop
%endmacro

; proc name: function label + begin, merged. Write `proc funcName`
; instead of `funcName:` followed by `begin`. Does not emit `global` --
; that's still declared separately at the top of the file, as before.
%macro proc 1
%1:
    begin
%endmacro

; args a1, ..., an: declare params in push order (a1 pushed first, an
; pushed last, landing at [rbp+16]). Must follow begin.
%macro args 1-*
    %assign %%n %0
    %assign %%i 1
    %rep %0
        %xdefine %[%$ %+ %1] (rbp + 16 + 8*(%%n - %%i))
        %assign %%i %%i+1
    %rotate 1
    %endrep
%endmacro

; local name[, size=8]: declare a local, accumulating __localSize (reset
; by begin). size must be a multiple of 8 (see AGENTS.md). Call
; endlocal once, after the last local, to emit the sub rsp.
%macro local 1-2 8
    %assign __localSize __localSize + %2
    %assign %[%$ %+ %1 %+ _offset] (-__localSize)
    %xdefine %[%$ %+ %1] (rbp + %[%$ %+ %1 %+ _offset])
%endmacro

%macro endlocal 0
    sub rsp, __localSize
%endmacro

; hexalign: pad rsp to 16-byte alignment before a real-ABI call. Under
; this ABI rsp is always at least 8-byte aligned, so it's only ever off
; by 0 or 8; no paired "undo" needed (end's mov rsp,rbp reclaims it).
%macro hexalign 0
    mov  rax, rsp
    and  rax, 8
    sub  rsp, rax
%endmacro

; preasmcall/postasmcall: push/pop every register (rax included), for
; calling into a custom-ABI function from inside a real-ABI callback
; (e.g. a C function-pointer callback) without clobbering what the
; real-ABI caller expects to survive. Stash any needed return value to
; memory before postasmcall -- it restores rax too.
%macro preasmcall 0
    push rax
    push rbx
    push rcx
    push rdx
    push rbp
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15
    sub  rsp, 8   ; 15 registers is odd, pad one slot to keep 16-byte alignment
%endmacro

%macro postasmcall 0
    add  rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rbp
    pop rdx
    pop rcx
    pop rbx
    pop rax
%endmacro

; ---- shared struct definitions ----

; ValueMeta: mirrors cbase/cbase.h's `struct value_meta`, the type-info
; bundle every generic cbase container carries.  The C prototype uses
; int/int for size/align, but under this runtime every field is kept as
; a full qword so the struct is uniformly 8-aligned and 64 bytes total.
;
;   int                size;    ; +0
;   int                align;   ; +8
;   drop_fn            drop;    ; +16
;   cmp_fn             cmp;     ; +24
;   eq_fn              eq;      ; +32
;   hash_fn            hash;    ; +40
;   copy_fn            copy;    ; +48
;   move_fn            move;    ; +56
;                                        total 64, all fields 8-aligned
struc ValueMeta
    .size:  resq 1
    .align: resq 1
    .drop:  resq 1
    .cmp:   resq 1
    .eq:    resq 1
    .hash:  resq 1
    .copy:  resq 1
    .move:  resq 1
endstruc

; Vec: mirrors cbase/cbase.h's `struct vec`, a generic growable
; array.  All four fields are qwords, so the struct is 32 bytes and
; 8-aligned.
;
;   void *data;     ; +0
;   size_t len;     ; +8
;   size_t capacity ; +16
;   struct value_meta *meta ; +24
struc Vec
    .data:     resq 1
    .len:      resq 1
    .capacity: resq 1
    .meta:     resq 1
endstruc

; ---- runtime exported symbols ----
;
; Signature comments use the custom ABI: caller pushes args in
; declaration order, callee cleans the stack with `ret N`, return
; value in rax.  Pointer parameters (and pointer return values) are
; named with a `p` prefix: pVec, pMeta, pBuf, ... -- so a glance at
; the signature tells you which slots carry addresses.

; main.asm
; rtExit(code) -- terminate the process with `code`, never returns
extern rtExit

; io.asm
; ioOpen(pPath, flags, mode) -> fd
extern ioOpen
; ioClose(fd) -> result
extern ioClose
; ioRead(fd, pBuf, count) -> bytesRead
extern ioRead
; ioWrite(fd, pBuf, count) -> bytesWritten
extern ioWrite
; ioSeek(fd, offset, whence) -> newOffset   ; whence: 0=SET, 1=CUR, 2=END
extern ioSeek
; ioWriteNum(fd, num) -> bytesWritten
extern ioWriteNum
; ioWriteChar(fd, ch) -> bytesWritten
extern ioWriteChar

; fs.asm
; fsStat(pPath, pStatBuf) -> result
extern fsStat
; fsFstat(fd, pStatBuf) -> result
extern fsFstat
; fsMkdir(pPath, mode) -> result
extern fsMkdir
; fsRmdir(pPath) -> result
extern fsRmdir
; fsUnlink(pPath) -> result
extern fsUnlink

; mem.asm
; memAlloc(size) -> pMem ; malloc wrapper, NULL on failure
extern memAlloc
; memFree(pMem) ; free a memAlloc'd block; rax is always 0
extern memFree
; memReloc(pMem, size) -> pMemNew ; realloc wrapper
extern memReloc
; memCopy(pDest, pSrc, n) -> pDest ; regions must not overlap
extern memCopy
; memMove(pDest, pSrc, n) -> pDest ; overlap-safe
extern memMove
; memFill(pDest, val, n) -> pDest ; fills n bytes with val's low byte
extern memFill

; assert.asm
; assert(pMsg, flag) -- if flag == 0, write pMsg to stderr and exit(-1)
extern assert

; str.asm
; strLen(pS) -> length ; NUL-terminated, excluding trailing NUL
extern strLen
; strEq(pA, pB) -> 1/0 ; NUL-terminated string equality
extern strEq

; utils.asm
; sort(pBase, nmemb, size, pCmpFn) -- quicksort over opaque elements;
;   pCmpFn(a, b) -> <0 / 0 / >0, custom-ABI comparator
extern sort
; fnv64(pData, dataSize, input) -> hash ; FNV-1a 64-bit
extern fnv64

; vec.asm
; vecInit(pVec, pMeta) -> 0 ; zero the vec, attach the ValueMeta
extern vecInit
; vecWithCapacity(pVec, pMeta, capacity) -> 0 ; pre-allocate room
extern vecWithCapacity
; vecReserve(pVec, additional) ; grow to fit len+additional
extern vecReserve
; vecPushCp(pVec, pElem) ; append a copy of *pElem
extern vecPushCp
; vecPushMv(pVec, pElem) ; append by moving *pElem
extern vecPushMv
; vecPop(pVec, pOut) -> 1/0 ; copy last elem to *pOut (pOut may be NULL)
extern vecPop
; vecGet(pVec, index) -> pElem ; NULL if out of bounds
extern vecGet
; vecSetCp(pVec, index, pElem) ; replace elem at index with a copy
extern vecSetCp
; vecSetMv(pVec, index, pElem) ; replace elem at index by move
extern vecSetMv
; vecFirst(pVec) -> pElem ; NULL if empty
extern vecFirst
; vecLast(pVec) -> pElem ; NULL if empty
extern vecLast
; vecLen(pVec) -> len
extern vecLen
; vecIsEmpty(pVec) -> 1/0
extern vecIsEmpty
; vecClear(pVec) ; drop all elems, keep buffer
extern vecClear
; vecTruncate(pVec, len) ; drop elems from `len` onward
extern vecTruncate
; vecDrop(pVec) ; drop all elems, free buffer, reset the vec in place
extern vecDrop
; vecSwapElement(pVec, a, b) ; byte-swap two elements
extern vecSwapElement
; vecSwap(pA, pB) ; swap two whole vec headers
extern vecSwap
; vecEq(pA, pB) -> 1/0 ; same len, element-wise eq via meta
extern vecEq
; vecInsertCp(pVec, index, pElem) ; insert a copy at index (0..len)
extern vecInsertCp
; vecInsertMv(pVec, index, pElem) ; insert by move at index (0..len)
extern vecInsertMv
; vecRemove(pVec, index, pOut) ; copy removed elem to *pOut (may be NULL)
extern vecRemove
; vecAsPtr(pVec) -> pData ; raw data pointer (may be NULL)
extern vecAsPtr
; vecCopy(pDst, pSrc) ; deep copy src into dst (no-op if same vec)
extern vecCopy
; vecMove(pDst, pSrc) ; transfer ownership, reset pSrc
extern vecMove
; vecSort(pVec) ; in-place via sort() + meta cmp
extern vecSort
; vecCmp(pA, pB) -> -1/0/1 ; lexicographic
extern vecCmp
; vecHash(pVec) -> hash ; FNV-1a over element hashes
extern vecHash
; vecMeta ; ValueMeta instance describing struct Vec itself
extern vecMeta

%endif ; ASMRT_INC
