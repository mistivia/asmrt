# ASM 开发模式：自定义调用 ABI（stack-based, callee-cleans-stack）

## 核心思想

不使用 System V AMD64 的寄存器传参 ABI，而是自定义一套更简单、心智负担更低的调用约定：

- **参数**：调用方通过 `push` 依次压栈传参（而非放入 rdi/rsi/rdx/...），且按参数声明顺序正向 push —— **第一个参数先 push，最后一个参数最后 push**。因此进入函数后 `[rbp+16]` 对应的是*最后一个参数*（最靠近返回地址），第一个参数反而在最大的偏移处（详见「参数与局部变量访问约定」）。
- **栈清理**：被调用方（callee）通过 `ret N` 自行清理栈上的参数（类似 stdcall，而非 cdecl）。`N` = 参数总字节数（不含局部变量）。
- **返回值**：统一放在 `rax`。
- **变量一律落栈**：所有变量——不管是参数还是函数内部的局部变量——都只以栈上内存单元的形式存在，通过 `%define` 起别名。别名本身只是一个**地址表达式**（`(rbp + 偏移)`），不是内存操作数——用到的地方要自己手动加 `[]`，写成 `[变量名]` 才是真正的内存访问，例如 `mov rax, [flag]`。**寄存器里永远不存变量**，只用来承载一次表达式求值过程中的中间结果，算完立刻写回栈上的变量，绝不让一个寄存器的值跨越到下一条语句、更不用说跨越一次 `call`。
- **调用会破坏所有寄存器**：不管是调用自定义 ABI 的函数，还是调用外部真实 ABI 的函数（如 libc 的 `printf`），一律默认——**除 `rax`（返回值）外，其余所有寄存器在 `call` 之后都视为已被破坏、值不可信**。因为变量本来就不放在寄存器里，这条规则不会造成任何负担：你不会有"调用前需要保护某个寄存器"的场景，因为需要在调用后还能用到的值，从一开始就该是栈上的变量，而不是寄存器里的临时值。

这套"调用清空所有寄存器"的假设对自定义 ABI 函数之间的调用、以及对外部真实 ABI 函数的调用都统一适用，因此**不需要任何寄存器保护宏**——无论是保存"局部要用的寄存器"，还是跨真实 ABI 边界时保护"caller-saved 寄存器"，这套设计里都不存在，直接删除即可。写函数时只需用 `begin` / `end` 两个宏建帧、收尾，中间该用哪个寄存器算表达式就用哪个，用完就扔。

## 命名约定

- **变量**（参数、局部变量、全局变量）用 `camelCase`：首字母小写，后续每个单词首字母大写，例如 `msg`、`flag`、`printMsg`。
- **函数（subroutine）名**用 `camelCase`：例如 `strLen`、`ioOpen`、`fsMkdir`、`printNum`。单个单词（`assert`、`fibo`）本身就是合法的 camelCase，不用额外处理。
- **结构体等类型名**用 `CamelCase`（首字母也大写，即 PascalCase）：例如 `Point`、`FileStat`。结构体字段偏移常量沿用「结构体字段偏移约定」里"类型名 + 字段名"的写法，类型部分保持 `CamelCase`、字段部分保持 `camelCase`，用下划线连接，例如 `Point_x`；整体大小常量写成 `sizeof` 加 `CamelCase` 类型名（不加下划线），例如 `sizeofPoint`。

## 两个宏：begin / end

```asm
%macro begin 0
    push rbp
    mov  rbp, rsp
%endmacro

%macro end 0
    mov  rsp, rbp
    pop  rbp
%endmacro
```

- `begin` 只做一件事：建立标准栈帧（`push rbp` + `mov rbp, rsp`）。因为寄存器不再需要保存/恢复，这个宏不用像原来的 `beginfn` 那样接受变长寄存器列表——固定两行，没有参数。
- `end` 对称地做收尾：`mov rsp, rbp` 把 `sub rsp, N` 分配的局部变量空间（以及下面 `hexalign` 可能垫过的那点空间）一次性归还，再 `pop rbp` 恢复调用方的帧指针。`end` 之后紧跟 `ret N` 清理参数。
- 局部变量的 `sub rsp, N` 写在 `begin` 之后、函数体之前；只要每个局部变量自身都按 8 字节整槽分配（下面「局部变量偏移约定」的硬性规定），`N` 自动就是 8 的整数倍，不需要再额外取整或者把参数个数算进去凑 16 字节——16 字节对齐这件事整个下放给 `hexalign` 在真正需要的调用点动态处理，见下一节。

