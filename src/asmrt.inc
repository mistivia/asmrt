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

; ---- runtime exported symbols ----

; main.asm
extern rtExit

; io.asm
extern ioOpen
extern ioClose
extern ioRead
extern ioWrite
extern ioSeek
extern ioWriteNum
extern ioWriteChar

; fs.asm
extern fsStat
extern fsFstat
extern fsMkdir
extern fsRmdir
extern fsUnlink

; mem.asm
extern memAlloc
extern memFree
extern memReloc
extern memCopy
extern memMove
extern memFill

; assert.asm
extern assert

; str.asm
extern strLen
extern strEq

; sort.asm
extern sort

%endif ; ASMRT_INC
