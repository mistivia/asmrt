; io.asm -- custom-ABI wrappers for opening/closing/reading/writing files
;
; All of these call the Linux x86-64 syscalls directly, no libc dependency.
; Every function follows the custom ABI: arguments pushed on the stack,
; return value in rax, callee cleans the stack with ret N.
; syscall clobbers rcx/r11, but since a call (including a bare syscall)
; already clobbers every register except rax by convention, there's no
; register-protection macro needed or available here.

%include "asmrt.inc"

section .text
    global ioOpen
    global ioClose
    global ioRead
    global ioWrite
    global ioSeek
    global ioWriteNum
    global ioWriteChar
    global ioWriteString

; ioOpen(path, flags, mode) -> fd
ioOpen:
    ; args: path, flags, mode
    argnum 3
    %assign path  arg(1)
    %assign flags arg(2)
    %assign mode  arg(3)

    begin
    mov rdi, [rbp + path]
    mov rsi, [rbp + flags]
    mov rdx, [rbp + mode]
    mov rax, 2          ; sys_open
    syscall
    end
    ret 24

; ioClose(fd) -> result
ioClose:
    ; args: fd
    argnum 1
    %assign fd arg(1)
    begin

    mov rdi, [rbp + fd]
    mov rax, 3          ; sys_close
    syscall
    end
    ret 8

; ioRead(fd, buf, count) -> bytes read
ioRead:
    ; args: fd, buf, count
    argnum 3
    %assign fd arg(1)
    %assign buf arg(2)
    %assign count arg(3)
    begin

    mov rdi, [rbp + fd]
    mov rsi, [rbp + buf]
    mov rdx, [rbp + count]
    mov rax, 0          ; sys_read
    syscall
    end
    ret 24

; ioWrite(fd, buf, count) -> bytes written
ioWrite:
    ; args: fd, buf, count
    argnum 3
    %assign fd arg(1)
    %assign buf arg(2)
    %assign count arg(3)
    begin

    mov rdi, [rbp + fd]
    mov rsi, [rbp + buf]
    mov rdx, [rbp + count]
    mov rax, 1          ; sys_write
    syscall
    end
    ret 24

; ioWriteNum(fd, num) -> bytes written, same as ioWrite's return value
; Writes the base-10 ASCII representation of the signed integer num to fd,
; with a leading '-' for negative values; no trailing newline.
ioWriteNum:
    ; args: fd, num
    argnum 2
    %assign fd arg(1)
    %assign num arg(2)
    begin

    ; local variables
    resetOffset

    decOffset 32
    %assign buf offset

    sub rsp, (-offset)

    ; build the digits back-to-front from the end of buf; no call happens
    ; during this build, so rax/rbx/rcx/rdx/r8 are just scratch throughout
    lea rbx, [rbp + buf + 32]    ; rbx = cursor, one past the last digit written
    mov rax, [rbp + num]
    xor rcx, rcx              ; rcx = 1 if num was negative, else 0
    test rax, rax
    jns .digitLoop
    mov rcx, 1
    neg rax
.digitLoop:
    xor rdx, rdx
    mov r8, 10
    div r8                     ; rax /= 10, rdx = remainder digit
    add dl, '0'
    dec rbx
    mov [rbx], dl
    test rax, rax
    jnz .digitLoop

    test rcx, rcx
    jz .lenDone
    dec rbx
    mov byte [rbx], '-'
.lenDone:
    lea rax, [rbp + buf + 32]
    sub rax, rbx                ; rax = number of bytes written into buf

    push qword [rbp + fd]
    push rbx
    push rax
    call ioWrite
    end
    ret 16

; ioWriteString(fd, string) -> bytes written
; Writes the whole length-prefixed string (a pointer to
; [8-byte len][data][NUL], see string.asm) to fd in one syscall.
; (The local symbol is `pStr` because `%assign string` would expand the
; word "string" in every comment of this file.)
ioWriteString:
    ; args: fd, pStr (the string pointer)
    argnum 2
    %assign fd arg(1)
    %assign pStr arg(2)
    begin

    mov rdi, [rbp + fd]
    mov rax, [rbp + pStr]
    mov rdx, [rax]          ; len
    lea rsi, [rax + 8]      ; data
    mov rax, 1              ; sys_write
    syscall
    end
    ret 16

; ioWriteChar(fd, ch) -> bytes written, same as ioWrite's return value
; Writes the single byte ch (low 8 bits of the pushed value) to fd.
ioWriteChar:
    ; args: fd, ch
    argnum 2
    %assign fd arg(1)
    %assign ch arg(2)
    begin

    ; local variables
    resetOffset
    ; char buf -- one-byte scratch buffer for ioWrite's source
    decOffset 8
    %assign buf offset
    ; endlocal
    sub rsp, (-offset)

    mov al, [rbp + ch]
    mov [rbp + buf], al
    lea rax, [rbp + buf]

    push qword [rbp + fd]
    push rax
    push 1
    call ioWrite
    end
    ret 16

; ioSeek(fd, offset, whence) -> new file offset
; whence: 0 = SEEK_SET, 1 = SEEK_CUR, 2 = SEEK_END
ioSeek:
    ; args: fd, offset, whence
    argnum 3
    %assign fd arg(1)
    %assign offset arg(2)
    %assign whence arg(3)
    begin

    mov rdi, [rbp + fd]
    mov rsi, [rbp + offset]
    mov rdx, [rbp + whence]
    mov rax, 8          ; sys_lseek
    syscall
    end
    ret 24
