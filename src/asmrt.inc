; asmrt.inc -- shared header for the asmrt runtime
;
; Custom ABI: caller pushes args in declaration order (last-pushed arg
; lands at [rbp+16]); callee cleans its own args with ret N; return value
; in rax; every register but rax is clobbered by any call (custom-ABI,
; real-ABI, or bare syscall) -- so no variable ever lives in a register
; across a call, only on the stack.
;
; Params and locals are declared with plain %assign offsets, e.g.:
;
;   ; args: x, y, z
;   argnum 3
;   %assign x arg(1)
;   %assign y arg(2)
;   %assign z arg(3)
;
; and accessed as [rbp + x].  Required order in every function:
;   name: -> begin -> arg declarations -> local declarations ->
;   endlocal -> body -> end.

%ifndef ASMRT_INC
%define ASMRT_INC

default rel

; ---- custom ABI support macros ----

%macro begin 0
    push rbp
    mov  rbp, rsp
%endmacro

%macro end 0
    mov  rsp, rbp
    pop  rbp
%endmacro

; hexalign: pad rsp to 16-byte alignment before a real-ABI call. Under
; this ABI rsp is always at least 8-byte aligned, so it's only ever off
; by 0 or 8; no paired "undo" needed (end's mov rsp,rbp reclaims it).
%macro hexalign 0
    mov  rax, rsp
    and  rax, 8
    sub  rsp, rax
%endmacro

; preasm/postasm: save/restore every register (rax included), for
; calling into a custom-ABI function from inside a real-ABI callback
; (e.g. a C function-pointer callback) without clobbering what the
; real-ABI caller expects to survive. Stash any needed return value to
; memory before postasm -- it restores rax too.
%macro preasm 0
    sub  rsp, 128 ; 16 slots = 15 registers + 1 pad slot, keeps 16-byte alignment
    mov [rsp+0],   rax
    mov [rsp+8],   rbx
    mov [rsp+16],  rcx
    mov [rsp+24],  rdx
    mov [rsp+32],  rbp
    mov [rsp+40],  rsi
    mov [rsp+48],  rdi
    mov [rsp+56],  r8
    mov [rsp+64],  r9
    mov [rsp+72],  r10
    mov [rsp+80],  r11
    mov [rsp+88],  r12
    mov [rsp+96],  r13
    mov [rsp+104], r14
    mov [rsp+112], r15
%endmacro

%macro postasm 0
    mov r15, [rsp+112]
    mov r14, [rsp+104]
    mov r13, [rsp+96]
    mov r12, [rsp+88]
    mov r11, [rsp+80]
    mov r10, [rsp+72]
    mov r9,  [rsp+64]
    mov r8,  [rsp+56]
    mov rdi, [rsp+48]
    mov rsi, [rsp+40]
    mov rbp, [rsp+32]
    mov rdx, [rsp+24]
    mov rcx, [rsp+16]
    mov rbx, [rsp+8]
    mov rax, [rsp+0]
    add  rsp, 128
%endmacro

%macro resetOffset 0
    %assign offset 0
%endmacro

%macro incOffset 1
    %assign offset (offset + %1)
%endmacro

%macro decOffset 1
    %assign offset (offset - %1)
%endmacro

%macro argnum 1
    %assign __argnum %1
%endmacro

%define arg(i) (16 + (__argnum - i) * 8)

; struct ValueMeta
resetOffset
%assign ValueMeta_objsize offset
incOffset 8
%assign ValueMeta_align offset
incOffset 8
%assign ValueMeta_drop offset
incOffset 8
%assign ValueMeta_cmp offset
incOffset 8
%assign ValueMeta_eq offset
incOffset 8
%assign ValueMeta_hash offset
incOffset 8
%assign ValueMeta_copy offset
incOffset 8
%assign ValueMeta_move offset
incOffset 8
%assign sizeof_ValueMeta offset
; end struct ValueMeta

; struct Vec
resetOffset
%assign Vec_data offset
incOffset 8
%assign Vec_len offset
incOffset 8
%assign Vec_capacity offset
incOffset 8
%assign Vec_meta offset
incOffset 8
%assign sizeof_Vec offset
; end struct Vec

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
; memSwap(pA, pB, size) ; swap `size` bytes between pA and pB
extern memSwap

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

%define FNV_OFFSET_BASIS 0xcbf29ce484222325
; fnv64(pData, dataSize, input) -> hash ; FNV-1a 64-bit
extern fnv64

; vec.asm
; vecInit(pVec, pMeta) -> 0 ; zero the vec, attach the ValueMeta
extern vecInit
; vecWithCapacity(pVec, pMeta, capacity) -> 0 ; pre-allocate room
extern vecWithCapacity
; vecReserve(pVec, additional) ; grow to fit len+additional
extern vecReserve
; vecPush(pVec, pElem, isMove) ; append a copy of *pElem, or move it in when isMove != 0
extern vecPush
; vecPop(pVec, pOut) -> 1/0 ; copy last elem to *pOut (pOut may be NULL)
extern vecPop
; vecGet(pVec, index) -> pElem ; NULL if out of bounds
extern vecGet
; vecSet(pVec, index, pElem, isMove) ; replace elem at index with a copy, or by move when isMove != 0
extern vecSet
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
; vecInsert(pVec, index, pElem, isMove) ; insert elem at index (0..len);
; isMove != 0 moves elem in (ValueMeta.move), otherwise copies
extern vecInsert
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
