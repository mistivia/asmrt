; list.asm -- doubly-linked list module, mirroring ckit's cbase/cbase.h
;
; A doubly-linked list whose element type is described by a ValueMeta
; bundle (size/align plus optional drop/cmp/eq/hash/copy/move callbacks),
; exactly like the vec module.  All trait callbacks speak the asmrt
; custom ABI.  The list owns sentinel head/tail nodes (vhead/vtail); a
; data node is a ListNodeBase (prev/next) followed by the element's
; bytes, so listGet(it) is just it + sizeof_ListNodeBase.
;
; Memory management goes through the runtime's memAlloc/memFree, whole-
; header swaps via memSwap -- all custom-ABI wrappers around libc, so no
; bare syscalls and no hexalign needed here.
;
; Naming follows cbase's list_* C functions (listInit/listPushBack/
; listInsertBefore/...), except every asmrt symbol is camelCase.
; The exported listMeta ValueMeta describes struct List itself, for
; nested containers (e.g. a list of lists).

%include "asmrt.inc"

; struct ListNode
resetOffset
%assign ListNode_prev offset
incOffset 8
%assign ListNode_next offset
incOffset 8
%assign sizeof_ListNodeBase offset
; endstruct ListNode

section .data
    global listMeta
listMeta:
    dq sizeof_List                   ; .size
    dq 8                             ; .align
    dq listDrop                      ; .drop
    dq listCmp                       ; .cmp
    dq listEq                        ; .eq
    dq listHash                      ; .hash
    dq listCopy                      ; .copy
    dq listMove                      ; .move

section .text
    global listInit
    global listDrop
    global listClear
    global listCopy
    global listMove
    global listSwap
    global listInsertBefore
    global listInsertAfter
    global listRemove
    global listSet
    global listBegin
    global listLast
    global listEnd
    global listNext
    global listPrev
    global listGet
    global listLen
    global listIsEmpty
    global listPushBack
    global listPushFront
    global listPopBack
    global listPopFront
    global listEq
    global listCmp
    global listHash
    extern memAlloc
    extern memFree
    extern memSwap
    extern fnv64

; ---- internal helpers ----

; nodeData(pIter) -> pData ; pointer to the node's element bytes
nodeData:
    ; args: pIter
    argnum 1
    %assign pIter arg(1)
    begin
    ; the element payload rides right after the prev/next header
    mov rax, [rbp + pIter]
    add rax, sizeof_ListNodeBase
    end
    ret 8

; newNode(elemSize) -> pNode ; allocate a data node (16 + elemSize bytes)
newNode:
    ; args: elemSize
    argnum 1
    %assign elemSize arg(1)
    begin
    ; grab one block for both the link header and the element
    mov rax, [rbp + elemSize]
    add rax, sizeof_ListNodeBase
    push rax
    call memAlloc
    end
    ret 8

; ---- construction / destruction ----

; listInit(pList, pMeta) -> 0.  Allocate the vhead/vtail sentinel nodes
; and attach the ValueMeta.
listInit:
    ; args: pList, pMeta
    argnum 2
    %assign pList arg(1)
    %assign pMeta arg(2)
    begin

    ; head sentinel anchors the front of the list
    push sizeof_ListNodeBase
    call memAlloc
    mov rbx, [rbp + pList]
    mov [rbx + List_vhead], rax

    ; tail sentinel anchors the back of the list
    push sizeof_ListNodeBase
    call memAlloc
    mov rbx, [rbp + pList]
    mov [rbx + List_vtail], rax

    ; an empty ring: sentinels point at each other, len=0, meta attached
    mov rax, [rbp + pList]
    mov rbx, [rax + List_vhead]
    mov rcx, [rax + List_vtail]
    mov qword [rbx + ListNode_prev], 0
    mov [rbx + ListNode_next], rcx
    mov [rcx + ListNode_prev], rbx
    mov qword [rcx + ListNode_next], 0
    mov qword [rax + List_len], 0
    mov rdx, [rbp + pMeta]
    mov [rax + List_pValueMeta], rdx

    ; success
    xor rax, rax
    end
    ret 16

