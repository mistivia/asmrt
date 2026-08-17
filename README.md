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
src/asmrt.inc   shared header: ABI macros + shared struct definitions + extern declarations for every runtime function
src/main.asm    process entry point (main -> entry), rtExit
src/assert.asm  assert(string, flag) -- writes the length-prefixed string to stderr on failure
src/io.asm      file I/O syscalls + ioWriteNum/ioWriteChar/ioWriteString
src/fs.asm      filesystem syscalls
src/mem.asm     malloc/free/realloc wrappers, plus native memcpy/memmove/memset-alikes
src/string.asm  length-prefixed string module (see the string.asm section below)
src/utils.asm   generic sort (qsort-style recursive quicksort) + fnv64 hash
src/vec.asm     generic vector container (value semantics + trait callbacks)
src/list.asm    generic doubly-linked list container (value semantics + trait callbacks)
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
| `ioWriteString(fd, string) -> bytesWritten` | writes a length-prefixed string (see string.asm) in one syscall |

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
| `assert(string, flag)` | if `flag` is false (0), writes the length-prefixed string `string` to stderr and terminates with exit code -1; otherwise returns normally |

**string.asm**

A string is just a pointer (8 bytes) to a length-prefixed buffer:
`string -> [8-byte len][data bytes][NUL]`, where `len` counts characters
and excludes the trailing NUL. A literal is written as
`name dq (name_end - name_start)` + `name_start: db "..."` +
`name_end: db 0`. Heap strings are one `8 + len + 1` allocation, created
by `stringFromCStr`/`stringFromRaw`/... and released with `stringDrop`.
The string pointer IS the value: `stringMeta` has objsize = 8 and
vec/list of strings stores one string per element. Container ValueMeta
callbacks receive the *element address* (a pointer to the 8-byte slot
inside the container) and deref it once to get the string.

| Function | Description |
|---|---|
| `stringLen(string) -> len` | character count, excluding the trailing NUL |
| `stringEq(pSlotA, pSlotB) -> 1/0` | same len + byte-for-byte equal; element addresses |
| `stringCmp(pSlotA, pSlotB) -> <0/0/>0` | byte order first, length on tie; element addresses |
| `stringInit(pObj)` | initialize an empty string in place (>= 9 bytes of storage) |
| `stringFromCStr(pCStr) -> string` | heap string copied from a NUL-terminated C string |
| `stringFromRaw(pBuf, n) -> string` | heap string from `n` raw bytes |
| `stringCopy(pDstSlot, pSrcSlot)` | deep-copy src element's string into dst element |
| `stringMove(pDstSlot, pSrcSlot)` | transfer ownership, zero the src element |
| `stringDrop(pSlot)` | free the heap string an element points to, zero the element |
| `stringCStr(string) -> pData` | pointer to the NUL-terminated data bytes (`string+8`) |
| `stringAt(string, index) -> ch` | character at `index`; 0 when out of range |
| `stringHash(string) -> hash` | FNV-1a over the chars |
| `stringSlotHash(pSlot) -> hash` | `stringMeta`'s `.hash` callback (element address) |
| `stringSubstring(string, start, endIdx) -> string` | chars `[start, endIdx)`, clamped to `[0, len]` |
| `stringConcat(pA, pB) -> string` | `a` followed by `b` |
| `stringStartsWith(string, pPrefixStr) -> 1/0` | prefix check (string argument) |
| `stringEndsWith(string, pSuffixStr) -> 1/0` | suffix check (string argument) |
| `stringFind(string, pSubStr) -> index or -1` | first occurrence of `sub` |
| `stringCount(string, pSubStr) -> count` | non-overlapping occurrences |
| `stringLower(string) -> string` | A-Z -> a-z |
| `stringUpper(string) -> string` | a-z -> A-Z |
| `stringCapitalize(string) -> string` | first char upper, rest lower |
| `stringStrip(string) -> string` | trim ASCII whitespace at both ends |
| `stringLStrip(string) -> string` | trim leading whitespace |
| `stringRStrip(string) -> string` | trim trailing whitespace |
| `stringRemovePrefix(string, pPrefixStr) -> string` | copy minus prefix when it matches |
| `stringRemoveSuffix(string, pSuffixStr) -> string` | copy minus suffix when it matches |
| `stringSplit(pVec, string, pSepStr) -> pVec` | split on `sep` (empty sep -> whole string as one element) |
| `stringSplitLines(pVec, string) -> pVec` | split on `\n`, strip a trailing `\r` |
| `stringJoin(pVec, pSepStr) -> string` | concatenate string elements with `sep` between them |
| `stringMeta` | `ValueMeta` describing a string element (objsize 8) |

**vec.asm**

