; test_str.asm -- length-prefixed string module tests
;
; String layout: string -> [8-byte len][data bytes][NUL], len counts chars
; (excluding the trailing NUL).  stringEq/stringCmp/stringCopy/... take
; string *slots* (8-byte slots holding a string pointer), matching the
; ValueMeta callback convention; stringLen/stringAt/stringHash/... take
; the string pointer itself.

%include "asmrt.inc"

section .data
; length-prefixed string literals
s1 dq (s1_end - s1_start)
    s1_start: db "hello"
    s1_end: db 0

s2 dq (s2_end - s2_start)
    s2_start: db "hello"
    s2_end: db 0

s3 dq (s3_end - s3_start)
    s3_start: db "world"
    s3_end: db 0

sHelloW dq (sHelloW_end - sHelloW_start)
    sHelloW_start: db "hello world"
    sHelloW_end: db 0

sWs dq (sWs_end - sWs_start)
    sWs_start: db "  trim me  "
    sWs_end: db 0

sCap dq (sCap_end - sCap_start)
    sCap_start: db "hELLo"
    sCap_end: db 0

    empty:
        dq 0
        db 0

sepComma dq (sepComma_end - sepComma_start)
    sepComma_start: db ","
    sepComma_end: db 0

sCSV dq (sCSV_end - sCSV_start)
    sCSV_start: db "a,b,c"
    sCSV_end: db 0

sLines dq (sLines_end - sLines_start)
    sLines_start: db "one", 10, "two", 10, "three"
    sLines_end: db 0

; error messages
errLen dq (errLen_end - errLen_start)
    errLen_start: db "stringLen wrong"
    errLen_end: db 0

errLenEmpty dq (errLenEmpty_end - errLenEmpty_start)
    errLenEmpty_start: db "stringLen(empty) != 0"
    errLenEmpty_end: db 0

errEq dq (errEq_end - errEq_start)
    errEq_start: db "stringEq wrong"
    errEq_end: db 0

errCmp dq (errCmp_end - errCmp_start)
    errCmp_start: db "stringCmp wrong"
    errCmp_end: db 0

errAt dq (errAt_end - errAt_start)
    errAt_start: db "stringAt wrong"
    errAt_end: db 0

errHash dq (errHash_end - errHash_start)
    errHash_start: db "stringHash wrong"
    errHash_end: db 0

errSub dq (errSub_end - errSub_start)
    errSub_start: db "stringSubstring wrong"
    errSub_end: db 0

errSub1 dq (errSub1_end - errSub1_start)
    errSub1_start: db "substring #1 wrong"
    errSub1_end: db 0

errSub2 dq (errSub2_end - errSub2_start)
    errSub2_start: db "substring #2 wrong"
    errSub2_end: db 0

errSub3 dq (errSub3_end - errSub3_start)
    errSub3_start: db "substring #3 wrong"
    errSub3_end: db 0

errConcat dq (errConcat_end - errConcat_start)
    errConcat_start: db "stringConcat wrong"
    errConcat_end: db 0

errStarts dq (errStarts_end - errStarts_start)
    errStarts_start: db "stringStartsWith wrong"
    errStarts_end: db 0

errEnds dq (errEnds_end - errEnds_start)
    errEnds_start: db "stringEndsWith wrong"
    errEnds_end: db 0

errFind dq (errFind_end - errFind_start)
    errFind_start: db "stringFind wrong"
    errFind_end: db 0

errCount dq (errCount_end - errCount_start)
    errCount_start: db "stringCount wrong"
    errCount_end: db 0

errLower dq (errLower_end - errLower_start)
    errLower_start: db "stringLower wrong"
    errLower_end: db 0

errUpper dq (errUpper_end - errUpper_start)
    errUpper_start: db "stringUpper wrong"
    errUpper_end: db 0

errCap dq (errCap_end - errCap_start)
    errCap_start: db "stringCapitalize wrong"
    errCap_end: db 0

errStrip dq (errStrip_end - errStrip_start)
    errStrip_start: db "stringStrip wrong"
    errStrip_end: db 0

errLStrip dq (errLStrip_end - errLStrip_start)
    errLStrip_start: db "stringLStrip wrong"
    errLStrip_end: db 0

errRStrip dq (errRStrip_end - errRStrip_start)
    errRStrip_start: db "stringRStrip wrong"
    errRStrip_end: db 0

errRemPref dq (errRemPref_end - errRemPref_start)
    errRemPref_start: db "stringRemovePrefix wrong"
    errRemPref_end: db 0

