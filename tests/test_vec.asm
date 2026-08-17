; test_vec.asm -- vec + fnv64 tests

%include "asmrt.inc"

section .data
    int64Meta:
        dq 8                     ; size
        dq 8                     ; align
        dq int64Drop             ; drop
        dq int64Cmp              ; cmp
        dq int64Eq               ; eq
        dq int64Hash             ; hash
        dq int64Copy             ; copy
        dq int64Move             ; move

    val10 dq 10
    val20 dq 20
    val30 dq 30
    val25 dq 25
    val15 dq 15
    val5  dq 5
    val1  dq 1
    val4  dq 4
    val7  dq 7
    val3  dq 3
    val9  dq 9

errInit dq (errInit_end - errInit_start)
    errInit_start: db "vecWithCapacity failed"
    errInit_end: db 0

errPushLen dq (errPushLen_end - errPushLen_start)
    errPushLen_start: db "vecPush len wrong"
    errPushLen_end: db 0

errPushVal dq (errPushVal_end - errPushVal_start)
    errPushVal_start: db "vecPush value wrong"
    errPushVal_end: db 0

errGet dq (errGet_end - errGet_start)
    errGet_start: db "vecGet wrong"
    errGet_end: db 0

errGetOob dq (errGetOob_end - errGetOob_start)
    errGetOob_start: db "vecGet OOB should be NULL"
    errGetOob_end: db 0

errFirst dq (errFirst_end - errFirst_start)
    errFirst_start: db "vecFirst wrong"
    errFirst_end: db 0

errLast dq (errLast_end - errLast_start)
    errLast_start: db "vecLast wrong"
    errLast_end: db 0

errIsEmpty dq (errIsEmpty_end - errIsEmpty_start)
    errIsEmpty_start: db "vecIsEmpty wrong"
    errIsEmpty_end: db 0

errSet dq (errSet_end - errSet_start)
    errSet_start: db "vecSet wrong"
    errSet_end: db 0

errPop dq (errPop_end - errPop_start)
    errPop_start: db "vecPop wrong"
    errPop_end: db 0

errInsert dq (errInsert_end - errInsert_start)
    errInsert_start: db "vecInsert wrong"
    errInsert_end: db 0

errRemove dq (errRemove_end - errRemove_start)
    errRemove_start: db "vecRemove wrong"
    errRemove_end: db 0

errSort dq (errSort_end - errSort_start)
    errSort_start: db "vecSort wrong"
    errSort_end: db 0

errTruncate dq (errTruncate_end - errTruncate_start)
    errTruncate_start: db "vecTruncate wrong"
    errTruncate_end: db 0

errClear dq (errClear_end - errClear_start)
    errClear_start: db "vecClear wrong"
    errClear_end: db 0

errSwapElem dq (errSwapElem_end - errSwapElem_start)
    errSwapElem_start: db "vecSwapElement wrong"
    errSwapElem_end: db 0

errSwap dq (errSwap_end - errSwap_start)
    errSwap_start: db "vecSwap wrong"
    errSwap_end: db 0

errCopy dq (errCopy_end - errCopy_start)
    errCopy_start: db "vecCopy wrong"
    errCopy_end: db 0

errEq dq (errEq_end - errEq_start)
    errEq_start: db "vecEq wrong"
    errEq_end: db 0

errCmp dq (errCmp_end - errCmp_start)
    errCmp_start: db "vecCmp wrong"
    errCmp_end: db 0

errHash dq (errHash_end - errHash_start)
    errHash_start: db "vecHash wrong"
    errHash_end: db 0

errMove dq (errMove_end - errMove_start)
    errMove_start: db "vecMove wrong"
    errMove_end: db 0

errDrop dq (errDrop_end - errDrop_start)
    errDrop_start: db "vecDrop wrong"
    errDrop_end: db 0

errFnv dq (errFnv_end - errFnv_start)
    errFnv_start: db "fnv64 wrong"
    errFnv_end: db 0

section .bss
    vecA     resb sizeof_Vec
    vecB     resb sizeof_Vec
    popped   resq 1
    removed  resq 1

section .text
    global entry

