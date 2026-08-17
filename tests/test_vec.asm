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

    errInit       db "vecWithCapacity failed", 0
    errPushLen    db "vecPushCp len wrong", 0
    errPushVal    db "vecPushCp value wrong", 0
    errGet        db "vecGet wrong", 0
    errGetOob     db "vecGet OOB should be NULL", 0
    errFirst      db "vecFirst wrong", 0
    errLast       db "vecLast wrong", 0
    errIsEmpty    db "vecIsEmpty wrong", 0
    errSet        db "vecSetCp wrong", 0
    errPop        db "vecPop wrong", 0
    errInsert     db "vecInsertCp wrong", 0
    errRemove     db "vecRemove wrong", 0
    errSort       db "vecSort wrong", 0
    errTruncate   db "vecTruncate wrong", 0
    errClear      db "vecClear wrong", 0
    errSwapElem   db "vecSwapElement wrong", 0
    errSwap       db "vecSwap wrong", 0
    errCopy       db "vecCopy wrong", 0
    errEq         db "vecEq wrong", 0
    errCmp        db "vecCmp wrong", 0
    errHash       db "vecHash wrong", 0
    errMove       db "vecMove wrong", 0
    errDrop       db "vecDrop wrong", 0
    errFnv        db "fnv64 wrong", 0

section .bss
    vecA     resb 32
    vecB     resb 32
    popped   resq 1
    removed  resq 1

section .text
    global entry

; ---- int64 trait callbacks (custom ABI, same as sort's comparators) ----

proc int64Drop
    args self
    xor rax, rax
    end
    ret 8

proc int64Cmp
    args a, b
    mov rax, [%$a]
    mov rax, [rax]
    mov rbx, [%$b]
    mov rbx, [rbx]
    sub rax, rbx
    end
    ret 16

proc int64Eq
    args a, b
    mov rax, [%$a]
    mov rax, [rax]
    mov rbx, [%$b]
    mov rbx, [rbx]
    cmp rax, rbx
    sete al
    movzx rax, al
    end
    ret 16

proc int64Hash
    args self
    mov rax, [%$self]
    mov rax, [rax]
    end
    ret 8

proc int64Copy
    args dst, src
    push [%$dst]
    push [%$src]
    push 8
    call memCopy
    end
    ret 16

proc int64Move
    args dst, src
    push [%$dst]
    push [%$src]
    push 8
    call memCopy
    end
    ret 16

; ---- helper: assert vecGet(vecPtr, idx) == expect ----
proc checkInt64
    args vecPtr, idx, expect, errMsg
    push [%$vecPtr]
    push [%$idx]
    call vecGet
    mov rbx, [rax]
    cmp rbx, [%$expect]
    sete al
    movzx rax, al
    push [%$errMsg]
    push rax
    call assert
    end
    ret 32

proc entry
    local tmp
    endlocal

    ; ---- fnv64 sanity ----
    push fnvData
    push 8
    mov rax, 0xcbf29ce484222325
    push rax
    call fnv64
    mov [%$tmp], rax
    push fnvData
    push 8
    mov rax, 0xcbf29ce484222325
    push rax
    call fnv64
    mov rbx, [%$tmp]
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

    cmp qword [vecA + Vec.capacity], 2
    sete al
    movzx rax, al
    push errInit
    push rax
    call assert

    cmp qword [vecA + Vec.data], 0
    setne al
    movzx rax, al
    push errInit
    push rax
    call assert

    ; ---- vecPushCp x3: [10, 20, 30] ----
    push vecA
    push val10
    call vecPushCp
    push vecA
    push val20
    call vecPushCp
    push vecA
    push val30
    call vecPushCp

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

    ; ---- vecSetCp(1, 25): [10, 25, 30] ----
    push vecA
    push 1
    push val25
    call vecSetCp

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

    ; ---- vecInsertCp(1, 15): [10, 15, 25] ----
    push vecA
    push 1
    push val15
    call vecInsertCp

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
    call vecPushCp
    push vecA
    push val1
    call vecPushCp
    push vecA
    push val4
    call vecPushCp

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
    call vecPushCp
    push vecA
    push val3
    call vecPushCp

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

    mov rax, [vecB + Vec.data]
    cmp rax, [vecA + Vec.data]
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
    call vecPushCp

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
    mov [%$tmp], rax
    push vecB
    push vecA
    call vecCopy
    push vecA
    call vecHash
    mov rbx, [%$tmp]
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

    cmp qword [vecA + Vec.data], 0
    sete al
    movzx rax, al
    push errMove
    push rax
    call assert
    cmp qword [vecA + Vec.len], 0
    sete al
    movzx rax, al
    push errMove
    push rax
    call assert
    cmp qword [vecB + Vec.len], 2
    sete al
    movzx rax, al
    push errMove
    push rax
    call assert

    ; ---- vecSwap(&vecA, &vecB): A gets [3, 7], B gets empty ----
    push vecA
    push vecB
    call vecSwap

    cmp qword [vecA + Vec.len], 2
    sete al
    movzx rax, al
    push errSwap
    push rax
    call assert
    cmp qword [vecB + Vec.len], 0
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

    cmp qword [vecA + Vec.data], 0
    sete al
    movzx rax, al
    push errDrop
    push rax
    call assert
    cmp qword [vecA + Vec.capacity], 0
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
