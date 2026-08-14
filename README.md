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

## Layout

```
src/asmrt.inc   shared header: ABI macros + extern declarations for every runtime function
src/main.asm    process entry point (main -> entry), rtExit
src/assert.asm  assert(msg, flag)
src/io.asm      file I/O syscalls: ioOpen, ioClose, ioRead, ioWrite, ioSeek
src/fs.asm      filesystem syscalls: fsStat, fsFstat, fsMkdir, fsRmdir, fsUnlink
src/mem.asm     malloc/free/realloc wrappers (memAlloc, memFree, memReloc)
                plus native memcpy/memmove/memset-alikes: memCopy, memMove, memFill
src/str.asm     NUL-terminated string helpers: strLen, strEq
src/sort.asm    generic in-place sort (qsort-style): sort(base, nmemb, size, cmpFn)
tests/          one test_*.asm per module, run via `make test`
```

Every runtime `.asm` file only needs `%include "asmrt.inc"` — it pulls in
the ABI macros and declares every exported function as `extern`, so
callers never hand-write their own `extern` lines.

## Writing a program against asmrt

A program provides its own entry point, `entry`, called by `main.asm`
with the process's `argc`/`argv`/`envp` (in that push order, so inside
`entry`, `[rbp+16]=envp`, `[rbp+24]=argv`, `[rbp+32]=argc`). `entry`'s
return value in `rax` becomes the process exit code.

```asm
%include "asmrt.inc"

section .data
    msg    db "hello, asmrt", 10
    msgLen equ $ - msg

section .text
    global entry

entry:
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
  stack. `%define` aliases expand to a bare address expression (e.g.
  `%define flag (rbp+16)`), not a full memory operand, so each use site
  adds its own `[]` (`[flag]`); locals get there via `%assign name_offset`
  for the raw number plus a `%define name (rbp + name_offset)` wrapper —
  see [AGENTS.md](AGENTS.md) for the full convention.

Macros provided by `asmrt.inc`:

| Macro | Purpose |
|---|---|
| `begin` / `end` | set up / tear down the standard stack frame |
| `hexalign` | pad the stack to 16-byte alignment right before a real-ABI call (e.g. libc), no paired "undo" needed |
| `preasmcall` / `postasmcall` | save/restore every register around a custom-ABI call made from inside a real-ABI callback (e.g. a function pointer handed to a C library) |

## Naming convention

- Variables (parameters, locals, globals): `camelCase`
- Functions: `camelCase`
- Struct-like types: `CamelCase`, with field-offset constants written
  `Type_field` and the size constant `sizeofType`