errRemSuf dq (errRemSuf_end - errRemSuf_start)
    errRemSuf_start: db "stringRemoveSuffix wrong"
    errRemSuf_end: db 0

errSplit dq (errSplit_end - errSplit_start)
    errSplit_start: db "stringSplit wrong"
    errSplit_end: db 0

errSplitLns dq (errSplitLns_end - errSplitLns_start)
    errSplitLns_start: db "stringSplitLines wrong"
    errSplitLns_end: db 0

errJoin dq (errJoin_end - errJoin_start)
    errJoin_start: db "stringJoin wrong"
    errJoin_end: db 0

errFromCStr dq (errFromCStr_end - errFromCStr_start)
    errFromCStr_start: db "stringFromCStr wrong"
    errFromCStr_end: db 0

errFromN dq (errFromN_end - errFromN_start)
    errFromN_start: db "stringFromRaw wrong"
    errFromN_end: db 0

errCopy dq (errCopy_end - errCopy_start)
    errCopy_start: db "stringCopy wrong"
    errCopy_end: db 0

errMove dq (errMove_end - errMove_start)
    errMove_start: db "stringMove wrong"
    errMove_end: db 0

errDrop dq (errDrop_end - errDrop_start)
    errDrop_start: db "stringDrop wrong"
    errDrop_end: db 0

errInit dq (errInit_end - errInit_start)
    errInit_start: db "stringInit wrong"
    errInit_end: db 0

errMeta dq (errMeta_end - errMeta_start)
    errMeta_start: db "stringMeta wrong"
    errMeta_end: db 0


section .bss
    initBuf  resb 16
    slot1    resq 1
    slot2    resq 1
    slot3    resq 1
    outSlot  resq 1
    outSlot2 resq 1
    outSlot3 resq 1
    vecA     resb sizeof_Vec

section .text
    global entry

; helper: assertEqualStr(expectedPStr, gotSlotPtr, errMsg)
;   checks stringLen(elem) == stringLen(expected) and bytes match
checkStr:
; args: pExpected, pSlot, errMsg
    argnum 3
    %assign pExpected arg(1)
    %assign pSlot arg(2)
    %assign pErr arg(3)
    begin
; local variables
    resetOffset
; i 8 bytes
    decOffset 8
    %assign i offset
; expCh 8 bytes
    decOffset 8
    %assign expCh offset
; endlocal
    sub rsp, (-offset)

; lengths must match
    push qword [rbp + pExpected]
    call stringLen
    mov rbx, rax                ; expected len
; pSlot is a slot (holds a string pointer), deref it first
    mov rax, [rbp + pSlot]
    mov rax, [rax]
    push rax
    call stringLen
    cmp rax, rbx
    sete al
    movzx rax, al
    push qword [rbp + pErr]
    push rax
    call assert

; byte-by-byte match
    mov qword [rbp + i], 0
.loop:
    mov rbx, [rbp + pExpected]
    mov rbx, [rbx]              ; expected len
    cmp [rbp + i], rbx
    jae .done

    push qword [rbp + pExpected]
    push qword [rbp + i]
    call stringAt
    mov [rbp + expCh], rax     ; regs are clobbered by calls, stash on stack
; pSlot is a slot (holds a string pointer), deref it first
    mov rax, [rbp + pSlot]
    mov rax, [rax]
    push rax
    push qword [rbp + i]
    call stringAt
    cmp rax, [rbp + expCh]
    sete al
    movzx rax, al
    push qword [rbp + pErr]
    push rax
    call assert

    inc qword [rbp + i]
    jmp .loop
.done:
    end
    ret 24

entry:
    begin
; local variables
    resetOffset
; hashTmp 8 bytes
    decOffset 8
    %assign hashTmp offset
; endlocal
    sub rsp, (-offset)

; ---- stringLen ----
    push s1
    call stringLen
    cmp rax, 5
    sete al
    movzx rax, al
    push errLen
    push rax
    call assert

    push empty
    call stringLen
    cmp rax, 0
    sete al
    movzx rax, al
    push errLenEmpty
    push rax
    call assert

; ---- slots for eq/cmp ----
    mov rax, s1
    mov [slot1], rax
    mov rax, s2
    mov [slot2], rax
    mov rax, s3
    mov [slot3], rax

; ---- stringEq ----
    push slot2
    push slot1
    call stringEq
    cmp rax, 1
    sete al
    movzx rax, al
    push errEq
    push rax
    call assert

    push slot3
    push slot1
    call stringEq
    cmp rax, 0
    sete al
    movzx rax, al
    push errEq
    push rax
    call assert