; listDrop(pList) -- drop every element, free every node (sentinels
; included), and reset the list in place.
listDrop:
    ; args: pList
    argnum 1
    %assign pList arg(1)
    begin
    ; local variables
    resetOffset
    ; cur 8 bytes
    decOffset 8
    %assign cur offset
    ; next 8 bytes
    decOffset 8
    %assign next offset
    ; endlocal
    sub rsp, (-offset)

    ; free every node (and every element) the list owns
    mov rax, [rbp + pList]
    mov rax, [rax + List_vhead]
    mov [rbp + cur], rax
.loop:
    cmp qword [rbp + cur], 0
    je .done

    ; keep the next pointer handy before releasing this node
    mov rax, [rbp + cur]
    mov rax, [rax + ListNode_next]
    mov [rbp + next], rax

    ; skip the sentinel nodes when dropping element data
    mov rax, [rbp + pList]
    mov rbx, [rbp + cur]
    cmp rbx, [rax + List_vhead]
    je .free
    cmp rbx, [rax + List_vtail]
    je .free

    mov rax, [rbp + cur]
    add rax, sizeof_ListNodeBase
    push rax
    mov rax, [rbp + pList]
    mov rax, [rax + List_pValueMeta]
    call [rax + ValueMeta_drop]
.free:
    ; release the node
    push qword [rbp + cur]
    call memFree

    ; keep walking
    mov rax, [rbp + next]
    mov [rbp + cur], rax
    jmp .loop
.done:
    ; leave the header fully reset so the list is reusable
    mov rax, [rbp + pList]
    mov qword [rax + List_vhead], 0
    mov qword [rax + List_vtail], 0
    mov qword [rax + List_len], 0
    mov qword [rax + List_pValueMeta], 0
    end
    ret 8

; listClear(pList) -- drop every element, free data nodes, keep the
; sentinels and relink them.
listClear:
    ; args: pList
    argnum 1
    %assign pList arg(1)
    begin
    ; local variables
    resetOffset
    ; cur 8 bytes
    decOffset 8
    %assign cur offset
    ; next 8 bytes
    decOffset 8
    %assign next offset
    ; endlocal
    sub rsp, (-offset)

    ; drop the elements and the data nodes, but keep the sentinels
    mov rax, [rbp + pList]
    mov rax, [rax + List_vhead]
    mov rax, [rax + ListNode_next]
    mov [rbp + cur], rax

    ; nothing to do on an empty list
    mov rax, [rbp + pList]
    mov rax, [rax + List_vtail]
    cmp [rbp + cur], rax
    je .relink
.loop:
    ; remember where to continue while this node is being torn down
    mov rax, [rbp + cur]
    mov rax, [rax + ListNode_next]
    mov [rbp + next], rax

    ; hand the element's owned data back
    mov rax, [rbp + cur]
    add rax, sizeof_ListNodeBase
    push rax
    mov rax, [rbp + pList]
    mov rax, [rax + List_pValueMeta]
    call [rax + ValueMeta_drop]

    ; release this node
    push qword [rbp + cur]
    call memFree

    ; continue until everything before vtail is gone
    mov rax, [rbp + next]
    mov [rbp + cur], rax
    mov rax, [rbp + pList]
    mov rbx, [rax + List_vtail]
    cmp [rbp + cur], rbx
    jne .loop
.relink:
    ; put the sentinels back in a ring and reset len
    mov rax, [rbp + pList]
    mov rbx, [rax + List_vhead]
    mov rcx, [rax + List_vtail]
    mov [rbx + ListNode_next], rcx
    mov [rcx + ListNode_prev], rbx
    mov qword [rax + List_len], 0
    end
    ret 8

; ---- whole-list operations ----

; listCopy(pDst, pSrc) -- deep copy src into dst.  No-op when dst == src.
listCopy:
    ; args: pDst, pSrc
    argnum 2
    %assign pDst arg(1)
    %assign pSrc arg(2)
    begin
    ; local variables
    resetOffset
    ; it 8 bytes
    decOffset 8
    %assign it offset
    ; endlocal
    sub rsp, (-offset)

    ; self-copy would just churn, so bail out
    mov rax, [rbp + pDst]
    cmp rax, [rbp + pSrc]
    je .done

    mov rax, [rbp + pSrc]
    mov rax, [rax + List_pValueMeta]
    ; start clean with the same element meta as the source
    push qword [rbp + pDst]
    push rax
    call listInit

    ; feed the source's elements into the fresh list
    mov rax, [rbp + pSrc]
    mov rax, [rax + List_vhead]
    mov rax, [rax + ListNode_next]
    mov [rbp + it], rax