## hexalign：真实 ABI 调用点的动态栈对齐

手算"参数个数 + 局部变量槽位数的奇偶性"来确保每个真实 ABI 调用点 16 字节对齐，写起来啰嗦又容易算错。更省心的办法是把这件事下放到运行时：调用真实 ABI 函数之前，直接检查一下当前 `rsp` 是不是已经 16 字节对齐，不是的话就现场垫 8 字节。

```asm
%macro hexalign 0
    mov  rax, rsp
    and  rax, 8          ; rsp 已 16 字节对齐时为 0，否则（差 8 字节）为 8
    sub  rsp, rax
%endmacro
```

原理很简单：这套自定义 ABI 里所有栈操作（`push` 参数、`sub rsp` 局部变量——因为「结构体字段偏移约定」「局部变量偏移约定」两节的硬性规定，每一样都是 8 字节的整数倍）都不会破坏"`rsp` 始终至少 8 字节对齐"这条不变式，所以 `rsp` 任何时候要么已经 16 字节对齐（`rsp & 8 == 0`），要么恰好差 8 字节（`rsp & 8 == 8`）——不会是别的情况。`hexalign` 就用 `rsp & 8` 算出"这次到底要不要垫、垫多少"（结果只会是 `0` 或 `8`），直接从 `rsp` 里减掉。

用法：真实 ABI 调用之前放一句 `hexalign` 即可，不需要配对的"撤销"宏：

```asm
hexalign
mov rdi, printMsg
mov rsi, x
xor rax, rax
call printf
```

几点说明：

- **不需要事后撤销，也就不需要 `endalign` 这样的宏**：`hexalign` 垫的那 8 字节没有必要记下来再退回去——局部变量、参数全部通过 `rbp` 相对寻址访问，从不依赖 `rsp` 的具体值，所以垫在那儿不影响后续任何代码的正确性；等函数结尾 `end` 执行 `mov rsp, rbp`，不管中途 `hexalign` 垫过几次、垫了多少，会连同局部变量空间一起被整体归还，不需要中途手动清理。
- **按调用点放，不是按函数放**：一个函数如果有好几处真实 ABI 调用，每处调用前都放一句 `hexalign`——因为不同调用点之前可能已经 `push` 了不同数量的参数，对齐状态并不一样，没法只在函数入口算一次就一劳永逸。
- **不会导致栈无限增长**：同一个调用点如果在循环里反复执行，`hexalign` 至多在第一次真正垫上那 8 字节——垫完之后 `rsp` 就变成 16 字节对齐，只要循环体本身的 push/pop 是对称的（这套 ABI 下调用自定义 ABI 函数本来就靠 `ret N` 自动清栈，天然对称），下一轮回到同一个调用点时 `rsp` 还是对齐的，不会再垫。所以额外占用的栈空间跟循环跑多少次无关，只跟函数体内有几个不同的真实 ABI 调用点有关，是一个很小的常数。
- 使用 `rax` 作为暂存寄存器计算垫多少——这跟"调用会破坏所有寄存器"的整体假设一致，`hexalign` 前不能指望 `rax` 里还留着什么有意义的值。

## preasmcall / postasmcall：C 回调场景下的全寄存器保护宏

`begin`/`end` 解决的是"纯自定义 ABI 世界内部"的寄存器管理问题。但有一种场景绕不开真实 ABI 的期望：**C 代码把一个函数指针注册为回调**（比如 `qsort` 的比较函数、信号处理函数等），回调本身是按真实 System V ABI 被调用的，而回调内部如果要转手调用自定义 ABI 的函数（后者按约定会破坏除 `rax` 外的所有寄存器），就必须先把"当前所有寄存器的值"原样保护起来，等自定义 ABI 调用结束后再恢复，否则会破坏真实 ABI 调用方本来指望保留的状态（尤其是 callee-saved 寄存器 `rbx`/`rbp`/`r12`-`r15`）。

`preasmcall` / `postasmcall` 就是为这个场景提供的一对宏：**把所有寄存器 push，调用结束后原样 pop 回来**，不做任何取舍：

```asm
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
    sub  rsp, 8   ; 15 个寄存器是奇数个，补一个占位槽凑够 16 字节对齐
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
```

用法：把要转调的自定义 ABI `call` 夹在两者中间——