; ---- stringCmp ----
    push slot2
    push slot1
    call stringCmp
    cmp rax, 0
    sete al
    movzx rax, al
    push errCmp
    push rax
    call assert

    push slot3
    push slot1
    call stringCmp
    test rax, rax
    setnz al
    movzx rax, al
    push errCmp
    push rax
    call assert

; ---- stringAt ----
    push s1
    push 0
    call stringAt
    cmp rax, 'h'
    sete al
    movzx rax, al
    push errAt
    push rax
    call assert

    push s1
    push 4
    call stringAt
    cmp rax, 'o'
    sete al
    movzx rax, al
    push errAt
    push rax
    call assert

; out of range -> 0
    push s1
    push 5
    call stringAt
    cmp rax, 0
    sete al
    movzx rax, al
    push errAt
    push rax
    call assert

; ---- stringHash ----
; hash(s1) must equal fnv64(s1_start, 5, FNV_OFFSET_BASIS)
    push s1
    call stringHash
    mov [rbp + hashTmp], rax

    push s1_start
    push 5
    mov rbx, FNV_OFFSET_BASIS
    push rbx
    call fnv64
    cmp rax, [rbp + hashTmp]
    sete al
    movzx rax, al
    push errHash
    push rax
    call assert

; ---- stringSubstring ----
; substring(sHelloW, 0, 5) == "hello"
    push sHelloW
    push 0
    push 5
    call stringSubstring
    mov [outSlot], rax
    push s1
    push outSlot
    push errSub1
    call checkStr

; substring(sHelloW, 6, 11) == "world"
    push sHelloW
    push 6
    push 11
    call stringSubstring
    mov [outSlot2], rax
    push s3
    push outSlot2
    push errSub2
    call checkStr

; clamp: substring(sHelloW, -1, 100) == whole
    push sHelloW
    push -1
    push 100
    call stringSubstring
    mov [outSlot3], rax
    push sHelloW
    push outSlot3
    push errSub3
    call checkStr

; ---- stringConcat ----
; concat(s1, s3) == "helloworld"
    push s1
    push s3
    call stringConcat
    mov [outSlot], rax
    mov rax, [outSlot]
    mov rax, [rax]
    cmp rax, 10
    sete al
    movzx rax, al
    push errConcat
    push rax
    call assert

; ---- stringStartsWith / stringEndsWith ----
; sHelloW starts with "hello"
    push sHelloW
    push s1
    call stringStartsWith
    cmp rax, 1
    sete al
    movzx rax, al
    push errStarts
    push rax
    call assert

; sHelloW does NOT start with s3 ("world")
    push sHelloW
    push s3
    call stringStartsWith
    cmp rax, 0
    sete al
    movzx rax, al
    push errStarts
    push rax
    call assert

; sHelloW ends with s3
    push sHelloW
    push s3
    call stringEndsWith
    cmp rax, 1
    sete al
    movzx rax, al
    push errEnds
    push rax
    call assert

; ---- stringFind / stringCount ----
; find("hello", "ll") == 2
    push s1
    push sGetLl   ; "ll"
    call stringFind
    cmp rax, 2
    sete al
    movzx rax, al
    push errFind
    push rax
    call assert

; find("hello", "world") == -1
    push s1
    push s3
    call stringFind
    cmp rax, -1
    sete al
    movzx rax, al
    push errFind
    push rax
    call assert

; count("hello", "l") == 2
    push s1
    push sGetL    ; "l"
    call stringCount
    cmp rax, 2
    sete al
    movzx rax, al
    push errCount
    push rax
    call assert

; ---- stringLower / stringUpper / stringCapitalize ----
    push sCap
    call stringLower
    mov [outSlot], rax
    push sCapLower  ; "hello"
    push outSlot
    push errLower
    call checkStr

    push sCap
    call stringUpper
    mov [outSlot], rax
    push sCapUpper  ; "HELLO"
    push outSlot
    push errUpper
    call checkStr

    push sCap
    call stringCapitalize
    mov [outSlot], rax
    push sCapCap    ; "Hello"
    push outSlot
    push errCap
    call checkStr

; ---- stringStrip / stringLStrip / stringRStrip ----
    push sWs
    call stringStrip
    mov [outSlot], rax
    push sTrimmed   ; "trim me"
    push outSlot
    push errStrip
    call checkStr

    push sWs
    call stringLStrip
    mov [outSlot], rax
    push sLTrimmed  ; "trim me  "
    push outSlot
    push errLStrip
    call checkStr

    push sWs
    call stringRStrip
    mov [outSlot], rax
    push sRTrimmed  ; "  trim me"
    push outSlot
    push errRStrip
    call checkStr