.loop:
    mov rax, [rbp + pSrc]
    mov rbx, [rax + List_vtail]
    cmp [rbp + it], rbx
    je .done

    mov rax, [rbp + it]
    add rax, sizeof_ListNodeBase
    ; append a copy of this element
    push qword [rbp + pDst]
    push rax
    push 0              ; isMove=0: copy
    call listPushBack

    ; on to the next source element
    mov rax, [rbp + it]
    mov rax, [rax + ListNode_next]
    mov [rbp + it], rax
    jmp .loop
.done:
    end
    ret 16

; listMove(pDst, pSrc) -- transfer ownership of src's nodes to dst and
; reset src.  No-op when dst == src.
listMove:
    ; args: pDst, pSrc
    argnum 2
    %assign pDst arg(1)
    %assign pSrc arg(2)
    begin

    ; self-move is a no-op
    mov rax, [rbp + pDst]
    cmp rax, [rbp + pSrc]
    je .done

    ; take over the source's storage wholesale
    mov rcx, [rbp + pSrc]
    mov rax, [rbp + pDst]
    mov rdx, [rcx + List_vhead]
    mov [rax + List_vhead], rdx
    mov rdx, [rcx + List_vtail]
    mov [rax + List_vtail], rdx
    mov rdx, [rcx + List_len]
    mov [rax + List_len], rdx
    mov rdx, [rcx + List_pValueMeta]
    mov [rax + List_pValueMeta], rdx

    ; leave the source as an empty shell
    mov qword [rcx + List_vhead], 0
    mov qword [rcx + List_vtail], 0
    mov qword [rcx + List_len], 0
    mov qword [rcx + List_pValueMeta], 0
.done:
    end
    ret 16

; listSwap(pA, pB) -- swap two whole list headers
listSwap:
    ; args: pA, pB
    argnum 2
    %assign pA arg(1)
    %assign pB arg(2)
    begin

    ; trade the two headers (and thereby their whole contents)
    push qword [rbp + pA]
    push qword [rbp + pB]
    push sizeof_List
    call memSwap
    end
    ret 16

; ---- insertion / removal ----

; listInsertBefore(pList, pIter, pElem, isMove) -> pNode ; insert elem
; into a new node placed before pIter; isMove != 0 moves elem in via
; ValueMeta.move, otherwise a copy is made (ValueMeta.copy).
; Returns NULL when pIter is NULL or is vhead.
listInsertBefore:
    ; args: pList, pIter, pElem, isMove
    argnum 4
    %assign pList arg(1)
    %assign pIter arg(2)
    %assign pElem arg(3)
    %assign isMove arg(4)
    begin
    ; local variables
    resetOffset
    ; node 8 bytes
    decOffset 8
    %assign node offset
    ; endlocal
    sub rsp, (-offset)

    ; refuse to insert before vhead -- there is no spot
    cmp qword [rbp + pIter], 0
    je .fail
    mov rax, [rbp + pIter]
    cmp qword [rax + ListNode_prev], 0
    je .fail

    ; make room for the element inside the new node
    mov rax, [rbp + pList]
    mov rax, [rax + List_pValueMeta]
    mov rax, [rax + ValueMeta_objsize]
    push rax
    call newNode
    mov [rbp + node], rax

    ; wire the new node between pIter->prev and pIter
    mov rax, [rbp + node]
    mov rbx, [rbp + pIter]
    mov rcx, [rbx + ListNode_prev]
    mov [rax + ListNode_prev], rcx
    mov [rax + ListNode_next], rbx

    ; keep a copy, or take ownership by moving, as requested
    add rax, sizeof_ListNodeBase
    push rax
    push qword [rbp + pElem]
    mov rax, [rbp + pList]
    mov rax, [rax + List_pValueMeta]
    cmp qword [rbp + isMove], 0
    jne .moveElem
    call [rax + ValueMeta_copy]
    jmp .link
.moveElem:
    call [rax + ValueMeta_move]
