; test_list.asm -- list module tests

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

    val1  dq 1
    val5  dq 5
    val7  dq 7
    val10 dq 10
    val15 dq 15
    val20 dq 20
    val25 dq 25
    val30 dq 30

errInit dq (errInit_end - errInit_start)
    errInit_start: db "listInit failed"
    errInit_end: db 0

errLen dq (errLen_end - errLen_start)
    errLen_start: db "listLen wrong"
    errLen_end: db 0

errIsEmpty dq (errIsEmpty_end - errIsEmpty_start)
    errIsEmpty_start: db "listIsEmpty wrong"
    errIsEmpty_end: db 0

errBegin dq (errBegin_end - errBegin_start)
    errBegin_start: db "listBegin wrong"
    errBegin_end: db 0

errLast dq (errLast_end - errLast_start)
    errLast_start: db "listLast wrong"
    errLast_end: db 0

errEnd dq (errEnd_end - errEnd_start)
    errEnd_start: db "listEnd wrong"
    errEnd_end: db 0

errGet dq (errGet_end - errGet_start)
    errGet_start: db "listGet wrong"
    errGet_end: db 0

errNext dq (errNext_end - errNext_start)
    errNext_start: db "listNext wrong"
    errNext_end: db 0

errPrev dq (errPrev_end - errPrev_start)
    errPrev_start: db "listPrev wrong"
    errPrev_end: db 0

errInsert dq (errInsert_end - errInsert_start)
    errInsert_start: db "listInsert wrong"
    errInsert_end: db 0

errSet dq (errSet_end - errSet_start)
    errSet_start: db "listSet wrong"
    errSet_end: db 0

errRemove dq (errRemove_end - errRemove_start)
    errRemove_start: db "listRemove wrong"
    errRemove_end: db 0

errPop dq (errPop_end - errPop_start)
    errPop_start: db "listPop wrong"
    errPop_end: db 0

errClear dq (errClear_end - errClear_start)
    errClear_start: db "listClear wrong"
    errClear_end: db 0

errCopy dq (errCopy_end - errCopy_start)
    errCopy_start: db "listCopy wrong"
    errCopy_end: db 0

errMove dq (errMove_end - errMove_start)
    errMove_start: db "listMove wrong"
    errMove_end: db 0

errSwap dq (errSwap_end - errSwap_start)
    errSwap_start: db "listSwap wrong"
    errSwap_end: db 0

errEq dq (errEq_end - errEq_start)
    errEq_start: db "listEq wrong"
    errEq_end: db 0

errCmp dq (errCmp_end - errCmp_start)
    errCmp_start: db "listCmp wrong"
    errCmp_end: db 0

errHash dq (errHash_end - errHash_start)
    errHash_start: db "listHash wrong"
    errHash_end: db 0

errDrop dq (errDrop_end - errDrop_start)
    errDrop_start: db "listDrop wrong"
    errDrop_end: db 0

errMeta dq (errMeta_end - errMeta_start)
    errMeta_start: db "listMeta wrong"
    errMeta_end: db 0

section .bss
    listA    resb sizeof_List
    listB    resb sizeof_List

section .text
    global entry

; ---- int64 trait callbacks (custom ABI) ----

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
    push [rbp + dst]
    push [rbp + src]
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
    push [rbp + dst]
    push [rbp + src]
    push 8
    call memCopy
    end
    ret 16

; ---- helper: assert listGet(node) == expect ----
checkNode:
    ; args: node, expect, errMsg
    argnum 3
    %assign node arg(1)
    %assign expect arg(2)
    %assign errMsg arg(3)
    begin
    push [rbp + node]
    call listGet
    mov rbx, [rax]
    cmp rbx, [rbp + expect]
    sete al
    movzx rax, al
    push [rbp + errMsg]
    push rax
    call assert
    end
    ret 24