; ---- stringRemovePrefix / stringRemoveSuffix ----
; removeprefix("hello world", "hello") == " world"
    push sHelloW
    push s1
    call stringRemovePrefix
    mov [outSlot], rax
    push sRemPref   ; " world"
    push outSlot
    push errRemPref
    call checkStr

; removesuffix("hello world", "world") == "hello "
    push sHelloW
    push s3
    call stringRemoveSuffix
    mov [outSlot], rax
    push sRemSuf    ; "hello "
    push outSlot
    push errRemSuf
    call checkStr

; ---- stringSplit ----
; split("a,b,c", ",") -> 3 elems each with len 1
    push vecA
    push sCSV
    push sepComma
    call stringSplit
    push vecA
    call vecLen
    cmp rax, 3
    sete al
    movzx rax, al
    push errSplit
    push rax
    call assert

; elem[0] == "a"
    push vecA
    push 0
    call vecGet
    push sGetA
    push rax
    push errSplit
    call checkStr

; ---- stringSplitLines ----
; splitlines("one\ntwo\nthree") -> 3 elems
    push vecA
    push sLines
    call stringSplitLines
    push vecA
    call vecLen
    cmp rax, 3
    sete al
    movzx rax, al
    push errSplitLns
    push rax
    call assert

; ---- stringJoin ----
; join(["a","b","c"], ",") == "a,b,c" -- re-split so vecA holds the
; split pieces again (stringSplitLines overwrote it above)
    push vecA
    push sCSV
    push sepComma
    call stringSplit
    push vecA
    push sepComma
    call stringJoin
    mov [outSlot], rax
    push sCSV
    push outSlot
    push errJoin
    call checkStr

; ---- stringFromCStr / stringFromRaw / stringDrop ----
; from_c_str("hello") == s1
    push s1_start
    call stringFromCStr
    mov [outSlot], rax
    push s1
    push outSlot
    push errFromCStr
    call checkStr
; cleanup
    push outSlot
    call stringDrop
    cmp qword [outSlot], 0
    sete al
    movzx rax, al
    push errDrop
    push rax
    call assert

; from_n(s1_start, 3) == "hel"
    push s1_start
    push 3
    call stringFromRaw
    mov [outSlot], rax
    push sGetHel   ; "hel"
    push outSlot
    push errFromN
    call checkStr
    push outSlot
    call stringDrop

; ---- stringCopy / stringMove (slot semantics) ----
; copy slot2 (s2 "hello") into outSlot
    push outSlot
    push slot2
    call stringCopy
    push s1
    push outSlot
    push errCopy
    call checkStr
; move outSlot into outSlot2
    push outSlot2
    push outSlot
    call stringMove
    cmp qword [outSlot], 0
    sete al
    movzx rax, al
    push errMove
    push rax
    call assert
    push s1
    push outSlot2
    push errMove
    call checkStr
; cleanup
    push outSlot2
    call stringDrop

; ---- stringInit ----
; stringInit initializes a string object in place (needs a >=9-byte
; buffer), it does not write a slot -- so use a dedicated initBuf
    push initBuf
    call stringInit
    cmp qword [initBuf], 0
    sete al
    movzx rax, al
    push errInit
    push rax
    call assert
    cmp byte [initBuf + 8], 0
    sete al
    movzx rax, al
    push errInit
    push rax
    call assert

; ---- stringMeta shape ----
    cmp qword [stringMeta + ValueMeta_objsize], 8
    sete al
    movzx rax, al
    push errMeta
    push rax
    call assert

; cleanup split/splitlines vecs
    push vecA
    call vecDrop

    mov rax, 0
    end
    ret 24

section .data
    sGetLl:
        dq 2
        db "ll"
    sGetL:
        dq 1
        db "l"
    sGetA:
        dq 1
        db "a"
    sGetHel:
        dq 3
        db "hel"
    sCapLower:
        dq 5
        db "hello"
    sCapUpper:
        dq 5
        db "HELLO"
    sCapCap:
        dq 5
        db "Hello"
    sTrimmed:
        dq 7
        db "trim me"
    sLTrimmed:
        dq 9
        db "trim me  "
    sRTrimmed:
        dq 9
        db "  trim me"
    sRemPref:
        dq 6
        db " world"
    sRemSuf:
        dq 6
        db "hello "