.link:
    ; close the ring: the neighbours now point at the new node
    mov rax, [rbp + pIter]
    mov rbx, [rax + ListNode_prev]
    mov rcx, [rbp + node]
    mov [rbx + ListNode_next], rcx
    mov [rax + ListNode_prev], rcx

    ; keep the length in sync
    mov rax, [rbp + pList]
    inc qword [rax + List_len]

    ; hand the new node back to the caller
    mov rax, [rbp + node]
    jmp .done
.fail:
    ; invalid iterator: nothing inserted, signal with NULL
    xor rax, rax
.done:
    end
    ret 32

; listInsertAfter(pList, pIter, pElem, isMove) -> pNode ; insert elem
; into a new node placed after pIter; isMove != 0 moves elem in via
; ValueMeta.move, otherwise a copy is made (ValueMeta.copy).
; Returns NULL when pIter is NULL or is vtail.
listInsertAfter:
    ; args: pList, pIter, pElem, isMove
    argnum 4
    %assign pList arg(1)
    %assign pIter arg(2)
    %assign pElem arg(3)
    %assign isMove arg(4)
    begin
    ; local variables
    resetOffset
    ; node 8 bytes
    decOffset 8
    %assign node offset
    ; endlocal
    sub rsp, (-offset)

    ; refuse to insert after vtail -- there is no spot
    cmp qword [rbp + pIter], 0
    je .fail
    mov rax, [rbp + pIter]
    cmp qword [rax + ListNode_next], 0
    je .fail

    ; make room for the element inside the new node
    mov rax, [rbp + pList]
    mov rax, [rax + List_pValueMeta]
    mov rax, [rax + ValueMeta_objsize]
    push rax
    call newNode
    mov [rbp + node], rax

    ; wire the new node between pIter and pIter->next
    mov rax, [rbp + node]
    mov rbx, [rbp + pIter]
    mov rcx, [rbx + ListNode_next]
    mov [rax + ListNode_next], rcx
    mov [rax + ListNode_prev], rbx

    ; keep a copy, or take ownership by moving, as requested
    add rax, sizeof_ListNodeBase
    push rax
    push qword [rbp + pElem]
    mov rax, [rbp + pList]
    mov rax, [rax + List_pValueMeta]
    cmp qword [rbp + isMove], 0
    jne .moveElem
    call [rax + ValueMeta_copy]
    jmp .link
.moveElem:
    call [rax + ValueMeta_move]
.link:
    ; close the ring: the neighbours now point at the new node
    mov rax, [rbp + pIter]
    mov rbx, [rax + ListNode_next]
    mov rcx, [rbp + node]
    mov [rbx + ListNode_prev], rcx
    mov [rax + ListNode_next], rcx

    ; keep the length in sync
    mov rax, [rbp + pList]
    inc qword [rax + List_len]

    ; hand the new node back to the caller
    mov rax, [rbp + node]
    jmp .done
.fail:
    ; invalid iterator: nothing inserted, signal with NULL
    xor rax, rax
.done:
    end
    ret 32

; listRemove(pList, pIter) -- drop elem, unlink and free the node.
; No-op when pIter is NULL or is a sentinel.
listRemove:
    ; args: pList, pIter
    argnum 2
    %assign pList arg(1)
    %assign pIter arg(2)
    begin

    ; only real data nodes can be removed -- sentinels and NULL are off-limits
    cmp qword [rbp + pIter], 0
    je .done
    mov rax, [rbp + pIter]
    cmp qword [rax + ListNode_prev], 0
    je .done
    cmp qword [rax + ListNode_next], 0
    je .done

    ; release whatever the element owns
    mov rax, [rbp + pIter]
    add rax, sizeof_ListNodeBase
    push rax
    mov rax, [rbp + pList]
    mov rax, [rax + List_pValueMeta]
    call [rax + ValueMeta_drop]

    ; splice the node out so its neighbours point at each other
    mov rax, [rbp + pIter]
    mov rbx, [rax + ListNode_prev]
    mov rcx, [rax + ListNode_next]
    mov [rbx + ListNode_next], rcx
    mov [rcx + ListNode_prev], rbx

    ; release the node itself
    push qword [rbp + pIter]
    call memFree

    ; keep the length in sync
    mov rax, [rbp + pList]
    dec qword [rax + List_len]
.done:
    end
    ret 16

