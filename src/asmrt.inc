; asmrt.inc -- shared header for the asmrt runtime
;
; Contains the custom-ABI support macros plus extern declarations for
; every function the runtime exposes. Any file that uses asmrt (including
; the runtime's own implementation files) only needs to
; %include "asmrt.inc" -- no need to hand-write extern lines one by one.
; (NASM allows a symbol to be both extern and global+defined in the same
;  file; the definition in this file wins, so implementation files can
;  safely include this header too.)
;
; Custom ABI conventions:
;   - Arguments are pushed onto the stack by the caller (never passed in
;     registers), in declaration order (the first argument is pushed
;     first).
;   - The callee cleans up its own arguments with ret N (N = total
;     argument bytes).
;   - The return value always goes in rax.
;   - Aside from rax, every register is considered clobbered after any
;     call (a custom-ABI call, a real-ABI call, or a bare syscall).
;     Because of that, all variables live on the stack: parameters and
;     locals are both accessed as [rbp+N] / [rbp-N] through %define
;     aliases, and registers only ever hold a scratch value for the
;     duration of one expression -- never carried across a call.
;
; begin/end: set up / tear down the standard stack frame.
;   begin = push rbp; mov rbp, rsp
;   end   = mov rsp, rbp; pop rbp
;   The sub rsp, N for locals goes right after begin, before the body of
;   the function; as long as every local variable itself occupies a
;   multiple of 8 bytes (hard rule, see AGENTS.md), N is automatically a
;   multiple of 8 too -- no extra rounding needed.
;
; hexalign: dynamic stack alignment at a real-ABI call site. Drop a
;   hexalign right before a real-ABI call; it checks/pads 8 bytes at
;   runtime as needed, so there's no need to hand-compute the parity of
;   argument/local counts at the function entry, and no paired "undo"
;   macro is needed either. See AGENTS.md.
;
; preasmcall/postasmcall: a pair of full-register-protection macros that
;   wrap a custom-ABI call made from inside a real-ABI callback (push
;   every register / pop them back). See AGENTS.md.

%ifndef ASMRT_INC
%define ASMRT_INC

; ---- custom ABI support macros ----

%macro begin 0
    push rbp
    mov  rbp, rsp
%endmacro

%macro end 0
    mov  rsp, rbp
    pop  rbp
%endmacro

; hexalign: dynamic stack alignment at a real-ABI call site, replacing
; the old "hand-compute argument/local parity" approach. Before calling
; a real-ABI function, it checks whether rsp is already 16-byte aligned
; (under this ABI rsp is always at least 8-byte aligned, so it can only
; be off by 0 or 8 bytes) and pads that 8 bytes if needed. No paired
; "undo" macro is needed -- the padding doesn't need to be reclaimed by
; hand, since end's mov rsp,rbp reclaims it along with everything else
; on the way out. See AGENTS.md.
%macro hexalign 0
    mov  rax, rsp
    and  rax, 8          ; 0 when rsp is already 16-byte aligned, 8 otherwise
    sub  rsp, rax
%endmacro

; preasmcall/postasmcall: full-register-protection macros for C callback
; scenarios. Used when a real-ABI callback (e.g. a function pointer
; registered with a C library) needs to call into a custom-ABI function
; -- push/pop every register around that call so the real-ABI caller's
; expectations (especially the callee-saved rbx/rbp/r12-r15) survive.
; The protected range includes rax: after postasmcall, rax is back to
; whatever it was before preasmcall, so if the intervening call's return
; value is needed it must be stashed to memory before postasmcall runs.
; See AGENTS.md.
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

; fs.asm
extern fsStat
extern fsFstat
extern fsMkdir
extern fsRmdir
extern fsUnlink

; assert.asm
extern assert

; str.asm
extern strLen
extern strEq

%endif ; ASMRT_INC
