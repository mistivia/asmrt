#ifndef ASMRT_INC_
#define ASMRT_INC_

.intel_syntax noprefix

#define a0 rdi
#define a1 rsi
#define a2 rdx
#define a3 rcx
#define a4 r8
#define a5 r9

#define a0d edi
#define a1d esi
#define a2d edx
#define a3d ecx
#define a4d r8d
#define a5d r9d

#define a0w di
#define a1w si
#define a2w dx
#define a3w cx
#define a4w r8w
#define a5w r9w

#define a0b dil
#define a1b sil
#define a2b dl
#define a3b cl
#define a4b r8b
#define a5b r9b

#define a2h dh
#define a3h ch

#define t0 r10
#define t1 r11

#define t0d r10d
#define t1d r11d

#define t0w r10w
#define t1w r11w

#define t0b r10b
#define t1b r11b

#define s0 rbx
#define s1 r12
#define s2 r13
#define s3 r14
#define s4 r15

#define s0d ebx
#define s1d r12d
#define s2d r13d
#define s3d r14d
#define s4d r15d

#define s0w bx
#define s1w r12w
#define s2w r13w
#define s3w r14w
#define s4w r15w

#define s0b bl
#define s1b r12b
#define s2b r13b
#define s3b r14b
#define s4b r15b

#define s0h bh

#define r0 rax
#define r0d eax
#define r0w ax
#define r0b al
#define r0h ah

#define sp rsp
#define fp rbp

.macro begin
    push rbp
    mov  rbp, rsp
.endm

.macro return
    mov  rsp, rbp
    pop  rbp
    ret
.endm

// struct ValueMeta
.set ValueMeta_size,   0
.set ValueMeta_align,  4
.set ValueMeta_drop,   8
.set ValueMeta_cmp,    16
.set ValueMeta_eq,     24
.set ValueMeta_hash,   32
.set ValueMeta_copy,   40
.set ValueMeta_move,   48
.set sizeof_ValueMeta, 56

// struct Vec
.set Vec_data,     0
.set Vec_len,      8
.set Vec_capacity, 16
.set Vec_meta,     24
.set sizeof_Vec,   32

.set List_vhead,  0
.set List_vtail,  8
.set List_len,    16
.set List_meta,   24
.set sizeof_List, 32

// io.S
.extern ioWriteString

// assert.S
.extern assertTrue

// mem.S
.extern memCopy
.extern memMove
.extern memFill
.extern memSwap

/*
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
*/

#endif // ASMRT_INC