entry:
    begin
    ; local variables
    resetOffset
    ; it 8 bytes
    decOffset 8
    %assign it offset
    ; endlocal
    sub rsp, (-offset)

    ; ---- listInit ----
    push listA
    push int64Meta
    call listInit
    cmp rax, 0
    sete al
    movzx rax, al
    push errInit
    push rax
    call assert

    cmp qword [listA + List_len], 0
    sete al
    movzx rax, al
    push errInit
    push rax
    call assert

    cmp qword [listA + List_vhead], 0
    setne al
    movzx rax, al
    push errInit
    push rax
    call assert

    cmp qword [listA + List_vtail], 0
    setne al
    movzx rax, al
    push errInit
    push rax
    call assert

    push listA
    call listIsEmpty
    cmp rax, 1
    sete al
    movzx rax, al
    push errIsEmpty
    push rax
    call assert

    ; ---- listPushBack x3 x3: [10, 20, 30] ----
    push listA
    push val10
    push 0              ; isMove=0: copy
    call listPushBack
    push listA
    push val20
    push 0              ; isMove=0: copy
    call listPushBack
    push listA
    push val30
    push 0              ; isMove=0: copy
    call listPushBack

    push listA
    call listLen
    cmp rax, 3
    sete al
    movzx rax, al
    push errLen
    push rax
    call assert

    push listA
    call listIsEmpty
    test rax, rax
    setz al
    movzx rax, al
    push errIsEmpty
    push rax
    call assert

    ; ---- listPushFront: [5, 10, 20, 30] ----
    push listA
    push val5
    push 0              ; isMove=0: copy
    call listPushFront

    push listA
    call listLen
    cmp rax, 4
    sete al
    movzx rax, al
    push errLen
    push rax
    call assert

    ; ---- listBegin / listGet: first == 5 ----
    push listA
    call listBegin
    mov [rbp + it], rax
    push [rbp + it]
    push 5
    push errBegin
    call checkNode

    ; ---- listLast == 30 ----
    push listA
    call listLast
    mov [rbp + it], rax
    push [rbp + it]
    push 30
    push errLast
    call checkNode

    ; ---- 向前遍历: 5 -> 10 -> 20 -> 30 ----
    push listA
    call listBegin
    mov [rbp + it], rax

    push [rbp + it]
    push 5
    push errGet
    call checkNode

    push [rbp + it]
    call listNext
    mov [rbp + it], rax
    push [rbp + it]
    push 10
    push errNext
    call checkNode

    push [rbp + it]
    call listNext
    mov [rbp + it], rax
    push [rbp + it]
    push 20
    push errNext
    call checkNode

    push [rbp + it]
    call listNext
    mov [rbp + it], rax
    push [rbp + it]
    push 30
    push errNext
    call checkNode

    ; next 之后到达 end (vtail)
    push [rbp + it]
    call listNext
    mov [rbp + it], rax
    push listA
    call listEnd
    cmp rax, [rbp + it]
    sete al
    movzx rax, al
    push errEnd
    push rax
    call assert

    ; ---- listPrev: 从 30 往回 -> 20 ----
    push listA
    call listLast
    mov [rbp + it], rax
    push [rbp + it]
    call listPrev
    mov [rbp + it], rax
    push [rbp + it]
    push 20
    push errPrev
    call checkNode

    ; ---- listInsertBefore: 在 10 之前插入 15 (copy) -> [5, 15, 10, 20, 30] ----
    push listA
    call listBegin
    mov [rbp + it], rax          ; it = first(5)
    push [rbp + it]
    call listNext
    mov [rbp + it], rax          ; it = 10 节点
    push listA
    push [rbp + it]
    push val15
    push 0              ; isMove=0: copy
    call listInsertBefore
    mov [rbp + it], rax          ; 返回的节点就是新插入的 15
    push [rbp + it]
    push 15
    push errInsert
    call checkNode

    push listA
    call listLen
    cmp rax, 5
    sete al
    movzx rax, al
    push errInsert
    push rax
    call assert

    ; 重新从 begin 走第 2 个节点应该是 15
    push listA
    call listBegin
    mov [rbp + it], rax
    push [rbp + it]
    call listNext
    mov [rbp + it], rax
    push [rbp + it]
    push 15
    push errInsert
    call checkNode

    ; ---- listInsertAfter: 在 5 之后插入 7 (copy) -> [5, 7, 15, 10, 20, 30] ----
    push listA
    call listBegin
    mov [rbp + it], rax          ; it = first(5)
    push listA
    push [rbp + it]
    push val7
    push 0              ; isMove=0: copy
    call listInsertAfter
    mov [rbp + it], rax          ; 返回的节点就是新插入的 7

    push listA
    call listLen
    cmp rax, 6
    sete al
    movzx rax, al
    push errInsert
    push rax
    call assert

    ; 第 2 个节点应该是 7
    push listA
    call listBegin
    mov [rbp + it], rax
    push [rbp + it]
    call listNext
    mov [rbp + it], rax
    push [rbp + it]
    push 7
    push errInsert
    call checkNode

    ; ---- listInsertBefore: 在 7 之前移动 25 (move) -> [5, 25, 7, 15, 10, 20, 30] ----
    push listA
    call listBegin
    mov [rbp + it], rax          ; it = first(5)
    push [rbp + it]
    call listNext
    mov [rbp + it], rax          ; it = 7 节点
    push listA
    push [rbp + it]
    push val25
    push 1              ; isMove=1: move
    call listInsertBefore
    mov [rbp + it], rax          ; 返回的节点就是新插入的 25
    push [rbp + it]
    push 25
    push errInsert
    call checkNode

    push listA
    call listLen
    cmp rax, 7
    sete al
    movzx rax, al
    push errInsert
    push rax
    call assert

    ; ---- listSet: 把 7 设为 20 (copy) -> [5, 25, 20, 15, 10, 20, 30] ----
    push listA
    call listBegin
    mov [rbp + it], rax
    push [rbp + it]
    call listNext
    mov [rbp + it], rax          ; it = first(5)->next = 25
    push [rbp + it]
    call listNext
    mov [rbp + it], rax          ; it = 7 节点
    push listA
    push [rbp + it]
    push val20
    push 0              ; isMove=0: copy
    call listSet
    push [rbp + it]
    push 20
    push errSet
    call checkNode

    ; ---- listRemove: 移除 15 -> [5, 25, 20, 10, 20, 30] ----
    ; 找到 15：begin -> 25 -> 20 -> 15
    push listA
    call listBegin
    mov [rbp + it], rax
    push [rbp + it]              ; 5
    call listNext
    mov [rbp + it], rax          ; 25
    push [rbp + it]
    call listNext
    mov [rbp + it], rax          ; 20
    push [rbp + it]
    call listNext
    mov [rbp + it], rax          ; 15
    push listA
    push [rbp + it]
    call listRemove

    push listA
    call listLen
    cmp rax, 6
    sete al
    movzx rax, al
    push errRemove
    push rax
    call assert

    ; ---- listPopFront: [25, 20, 10, 20, 30] ----
    push listA
    call listPopFront
    push listA
    call listLen
    cmp rax, 5
    sete al
    movzx rax, al
    push errPop
    push rax
    call assert

    push listA
    call listBegin
    mov [rbp + it], rax
    push [rbp + it]
    push 25
    push errPop
    call checkNode

    ; ---- listPopBack: [25, 20, 10, 20] ----
    push listA
    call listPopBack
    push listA
    call listLen
    cmp rax, 4
    sete al
    movzx rax, al
    push errPop
    push rax
    call assert

    push listA
    call listLast
    mov [rbp + it], rax
    push [rbp + it]
    push 20
    push errPop
    call checkNode

    ; ---- listPushBack: 追加 30 (move) -> [25, 20, 10, 20, 30] ----
    push listA
    push val30
    push 1              ; isMove=1: move
    call listPushBack
    push listA
    call listLast
    mov [rbp + it], rax
    push [rbp + it]
    push 30
    push errPop
    call checkNode

    ; ---- listClear: [] ----
    push listA
    call listClear
    push listA
    call listLen
    cmp rax, 0
    sete al
    movzx rax, al
    push errClear
    push rax
    call assert

    push listA
    call listIsEmpty
    cmp rax, 1
    sete al
    movzx rax, al
    push errClear
    push rax
    call assert

    ; ---- 重新填充 [10, 20, 30] ----
    push listA
    push val10
    push 0              ; isMove=0: copy
    call listPushBack
    push listA
    push val20
    push 0              ; isMove=0: copy
    call listPushBack
    push listA
    push val30
    push 0              ; isMove=0: copy
    call listPushBack

    ; ---- listCopy: B = A -> [10, 20, 30] ----
    push listB
    push listA
    call listCopy
    push listB
    call listLen
    cmp rax, 3
    sete al
    movzx rax, al
    push errCopy
    push rax
    call assert

    ; ---- listEq(A, B) == 1 ----
    push listB
    push listA
    call listEq
    cmp rax, 1
    sete al
    movzx rax, al
    push errEq
    push rax
    call assert

    ; ---- listCmp(A, B) == 0 ----
    push listB
    push listA
    call listCmp
    cmp rax, 0
    sete al
    movzx rax, al
    push errCmp
    push rax
    call assert

    ; 修改 B 的第二项: B = [10, 25, 30]
    push listB
    call listBegin
    mov [rbp + it], rax
    push [rbp + it]
    call listNext
    mov [rbp + it], rax          ; it = B 的第二项
    push listB
    push [rbp + it]
    push val25
    push 0              ; isMove=0: copy
    call listSet

    ; ---- listEq(A, B) == 0 ----
    push listB
    push listA
    call listEq
    cmp rax, 0
    sete al
    movzx rax, al
    push errEq
    push rax
    call assert

    ; ---- listCmp(A, B) < 0 (20 < 25) ----
    push listA
    push listB
    call listCmp
    test rax, rax
    js .cmpNegOk
    xor rax, rax
    jmp .cmpAssert