```asm
; 真实 ABI 回调入口（比如注册给某个 C 库的函数指针）
myCallback:
    preasmcall
    ; ... 按自定义 ABI 的规则 push 参数 ...
    call someAsmrtFunc     ; 自定义 ABI 调用，会破坏除 rax 外的所有寄存器
    postasmcall
    ; 如果需要用到 someAsmrtFunc 的返回值，必须在 postasmcall 之前
    ; 就把 rax 另存到内存里——postasmcall 会把 rax 也恢复成调用前的值，
    ; 调用结果不会自动保留下来
    ret
```

几点约定：

- **保护范围是"所有寄存器"，包含 `rax`**：这意味着 `postasmcall` 执行完之后，所有寄存器（包括 `rax`）都会变回 `preasmcall` 执行前的样子。如果业务逻辑需要用到中间那次自定义 ABI 调用的返回值，必须在 `postasmcall` 之前把 `rax` 存到内存（全局变量、`.bss`、或者其它不受这次保护/恢复影响的位置），不能指望它能穿过 `postasmcall` 活下来。
- **也包含 `rbp`**：`preasmcall`/`postasmcall` 之间 `rbp` 本身也被当成普通寄存器一起保护、可能被自定义 ABI 调用临时改写又恢复。因此**不要在 `preasmcall` 和 `postasmcall` 之间通过 `[rbp±N]` 访问当前函数自己的参数/局部变量**——这段区间里 `rbp` 的语义不受保证，只应该用来完成"转调自定义 ABI 函数"这一件事。
- 15 个寄存器是奇数个，`preasmcall` 用一个 `sub rsp, 8` 占位槽把它凑成 16 字节的整数倍，配合 `postasmcall` 开头的 `add rsp, 8`，保证这一对宏本身不会破坏调用点的栈对齐。

## 参数与局部变量访问约定

### 栈帧布局

进入函数、`begin` 建好帧之后，栈布局固定为：

```
[rbp - Sm]                 局部变量 m （离 rbp 最远的局部变量，Sm 由声明顺序累加各自实际大小得出）
...
[rbp - S2]                 局部变量 2
[rbp - S1]                 局部变量 1 （最靠近 rbp，S1 = 该变量自身大小）
[rbp + 0]                  旧 rbp
[rbp + 8]                  返回地址（call 压入）
[rbp + 16]                 pn      （最后一个参数，最后 push，离返回地址最近）
[rbp + 24]                 p(n-1)
...
[rbp + 16 + 8*(n-1)]       p1      （第一个参数，最先 push，离返回地址最远）
```

也就是说：

- **参数**在正偏移一侧，从最后一个参数往前数：最后一个参数固定在 `[rbp+16]`，往前每多一个参数偏移 +8，第一个参数在最大偏移处。参数统一占 8 字节一格（不管声明类型是什么，调用方总是按 8 字节 push），用 `%define` 给它起一个**纯地址表达式**别名（不带 `[]`），例如 `%define flag (rbp + 16)`；用到的地方自己手动加 `[]`，写成 `[flag]`。**硬性规定：所有函数（subroutine）的每一个参数都必须恰好是 8 字节**——要么是一个能装进 8 字节的普通标量值（整数、指针……），要么如果要传结构体，只能传"指向该结构体的指针"，绝不把结构体按值展开成多个栈槽传递。这样参数区的布局才能保持"每个参数固定 8 字节、`[rbp+16+8k]` 规律排列"这条简单规则，不需要为某个参数特殊照顾。
- **局部变量**在负偏移一侧，但**不再假定每个变量固定占 8 字节**——每个局部变量按自己的实际大小（`int32_t` 占 4 字节、结构体占 `sizeof` + `CamelCase` 类型名 字节……）挨着上一个变量的末尾继续往负方向排。局部变量的别名分两步起：先用 `%assign` 给它的**纯数值偏移**起一个 `变量名_offset` 形式的别名（例如 `%assign fd_offset (-8)`），再用 `%define` 把它包成跟参数一样的**纯地址表达式**别名（`%define fd (rbp + fd_offset)`）。这样访问的时候局部变量和参数完全统一：都写 `[变量名]`（结构体成员则是 `[变量名 + 类型名_字段名]`——因为`变量名` 本身已经是 `rbp + 偏移` 这个地址表达式，直接加字段偏移就是字段地址，不用再写一遍 `rbp`）。具体写法见下面「结构体字段偏移约定」和「局部变量偏移约定」两节。

不管是参数还是局部变量，`%define`/`%assign` 别名的书写顺序都按**声明顺序**（第一个写在最前面），不用跟着偏移正负方向排——只是每个别名对应的具体偏移值要按规则算。

### 结构体字段偏移约定

结构体的字段偏移和整体大小用 `%assign` 表达，不依赖任何宏，纯粹是一串累加：