; listSet(pList, pIter, pElem, isMove) -- replace elem at pIter;
; isMove != 0 moves elem in via ValueMeta.move, otherwise a copy is
; made (ValueMeta.copy).  No-op when pIter is NULL or is a sentinel.
listSet:
    ; args: pList, pIter, pElem, isMove
    argnum 4
    %assign pList arg(1)
    %assign pIter arg(2)
    %assign pElem arg(3)
    %assign isMove arg(4)
    begin

    ; only real data nodes may be rewritten
    cmp qword [rbp + pIter], 0
    je .done
    mov rax, [rbp + pIter]
    cmp qword [rax + ListNode_prev], 0
    je .done
    cmp qword [rax + ListNode_next], 0
    je .done

    ; the old value is gone before the new one comes in
    mov rax, [rbp + pIter]
    add rax, sizeof_ListNodeBase
    push rax
    mov rax, [rbp + pList]
    mov rax, [rax + List_pValueMeta]
    call [rax + ValueMeta_drop]

    ; put the replacement in place (copy or move)
    mov rax, [rbp + pIter]
    add rax, sizeof_ListNodeBase
    push rax
    push qword [rbp + pElem]
    mov rax, [rbp + pList]
    mov rax, [rax + List_pValueMeta]
    cmp qword [rbp + isMove], 0
    jne .moveElem
    call [rax + ValueMeta_copy]
    jmp .done
.moveElem:
    call [rax + ValueMeta_move]
.done:
    end
    ret 32

listBegin:
    ; args: pList
    argnum 1
    %assign pList arg(1)
    begin

    ; first element is right after vhead (vtail itself when empty)
    mov rax, [rbp + pList]
    mov rax, [rax + List_vhead]
    mov rax, [rax + ListNode_next]
    end
    ret 8

; listLast(pList) -> pNode ; last data node, NULL if empty
listLast:
    ; args: pList
    argnum 1
    %assign pList arg(1)
    begin

    ; last element is right before vtail (nothing when empty)
    mov rax, [rbp + pList]
    mov rbx, [rax + List_vhead]
    mov rax, [rax + List_vtail]
    mov rcx, [rax + ListNode_prev]
    cmp rcx, rbx
    je .empty
    mov rax, rcx
    jmp .done
.empty:
    xor rax, rax
.done:
    end
    ret 8

; listEnd(pList) -> pNode ; the vtail sentinel
listEnd:
    ; args: pList
    argnum 1
    %assign pList arg(1)
    begin

    ; vtail is the end marker
    mov rax, [rbp + pList]
    mov rax, [rax + List_vtail]
    end
    ret 8

; listNext(pIter) -> pNode ; pIter->next, NULL when pIter is NULL
listNext:
    ; args: pIter
    argnum 1
    %assign pIter arg(1)
    begin

    ; move to the next node
    cmp qword [rbp + pIter], 0
    je .empty
    mov rax, [rbp + pIter]
    mov rax, [rax + ListNode_next]
    jmp .done
.empty:
    xor rax, rax
.done:
    end
    ret 8

; listPrev(pIter) -> pNode ; pIter->prev, NULL when pIter is NULL, would
; be vhead, or pIter is vhead.
listPrev:
    ; args: pIter
    argnum 1
    %assign pIter arg(1)
    begin

    ; step back one node, never exposing vhead
    cmp qword [rbp + pIter], 0
    je .empty
    mov rax, [rbp + pIter]
    mov rbx, [rax + ListNode_prev]
    test rbx, rbx
    jz .empty
    mov rax, [rbx + ListNode_prev]
    test rax, rax
    jz .empty
    mov rax, rbx
    jmp .done
.empty:
    xor rax, rax
.done:
    end
    ret 8

; listGet(pIter) -> pElem ; pointer to the node's element, NULL when NULL
listGet:
    ; args: pIter
    argnum 1
    %assign pIter arg(1)
    begin

    ; expose the element this node carries
    cmp qword [rbp + pIter], 0
    je .empty
    mov rax, [rbp + pIter]
    add rax, sizeof_ListNodeBase
    jmp .done
.empty:
    xor rax, rax
.done:
    end
    ret 8

; listLen(pList) -> len
listLen:
    ; args: pList
    argnum 1
    %assign pList arg(1)
    begin

    ; report how many elements are stored
    mov rax, [rbp + pList]
    mov rax, [rax + List_len]
    end
    ret 8

