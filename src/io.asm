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
proc ioOpen
    args path, flags, mode

    mov rdi, [%$path]
    mov rsi, [%$flags]
    mov rdx, [%$mode]
    mov rax, 2          ; sys_open
    syscall

    end
    ret 24

; ioClose(fd) -> result (rax)
proc ioClose
    args fd

    mov rdi, [%$fd]
    mov rax, 3          ; sys_close
    syscall

    end
    ret 8

; ioRead(fd, buf, count) -> bytes read
proc ioRead
    args fd, buf, count

    mov rdi, [%$fd]
    mov rsi, [%$buf]
    mov rdx, [%$count]
    mov rax, 0          ; sys_read
    syscall

    end
    ret 24

; ioWrite(fd, buf, count) -> bytes written
proc ioWrite
    args fd, buf, count

    mov rdi, [%$fd]
    mov rsi, [%$buf]
    mov rdx, [%$count]
    mov rax, 1          ; sys_write
    syscall

    end
    ret 24

; ioWriteNum(fd, num) -> bytes written (rax), same as ioWrite's return value
; Writes the base-10 ASCII representation of the signed integer num to fd,
; with a leading '-' for negative values; no trailing newline.
proc ioWriteNum
    args fd, num
    local buf, 32    ; scratch digit buffer: enough for a 64-bit value + sign
    endlocal

    ; build the digits back-to-front from the end of buf; no call happens
    ; during this build, so rax/rbx/rcx/rdx/r8 are just scratch throughout
    lea rbx, [%$buf + 32]    ; rbx = cursor, one past the last digit written
    mov rax, [%$num]
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
    lea rax, [%$buf + 32]
    sub rax, rbx                ; rax = number of bytes written into buf

    push [%$fd]
    push rbx
    push rax
    call ioWrite

    end
    ret 16

; ioWriteChar(fd, ch) -> bytes written (rax), same as ioWrite's return value
; Writes the single byte ch (low 8 bits of the pushed value) to fd.
proc ioWriteChar
    args fd, ch
    local buf        ; one-byte scratch buffer for ioWrite's source
    endlocal

    mov al, [%$ch]
    mov [%$buf], al
    lea rax, [%$buf]

    push [%$fd]
    push rax
    push 1
    call ioWrite

    end
    ret 16

; ioSeek(fd, offset, whence) -> new file offset (rax)
; whence: 0 = SEEK_SET, 1 = SEEK_CUR, 2 = SEEK_END
proc ioSeek
    args fd, offset, whence

    mov rdi, [%$fd]
    mov rsi, [%$offset]
    mov rdx, [%$whence]
    mov rax, 8          ; sys_lseek
    syscall

    end
    ret 24