```asm
; struct Sample { int32_t x; int32_t y; int64_t z; };
%assign Sample_x (0)
%assign Sample_y (Sample_x + 4)
%assign Sample_z (Sample_y + 4)
%assign sizeofSample (Sample_z + 8)
```

规则很直白：从 `0` 开始，每个字段的偏移 = 上一个字段的偏移 + 上一个字段的大小；最后一个 `%assign`（`sizeof` + `CamelCase` 类型名，例如 `sizeofSample`）= 最后一个字段的偏移 + 它的大小，就是整个结构体的字节数。字段按声明顺序依次排布，不自动插入字段间的对齐 padding——如果某个字段需要对齐（比如想让 `int64_t` 落在 8 字节边界上），由写结构体定义的人自己在字段顺序/间隙上处理，和手写 C 结构体 layout 是一回事。

**硬性规定：`sizeof` + 类型名这个常量必须是 8 的整数倍。** 这不是为了性能，而是让结构体不管出现在哪（栈上局部变量、`sub rsp` 计算、还是作为参数传递指针指向的内存）都不需要单独考虑对齐——下面「局部变量偏移约定」要求每个局部变量都占 8 字节的整数倍，结构体作为局部变量时自然要满足这一点。如果字段本身凑不满 8 的整数倍，在最后手动垫一个 padding 字段：

```asm
; struct Tiny { int32_t x; };   （只有 4 字节，凑不满 8 的整数倍）
%assign Tiny_x (0)
%assign sizeofTiny (Tiny_x + 4 + 4)   ; 4 字节实际数据 + 4 字节 padding，凑够 8
```

有了这套偏移常量，不管这个结构体实例是全局变量、堆内存，还是接下来要讲的栈上局部变量，访问某个字段都统一是「基址 + 字段偏移」，比如 `[c + Sample_y]`（`c` 是栈上局部变量 `Sample` 的地址别名，本身已经展开成 `rbp + c 的偏移`，直接加 `Sample_y` 就是字段地址）或者 `[somePtr + Sample_y]`（`somePtr` 是指向堆/全局 `Sample` 实例的指针，一般也就是作为参数传进来的那个结构体指针，同样按 `[somePtr]` 的方式取用）。

### 局部变量偏移约定

局部变量的数值偏移同样用 `%assign` 表达：从「`-`（第 1 个变量占用的字节数）」开始，之后每多声明一个变量，偏移再往负方向减去**上一个变量占用的字节数**。但和旧写法不同的是，`%assign` 只负责起这个纯数值偏移的别名（命名为 `变量名_offset`——这里的 `_offset` 是个固定后缀，标记"这只是个偏移数字，不是变量本身"，所以不跟随 camelCase 规则，`_offset` 前的变量名部分才按 camelCase 命名），不直接当成变量本身用；变量本身还要再用 `%define` 包一层，变成跟参数一样的 `(rbp + 变量名_offset)` 地址表达式，访问时统一写 `[变量名]`。

**硬性规定：每个局部变量占用的空间也必须是 8 的整数倍**，不管它声明的类型本身多大。`int32_t` 只需要 4 字节存数据，但还是要按 8 字节分配一整个槽，高位 4 字节空着不用；结构体因为上一节的硬性规定，`sizeof` + 类型名本来就已经是 8 的整数倍，天然满足。这条规则换来的好处是：局部变量区的总字节数（例中的 `stksz`）自动就是 8 的整数倍，**不需要再单独做一次"向上取整到 8"**——`sub rsp` 直接传 `stksz` 本身即可（这也是这套写法比手算 16 字节对齐"好实现很多"的地方：每一层——参数、结构体字段、局部变量——都各自保证 8 字节对齐，组合起来自然处处对齐，不需要在某个中心位置统一补救）。

例如函数里声明了 `int32_t a, b; struct Sample c;`：

```asm
%assign a_offset (-8)                       ; a 是 int32_t，只用 4 字节数据，但仍按 8 字节整槽分配
%define a (rbp + a_offset)

%assign b_offset (a_offset - 8)             ; b 同理
%define b (rbp + b_offset)

%assign c_offset (b_offset - sizeofSample)  ; c 是 struct Sample，sizeofSample 已经是 8 的整数倍（16）
%define c (rbp + c_offset)

%assign stksz (-c_offset)                   ; 天然是 8 的整数倍，不需要再单独取整
sub rsp, stksz
```

访问的时候：

```asm
; c.y
mov eax, [c + Sample_y]

; a
mov eax, [a]
```

### 示例（`assert(msg, flag)`，2 个参数，1 个局部变量）

