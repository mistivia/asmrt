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

; ioOpen(path, flags, mode) -> fd
ioOpen:
    ;; args: path, flags, mode
    %assign N 3
    %assign path (16 + (N-1) * 8)
    %assign flags (16 + (N-2) * 8)
    %assign mode (16 + (N-3) * 8)
    begin

    mov rdi, [rbp + path]
    mov rsi, [rbp + flags]
    mov rdx, [rbp + mode]
    mov rax, 2          ; sys_open
    syscall

    end
    ret 24

; ioClose(fd) -> result (rax)
ioClose:
    ;; args: fd
    %assign N 1
    %assign fd (16 + (N-1) * 8)
    begin

    mov rdi, [rbp + fd]
    mov rax, 3          ; sys_close
    syscall

    end
    ret 8

; ioRead(fd, buf, count) -> bytes read
ioRead:
    ;; args: fd, buf, count
    %assign N 3
    %assign fd (16 + (N-1) * 8)
    %assign buf (16 + (N-2) * 8)
    %assign count (16 + (N-3) * 8)
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
    ;; args: fd, buf, count
    %assign N 3
    %assign fd (16 + (N-1) * 8)
    %assign buf (16 + (N-2) * 8)
    %assign count (16 + (N-3) * 8)
    begin

    mov rdi, [rbp + fd]
    mov rsi, [rbp + buf]
    mov rdx, [rbp + count]
    mov rax, 1          ; sys_write
    syscall

    end
    ret 24

; ioWriteNum(fd, num) -> bytes written (rax), same as ioWrite's return value
; Writes the base-10 ASCII representation of the signed integer num to fd,
; with a leading '-' for negative values; no trailing newline.
ioWriteNum:
    ;; args: fd, num
    %assign N 2
    %assign fd (16 + (N-1) * 8)
    %assign num (16 + (N-2) * 8)
    begin

    ;; local variables
    %assign offset 0
    ;; char buf[32] -- scratch digit buffer: enough for a 64-bit value + sign
    %assign offset (offset - 32)
    %assign buf offset
    ;; endlocal
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

    push [rbp + fd]
    push rbx
    push rax
    call ioWrite

    end
    ret 16

; ioWriteChar(fd, ch) -> bytes written (rax), same as ioWrite's return value
; Writes the single byte ch (low 8 bits of the pushed value) to fd.
ioWriteChar:
    ;; args: fd, ch
    %assign N 2
    %assign fd (16 + (N-1) * 8)
    %assign ch (16 + (N-2) * 8)
    begin

    ;; local variables
    %assign offset 0
    ;; char buf -- one-byte scratch buffer for ioWrite's source
    %assign offset (offset - 8)
    %assign buf offset
    ;; endlocal
    sub rsp, (-offset)

    mov al, [rbp + ch]
    mov [rbp + buf], al
    lea rax, [rbp + buf]

    push [rbp + fd]
    push rax
    push 1
    call ioWrite

    end
    ret 16

; ioSeek(fd, offset, whence) -> new file offset (rax)
; whence: 0 = SEEK_SET, 1 = SEEK_CUR, 2 = SEEK_END
ioSeek:
    ;; args: fd, offset, whence
    %assign N 3
    %assign fd (16 + (N-1) * 8)
    %assign offset (16 + (N-2) * 8)
    %assign whence (16 + (N-3) * 8)
    begin

    mov rdi, [rbp + fd]
    mov rsi, [rbp + offset]
    mov rdx, [rbp + whence]
    mov rax, 8          ; sys_lseek
    syscall

    end
    ret 24