; ---- int64 trait callbacks (custom ABI, same as sort's comparators) ----

int64Drop:
    ; args: self
    argnum 1
    %assign self arg(1)
    begin
    xor rax, rax
    end
    ret 8

int64Cmp:
    ; args: a, b
    argnum 2
    %assign a arg(1)
    %assign b arg(2)
    begin
    mov rax, [rbp + a]
    mov rax, [rax]
    mov rbx, [rbp + b]
    mov rbx, [rbx]
    sub rax, rbx
    end
    ret 16

int64Eq:
    ; args: a, b
    argnum 2
    %assign a arg(1)
    %assign b arg(2)
    begin
    mov rax, [rbp + a]
    mov rax, [rax]
    mov rbx, [rbp + b]
    mov rbx, [rbx]
    cmp rax, rbx
    sete al
    movzx rax, al
    end
    ret 16

int64Hash:
    ; args: self
    argnum 1
    %assign self arg(1)
    begin
    mov rax, [rbp + self]
    mov rax, [rax]
    end
    ret 8

int64Copy:
    ; args: dst, src
    argnum 2
    %assign dst arg(1)
    %assign src arg(2)
    begin
    push qword [rbp + dst]
    push qword [rbp + src]
    push 8
    call memCopy
    end
    ret 16

int64Move:
    ; args: dst, src
    argnum 2
    %assign dst arg(1)
    %assign src arg(2)
    begin
    push qword [rbp + dst]
    push qword [rbp + src]
    push 8
    call memCopy
    end
    ret 16

; ---- helper: assert vecGet(vecPtr, idx) == expect ----
checkInt64:
    ; args: vecPtr, idx, expect, errMsg
    argnum 4
    %assign vecPtr arg(1)
    %assign idx arg(2)
    %assign expect arg(3)
    %assign errMsg arg(4)
    begin
    push qword [rbp + vecPtr]
    push qword [rbp + idx]
    call vecGet
    mov rbx, [rax]
    cmp rbx, [rbp + expect]
    sete al
    movzx rax, al
    push qword [rbp + errMsg]
    push rax
    call assert
    end
    ret 32

entry:
    begin
    ; local variables
    resetOffset
    ; tmp 8 bytes
    decOffset 8
    %assign tmp offset
    ; endlocal
    sub rsp, (-offset)

    ; ---- fnv64 sanity ----
    push fnvData
    push 8
    mov rax, FNV_OFFSET_BASIS
    push rax
    call fnv64
    mov [rbp + tmp], rax
    push fnvData
    push 8
    mov rax, FNV_OFFSET_BASIS
    push rax
    call fnv64
    mov rbx, [rbp + tmp]
    cmp rax, rbx
    sete al
    movzx rax, al
    push errFnv
    push rax
    call assert

    ; ---- vecWithCapacity ----
    push vecA
    push int64Meta
    push 2
    call vecWithCapacity
    cmp rax, 0
    sete al
    movzx rax, al
    push errInit
    push rax
    call assert

    cmp qword [vecA + Vec_capacity], 2
    sete al
    movzx rax, al
    push errInit
    push rax
    call assert

    cmp qword [vecA + Vec_data], 0
    setne al
    movzx rax, al
    push errInit
    push rax
    call assert

    ; ---- vecPush x3: [10, 20, 30] ----
    push vecA
    push val10
    push 0          ; isMove=0: copy
    call vecPush
    push vecA
    push val20
    push 0          ; isMove=0: copy
    call vecPush
    push vecA
    push val30
    push 0          ; isMove=0: copy
    call vecPush

    push vecA
    call vecLen
    cmp rax, 3
    sete al
    movzx rax, al
    push errPushLen
    push rax
    call assert

    push vecA
    call vecIsEmpty
    test rax, rax
    setz al
    movzx rax, al
    push errIsEmpty
    push rax
    call assert

    push vecA
    call vecFirst
    mov rbx, [rax]
    cmp rbx, 10
    sete al
    movzx rax, al
    push errFirst
    push rax
    call assert

    push vecA
    call vecLast
    mov rbx, [rax]
    cmp rbx, 30
    sete al
    movzx rax, al
    push errLast
    push rax
    call assert

    push vecA
    push 1
    call vecGet
    mov rbx, [rax]
    cmp rbx, 20
    sete al
    movzx rax, al
    push errGet
    push rax
    call assert

    push vecA
    push 99
    call vecGet
    test rax, rax
    setz al
    movzx rax, al
    push errGetOob
    push rax
    call assert

    ; ---- vecSet(1, 25): [10, 25, 30] ----
    push vecA
    push 1
    push val25
    push 0          ; isMove=0: copy
    call vecSet

    push vecA
    push 1
    call vecGet
    mov rbx, [rax]
    cmp rbx, 25
    sete al
    movzx rax, al
    push errSet
    push rax
    call assert

    ; ---- vecPop -> 30, len 2, [10, 25] ----
    push vecA
    push popped
    call vecPop
    cmp rax, 1
    sete al
    movzx rax, al
    push errPop
    push rax
    call assert

    cmp qword [popped], 30
    sete al
    movzx rax, al
    push errPop
    push rax
    call assert

    push vecA
    call vecLen
    cmp rax, 2
    sete al
    movzx rax, al
    push errPop
    push rax
    call assert

    ; ---- vecInsert(1, 15, copy): [10, 15, 25] ----
    push vecA
    push 1
    push val15
    push 0               ; isMove=0: copy
    call vecInsert

    push vecA
    call vecLen
    cmp rax, 3
    sete al
    movzx rax, al
    push errInsert
    push rax
    call assert

    push vecA
    push 1
    call vecGet
    mov rbx, [rax]
    cmp rbx, 15
    sete al
    movzx rax, al
    push errInsert
    push rax
    call assert

    ; ---- vecRemove(1, &removed) -> removed=15, [10, 25] ----
    push vecA
    push 1
    push removed
    call vecRemove

    cmp qword [removed], 15
    sete al
    movzx rax, al
    push errRemove
    push rax
    call assert

    push vecA
    call vecLen
    cmp rax, 2
    sete al
    movzx rax, al
    push errRemove
    push rax
    call assert

    ; ---- push 5, 1, 4 -> [10, 25, 5, 1, 4]; vecSort -> [1, 4, 5, 10, 25] ----
    push vecA
    push val5
    push 0          ; isMove=0: copy
    call vecPush
    push vecA
    push val1
    push 0          ; isMove=0: copy
    call vecPush
    push vecA
    push val4
    push 0          ; isMove=0: copy
    call vecPush

    push vecA
    call vecSort

    push vecA
    push 0
    push 1
    push errSort
    call checkInt64
    push vecA
    push 1
    push 4
    push errSort
    call checkInt64
    push vecA
    push 2
    push 5
    push errSort
    call checkInt64
    push vecA
    push 3
    push 10
    push errSort
    call checkInt64
    push vecA
    push 4
    push 25
    push errSort
    call checkInt64

    ; ---- vecTruncate(2) -> [1, 4] ----
    push vecA
    push 2
    call vecTruncate

    push vecA
    call vecLen
    cmp rax, 2
    sete al
    movzx rax, al
    push errTruncate
    push rax
    call assert

    ; ---- vecClear -> len 0 ----
    push vecA
    call vecClear

    push vecA
    call vecLen
    test rax, rax
    setz al
    movzx rax, al
    push errClear
    push rax
    call assert

    ; ---- push 7, 3 -> [7, 3]; vecSwapElement(0,1) -> [3, 7] ----
    push vecA
    push val7
    push 0          ; isMove=0: copy
    call vecPush
    push vecA
    push val3
    push 0          ; isMove=0: copy
    call vecPush

    push vecA
    push 0
    push 1
    call vecSwapElement

    push vecA
    push 0
    push 3
    push errSwapElem
    call checkInt64
    push vecA
    push 1
    push 7
    push errSwapElem
    call checkInt64

    ; ---- vecCopy(&vecB, &vecA) -> B == [3, 7], distinct buffers ----
    push vecB
    push vecA
    call vecCopy

    mov rax, [vecB + Vec_data]
    cmp rax, [vecA + Vec_data]
    setne al
    movzx rax, al
    push errCopy
    push rax
    call assert

    push vecA
    push vecB
    call vecEq
    cmp rax, 1
    sete al
    movzx rax, al
    push errEq
    push rax
    call assert

    push vecA
    push vecB
    call vecCmp
    cmp rax, 0
    sete al
    movzx rax, al
    push errCmp
    push rax
    call assert

    ; ---- append 9 to B -> [3, 7, 9]; vecCmp(A, B) == -1 ----
    push vecB
    push val9
    push 0          ; isMove=0: copy
    call vecPush

    push vecA
    push vecB
    call vecCmp
    cmp rax, -1
    sete al
    movzx rax, al
    push errCmp
    push rax
    call assert

    ; ---- vecHash equal for two equal vecs ----
    push vecA
    call vecHash
    mov [rbp + tmp], rax
    push vecB
    push vecA
    call vecCopy
    push vecA
    call vecHash
    mov rbx, [rbp + tmp]
    cmp rax, rbx
    sete al
    movzx rax, al
    push errHash
    push rax
    call assert

    ; ---- vecMove(&vecB, &vecA): A transfers to B, A reset ----
    push vecB
    push vecA
    call vecMove

    cmp qword [vecA + Vec_data], 0
    sete al
    movzx rax, al
    push errMove
    push rax
    call assert
    cmp qword [vecA + Vec_len], 0
    sete al
    movzx rax, al
    push errMove
    push rax
    call assert
    cmp qword [vecB + Vec_len], 2
    sete al
    movzx rax, al
    push errMove
    push rax
    call assert

    ; ---- vecSwap(&vecA, &vecB): A gets [3, 7], B gets empty ----
    push vecA
    push vecB
    call vecSwap

    cmp qword [vecA + Vec_len], 2
    sete al
    movzx rax, al
    push errSwap
    push rax
    call assert
    cmp qword [vecB + Vec_len], 0
    sete al
    movzx rax, al
    push errSwap
    push rax
    call assert

    ; ---- vecDrop both ----
    push vecA
    call vecDrop
    push vecB
    call vecDrop

    cmp qword [vecA + Vec_data], 0
    sete al
    movzx rax, al
    push errDrop
    push rax
    call assert
    cmp qword [vecA + Vec_capacity], 0
    sete al
    movzx rax, al
    push errDrop
    push rax
    call assert

    mov rax, 0
    end
    ret 24

section .data
fnvData dq 0x123456789abcdef0