```asm
; 调用方：第一个参数先 push
push msg
push flag
call assert

; assert 内部：
assert:
    ;; params
    %define msg    (rbp + 24) ; 第 1 个参数，最先 push
    %define flag   (rbp + 16) ; 第 2 个参数，最后 push，离返回地址最近

    begin
    ;; local vars
    %assign result_offset (-8)           ; 第 1 个局部变量，8 字节
    %define result (rbp + result_offset)  ; 通过 [result] 访问
    sub  rsp, 8            ;; stksz=8，已是 8 的倍数，N=8

    ; ... 用 [result] 存中间结果 ...
    mov rax, [result] ;; rax 是返回值

    end
    ret  16    ; 清理调用方压入的 2 个参数（16 字节），局部变量随 end 里的 mov rsp,rbp 一并归还
```

单参数、无局部变量的函数（如下面例子里的 `fibo`、`printNum`）参数恒定落在 `(rbp+16)`（访问时写 `[x]`）；没有局部变量时 `stksz=0`，`sub rsp` 直接省略。

## 完整调用示例（递归 fibo）

```asm
main:
    begin

    push 10          ; 传参：压栈
    call fibo
    push rax         ; fibo 返回值在 rax，作为参数传给 printNum
    call printNum
    ...

fibo:
    ;; params
    %define x   (rbp + 16)

    begin
    ;; local vars
    %assign acc_offset (-8)   ; 用来存第一次递归调用的结果，8 字节
    %define acc (rbp + acc_offset)
    sub  rsp, 8          ; stksz=8，已是 8 的倍数，N=8

    mov rax, [x]
    cmp rax, 2
    jg .calc
    mov rax, 1
    jmp .end
.calc:
    mov rax, [x]
    sub rax, 1
    push rax
    call fibo        ; 调用之后除 rax 外所有寄存器视为已破坏
    mov [acc], rax      ; 立刻把结果存回栈上的局部变量，不留在寄存器里

    mov rax, [x]
    sub rax, 2
    push rax
    call fibo
    add rax, [acc]      ; acc 是栈上变量，不受两次调用之间寄存器被破坏的影响
.end:
    end
    ret  8            ; 清理调用方压入的 1 个 8 字节参数（局部变量随 end 里的 mov rsp,rbp 一并归还）

printNum:
    ;; params
    %define x (rbp + 16)

    begin
    ;; 没有真正的局部变量，stksz=0，不需要 sub rsp——对齐交给下面的 hexalign 动态处理

    hexalign
    mov rdi, printMsg   ; 按真实 System V ABI 准备 printf 的参数
    mov rsi, [x]
    xor rax, rax         ; printf 是变参函数，rax 需清零表示 0 个向量寄存器参数
    call printf           ; 无需任何寄存器保护——本来就没有寄存器里的值需要在调用后存活

    end
    ret  8
```

## 这个模式解决的问题

写手工汇编时最烦的两件事：

1. 每个函数都要小心翼翼记住"我用了哪个寄存器、要不要保存、调用前后哪些寄存器还能信"——这套设计把答案统一成一句话："调用之后除 rax 外全部作废"，于是干脆不把任何东西放进寄存器里长期存活，问题直接消失，不需要再靠宏机械地保存/恢复。
2. 递归/多层调用时，寄存器容易在调用链上被不同层覆写而出 bug——把所有变量（参数和局部变量）都固定摆在栈上用 `%define` 访问，天然不受任何一次 `call` 影响，寄存器纯粹是"这一行算式"的草稿纸，用完即弃，从根源上不存在"寄存器被子调用覆写"这类 bug。

## 适用场景与局限

- 适合纯自研代码内部（函数间互相调用只走这套约定），把"要不要保存寄存器"这个问题直接消灭，心智负担比"callee-saved 约定 + 宏保存"更低。
- 边界清晰：一旦调用外部库（libc、系统调用等使用标准 ABI 的代码），只需按真实 ABI 把参数放进对应寄存器（如例中 `mov rdi, ...` / `mov rsi, ...`），不需要任何额外的寄存器保护步骤——因为本来就没有值指望在 `call` 之后还活在寄存器里；真实 ABI 要求的调用点 16 字节栈对齐也不需要手算，调用点前放一句 `hexalign` 即可动态处理。
- 代价：所有变量读写都要走一次内存访问（`[rbp±N]`），比全寄存器分配慢很多，也比"寄存器变量 + callee-saved 宏"的版本多一些 `mov`；仅适合教学/实验/把心智负担降到最低优先于性能的场景。