; listIsEmpty(pList) -> 1 if len == 0, else 0
listIsEmpty:
    ; args: pList
    argnum 1
    %assign pList arg(1)
    begin

    ; a zero length is the emptiness test
    mov rax, [rbp + pList]
    cmp qword [rax + List_len], 0
    sete al
    movzx rax, al
    end
    ret 8

; listPushBack(pList, pElem, isMove) -> pNode ; append elem to the
; tail; isMove != 0 moves elem in via ValueMeta.move, otherwise a copy
; is made (ValueMeta.copy).
listPushBack:
    ; args: pList, pElem, isMove
    argnum 3
    %assign pList arg(1)
    %assign pElem arg(2)
    %assign isMove arg(3)
    begin

    ; append: insert right before vtail
    mov rax, [rbp + pList]
    mov rax, [rax + List_vtail]
    push qword [rbp + pList]
    push rax
    push qword [rbp + pElem]
    push qword [rbp + isMove]
    call listInsertBefore
    end
    ret 24

; listPushFront(pList, pElem, isMove) -> pNode ; prepend elem to the
; head; isMove != 0 moves elem in via ValueMeta.move, otherwise a copy
; is made (ValueMeta.copy).
listPushFront:
    ; args: pList, pElem, isMove
    argnum 3
    %assign pList arg(1)
    %assign pElem arg(2)
    %assign isMove arg(3)
    begin

    ; prepend: insert right after vhead
    mov rax, [rbp + pList]
    mov rax, [rax + List_vhead]
    push qword [rbp + pList]
    push rax
    push qword [rbp + pElem]
    push qword [rbp + isMove]
    call listInsertAfter
    end
    ret 24

; listPopBack(pList) -- drop and remove the last elem; no-op if empty
listPopBack:
    ; args: pList
    argnum 1
    %assign pList arg(1)
    begin

    ; drop the last element
    mov rax, [rbp + pList]
    mov rax, [rax + List_vtail]
    mov rax, [rax + ListNode_prev]
    push qword [rbp + pList]
    push rax
    call listRemove
    end
    ret 8

; listPopFront(pList) -- drop and remove the first elem; no-op if empty
listPopFront:
    ; args: pList
    argnum 1
    %assign pList arg(1)
    begin

    ; drop the first element
    mov rax, [rbp + pList]
    mov rax, [rax + List_vhead]
    mov rax, [rax + ListNode_next]
    push qword [rbp + pList]
    push rax
    call listRemove
    end
    ret 8

; ---- comparisons / hashing ----

; listEq(pA, pB) -> 1 if both lists have the same length and every pair
; of elements compares equal via a's meta->eq, else 0.
listEq:
    ; args: pA, pB
    argnum 2
    %assign pA arg(1)
    %assign pB arg(2)
    begin
    ; local variables
    resetOffset
    ; ia 8 bytes
    decOffset 8
    %assign ia offset
    ; ib 8 bytes
    decOffset 8
    %assign ib offset
    ; endlocal
    sub rsp, (-offset)

    ; different lengths can never be equal
    mov rax, [rbp + pA]
    mov rbx, [rbp + pB]
    mov rcx, [rax + List_len]
    cmp rcx, [rbx + List_len]
    jne .notEq

    ; walk both lists side by side
    mov rax, [rbp + pA]
    mov rax, [rax + List_vhead]
    mov rax, [rax + ListNode_next]
    mov [rbp + ia], rax

    mov rax, [rbp + pB]
    mov rax, [rax + List_vhead]
    mov rax, [rax + ListNode_next]
    mov [rbp + ib], rax
.loop:
    mov rax, [rbp + pA]
    mov rbx, [rax + List_vtail]
    cmp [rbp + ia], rbx
    je .eq

    ; this pair must agree
    mov rax, [rbp + ia]
    add rax, sizeof_ListNodeBase
    push rax
    mov rax, [rbp + ib]
    add rax, sizeof_ListNodeBase
    push rax
    mov rax, [rbp + pA]
    mov rax, [rax + List_pValueMeta]
    call [rax + ValueMeta_eq]
    test rax, rax
    jz .notEq

    ; advance both walks together
    mov rax, [rbp + ia]
    mov rax, [rax + ListNode_next]
    mov [rbp + ia], rax
    mov rax, [rbp + ib]
    mov rax, [rax + ListNode_next]
    mov [rbp + ib], rax
    jmp .loop
