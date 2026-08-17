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

; struct List
resetOffset
%assign List_vhead offset
incOffset 8
%assign List_vtail offset
incOffset 8
%assign List_len offset
incOffset 8
%assign List_pValueMeta offset
incOffset 8
%assign sizeof_List offset
; end struct List

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
; ioWriteString(fd, string) -> bytesWritten ; write a length-prefixed string
extern ioWriteString

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
; assert(pMsg, flag) -- if flag == 0, write pMsg (length-prefixed string)
; to stderr and exit(-1)
extern assert

; string.asm
;
; String layout (this module's convention):
;   string -> [ 8-byte len ][ data bytes ... ][ NUL ]
; where len counts chars, excluding the trailing NUL.  A string is a
; pointer (8 bytes) to that buffer; it can be a static literal
; (built with `dq len` + `db "..",0`) or a heap object allocated by
; stringFromRaw/CStr/... and released with stringDrop.
; The string pointer IS the value: a vec/list of strings stores one
; string per element and uses stringMeta (objsize = 8).  The ValueMeta
; callbacks receive the address of an element (a pointer to the 8-byte
; slot inside the container) and deref it once to get the string.
; stringLen(string) -> len ; chars, excluding the trailing NUL
extern stringLen
; stringEq(pA, pB) -> 1/0 ; element addresses; same len + byte-equal
extern stringEq
; stringCmp(pA, pB) -> <0/0/>0 ; element addresses; byte order, then length
extern stringCmp
; stringInit(pObj) ; empty string; pObj needs >= 9 usable bytes
extern stringInit
; stringFromCStr(pCStr) -> string ; alloc + copy a NUL-terminated C string
extern stringFromCStr
; stringFromRaw(pBuf, n) -> string ; alloc + copy exactly n bytes
extern stringFromRaw
; stringCopy(pDst, pSrc) ; deep-copy src element's string into dst element
extern stringCopy
; stringMove(pDst, pSrc) ; transfer ownership, zero the src element
extern stringMove
; stringDrop(pSlot) ; free the heap string an element points to, zero it
extern stringDrop
; stringCStr(string) -> pData ; pointer to the bytes (string+8)
extern stringCStr
; stringAt(string, index) -> ch ; 0 if out of range
extern stringAt
; stringHash(string) -> hash ; FNV-1a over the chars
extern stringHash
; stringSlotHash(pSlot) -> hash ; stringMeta's .hash callback (element addr)
extern stringSlotHash
; stringSubstring(string, start, endIdx) -> string ; clamped, start..endIdx
extern stringSubstring
; stringConcat(pA, pB) -> string ; a followed by b
extern stringConcat
; stringStartsWith(string, pPrefixStr) -> 1/0
extern stringStartsWith
; stringEndsWith(string, pSuffixStr) -> 1/0
extern stringEndsWith
; stringFind(string, pSubStr) -> index or -1 ; first occurrence
extern stringFind
; stringCount(string, pSubStr) -> count ; non-overlapping occurrences
extern stringCount
; stringLower(string) -> string ; A-Z -> a-z
extern stringLower
; stringUpper(string) -> string ; a-z -> A-Z
extern stringUpper
; stringCapitalize(string) -> string ; first upper, rest lower
extern stringCapitalize
; stringStrip(string) -> string ; trim ASCII whitespace both ends
extern stringStrip
; stringLStrip(string) -> string ; trim leading whitespace
extern stringLStrip
; stringRStrip(string) -> string ; trim trailing whitespace
extern stringRStrip
; stringRemovePrefix(string, pPrefixStr) -> string ; copy sans prefix when it matches
extern stringRemovePrefix
; stringRemoveSuffix(string, pSuffixStr) -> string ; copy sans suffix when it matches
extern stringRemoveSuffix
; stringSplit(pVec, string, pSepStr) -> pVec ; split on sep (empty -> whole string)
extern stringSplit
; stringSplitLines(pVec, string) -> pVec ; split on \n, strip trailing \r
extern stringSplitLines
; stringJoin(pVec, pSepStr) -> string ; concatenate string elements
extern stringJoin
; stringMeta ; ValueMeta describing a string element (objsize 8)
extern stringMeta

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

; list.asm
; listInit(pList, pMeta) -> 0 ; alloc sentinel nodes, attach the ValueMeta
extern listInit
; listDrop(pList) ; drop every elem, free all nodes incl. sentinels, reset in place
extern listDrop
; listClear(pList) ; drop every elem, keep sentinel nodes
extern listClear
; listCopy(pDst, pSrc) ; deep copy src into dst (no-op if same list)
extern listCopy
; listMove(pDst, pSrc) ; transfer ownership, reset pSrc
extern listMove
; listSwap(pA, pB) ; swap two whole list headers
extern listSwap
; listInsertBefore(pList, pIter, pElem, isMove) -> pNode ; insert elem before iter; isMove != 0 moves, else copies; NULL if iter invalid
extern listInsertBefore
; listInsertAfter(pList, pIter, pElem, isMove) -> pNode ; insert elem after iter; isMove != 0 moves, else copies; NULL if iter invalid
extern listInsertAfter
; listRemove(pList, pIter) ; drop elem, unlink and free the node
extern listRemove
; listSet(pList, pIter, pElem, isMove) ; replace elem at iter; isMove != 0 moves, else copies
extern listSet
; listBegin(pList) -> pNode ; first data node (or vtail sentinel if empty)
extern listBegin
; listLast(pList) -> pNode ; last data node, NULL if empty
extern listLast
; listEnd(pList) -> pNode ; the vtail sentinel
extern listEnd
; listNext(pIter) -> pNode ; iter->next; NULL if pIter is NULL
extern listNext
; listPrev(pIter) -> pNode ; iter->prev; NULL if pIter is NULL or would be vhead
extern listPrev
; listGet(pIter) -> pElem ; pointer to the node's element; NULL if pIter is NULL
extern listGet
; listLen(pList) -> len
extern listLen
; listIsEmpty(pList) -> 1/0
extern listIsEmpty
; listPushBack(pList, pElem, isMove) -> pNode ; append elem; isMove != 0 moves, else copies
extern listPushBack
; listPushFront(pList, pElem, isMove) -> pNode ; prepend elem; isMove != 0 moves, else copies
extern listPushFront
; listPopBack(pList) ; drop and remove the last elem
extern listPopBack
; listPopFront(pList) ; drop and remove the first elem
extern listPopFront
; listEq(pA, pB) -> 1/0 ; same len, element-wise eq via meta
extern listEq
; listCmp(pA, pB) -> -1/0/1 ; lexicographic
extern listCmp
; listHash(pList) -> hash ; FNV-1a over element hashes
extern listHash
; listMeta ; ValueMeta instance describing struct List itself
extern listMeta

%endif ; ASMRT_INC