| Function | Description |
|---|---|
| `vecInit(pVec, pMeta) -> 0` | zero the vec and attach the ValueMeta |
| `vecWithCapacity(pVec, pMeta, capacity) -> 0` | like vecInit, but pre-allocate room |
| `vecReserve(pVec, additional)` | grow capacity to fit `len + additional` |
| `vecPush(pVec, pElem, isMove)` | append a copy of *pElem (or move it in when isMove != 0) |
| `vecPop(pVec, pOut) -> 1/0` | copy last elem to *pOut (pOut may be NULL) |
| `vecGet(pVec, index) -> pElem` | pointer to element, NULL if out of bounds |
| `vecSet(pVec, index, pElem, isMove)` | replace elem at index (copy or move) |
| `vecFirst(pVec) -> pElem` | first element, NULL if empty |
| `vecLast(pVec) -> pElem` | last element, NULL if empty |
| `vecLen(pVec) -> len` | element count |
| `vecIsEmpty(pVec) -> 1/0` | len == 0 |
| `vecClear(pVec)` | drop all elems, keep the buffer |
| `vecTruncate(pVec, len)` | drop elems from `len` onward |
| `vecDrop(pVec)` | drop all elems, free the buffer, reset the vec |
| `vecSwapElement(pVec, a, b)` | byte-swap two elements |
| `vecSwap(pA, pB)` | swap two whole vec headers |
| `vecInsert(pVec, index, pElem, isMove)` | insert elem at index (0..len) |
| `vecRemove(pVec, index, pOut)` | copy removed elem to *pOut (may be NULL) |
| `vecAsPtr(pVec) -> pData` | raw data pointer (may be NULL) |
| `vecCopy(pDst, pSrc)` | deep copy src into dst |
| `vecMove(pDst, pSrc)` | transfer ownership, reset pSrc |
| `vecSort(pVec)` | in-place sort via meta->cmp |
| `vecCmp(pA, pB) -> -1/0/1` | lexicographic compare |
| `vecHash(pVec) -> hash` | FNV-1a over element hashes |
| `vecMeta` | `ValueMeta` instance describing struct Vec itself |

**list.asm**

| Function | Description |
|---|---|
| `listInit(pList, pMeta) -> 0` | allocate sentinel nodes, attach the ValueMeta |
| `listDrop(pList)` | drop every elem, free all nodes incl. sentinels, reset the list |
| `listClear(pList)` | drop every elem, keep the sentinels |
| `listCopy(pDst, pSrc)` | deep copy src into dst |
| `listMove(pDst, pSrc)` | transfer ownership, reset pSrc |
| `listSwap(pA, pB)` | swap two whole list headers |
| `listInsertBefore(pList, pIter, pElem, isMove) -> pNode` | insert before pIter (copy or move) |
| `listInsertAfter(pList, pIter, pElem, isMove) -> pNode` | insert after pIter (copy or move) |
| `listRemove(pList, pIter)` | drop elem, unlink and free the node |
| `listSet(pList, pIter, pElem, isMove)` | replace elem at pIter (copy or move) |
| `listBegin(pList) -> pNode` | first data node (vtail if empty) |
| `listLast(pList) -> pNode` | last data node, NULL if empty |
| `listEnd(pList) -> pNode` | the vtail sentinel |
| `listNext(pIter) -> pNode` | next node |
| `listPrev(pIter) -> pNode` | previous data node (never vhead) |
| `listGet(pIter) -> pElem` | the node's element (NULL if pIter is NULL) |
| `listLen(pList) -> len` | element count |
| `listIsEmpty(pList) -> 1/0` | len == 0 |
| `listPushBack(pList, pElem, isMove) -> pNode` | append (copy or move) |
| `listPushFront(pList, pElem, isMove) -> pNode` | prepend (copy or move) |
| `listPopBack(pList)` | remove the last element |
| `listPopFront(pList)` | remove the first element |
| `listEq(pA, pB) -> 1/0` | same len + element-wise eq via meta |
| `listCmp(pA, pB) -> -1/0/1` | lexicographic compare |
| `listHash(pList) -> hash` | FNV-1a over element hashes |
| `listMeta` | `ValueMeta` instance describing struct List itself |

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
    ; args: argc, argv, envp
    argnum 3
    %assign argc arg(1)
    %assign argv arg(2)
    %assign envp arg(3)
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
| `decOffset size)` / `%assign local offset` | declare a local of `size` bytes; use as `[rbp + local]`; end these with `sub rsp, (-offset)` |
| `hexalign` | pad the stack to 16-byte alignment right before a real-ABI call (e.g. libc), no paired "undo" needed |
| `preasm` / `postasm` | save/restore every register around a custom-ABI call made from inside a real-ABI callback (e.g. a function pointer handed to a C library) |

## Naming convention

- Variables (parameters, locals, globals): `camelCase`
- Functions: `camelCase`
- Struct-like types: `CamelCase`, with offsets declared as
  `Type_field` and total size as `Type_size` (see the "shared struct
  definitions" section of `asmrt.inc` for the pattern)