.eq:
    ; every pair matched -- equal
    mov rax, 1
    jmp .done
.notEq:
    xor rax, rax
.done:
    end
    ret 16

; listCmp(pA, pB) -> lexicographic order: -1/0/1.  Elements are compared
; with a's meta->cmp; shorter list is less when all shared elements tie.
listCmp:
    ; args: pA, pB
    argnum 2
    %assign pA arg(1)
    %assign pB arg(2)
    begin
    ; local variables
    resetOffset
    ; ia 8 bytes
    decOffset 8
    %assign ia offset
    ; ib 8 bytes
    decOffset 8
    %assign ib offset
    ; endlocal
    sub rsp, (-offset)

    ; walk both lists side by side
    mov rax, [rbp + pA]
    mov rax, [rax + List_vhead]
    mov rax, [rax + ListNode_next]
    mov [rbp + ia], rax

    mov rax, [rbp + pB]
    mov rax, [rax + List_vhead]
    mov rax, [rax + ListNode_next]
    mov [rbp + ib], rax
.loop:
    mov rax, [rbp + pA]
    mov rbx, [rax + List_vtail]
    cmp [rbp + ia], rbx
    je .compareLens
    mov rax, [rbp + pB]
    mov rbx, [rax + List_vtail]
    cmp [rbp + ib], rbx
    je .compareLens

    ; the first differing pair decides the order
    mov rax, [rbp + ia]
    add rax, sizeof_ListNodeBase
    push rax
    mov rax, [rbp + ib]
    add rax, sizeof_ListNodeBase
    push rax
    mov rax, [rbp + pA]
    mov rax, [rax + List_pValueMeta]
    call [rax + ValueMeta_cmp]
    test rax, rax
    jnz .done

    ; keep the walks in lockstep
    mov rax, [rbp + ia]
    mov rax, [rax + ListNode_next]
    mov [rbp + ia], rax
    mov rax, [rbp + ib]
    mov rax, [rax + ListNode_next]
    mov [rbp + ib], rax
    jmp .loop
.compareLens:
    ; shared prefix equal -- shorter list sorts first
    mov rax, [rbp + pA]
    mov rbx, [rbp + pB]
    mov rax, [rax + List_len]
    mov rbx, [rbx + List_len]
    cmp rax, rbx
    jl .less
    jg .greater
    xor rax, rax
    jmp .done
.less:
    ; a ran dry first: a is the shorter one
    mov rax, -1
    jmp .done
.greater:
    ; b ran dry first: a is the longer one
    mov rax, 1
.done:
    end
    ret 16

; listHash(pList) -> deterministic FNV-1a hash over the element hashes:
; each element's meta->hash is folded through fnv64, exactly like
; cbase's list_hash.
listHash:
    ; args: pList
    argnum 1
    %assign pList arg(1)
    begin
    ; local variables
    resetOffset
    ; hash 8 bytes
    decOffset 8
    %assign hash offset
    ; it 8 bytes
    decOffset 8
    %assign it offset
    ; elemHash 8 bytes
    decOffset 8
    %assign elemHash offset
    ; endlocal
    sub rsp, (-offset)

    ; seed the running hash with the FNV basis
    mov rax, FNV_OFFSET_BASIS
    mov [rbp + hash], rax

    ; fold every element's identity into the hash
    mov rax, [rbp + pList]
    mov rax, [rax + List_vhead]
    mov rax, [rax + ListNode_next]
    mov [rbp + it], rax
.loop:
    mov rax, [rbp + pList]
    mov rbx, [rax + List_vtail]
    cmp [rbp + it], rbx
    je .done

    ; this element's contribution comes from its meta
    mov rax, [rbp + it]
    add rax, sizeof_ListNodeBase
    push rax
    mov rax, [rbp + pList]
    mov rax, [rax + List_pValueMeta]
    call [rax + ValueMeta_hash]
    mov [rbp + elemHash], rax

    ; mix that contribution into the running hash
    lea rax, [rbp + elemHash]
    push rax
    push 8
    push qword [rbp + hash]
    call fnv64
    mov [rbp + hash], rax

    ; on to the next element
    mov rax, [rbp + it]
    mov rax, [rax + ListNode_next]
    mov [rbp + it], rax
    jmp .loop
.done:
    mov rax, [rbp + hash]
    end
    ret 8
