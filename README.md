# asmrt

A small NASM (x86-64, Linux) runtime built around a custom, stack-based
calling convention: arguments are pushed by the caller instead of passed
in registers, the callee cleans its own arguments off the stack with
`ret N`, and every register except `rax` is considered clobbered after
any `call`. The full rationale and the hand-written-assembly conventions
that follow from it (stack frame layout, struct/local-variable offsets,
naming, stack alignment) are documented in [AGENTS.md](AGENTS.md) — this
file is just a practical overview of what's in the repo and how to build
and use it.

## Building

Requires `nasm`, `ar`, and `gcc` (used only as the linker driver, to pull
in a normal C runtime and libc).

```sh
make        # build build/libasmrt.a
make test   # build and run every test in tests/
make clean
```

`make install` installs `libasmrt.a` into `$(PREFIX)/lib` and
`asmrt.inc` into `$(PREFIX)/include/nasm` (so it's found by
`nasm -I /usr/local/include/nasm/ ...` or just dropped alongside a
project's own `-I` path). `PREFIX` defaults to `/usr/local` and can be
overridden (`make install PREFIX=/usr`); `DESTDIR` is honored too, for
staged installs. `make uninstall` removes both. Installing system-wide
typically needs root, e.g. `sudo make install`.

```sh
sudo make install
make uninstall
```

## Layout

```
src/asmrt.inc   shared header: ABI macros + extern declarations for every runtime function
src/main.asm    process entry point (main -> entry), rtExit
src/assert.asm  assert(msg, flag)
src/io.asm      file I/O syscalls
src/fs.asm      filesystem syscalls
src/mem.asm     malloc/free/realloc wrappers, plus native memcpy/memmove/memset-alikes
src/str.asm     NUL-terminated string helpers
src/utils.asm   generic sort (qsort-style recursive quicksort) + fnv64 hash
tests/          one test_*.asm per module, run via `make test`
```

See [Function reference](#function-reference) below for the full list of
what each module exports.

Every runtime `.asm` file only needs `%include "asmrt.inc"` — it pulls in
the ABI macros and declares every exported function as `extern`, so
callers never hand-write their own `extern` lines.

## Function reference

Every function below follows the custom ABI (see
[The ABI in short](#the-abi-in-short)): arguments pushed by the caller
in declaration order, return value in `rax`, callee cleans the stack
with `ret N`. All of them are `global` and declared `extern` in
`asmrt.inc`, so any file that includes it can call them directly.

**main.asm**

| Function | Description |
|---|---|
| `rtExit(code)` | terminate the process with `code` — the only place under this ABI that should issue `sys_exit` directly |

**io.asm**

| Function | Description |
|---|---|
| `ioOpen(path, flags, mode) -> fd` | `sys_open` |
| `ioClose(fd) -> result` | `sys_close` |
| `ioRead(fd, buf, count) -> bytesRead` | `sys_read` |
| `ioWrite(fd, buf, count) -> bytesWritten` | `sys_write` |
| `ioSeek(fd, offset, whence) -> newOffset` | `sys_lseek`; `whence`: 0=SEEK_SET, 1=SEEK_CUR, 2=SEEK_END |
| `ioWriteNum(fd, num) -> bytesWritten` | writes `num`'s base-10 ASCII representation (signed, no trailing newline) |
| `ioWriteChar(fd, ch) -> bytesWritten` | writes the single byte `ch` |

**fs.asm**

| Function | Description |
|---|---|
| `fsStat(path, statBuf) -> result` | `sys_stat` |
| `fsFstat(fd, statBuf) -> result` | `sys_fstat` |
| `fsMkdir(path, mode) -> result` | `sys_mkdir` |
| `fsRmdir(path) -> result` | `sys_rmdir` |
| `fsUnlink(path) -> result` | `sys_unlink` |

**mem.asm**

| Function | Description |
|---|---|
| `memAlloc(size) -> ptr` | wraps libc `malloc`; NULL on failure |
| `memFree(ptr)` | wraps libc `free`; `rax` is always 0 |
| `memReloc(ptr, size) -> newPtr` | wraps libc `realloc`; NULL on failure, `ptr` left untouched |
| `memCopy(dest, src, n) -> dest` | native memcpy-alike; the two regions must not overlap |
| `memMove(dest, src, n) -> dest` | native memmove-alike; safe for overlapping regions |
| `memFill(dest, val, n) -> dest` | native memset-alike; fills `n` bytes with `val`'s low byte |

**assert.asm**

| Function | Description |
|---|---|
| `assert(msg, flag)` | if `flag` is false (0), writes `msg` to stderr and terminates with exit code -1; otherwise returns normally |

**str.asm**

| Function | Description |
|---|---|
| `strLen(s) -> length` | length of a NUL-terminated string, excluding the trailing NUL |
| `strEq(a, b) -> 1/0` | 1 if the two NUL-terminated strings are equal, 0 otherwise |

**utils.asm**

| Function | Description |
|---|---|
| `sort(base, nmemb, size, cmpFn)` | recursive quicksort (Lomuto partition) over `nmemb` elements of `size` bytes each at `base`, ordered by the custom-ABI comparator `cmpFn(a, b)` — same contract as libc's qsort comparator, just called through this runtime's own ABI |

`partition`/`swapElems` (utils.asm) and `copyForward` (mem.asm) are
internal helpers used only within their own file — not `global`, not
declared in `asmrt.inc`, and not meant to be called from elsewhere.

## Writing a program against asmrt

A program provides its own entry point, `entry`, called by `main.asm`
with the process's `argc`/`argv`/`envp` (in that push order, so the
`%assign` parameter declarations after `entry:` give you
`[rbp + argc]`/`[rbp + argv]`/`[rbp + envp]`). `entry`'s return value
in `rax` becomes the process exit code.

```asm
%include "asmrt.inc"

section .data
    msg    db "hello, asmrt", 10
    msgLen equ $ - msg

section .text
    global entry

entry:
    ;; args: argc, argv, envp
    %assign N 3
    %assign argc (16 + (N-1) * 8)
    %assign argv (16 + (N-2) * 8)
    %assign envp (16 + (N-3) * 8)
    begin

    push 1
    push msg
    push msgLen
    call ioWrite

    mov rax, 0
    end
    ret 24
```

Link the object file together with `build/libasmrt.a` using `gcc`, e.g.:

```sh
nasm -f elf64 -I src/ hello.asm -o hello.o
gcc -no-pie hello.o build/libasmrt.a -o hello
```

## The ABI in short

- Arguments: pushed by the caller in declaration order (first argument
  pushed first), so the last-pushed argument lands at `[rbp+16]` and
  earlier ones sit at increasing offsets above it.
- Stack cleanup: the callee cleans its own arguments with `ret N`.
- Return value: always in `rax`.
- Registers: aside from `rax`, every register is clobbered by any call
  (custom-ABI call, real-ABI call, or bare `syscall`), so no variable is
  ever kept live in a register across a call — everything lives on the
  stack, declared with plain `%assign` offsets and accessed as
  `[rbp + name]` — see [AGENTS.md](AGENTS.md) for the full convention.

Macros and declaration style used in every function (write order:
`name:` → parameter `%assign`s → `begin` → local `%assign`s → `endlocal`
→ body → `end`; functions without parameters go straight from `name:`
to `begin`):

| Macro | Purpose |
|---|---|
| `begin` / `end` | set up / tear down the standard stack frame |
| `%assign param (16 + (N-i) * 8)` | declare the `i`-th of `N` parameters; use as `[rbp + param]` |
| `%assign offset (offset - size)` / `%assign local offset` | declare a local of `size` bytes; use as `[rbp + local]`; end these with `sub rsp, (-offset)` |
| `hexalign` | pad the stack to 16-byte alignment right before a real-ABI call (e.g. libc), no paired "undo" needed |
| `preasm` / `postasm` | save/restore every register around a custom-ABI call made from inside a real-ABI callback (e.g. a function pointer handed to a C library) |

## Naming convention

- Variables (parameters, locals, globals): `camelCase`
- Functions: `camelCase`
- Struct-like types: `CamelCase`, with offsets declared as
  `Type_field` and total size as `Type_size` (see the "shared struct
  definitions" section of `asmrt.inc` for the pattern)
