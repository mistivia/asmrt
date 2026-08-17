; str.asm -- length-prefixed string operations, custom ABI
;
; String layout (this module's convention):
;
;   pStr -> [ 8-byte len ][ data bytes ... ][ NUL ]
;
; len counts the characters, excluding the trailing NUL.  A string can
; be a static literal:
;
;   hello:
;       dq hello_end - hello_data - 1   ; chars only, no NUL
;   hello_data:
;       db "hello world", 0
;   hello_end:
;
; or a heap object returned by stringFromCStr/stringFromN/... and
; released with stringDrop.  Heap objects are one allocation of
; 8 + len + 1 bytes.
;
; The ValueMeta callbacks use "pStr-slot" semantics: the element is an
; 8-byte slot holding a pStr (pointer to the len-prefixed object).
; stringMeta therefore has objsize = 8, and vec/list<string> stores one
; pStr per element.  stringCopy/stringMove/stringDrop/stringEq/stringCmp all
; take slot pointers, which matches what ValueMeta callbacks receive.
;
; All memory goes through the runtime's memAlloc/memFree wrappers and
; byte shuffling through memCopy -- custom-ABI wrappers around libc,
; so no bare syscalls and no hexalign needed here.

%include "asmrt.inc"

section .data
    global stringMeta
stringMeta:
    dq 8                        ; .size (a pStr slot)
    dq 8                        ; .align
    dq stringDrop               ; .drop (slot pointer)
    dq stringCmp                ; .cmp (slot pointers)
    dq stringEq                ; .eq (slot pointers)
    dq stringSlotHash          ; .hash (slot pointer)
    dq stringCopy               ; .copy (slot pointers)
    dq stringMove               ; .move (slot pointers)

section .text
    global stringLen
    global stringEq
    global stringCmp
    global stringInit
    global stringFromCStr
    global stringFromN
    global stringCopy
    global stringMove
    global stringDrop
    global stringCStr
    global stringLen
    global stringAt
    global stringHash
    global stringSubstring
    global stringConcat
    global stringStartsWith
    global stringEndsWith
    global stringFind
    global stringCount
    global stringLower
    global stringUpper
    global stringCapitalize
    global stringStrip
    global stringLStrip
    global stringRStrip
    global stringRemovePrefix
    global stringRemoveSuffix
    global stringSplit
    global stringSplitLines
    global stringJoin
    global stringSlotHash
    extern memAlloc
    extern memFree
    extern memCopy
    extern fnv64
    extern vecInit
    extern vecPush
    extern vecGet
    extern vecLen

; ---- internal helpers ----

; cStrLen(pCStr) -> len ; scan a NUL-terminated C string
cStrLen:
    ; args: pCStr
    argnum 1
    %assign pCStr arg(1)
    begin
    mov rbx, [rbp + pCStr]
    xor rax, rax
.loop:
    cmp byte [rbx + rax], 0
    je .done
    inc rax
    jmp .loop
.done:
    end
    ret 8

; allocStr(len) -> pStr ; allocate 8+len+1 bytes, write the len prefix
; (data bytes and the NUL are the caller's job)
allocStr:
    ; args: len
    argnum 1
    %assign len arg(1)
    begin
    mov rax, [rbp + len]
    add rax, 9                  ; 8-byte prefix + len + NUL
    push rax
    call memAlloc               ; rax = pStr
    mov rbx, [rbp + len]
    mov [rax], rbx              ; write the len prefix
    end
    ret 8

; ---- length / comparison ----

; stringLen(pStr) -> len ; chars, excluding the trailing NUL
stringLen:
    ; args: pStr
    argnum 1
    %assign pStr arg(1)
    begin
    mov rax, [rbp + pStr]
    mov rax, [rax]              ; the len prefix is the answer
    end
    ret 8

; stringEq(pA, pB) -> 1/0 ; pA/pB are pStr slots (what ValueMeta
; callbacks receive); equal = same len + byte-for-byte identical data
stringEq:
    ; args: pA, pB
    argnum 2
    %assign pA arg(1)
    %assign pB arg(2)
    begin

    mov rax, [rbp + pA]
    mov rax, [rax]              ; pStrA
    mov rbx, [rbp + pB]
    mov rbx, [rbx]              ; pStrB
    mov rcx, [rax]              ; lenA
    cmp rcx, [rbx]
    jne .neq

    xor rdx, rdx                ; i
.loop:
    cmp rdx, rcx
    jae .eq
    mov rsi, [rax + 8 + rdx]
    cmp sil, [rbx + 8 + rdx]
    jne .neq
    inc rdx
    jmp .loop
.eq:
    mov rax, 1
    jmp .done
.neq:
    xor rax, rax
.done:

    end
    ret 16

; stringCmp(pA, pB) -> <0/0/>0 ; pStr slots; byte order first, length on tie
stringCmp:
    ; args: pA, pB
    argnum 2
    %assign pA arg(1)
    %assign pB arg(2)
    begin

    mov rax, [rbp + pA]
    mov rax, [rax]              ; pStrA
    mov rbx, [rbp + pB]
    mov rbx, [rbx]              ; pStrB
    mov rcx, [rax]              ; lenA
    mov rdx, [rbx]              ; lenB

    ; minLen = rcx < rdx ? rcx : rdx ; also keep the full lens
    mov r8, rcx
    cmp rcx, rdx
    jbe .haveMin
    mov r8, rdx
.haveMin:
    xor r9, r9                  ; i
.loop:
    cmp r9, r8
    jae .compareLens
    mov sil, [rax + 8 + r9]
    mov dil, [rbx + 8 + r9]
    cmp sil, dil
    je .next
    movzx rax, sil
    movzx rbx, dil
    sub rax, rbx
    jmp .done
.next:
    inc r9
    jmp .loop
.compareLens:
    cmp rcx, rdx
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

; ---- construction / destruction ----

; stringInit(pObj) ; initialise an empty string in caller-provided storage
; (needs >= 9 usable bytes).  Returns 0.
stringInit:
    ; args: pObj
    argnum 1
    %assign pObj arg(1)
    begin
    mov rax, [rbp + pObj]
    mov qword [rax], 0          ; len = 0
    mov byte [rax + 8], 0       ; data[0] = NUL
    xor rax, rax
    end
    ret 8

; stringFromCStr(pOut, pCStr) -> pStr ; heap string from a C string
stringFromCStr:
    ; args: pOut, pCStr
    argnum 2
    %assign pOut arg(1)
    %assign pCStr arg(2)
    begin

    push [rbp + pCStr]
    call cStrLen                ; rax = strlen
    push [rbp + pOut]
    push [rbp + pCStr]
    push rax
    call stringFromN

    end
    ret 16

; stringFromN(pOut, pBuf, n) -> pStr ; heap string from n raw bytes
stringFromN:
    ; args: pOut, pBuf, n
    argnum 3
    %assign pOut arg(1)
    %assign pBuf arg(2)
    %assign n arg(3)
    begin
    ; local variables
    resetOffset
    ; pStr 8 bytes
    decOffset 8
    %assign pStr offset
    ; endlocal
    sub rsp, (-offset)

    push [rbp + n]
    call allocStr
    mov [rbp + pStr], rax

    ; data bytes = memCopy(pStr+8, pBuf, n)
    mov rax, [rbp + pStr]
    add rax, 8
    push rax
    push [rbp + pBuf]
    push [rbp + n]
    call memCopy

    ; trailing NUL
    mov rax, [rbp + pStr]
    mov rbx, [rbp + n]
    mov byte [rax + 8 + rbx], 0

    ; store into the slot and return
    mov rax, [rbp + pStr]
    mov rbx, [rbp + pOut]
    mov [rbx], rax

    end
    ret 24

; stringDrop(pSlot) ; free the heap string a slot points to, zero the slot
stringDrop:
    ; args: pSlot
    argnum 1
    %assign pSlot arg(1)
    begin

    mov rax, [rbp + pSlot]
    mov rax, [rax]              ; pStr (NULL slot -> nothing to do)
    test rax, rax
    jz .done
    push rax
    call memFree
    mov rax, [rbp + pSlot]
    mov qword [rax], 0
.done:

    end
    ret 8

; stringCopy(pDst, pSrc) ; deep-copy src slot's string into dst slot
; (stringMeta's .copy callback; dst slot is expected to be empty)
stringCopy:
    ; args: pDst, pSrc
    argnum 2
    %assign pDst arg(1)
    %assign pSrc arg(2)
    begin

    mov rax, [rbp + pSrc]
    mov rax, [rax]              ; pStr
    mov rbx, [rax]              ; len
    push [rbp + pDst]
    add rax, 8                  ; data starts after the 8-byte len prefix
    push rax
    push rbx
    call stringFromN

    end
    ret 16

; stringMove(pDst, pSrc) ; transfer ownership, zero the src slot
; (stringMeta's .move callback)
stringMove:
    ; args: pDst, pSrc
    argnum 2
    %assign pDst arg(1)
    %assign pSrc arg(2)
    begin

    mov rax, [rbp + pDst]
    cmp rax, [rbp + pSrc]
    je .done

    mov rbx, [rbp + pSrc]
    mov rcx, [rbx]              ; pStr
    mov rax, [rbp + pDst]
    mov [rax], rcx
    mov qword [rbx], 0          ; src slot empty
.done:

    end
    ret 16

; ---- access ----

; stringCStr(pStr) -> pData ; pointer to the chars (NUL-terminated)
stringCStr:
    ; args: pStr
    argnum 1
    %assign pStr arg(1)
    begin
    mov rax, [rbp + pStr]
    add rax, 8
    end
    ret 8


; stringAt(pStr, index) -> ch ; 0 when out of range
stringAt:
    ; args: pStr, index
    argnum 2
    %assign pStr arg(1)
    %assign stringAt_index arg(2)
    begin

    mov rax, [rbp + pStr]
    mov rcx, [rbp + stringAt_index]
    cmp rcx, [rax]
    jae .oob
    movzx rax, byte [rax + 8 + rcx]
    jmp .done
.oob:
    xor rax, rax
.done:

    end
    ret 16

; stringHash(pStr) -> hash ; FNV-1a over the chars
stringHash:
    ; args: pStr
    argnum 1
    %assign pStr arg(1)
    begin

    mov rax, [rbp + pStr]
    add rax, 8
    push rax
    mov rax, [rbp + pStr]
    mov rax, [rax]
    push rax
    mov rax, FNV_OFFSET_BASIS
    push rax
    call fnv64

    end
    ret 8

; stringSlotHash(pSlot) -> hash ; stringMeta's .hash callback (slot ptr)
stringSlotHash:
    ; args: pSlot
    argnum 1
    %assign pSlot arg(1)
    begin
    mov rax, [rbp + pSlot]
    mov rax, [rax]              ; pStr
    push rax
    call stringHash
    end
    ret 8

; ---- slicing / concatenation ----

; stringSubstring(pOut, pStr, start, endIdx) -> pStr ; chars [start, endIdx),
; indices clamped to [0, len]; start >= endIdx yields the empty string
stringSubstring:
    ; args: pOut, pStr, start, endIdx
    argnum 4
    %assign pOut arg(1)
    %assign pStr arg(2)
    %assign start arg(3)
    %assign stringSubstring_endIdx arg(4)
    begin
    ; local variables
    resetOffset
    ; s 8 bytes
    decOffset 8
    %assign s offset
    ; e 8 bytes
    decOffset 8
    %assign e offset
    ; pResult 8 bytes
    decOffset 8
    %assign pResult offset
    ; endlocal
    sub rsp, (-offset)

    mov rax, [rbp + pStr]
    mov rbx, [rax]              ; len
    mov rax, [rbp + start]
    test rax, rax
    jns .startOk
    xor rax, rax
.startOk:
    mov [rbp + s], rax
    mov rax, [rbp + stringSubstring_endIdx]
    cmp rax, rbx
    jle .endOk
    mov rax, rbx
.endOk:
    mov [rbp + e], rax

    mov rax, [rbp + s]
    cmp rax, [rbp + e]
    jge .empty

    ; slice length
    mov rax, [rbp + e]
    sub rax, [rbp + s]
    push rax
    call allocStr
    mov [rbp + pResult], rax

    ; copy the slice into the new object
    mov rax, [rbp + pStr]
    mov rbx, [rbp + s]
    add rax, rbx
    add rax, 8                  ; src = pStr+8+start
    mov rcx, [rbp + pResult]
    add rcx, 8                  ; dst = result+8
    mov rdx, [rbp + e]
    sub rdx, [rbp + s]          ; n = end-start
    push rcx
    push rax
    push rdx
    call memCopy

    ; trailing NUL
    mov rax, [rbp + pResult]
    mov rbx, [rbp + e]
    sub rbx, [rbp + s]
    mov byte [rax + 8 + rbx], 0

    mov rax, [rbp + pResult]
    mov rbx, [rbp + pOut]
    mov [rbx], rax
    jmp .done

.empty:
    ; result = empty string (static empty object)
    mov rax, [rbp + pOut]
    lea rbx, [rel emptyStr]
    mov [rax], rbx
    lea rax, [rel emptyStr]
.done:

    end
    ret 32

; stringConcat(pOut, pA, pB) -> pStr ; a followed by b
stringConcat:
    ; args: pOut, pA, pB
    argnum 3
    %assign pOut arg(1)
    %assign pA arg(2)
    %assign pB arg(3)
    begin
    ; local variables
    resetOffset
    ; pResult 8 bytes
    decOffset 8
    %assign pResult offset
    ; la 8 bytes
    decOffset 8
    %assign la offset
    ; endlocal
    sub rsp, (-offset)

    mov rax, [rbp + pA]
    mov rax, [rax]              ; lenA
    mov [rbp + la], rax
    mov rbx, [rbp + pB]
    mov rbx, [rbx]              ; lenB
    add rax, rbx
    push rax
    call allocStr
    mov [rbp + pResult], rax

    ; copy A's bytes
    mov rax, [rbp + pResult]
    add rax, 8
    push rax
    mov rax, [rbp + pA]
    add rax, 8
    push rax
    push [rbp + la]
    call memCopy

    ; copy B's bytes
    mov rax, [rbp + pResult]
    add rax, 8
    add rax, [rbp + la]
    push rax
    mov rax, [rbp + pB]
    add rax, 8
    push rax
    mov rax, [rbp + pB]
    mov rax, [rax]
    push rax
    call memCopy

    ; trailing NUL: write at offset 8 + (lenA + lenB)
    mov rax, [rbp + pResult]
    mov rbx, [rbp + pA]
    mov rbx, [rbx]
    mov rcx, [rbp + pB]
    mov rcx, [rcx]
    add rbx, rcx
    mov byte [rax + 8 + rbx], 0

    mov rax, [rbp + pResult]
    mov rbx, [rbp + pA]
    mov rbx, [rbx]
    mov rcx, [rbp + pB]
    mov rcx, [rcx]
    add rbx, rcx
    mov byte [rax + 8 + rbx], 0

    mov rax, [rbp + pResult]
    mov rbx, [rbp + pOut]
    mov [rbx], rax

    end
    ret 24

; ---- prefix / suffix / search ----

; stringStartsWith(pStr, pPrefixStr) -> 1/0
stringStartsWith:
    ; args: pStr, pPrefixStr
    argnum 2
    %assign pStr arg(1)
    %assign pPrefixStr arg(2)
    begin

    mov rbx, [rbp + pPrefixStr]
    mov rax, [rbx]              ; plen
    mov rcx, [rbp + pStr]
    mov rcx, [rcx]              ; len
    cmp rax, rcx
    ja .no

    ; compare the first plen bytes
    mov rdx, rax                ; plen
    xor r8, r8                  ; i
    mov rax, [rbp + pStr]
    add rax, 8
    mov rbx, [rbp + pPrefixStr]
    add rbx, 8                  ; prefix data
.cmpLoop:
    cmp r8, rdx
    jae .yes
    mov sil, [rax + r8]
    cmp sil, [rbx + r8]
    jne .no
    inc r8
    jmp .cmpLoop
.yes:
    mov rax, 1
    jmp .done
.no:
    xor rax, rax
.done:

    end
    ret 16

; stringEndsWith(pStr, pSuffixStr) -> 1/0
stringEndsWith:
    ; args: pStr, pSuffixStr
    argnum 2
    %assign pStr arg(1)
    %assign pSuffixStr arg(2)
    begin

    mov rbx, [rbp + pSuffixStr]
    mov rax, [rbx]              ; slen
    mov rcx, [rbp + pStr]
    mov rcx, [rcx]              ; len
    cmp rax, rcx
    ja .no

    mov rdx, rax                ; slen
    sub rcx, rdx                ; offset = len - slen
    xor r8, r8                  ; i
    mov rax, [rbp + pStr]
    add rax, 8
    add rax, rcx                ; data + len - slen
    mov rbx, [rbp + pSuffixStr]
    add rbx, 8                  ; suffix data
.cmpLoop:
    cmp r8, rdx
    jae .yes
    mov sil, [rax + r8]
    cmp sil, [rbx + r8]
    jne .no
    inc r8
    jmp .cmpLoop
.yes:
    mov rax, 1
    jmp .done
.no:
    xor rax, rax
.done:

    end
    ret 16

; stringFind(pStr, pSubStr) -> index or -1 ; first occurrence of sub
stringFind:
    ; args: pStr, pSubStr
    argnum 2
    %assign pStr arg(1)
    %assign pSubStr arg(2)
    begin
    ; local variables
    resetOffset
    ; subLen 8 bytes
    decOffset 8
    %assign subLen offset
    ; i 8 bytes
    decOffset 8
    %assign i offset
    ; limit 8 bytes
    decOffset 8
    %assign limit offset
    ; endlocal
    sub rsp, (-offset)

    mov rax, [rbp + pSubStr]
    mov rax, [rax]
    mov [rbp + subLen], rax

    cmp rax, 0
    je .found0

    mov rax, [rbp + pStr]
    mov rax, [rax]              ; len
    mov rbx, [rbp + subLen]
    cmp rax, rbx
    jb .notFound

    mov rbx, [rbp + subLen]
    sub rax, rbx                ; limit = len - subLen
    mov [rbp + limit], rax

    mov qword [rbp + i], 0
.outer:
    mov rax, [rbp + i]
    cmp rax, [rbp + limit]
    ja .notFound

    ; try matching sub at [i]
    xor r8, r8                  ; j
    mov rax, [rbp + pStr]
    add rax, 8
    add rax, [rbp + i]
    mov rbx, [rbp + pSubStr]
    add rbx, 8                  ; sub data
.inner:
    mov rcx, [rbp + subLen]
    cmp r8, rcx
    jae .matchFound
    mov sil, [rax + r8]
    cmp sil, [rbx + r8]
    jne .noMatchAtI
    inc r8
    jmp .inner
.noMatchAtI:
    inc qword [rbp + i]
    jmp .outer
.matchFound:
    mov rax, [rbp + i]
    jmp .done
.found0:
    xor rax, rax
    jmp .done
.notFound:
    mov rax, -1
.done:

    end
    ret 16

; stringCount(pStr, pSubStr) -> count ; non-overlapping occurrences
stringCount:
    ; args: pStr, pSubStr
    argnum 2
    %assign pStr arg(1)
    %assign pSubStr arg(2)
    begin
    ; local variables
    resetOffset
    ; subLen 8 bytes
    decOffset 8
    %assign subLen offset
    ; i 8 bytes
    decOffset 8
    %assign i offset
    ; cnt 8 bytes
    decOffset 8
    %assign cnt offset
    ; limit 8 bytes
    decOffset 8
    %assign limit offset
    ; endlocal
    sub rsp, (-offset)

    mov rax, [rbp + pSubStr]
    mov rax, [rax]
    mov [rbp + subLen], rax

    mov rax, [rbp + pStr]
    mov rax, [rax]              ; len
    cmp qword [rbp + subLen], 0
    je .countEmpty

    mov rbx, [rbp + subLen]
    cmp rax, rbx
    jb .zero

    mov rbx, [rbp + subLen]
    sub rax, rbx
    mov [rbp + limit], rax
    mov qword [rbp + i], 0
    mov qword [rbp + cnt], 0

.outer:
    mov rax, [rbp + i]
    cmp rax, [rbp + limit]
    ja .doneCnt

    ; try matching at [i]
    xor r8, r8
    mov rax, [rbp + pStr]
    add rax, 8
    add rax, [rbp + i]
    mov rbx, [rbp + pSubStr]
    add rbx, 8                  ; sub data
.inner:
    mov rcx, [rbp + subLen]
    cmp r8, rcx
    jae .matchAtI
    mov sil, [rax + r8]
    cmp sil, [rbx + r8]
    jne .noMatchAtI
    inc r8
    jmp .inner
.matchAtI:
    ; count it, skip past the match (non-overlapping)
    inc qword [rbp + cnt]
    mov rax, [rbp + i]
    add rax, [rbp + subLen]
    mov [rbp + i], rax
    jmp .outer
.noMatchAtI:
    inc qword [rbp + i]
    jmp .outer
.countEmpty:
    ; empty needle: convention is len+1 (cbase)
    inc rax
    jmp .done
.zero:
    xor rax, rax
    jmp .done
.doneCnt:
    mov rax, [rbp + cnt]
.done:

    end
    ret 16

; ---- case / whitespace transforms ----

; stringLower(pOut, pStr) -> pStr ; A-Z -> a-z
stringLower:
    ; args: pOut, pStr
    argnum 2
    %assign pOut arg(1)
    %assign pStr arg(2)
    begin
    ; local variables
    resetOffset
    ; pResult 8 bytes
    decOffset 8
    %assign pResult offset
    ; len 8 bytes
    decOffset 8
    %assign len offset
    ; i 8 bytes
    decOffset 8
    %assign i offset
    ; endlocal
    sub rsp, (-offset)

    mov rax, [rbp + pStr]
    mov rax, [rax]
    mov [rbp + len], rax

    push rax
    call allocStr
    mov [rbp + pResult], rax

    mov qword [rbp + i], 0
.loop:
    mov rax, [rbp + i]
    cmp rax, [rbp + len]
    jae .finish

    mov rax, [rbp + pStr]
    mov rbx, [rbp + i]
    movzx rcx, byte [rax + 8 + rbx]
    ; is A-Z?
    cmp rcx, 'A'
    jb .store
    cmp rcx, 'Z'
    ja .store
    add rcx, 32                 ; to a-z
.store:
    mov rax, [rbp + pResult]
    mov rbx, [rbp + i]
    mov [rax + 8 + rbx], cl

    inc qword [rbp + i]
    jmp .loop
.finish:
    mov rax, [rbp + pResult]
    mov rbx, [rbp + len]
    mov byte [rax + 8 + rbx], 0 ; NUL

    mov rax, [rbp + pResult]
    mov rbx, [rbp + pOut]
    mov [rbx], rax

    end
    ret 16

; stringUpper(pOut, pStr) -> pStr ; a-z -> A-Z
stringUpper:
    ; args: pOut, pStr
    argnum 2
    %assign pOut arg(1)
    %assign pStr arg(2)
    begin
    ; local variables
    resetOffset
    ; pResult 8 bytes
    decOffset 8
    %assign pResult offset
    ; len 8 bytes
    decOffset 8
    %assign len offset
    ; i 8 bytes
    decOffset 8
    %assign i offset
    ; endlocal
    sub rsp, (-offset)

    mov rax, [rbp + pStr]
    mov rax, [rax]
    mov [rbp + len], rax

    push rax
    call allocStr
    mov [rbp + pResult], rax

    mov qword [rbp + i], 0
.loop:
    mov rax, [rbp + i]
    cmp rax, [rbp + len]
    jae .finish

    mov rax, [rbp + pStr]
    mov rbx, [rbp + i]
    movzx rcx, byte [rax + 8 + rbx]
    ; is a-z?
    cmp rcx, 'a'
    jb .store
    cmp rcx, 'z'
    ja .store
    sub rcx, 32                 ; to A-Z
.store:
    mov rax, [rbp + pResult]
    mov rbx, [rbp + i]
    mov [rax + 8 + rbx], cl

    inc qword [rbp + i]
    jmp .loop
.finish:
    mov rax, [rbp + pResult]
    mov rbx, [rbp + len]
    mov byte [rax + 8 + rbx], 0 ; NUL

    mov rax, [rbp + pResult]
    mov rbx, [rbp + pOut]
    mov [rbx], rax

    end
    ret 16

; stringCapitalize(pOut, pStr) -> pStr ; first char upper, rest lower
stringCapitalize:
    ; args: pOut, pStr
    argnum 2
    %assign pOut arg(1)
    %assign pStr arg(2)
    begin
    ; local variables
    resetOffset
    ; pResult 8 bytes
    decOffset 8
    %assign pResult offset
    ; len 8 bytes
    decOffset 8
    %assign len offset
    ; i 8 bytes
    decOffset 8
    %assign i offset
    ; endlocal
    sub rsp, (-offset)

    mov rax, [rbp + pStr]
    mov rax, [rax]
    mov [rbp + len], rax

    push rax
    call allocStr
    mov [rbp + pResult], rax

    mov qword [rbp + i], 0
.loop:
    mov rax, [rbp + i]
    cmp rax, [rbp + len]
    jae .finish

    mov rax, [rbp + pStr]
    mov rbx, [rbp + i]
    movzx rcx, byte [rax + 8 + rbx]
    cmp qword [rbp + i], 0
    je .firstChar
    ; rest: tolower
    cmp rcx, 'A'
    jb .store
    cmp rcx, 'Z'
    ja .store
    add rcx, 32
    jmp .store
.firstChar:
    ; first: toupper
    cmp rcx, 'a'
    jb .store
    cmp rcx, 'z'
    ja .store
    sub rcx, 32
.store:
    mov rax, [rbp + pResult]
    mov rbx, [rbp + i]
    mov [rax + 8 + rbx], cl

    inc qword [rbp + i]
    jmp .loop
.finish:
    mov rax, [rbp + pResult]
    mov rbx, [rbp + len]
    mov byte [rax + 8 + rbx], 0 ; NUL

    mov rax, [rbp + pResult]
    mov rbx, [rbp + pOut]
    mov [rbx], rax

    end
    ret 16

; isSpace(ch) -> 1/0 ; ASCII whitespace: space, tab, LF, VT, FF, CR
isSpace:
    ; args: ch
    argnum 1
    %assign ch arg(1)
    begin
    mov rax, [rbp + ch]
    cmp rax, 0x20
    je .yes
    cmp rax, 0x09
    je .yes
    cmp rax, 0x0A
    je .yes
    cmp rax, 0x0B
    je .yes
    cmp rax, 0x0C
    je .yes
    cmp rax, 0x0D
    je .yes
    xor rax, rax
    jmp .done
.yes:
    mov rax, 1
.done:
    end
    ret 8

; stringStrip(pOut, pStr) -> pStr ; trim ASCII whitespace both ends
stringStrip:
    ; args: pOut, pStr
    argnum 2
    %assign pOut arg(1)
    %assign pStr arg(2)
    begin
    ; local variables
    resetOffset
    ; start 8 bytes
    decOffset 8
    %assign start offset
    ; e 8 bytes
    decOffset 8
    %assign e offset
    ; ch 8 bytes
    decOffset 8
    %assign ch offset
    ; endlocal
    sub rsp, (-offset)

    mov rax, [rbp + pStr]
    mov rax, [rax]              ; len
    mov [rbp + e], rax
    mov qword [rbp + start], 0

    ; scan forward
.lstrip:
    mov rax, [rbp + start]
    cmp rax, [rbp + e]
    jae .doneScan
    mov rax, [rbp + pStr]
    mov rbx, [rbp + start]
    movzx rax, byte [rax + 8 + rbx]
    mov [rbp + ch], rax
    push [rbp + ch]
    call isSpace
    test rax, rax
    jz .doneScan
    inc qword [rbp + start]
    jmp .lstrip
.doneScan:
    ; scan backward
.rstrip:
    mov rax, [rbp + e]
    cmp rax, [rbp + start]
    jbe .slice
    mov rax, [rbp + pStr]
    mov rbx, [rbp + e]
    movzx rax, byte [rax + 7 + rbx]     ; data[e-1] = pStr[8+e-1]
    mov [rbp + ch], rax
    push [rbp + ch]
    call isSpace
    test rax, rax
    jz .slice
    dec qword [rbp + e]
    jmp .rstrip
.slice:
    ; result = substring(start, e)
    push [rbp + pOut]
    push [rbp + pStr]
    push [rbp + start]
    push [rbp + e]
    call stringSubstring

    end
    ret 16

; stringLStrip(pOut, pStr) -> pStr ; trim leading whitespace
stringLStrip:
    ; args: pOut, pStr
    argnum 2
    %assign pOut arg(1)
    %assign pStr arg(2)
    begin
    ; local variables
    resetOffset
    ; start 8 bytes
    decOffset 8
    %assign start offset
    ; ch 8 bytes
    decOffset 8
    %assign ch offset
    ; endlocal
    sub rsp, (-offset)

    mov qword [rbp + start], 0
.lstrip:
    mov rax, [rbp + pStr]
    mov rax, [rax]              ; len
    cmp [rbp + start], rax
    jae .slice
    mov rax, [rbp + pStr]
    mov rbx, [rbp + start]
    movzx rax, byte [rax + 8 + rbx]
    mov [rbp + ch], rax
    push [rbp + ch]
    call isSpace
    test rax, rax
    jz .slice
    inc qword [rbp + start]
    jmp .lstrip
.slice:
    ; result = substring(start, len)
    push [rbp + pOut]
    push [rbp + pStr]
    push [rbp + start]
    mov rax, [rbp + pStr]
    mov rax, [rax]
    push rax
    call stringSubstring

    end
    ret 16

; stringRStrip(pOut, pStr) -> pStr ; trim trailing whitespace
stringRStrip:
    ; args: pOut, pStr
    argnum 2
    %assign pOut arg(1)
    %assign pStr arg(2)
    begin
    ; local variables
    resetOffset
    ; e 8 bytes
    decOffset 8
    %assign e offset
    ; ch 8 bytes
    decOffset 8
    %assign ch offset
    ; endlocal
    sub rsp, (-offset)

    mov rax, [rbp + pStr]
    mov rax, [rax]
    mov [rbp + e], rax
.rstrip:
    cmp qword [rbp + e], 0
    je .slice
    mov rax, [rbp + pStr]
    mov rbx, [rbp + e]
    movzx rax, byte [rax + 7 + rbx]     ; data[e-1]
    mov [rbp + ch], rax
    push [rbp + ch]
    call isSpace
    test rax, rax
    jz .slice
    dec qword [rbp + e]
    jmp .rstrip
.slice:
    ; result = substring(0, e)
    push [rbp + pOut]
    push [rbp + pStr]
    push 0
    push [rbp + e]
    call stringSubstring

    end
    ret 16

; ---- prefix / suffix removal ----

; stringRemovePrefix(pOut, pStr, pPrefixStr) -> pStr ; copy sans prefix when it matches
stringRemovePrefix:
    ; args: pOut, pStr, pPrefixStr
    argnum 3
    %assign pOut arg(1)
    %assign pStr arg(2)
    %assign pPrefixStr arg(3)
    begin

    push [rbp + pStr]
    push [rbp + pPrefixStr]
    call stringStartsWith
    test rax, rax
    jz .copyAll

    ; prefix matches: slice [plen, len)
    mov rax, [rbp + pPrefixStr]
    mov rax, [rax]              ; plen
    mov rbx, [rbp + pStr]
    mov rbx, [rbx]              ; len
    push [rbp + pOut]
    push [rbp + pStr]
    push rax
    push rbx
    call stringSubstring
    jmp .done
.copyAll:
    ; just copy the whole string
    push [rbp + pOut]
    push [rbp + pStr]
    call stringCopy
    ; stringCopy returns via slot; rax from stringCopy is pStr but we
    ; return the slot's value for consistency
    mov rax, [rbp + pOut]
    mov rax, [rax]
.done:

    end
    ret 24

; stringRemoveSuffix(pOut, pStr, pSuffixStr) -> pStr ; copy sans suffix when it matches
stringRemoveSuffix:
    ; args: pOut, pStr, pSuffixStr
    argnum 3
    %assign pOut arg(1)
    %assign pStr arg(2)
    %assign pSuffixStr arg(3)
    begin

    push [rbp + pStr]
    push [rbp + pSuffixStr]
    call stringEndsWith
    test rax, rax
    jz .copyAll

    ; suffix matches: slice [0, len-slen)
    mov rax, [rbp + pSuffixStr]
    mov rax, [rax]              ; slen
    mov rbx, [rbp + pStr]
    mov rbx, [rbx]              ; len
    sub rbx, rax                ; len - slen
    push [rbp + pOut]
    push [rbp + pStr]
    push 0
    push rbx
    call stringSubstring
    jmp .done
.copyAll:
    push [rbp + pOut]
    push [rbp + pStr]
    call stringCopy
    mov rax, [rbp + pOut]
    mov rax, [rax]
.done:

    end
    ret 24

; ---- split / join ----

; stringSplit(pVec, pStr, pSepStr) -> pVec ; split on sep
; (empty-string separator -> vec with the whole string as one element)
stringSplit:
    ; args: pVec, pStr, pSepStr
    argnum 3
    %assign pVec arg(1)
    %assign pStr arg(2)
    %assign pSepStr arg(3)
    begin
    ; local variables
    resetOffset
    ; sepLen 8 bytes
    decOffset 8
    %assign sepLen offset
    ; start 8 bytes
    decOffset 8
    %assign start offset
    ; i 8 bytes
    decOffset 8
    %assign i offset
    ; part 8 bytes ; pStr slot
    decOffset 8
    %assign part offset
    ; endlocal
    sub rsp, (-offset)

    push [rbp + pVec]
    push stringMeta
    call vecInit

    mov rax, [rbp + pSepStr]
    mov rax, [rax]
    mov [rbp + sepLen], rax

    cmp rax, 0
    jne .normal

    ; empty separator: whole string is one element
    mov rax, [rbp + pStr]
    mov rax, [rax]              ; len = whole string length
    mov [rbp + i], rax
    ; stringSubstring(part, pStr, 0, len)
    lea rax, [rbp + part]
    push rax
    push [rbp + pStr]
    push 0
    push [rbp + i]
    call stringSubstring
    push [rbp + pVec]
    lea rax, [rbp + part]
    push rax
    push 1                      ; isMove=1
    call vecPush
    jmp .done

.normal:
    mov qword [rbp + start], 0
    mov qword [rbp + i], 0
.scan:
    mov rax, [rbp + pStr]
    mov rax, [rax]
    mov rbx, [rbp + sepLen]
    sub rax, rbx
    cmp [rbp + i], rax
    ja .tail

    ; try match sep at i
    xor r8, r8
    mov rax, [rbp + pStr]
    add rax, 8
    add rax, [rbp + i]
    mov rbx, [rbp + pSepStr]
    add rbx, 8                  ; sep data
.matchLoop:
    mov rcx, [rbp + sepLen]
    cmp r8, rcx
    jae .matchAtI
    mov sil, [rax + r8]
    cmp sil, [rbx + r8]
    jne .noMatch
    inc r8
    jmp .matchLoop
.matchAtI:
    ; slice [start, i)
    lea rax, [rbp + part]
    push rax
    push [rbp + pStr]
    push [rbp + start]
    push [rbp + i]
    call stringSubstring
    push [rbp + pVec]
    lea rax, [rbp + part]
    push rax
    push 1                      ; isMove=1
    call vecPush

    mov rax, [rbp + i]
    add rax, [rbp + sepLen]
    mov [rbp + i], rax
    mov [rbp + start], rax
    jmp .scan
.noMatch:
    inc qword [rbp + i]
    jmp .scan
.tail:
    ; slice [start, len)
    mov rax, [rbp + pStr]
    mov rax, [rax]              ; len
    lea rbx, [rbp + part]
    push rbx
    push [rbp + pStr]
    push [rbp + start]
    push rax
    call stringSubstring
    push [rbp + pVec]
    lea rax, [rbp + part]
    push rax
    push 1                      ; isMove=1
    call vecPush
.done:
    mov rax, [rbp + pVec]

    end
    ret 24

; stringSplitLines(pVec, pStr) -> pVec ; split on '\n', strip trailing '\r'
stringSplitLines:
    ; args: pVec, pStr
    argnum 2
    %assign pVec arg(1)
    %assign pStr arg(2)
    begin
    ; local variables
    resetOffset
    ; start 8 bytes
    decOffset 8
    %assign start offset
    ; i 8 bytes
    decOffset 8
    %assign i offset
    ; part 8 bytes
    decOffset 8
    %assign part offset
    ; endlocal
    sub rsp, (-offset)

    push [rbp + pVec]
    push stringMeta
    call vecInit

    mov qword [rbp + start], 0
    mov qword [rbp + i], 0
.scan:
    mov rax, [rbp + pStr]
    mov rax, [rax]              ; len
    cmp [rbp + i], rax
    jae .tail

    mov rax, [rbp + pStr]
    mov rbx, [rbp + i]
    movzx rax, byte [rax + 8 + rbx]
    cmp rax, 10
    jne .next

    ; line = [start, i), minus a trailing '\r'
    mov rax, [rbp + i]
    cmp rax, [rbp + start]
    je .emptyLine
    mov rax, [rbp + pStr]
    mov rbx, [rbp + i]
    movzx rax, byte [rax + 7 + rbx]
    cmp rax, 13
    jne .noCr
    dec qword [rbp + i]
.noCr:
    lea rax, [rbp + part]
    push rax
    push [rbp + pStr]
    push [rbp + start]
    push [rbp + i]
    call stringSubstring
    push [rbp + pVec]
    lea rax, [rbp + part]
    push rax
    push 1                      ; isMove=1
    call vecPush
    jmp .lineDone
.emptyLine:
    ; empty line -> push an empty string
    lea rax, [rbp + part]
    push rax
    push [rbp + pStr]
    push 0
    push 0
    call stringSubstring        ; start=0, end=0 -> empty
    push [rbp + pVec]
    lea rax, [rbp + part]
    push rax
    push 1
    call vecPush
.lineDone:
    ; i points at the '\n'; next line starts after it
    mov rax, [rbp + i]
    inc rax
    mov [rbp + i], rax
    mov [rbp + start], rax
    jmp .scan
.next:
    inc qword [rbp + i]
    jmp .scan
.tail:
    ; tail line [start, len) unless empty (trailing newline)
    mov rax, [rbp + pStr]
    mov rax, [rax]
    cmp [rbp + start], rax
    jae .done

    ; strip trailing '\r' from the last line too
    mov rax, [rbp + pStr]
    mov rbx, [rax]              ; len
    movzx rax, byte [rax + 7 + rbx]
    cmp rax, 13
    jne .tailNoCr
    mov rax, [rbp + pStr]
    mov rax, [rax]
    dec rax
    mov [rbp + i], rax
    jmp .tailSlice
.tailNoCr:
    mov rax, [rbp + pStr]
    mov rax, [rax]
    mov [rbp + i], rax
.tailSlice:
    lea rax, [rbp + part]
    push rax
    push [rbp + pStr]
    push [rbp + start]
    push [rbp + i]
    call stringSubstring
    push [rbp + pVec]
    lea rax, [rbp + part]
    push rax
    push 1
    call vecPush
.done:
    mov rax, [rbp + pVec]

    end
    ret 16

; stringJoin(pOut, pVec, pSepStr) -> pStr ; concatenate pStr elements
; with sep between them (empty sep -> plain concatenation)
stringJoin:
    ; args: pOut, pVec, pSepStr
    argnum 3
    %assign pOut arg(1)
    %assign pVec arg(2)
    %assign pSepStr arg(3)
    begin
    ; local variables
    resetOffset
    ; sepLen 8 bytes
    decOffset 8
    %assign sepLen offset
    ; count 8 bytes
    decOffset 8
    %assign stringJoin_count offset
    ; total 8 bytes
    decOffset 8
    %assign total offset
    ; i 8 bytes
    decOffset 8
    %assign i offset
    ; pResult 8 bytes
    decOffset 8
    %assign pResult offset
    ; pos 8 bytes
    decOffset 8
    %assign pos offset
    ; endlocal
    sub rsp, (-offset)

    mov rax, [rbp + pSepStr]
    mov rax, [rax]
    mov [rbp + sepLen], rax

    push [rbp + pVec]
    call vecLen
    mov [rbp + stringJoin_count], rax

    ; total = sum of element lens + sepLen * (count-1)
    mov qword [rbp + total], 0
    mov qword [rbp + i], 0
.lenLoop:
    mov rax, [rbp + i]
    cmp rax, [rbp + stringJoin_count]
    jae .lenDone

    push [rbp + pVec]
    push [rbp + i]
    call vecGet                 ; rax = pElem (slot ptr)
    mov rax, [rax]              ; pStr
    mov rax, [rax]              ; len
    add [rbp + total], rax
    ; last element (i >= count-1) contributes no trailing sep
    mov rax, [rbp + stringJoin_count]
    dec rax
    cmp [rbp + i], rax
    jae .lenNext
    mov rax, [rbp + total]
    add rax, [rbp + sepLen]
    mov [rbp + total], rax
.lenNext:
    inc qword [rbp + i]
    jmp .lenLoop
.lenDone:
    push [rbp + total]
    call allocStr
    mov [rbp + pResult], rax

    mov qword [rbp + pos], 0
    mov qword [rbp + i], 0
.catLoop:
    mov rax, [rbp + i]
    cmp rax, [rbp + stringJoin_count]
    jae .finish

    push [rbp + pVec]
    push [rbp + i]
    call vecGet                 ; rax = slot ptr
    mov rax, [rax]              ; pStr
    mov rbx, [rax]              ; len
    ; memCopy(result+8+pos, pStr+8, len)
    mov rcx, [rbp + pResult]
    add rcx, 8
    add rcx, [rbp + pos]
    push rcx
    add rax, 8
    push rax
    push rbx
    call memCopy

    ; advance pos by this element's length
    push [rbp + pVec]
    push [rbp + i]
    call vecGet
    mov rax, [rax]              ; pStr
    mov rax, [rax]              ; len
    add [rbp + pos], rax

    ; then sep (except after last: i >= count-1)
    mov rax, [rbp + stringJoin_count]
    dec rax                      ; count - 1
    cmp [rbp + i], rax
    jae .catNext
    ; memCopy(result+8+pos, sep, sepLen)
    mov rax, [rbp + pResult]
    add rax, 8
    add rax, [rbp + pos]
    push rax
    mov rax, [rbp + pSepStr]
    add rax, 8                  ; sep data
    push rax
    push [rbp + sepLen]
    call memCopy
    mov rax, [rbp + pos]
    add rax, [rbp + sepLen]
    mov [rbp + pos], rax
.catNext:
    inc qword [rbp + i]
    jmp .catLoop
.finish:
    mov rax, [rbp + pResult]
    mov rbx, [rbp + total]
    mov byte [rax + 8 + rbx], 0 ; NUL

    mov rax, [rbp + pResult]
    mov rbx, [rbp + pOut]
    mov [rbx], rax

    end
    ret 24

section .rodata
emptyStr:
    dq 0
    db 0