.cmpNegOk:
    mov rax, 1
.cmpAssert:
    push errCmp
    push rax
    call assert

    ; ---- listHash: A 和 (恢复后的) B hash 相同 ----
    push listA
    call listHash
    mov [rbp + it], rax          ; 复用 it 存 hashA

    ; 把 B 的第二项改回 20 -> B = [10, 20, 30]
    push listB
    call listBegin
    mov rbx, rax
    push rbx
    call listNext
    push listB
    push rax
    push val20
    push 0              ; isMove=0: copy
    call listSet

    push listB
    call listHash
    cmp rax, [rbp + it]
    sete al
    movzx rax, al
    push errHash
    push rax
    call assert

    ; ---- listMove: A 转移到 B, A 被重置 ----
    push listB
    push listA
    call listMove

    cmp qword [listA + List_vhead], 0
    sete al
    movzx rax, al
    push errMove
    push rax
    call assert

    cmp qword [listA + List_len], 0
    sete al
    movzx rax, al
    push errMove
    push rax
    call assert

    cmp qword [listB + List_len], 3
    sete al
    movzx rax, al
    push errMove
    push rax
    call assert

    ; ---- listSwap: A 和 B 交换 ----
    ; 重新 init A
    push listA
    push int64Meta
    call listInit
    push listA
    push val1
    push 0              ; isMove=0: copy
    call listPushBack

    push listA
    push listB
    call listSwap

    cmp qword [listA + List_len], 3
    sete al
    movzx rax, al
    push errSwap
    push rax
    call assert

    cmp qword [listB + List_len], 1
    sete al
    movzx rax, al
    push errSwap
    push rax
    call assert

    ; ---- listDrop 两个 list ----
    push listA
    call listDrop
    push listB
    call listDrop

    cmp qword [listA + List_vhead], 0
    sete al
    movzx rax, al
    push errDrop
    push rax
    call assert

    cmp qword [listA + List_vtail], 0
    sete al
    movzx rax, al
    push errDrop
    push rax
    call assert

    cmp qword [listB + List_vhead], 0
    sete al
    movzx rax, al
    push errDrop
    push rax
    call assert

    ; ---- listMeta 字段检查 ----
    cmp qword [listMeta + ValueMeta_objsize], sizeof_List
    sete al
    movzx rax, al
    push errMeta
    push rax
    call assert

    cmp qword [listMeta + ValueMeta_align], 8
    sete al
    movzx rax, al
    push errMeta
    push rax
    call assert

    mov rax, [listMeta + ValueMeta_drop]
    cmp rax, listDrop
    sete al
    movzx rax, al
    push errMeta
    push rax
    call assert

    mov rax, [listMeta + ValueMeta_cmp]
    cmp rax, listCmp
    sete al
    movzx rax, al
    push errMeta
    push rax
    call assert

    mov rax, [listMeta + ValueMeta_eq]
    cmp rax, listEq
    sete al
    movzx rax, al
    push errMeta
    push rax
    call assert

    mov rax, [listMeta + ValueMeta_hash]
    cmp rax, listHash
    sete al
    movzx rax, al
    push errMeta
    push rax
    call assert

    mov rax, [listMeta + ValueMeta_copy]
    cmp rax, listCopy
    sete al
    movzx rax, al
    push errMeta
    push rax
    call assert

    mov rax, [listMeta + ValueMeta_move]
    cmp rax, listMove
    sete al
    movzx rax, al
    push errMeta
    push rax
    call assert

    mov rax, 0
    end
    ret 24
