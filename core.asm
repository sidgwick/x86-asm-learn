        ; 第十四章, 内核

        [bits 32]

        ; 以下常量定义部分
        ; 内核的大部分内容都应当固定
        core_code_seg_sel   equ 0x38 ; 内核代码段选择子 0011_1000 = 7#
        core_data_seg_sel   equ 0x30 ; 内核数据段选择子 0011_0000 = 6#
        sys_routine_seg_sel equ 0x28 ; 系统公共例程代码段的选择子 0010_1000 = 5#
        video_ram_seg_sel   equ 0x20 ; 视频显示缓冲区的段选择子 0010_0000 = 4#
        core_stack_seg_sel  equ 0x18 ; 内核堆栈段选择子 0001_1000 = 3#
        mem_0_4_gb_seg_sel  equ 0x08 ; 整个 0~4GB 内存的段的选择子 = 0000_1000 = 1#

;-------------------------------------------------------------------------------
        ; 以下是系统核心的头部, 用于加载核心程序
        core_length     dd core_end                  ; 核心程序总长度 #00
        sys_routine_seg dd section.sys_routine.start ; 系统公用例程段位置 #04
        core_data_seg   dd section.core_data.start   ; 核心数据段位置 #08
        core_code_seg   dd section.core_code.start   ; 核心代码段位置 #0c
        core_entry      dd start                     ; 核心代码段入口点 #10
                        dw core_code_seg_sel ; 内核代码段选择子, 配合 start, 可以直接成为一个 jmp far 跳转点

;===============================================================================
; 系统公共例程代码段
; 注意系统公共例程被设计成一个单独的代码段, 因此函数返回值都是段间返回
SECTION sys_routine vstart=0

;-------------------------------------------------------------------------------
; 字符串显示例程
; 用于显示 0 终止的字符串并移动光标
;     输入: DS:EBX = 串地址
put_string:
        push ecx

    .getc:
        mov  cl, [ebx]
        or   cl, cl
        jz   .exit     ; 到达 0 终止的字符结尾了
        call put_char
        inc  ebx
        jmp  .getc

    .exit:
        pop ecx
        retf

;-------------------------------------------------------------------------------
; 在当前光标处显示一个字符, 并推进光标
; 仅用于段内调用
;     输入: CL = 字符ASCII码
put_char:
        ; 先把所有的通用寄存器压栈
        ; 等于 push EDI, ESI, EBP, ESP, EBX, EDX, ECX, EAX
        pushad


        ; 以下取当前光标位置
        mov dx, 0x3d4
        mov al, 0x0e
        out dx, al    ; 端口号大于 255 的时候, 只能使用 DX 表示, `out 0x3d4, al` 是不合法的
        inc dx
        in  al, dx
        mov ah, al    ; 低字节

        dec dx
        mov al, 0x0f
        out dx, al
        inc dx
        in  al, dx   ; 低字

        mov bx, ax ; BX 代表光标位置的 16 位数

        ; 处理回车符, 将光标退回到本行开头
        cmp cl, 0x0d
        jnz .put_0a
        mov ax, bx
        mov bl, 80
        div bl
        mul bl
        mov bx, ax
        jmp .set_cursor

        ; 处理换行符, 光标移动到下一行相同的列
    .put_0a:
        cmp cl, 0x0a
        jnz .put_other
        add bx, 80
        jmp .roll_screen

        ; 显示其他字符
    .put_other:
        push es
        mov  eax,     video_ram_seg_sel ; 显示缓冲区段选择子
        mov  es,      eax
        shl  bx,      1                 ; 一个字符对应两个字节, 因此这里要 x2
        mov  [es:bx], cl
        pop  es

        ; 以下将光标位置推进一个字符
        shr bx, 1
        inc bx

        ; 如有必要, 滚屏
    .roll_screen:
        cmp bx, 2000
        jl  .set_cursor

        push ds
        push es
        mov  eax, video_ram_seg_sel
        mov  ds,  eax
        mov  es,  eax

        cld ; movsX 指针正向增长

        mov esi, 0xa0
        mov edi, 0x00
        mov ecx, (2000-80)*2/4 ; =960

        ; 这不是一口气移动 4 个, 那么只需要 cx 设置 (2000-80)*2/4 = 960 就可以了吗?
        ; 经过测试, 确实可以使用 960 来控制循环. 原书老师的代码应该是多操作了数据
        rep movsd

        ; 清除屏幕最下方的一行
        mov bx,  3840
        mov ecx, 80
    .cls:
        mov  word [es:bx], 0x0720
        add  bx,           2
        loop .cls

        pop es
        pop ds

        mov bx, 1920

    .set_cursor:
        call set_cursor

        popad
        ret ; 段内返回

; -------------------------------------------------------------------------------
; 设置光标
;   输入: BX = 光标位置
set_cursor:
        push edx
        push eax

        mov dx, 0x3d4
        mov al, 0x0e
        out dx, al
        inc dx
        mov al, bh
        out dx, al    ; 写低字节

        dec dx
        mov al, 0x0f
        out dx, al
        inc dx
        mov al, bl
        out dx, al   ; 写高字节

        pop eax
        pop edx

        ret ; 段内返回

; -------------------------------------------------------------------------------
; 清屏, 并把光标移动到开始位置
clear_screen:
        push ecx
        push eax
        push ebx
        push ds

        mov eax, video_ram_seg_sel
        mov ds,  eax

        ; 屏幕上输出 2000 个空格, 就是清屏了
        mov ecx, 2000
        mov ebx, 0
    .cb1:
        mov  word [ebx], 0x0720
        add  ebx,        2
        loop .cb1

        ; 光标设置到 (0,0) 位置
        mov  bx, 0
        call set_cursor

        pop ds
        pop ebx
        pop eax
        pop ecx

        retf

; -------------------------------------------------------------------------------
; 从硬盘读取一个逻辑扇区
;     EAX = 逻辑扇区号
;     DS:EBX = 目标缓冲区地址
;     返回 ==> EBX = EBX+512
read_hard_disk_0:
        push eax
        push ecx
        push edx

        ; 扇区数量需要用 eax 寄存器, 因此要先保存一下
        push eax

        ; 0x1f2, 读取的扇区数
        mov dx, 0x1f2
        mov al, 1
        out dx, al

        pop eax

        ; 0x1f3 端口写 LBA 7~0 位
        inc dx
        out dx, al

        mov cl, 8

        ; 0x1f4 端口写 LBA 15~8 位
        inc dx
        shr eax, cl
        out dx,  al

        ; 0x1f5 端口写 LBA 23~16 位
        inc dx
        shr eax, cl
        out dx,  al

        ; 0x1f6, 指定第一硬盘 以及 LBA 地址 27~24
        ; 0xe0 的解释: 1110_0000B, bit(4)=0/1-表示主/从硬盘, bit(6)=0/1指定 CHS/LBA 地址模式, bit(5|7) 是保留位始终为 1
        inc dx
        shr eax, cl
        or  al,  0xe0
        out dx,  al

        ; 0x1f7
        ;    1. 发送 0x20 表示开始读取硬盘数据
        ;    2. 直接读取 0x1f7 端口可以获取到硬盘的状态信息
        inc dx
        mov al, 0x20
        out dx, al

        ; 接下来等待读取完成
    .waits:
        in  al, dx
        and al, 0x88 ; 1000_1000B, bit(3)=1 表示硬盘已经准备好和内存交换数据, bit(7)=1 表示硬盘忙
        cmp al, 0x08
        jnz .waits   ; 不忙(bit7), 且硬盘已准备好数据传输(bit3)

        ; 0x1f0 端口, 正式读取硬盘数据
        mov dx,  0x1f0
        mov ecx, 256   ; 准备读取 256 字节
    .readw:
        in   ax,    dx
        mov  [ebx], ax
        add  ebx,   2
        loop .readw

        pop edx
        pop ecx
        pop eax

        retf

;-------------------------------------------------------------------------------
; 汇编语言程序是极难一次成功, 而且调试非常困难. 这个例程可以提供帮助
; 在当前光标处以十六进制形式显示一个双字并推进光标
;     输入: EDX=要转换并显示的数字
;     输出: 无
put_hex_dword:
        pushad
        push ds

        ; 切换到核心数据段
        mov ax, core_data_seg_sel
        mov ds, ax

        ; ebx 指向核心数据段内的转换表
        mov ebx, bin_hex
        mov ecx, 8

    .xlt:
        rol edx, 4
        mov eax, edx
        and eax, 0x0000000F

        ; 从内存表中读取一个字节, 其地址由 [DS:EBX + AL] 计算得出, 并将该字节放入 AL 寄存器
        xlat

        push ecx
        mov  cl, al
        call put_char
        pop  ecx

        loop .xlt

        pop ds
        popad

        retf

;-------------------------------------------------------------------------------
; 分配内存
;     输入: ECX=希望分配的字节数
;     输出: ECX=起始线性地址
allocate_memory:
        push ds
        push eax
        push ebx

        mov eax, core_data_seg_sel
        mov ds,  eax

        ; 计算好下一次分配时的起始地址
        mov eax, [ram_alloc]
        add eax, ecx

        ; 这里应当有检测可用内存数量的指令

        ; 返回分配的起始地址
        mov ecx, [ram_alloc]

        ; 下一个可用内存的地址

        ; 考虑到效率, 这里需要计算好用 4 字节对齐
        ; 先向下砍到 4 字节对齐, 再向上移动 4 字节
        mov ebx, eax
        and ebx, 0xfffffffc ; ... 1100B
        add ebx, 4          ; 强制对齐

        ; test 结果类似 and 指令, 但是不会保存操作结果, 只影响 ecflags 标记
        ; 如果以前 eax 就是 4 字节对齐的, test 执行结果是 0, 否则非 0
        ; 然后使用条件移动指令 cmovnz, 仅在 eax 不是 4 字节对齐的时候, 才将 EAX=EBX
        test   eax, 0x00000003
        cmovnz eax, ebx

        ; 下次从该地址分配内存
        mov [ram_alloc], eax

        pop ebx
        pop eax
        pop ds

        retf

;-------------------------------------------------------------------------------
; 在GDT内安装一个新的描述符
;     输入: EDX:EAX=描述符
;     输出: CX=描述符的选择子
set_up_gdt_descriptor:
        push eax
        push ebx
        push edx

        push ds
        push es

        ; 切换到核心数据段
        mov ebx, core_data_seg_sel
        mov ds,  ebx

        ; 保存当前的 GDTR 数值到内存, 以便待会儿更新 GDT
        sgdt [pgdt]

        mov ebx, mem_0_4_gb_seg_sel
        mov es,  ebx

        ; mov with zero extend
        ; 把 [pgdt] 位置的 2 个字节, 移动到 ebx, 高 16 位用 0 填充
        ; [pgdt+2] 记录的是 GDT 的基地址
        ; 注意 `inc bx` 只能用 bx, 以防止有溢出的情况影响 EBX 的高 16 位
        movzx ebx, word [pgdt] ; GDT界限
        inc   bx               ; GDT总字节数, 也是下一个描述符偏移
        add   ebx, [pgdt+2]    ; 下一个描述符的线性地址 - 绝对地址

        ; 安装描述符
        mov [es:ebx],   eax
        mov [es:ebx+4], edx

        ; 增加一个描述符的大小
        add word [pgdt], 8

        ; 对 GDT 的更改生效
        lgdt [pgdt]

        ; 得到 GDT 界限值, 然后计算出刚才这个描述符的索引号
        mov ax, [pgdt]
        xor dx, dx
        mov bx, 8
        div bx         ; 除以8
        mov cx, ax     ; 取商就是索引号
        shl cx, 3      ; 将索引号移到正确位置(bit0/1 是特权级, bit2 是 GDT/LDT)

        pop es
        pop ds

        pop edx
        pop ebx
        pop eax

        retf

;-------------------------------------------------------------------------------
; 构造描述符
;    输入: EAX=线性基地址
;          EBX=段界限
;          ECX=属性(各属性位都在原始位置，其它没用到的位置0)
;    返回: EDX:EAX=完整的描述符
;
; 描述符组成(左高右低, 上高下低, B=base, L=limit):
;    BBXL_YZBB, X=G_(D/B)_L_AVL, Y=P_(DPL-2)_S, Z=TYPE(XCRA/XEWA)
;    BBBB_LLLL
make_seg_descriptor:
        ; lower = LLLL_BBBB
        mov edx, eax
        shl eax, 16
        or  ax,  bx

        ; 下面组装高字节, high = BBPL_PPBB

        ; 这里装配段基址
        and   edx, 0xFFFF0000
        rol   edx, 8          ; 循环左移位, 变成了 BB0000bb
        bswap edx             ; 交换字节顺序 bb0000BB

        ; 装配段界限的高4位
        xor bx,  bx
        or  edx, ebx

        ; 装配段属性
        or edx, ecx

        retf


;-------------------------------------------------------------------------------
; 构造门的描述符(调用门等)
;     输入: EAX=门代码在段内偏移地址
;           BX=门代码所在段的选择子
;           CX=段类型及属性等(各属性位都在原始位置)
;     返回: EDX:EAX=完整的描述符
;
; 描述符组成(左高右低, 上高下低, O=offset, S=selector):
;    OOOO_ABCD
;    SSSS_OOOO
; 调用门: A=P_(DPL-2)_0, B=TYPE(1100), CD=000_(param-count)
make_gate_descriptor:
        push ebx
        push ecx

        mov edx, eax
        and edx, 0xffff0000 ;得到偏移地址高16位
        or  dx,  cx         ;组装属性部分到EDX

        and eax, 0x0000ffff ;得到偏移地址低16位
        shl ebx, 16
        or  eax, ebx        ;组装段选择子部分

        pop ecx
        pop ebx

        retf

sys_routine_end:

;===============================================================================
; 系统核心的数据段
SECTION core_data vstart=0

        pgdt dw 0 ; 用于设置和修改 GDT
             dd 0

        ram_alloc dd 0x00100000 ; 下次分配内存时的起始地址

        ; 符号地址检索表
    salt:
        ; salt 名称部分是 256 字节, 不足部分用 0 补齐
        ;      之后是函数的偏移地址和它所在的代码段描述符选择子
        salt_1 db '@PrintString'
               times 256-($-salt_1) db 0

               dd put_string
               dw sys_routine_seg_sel

        salt_2 db '@ReadDiskData'
               times 256-($-salt_2) db 0

               dd read_hard_disk_0
               dw sys_routine_seg_sel

        salt_3 db '@PrintDwordAsHexString'
               times 256-($-salt_3) db 0

               dd put_hex_dword
               dw sys_routine_seg_sel

        salt_4 db '@TerminateProgram'
               times 256-($-salt_4) db 0

               dd return_point
               dw core_code_seg_sel

        salt_item_len equ $-salt_4
        salt_items    equ ($-salt)/salt_item_len

        message_1 db '  If you seen this message,that means we '
                  db 'are now in protect mode,and the system '
                  db 'core is loaded,and the video display '
                  db 'routine works perfectly.', 0x0d, 0x0a, 0

        message_2 db '  System wide CALL-GATE mounted.', 0x0d, 0x0a, 0
        message_3 db 0x0d, 0x0a, '  Loading user program...', 0

        do_status db 'Done.', 0x0d, 0x0a, 0

        message_6 db 0x0d, 0x0a, 0x0d, 0x0a, 0x0d, 0x0a
                  db '  User program terminated,control returned.', 0

        ; put_hex_dword 子过程用的查找表
        bin_hex db '0123456789ABCDEF'

        ; 内核用的缓冲区
        core_buf times 2048 db 0

        ; 内核用来临时保存自己的栈指针
        esp_pointer dd 0

        cpu_brnd0 db 0x0d, 0x0a, '  ', 0
        cpu_brand times 52 db 0
        cpu_brnd1 db 0x0d, 0x0a, 0x0d, 0x0a, 0

        ; 任务控制块链
        tcb_chain dd 0

core_data_end:

;===============================================================================
; 系统核心代码段
SECTION core_code vstart=0

;-------------------------------------------------------------------------------
; 在LDT内安装一个新的描述符
;     输入: EDX:EAX=描述符
;           EBX=TCB基地址
;     输出: CX=描述符的选择子
fill_descriptor_in_ldt:
        push eax
        push edx
        push edi
        push ds

        mov ecx, mem_0_4_gb_seg_sel
        mov ds,  ecx

        mov edi, [ebx+0x0c] ; 获得 LDT 基地址

        xor ecx, ecx
        mov cx,  [ebx+0x0a] ; 获得 LDT 界限
        inc cx              ;  LDT 的总字节数, 即新描述符偏移地址

        mov [edi+ecx+0x00], eax
        mov [edi+ecx+0x04], edx ; 安装描述符

        add cx, 8
        dec cx    ; 得到新的 LDT 界限值

        mov [ebx+0x0a], cx ; 更新 LDT 界限值到 TCB

        mov ax, cx
        xor dx, dx
        mov cx, 8
        div cx

        mov cx, ax
        shl cx, 3                    ; 左移 3 位, 并且
        or  cx, 0000_0000_0000_0100B ; 使 TI=1, 指向 LDT, 最后使 RPL=00

        pop ds
        pop edi
        pop edx
        pop eax

        ret

;-------------------------------------------------------------------------------
; 加载并重定位用户程序
;     输入: PUSH 逻辑扇区号, PUSH 任务控制块 TCB 基地址
;     返回: 无
load_relocate_program:
        pushad

        push ds
        push es

        ; 首先从栈里面取出来所需的参数

        ; 为访问通过堆栈传递的参数做准备
        mov ebp, esp

        mov ecx, mem_0_4_gb_seg_sel
        mov es,  ecx

        mov esi, [ebp+11*4] ; 从堆栈中取得 TCB 的基地址

        ; 以下申请创建 LDT 所需要的内存
        ; 允许安装 20 个 LDT 描述符
        mov  ecx,                160
        call sys_routine_seg_sel:allocate_memory
        mov  [es:esi+0x0c],      ecx             ; 登记 LDT 基地址到 TCB 中
        mov  word [es:esi+0x0a], 0xffff          ; 登记 LDT 初始的界限到 TCB 中
        ; TODO: 为啥是 0xFFFF, 不应该是 160=0xA0 吗?

        ; 以下开始加载用户程序

        ; 切换DS到内核数据段
        mov eax, core_data_seg_sel
        mov ds,  eax

        ; 从堆栈中取出用户程序起始扇区号
        mov  eax, [ebp+12*4]
        mov  ebx, core_buf
        call sys_routine_seg_sel:read_hard_disk_0

        ; 以下判断整个程序有多大
        mov    eax, [core_buf] ;程序尺寸
        mov    ebx, eax
        ; 下面使程序大小以 512 字节对齐
        and    ebx, 0xfffffe00
        add    ebx, 512
        test   eax, 0x000001ff
        cmovnz eax, ebx

        mov  ecx,           eax
        call sys_routine_seg_sel:allocate_memory ; ECX 里面有所分配的内存的起始地址
        mov  [es:esi+0x06], ecx                  ; 登记程序加载基地址到 TCB 中
        ; push ebx
        mov  ebx,           ecx                  ; EBX 现在有 申请到的内存首地址

        ; 接下来做一个除法计算, 算一下程序有多少扇区
        ; 因为上面 eax 做了 512 对齐, 因此这里的除法, 一定是整除
        xor edx, edx
        mov ecx, 512
        div ecx
        mov ecx, eax

        mov eax, mem_0_4_gb_seg_sel ; 切换 DS 到 0~4GB 的段
        mov ds,  eax

        ; 把用户程序读取到内存(注意这里重新读取了一遍第一个扇区)
        mov eax, [ebp+12*4] ; 起始扇区号
    .b1:
        call sys_routine_seg_sel:read_hard_disk_0
        inc  eax
        loop .b1

        ; 现在程序已经在内存中了, 程序所在内存块的首地址登记在 TCB 里面
        mov edi, [es:esi+0x06] ; 获得程序加载基地址
        ; pop edi

        ; ---------------- 建立程序 `头部段` 描述符 ----------------
        mov eax, edi
        mov ebx, [edi+0x04] ; 段长度, 也是 `头部段` 的长度
        inc ebx             ; 段界限
        mov ecx, 0x0040f200 ; 字节粒度, 数据段描述符, dpl=3, g_db_l_val = 0100, p_dpl_s_type = 1111_0010

        call sys_routine_seg_sel:make_seg_descriptor

        ; 安装头部段描述符到 LDT 中
        mov  ebx, esi               ; TCB 的基地址
        call fill_descriptor_in_ldt

        ; CX 里面是刚刚创建好的描述符选择子, 把它登记到 TCB 里面, 同时也放到原来记录 `头部段` 长度的位置
        or  cx,            0000_0000_0000_0011B ; 设置选择子的特权级为 3
        mov [es:esi+0x44], cx                   ; 登记程序头部段选择子到 TCB
        mov [edi+0x04],    cx                   ; 和头部内


        ; ---------------- 建立程序 `代码段` 描述符 ----------------
        mov eax, edi
        add eax, [edi+0x14] ; 代码起始线性地址
        mov ebx, [edi+0x18] ; 段长度
        dec ebx
        mov ecx, 0x0040f800 ; 字节粒度的代码段描述符, dpl=3, g_db_l_val = 0100, p_dpl_s_type = 1111_1000

        call sys_routine_seg_sel:make_seg_descriptor

        mov  ebx, esi               ; TCB的基地址
        call fill_descriptor_in_ldt

        or  cx,         0000_0000_0000_0011B ; 设置选择子的特权级为 3
        mov [edi+0x14], cx                   ; 登记代码段选择子到头部

        ; ---------------- 建立程序数据段描述符 ----------------
        mov eax, edi
        add eax, [edi+0x1c]
        mov ebx, [edi+0x20]
        dec ebx
        mov ecx, 0x0040f200 ; 0100, 1111_0010

        call sys_routine_seg_sel:make_seg_descriptor

        mov  ebx, esi               ; TCB的基地址
        call fill_descriptor_in_ldt

        or  cx,         0000_0000_0000_0011B ; 设置选择子的特权级为 3
        mov [edi+0x1c], cx                   ; 登记数据段选择子到头部


        ; 建立程序堆栈段描述符
        ; ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        ; 注意看堆栈段描述符的计算过程
        ;   G = 1 的时候:
        ;     - limit = 0xFFFFF - stack_size/4
        ;     - base = stack_size + LA

        ; stack_size/4, 这个是程序建议 core 为自己预留的堆栈大小
        mov ecx, [edi+0x0c] ; 4KB 的倍率

        ; 段界限下限计算
        mov ebx, 0x000fffff
        sub ebx, ecx

        ; 计算栈空间大小(以字节为单位)
        mov eax, 4096
        mul ecx

        ; 准备为堆栈分配内存
        mov  ecx, eax
        call sys_routine_seg_sel:allocate_memory

        add  eax, ecx                                ; EAX 是栈空间大小, LA=ecx
        mov  ecx, 0x00c0f600                         ; 4KB, dpl=3 g_db_l_avl=1100, p_dpl_s_type=1001_0110
        call sys_routine_seg_sel:make_seg_descriptor

        mov  ebx, esi               ; TCB的基地址
        call fill_descriptor_in_ldt

        or  cx,         0000_0000_0000_0011B ; 设置选择子的特权级为 3
        mov [edi+0x08], cx                   ; 登记堆栈段选择子到头部
        ; ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

        ; 重定位SALT
        ;
        ; for (c in core_salts) {
        ;     for (u in user_salts) {
        ;         if (c.name == u.name) {
        ;             // do sth
        ;         }
        ;     }
        ; }

        ; 系统调用查找表
        ; 做了 2 层循环
        ;    第一层遍历用户程序需要的 SALT 列表
        ;    第二层遍历系统公共例程 SALT 表, 并将系统例程段选择子和偏移信息填充到用户程序
        ; ------------------------
        ; 重定位 SALT
        ; 这里的 SALT 更多的是对系统公共例程的处理

        ; 这里和前一章不同, 头部段描述符已安装, 但还没有生效, 故只能通过 4GB 段访问用户程序头部
        mov eax, mem_0_4_gb_seg_sel
        mov es,  eax
        mov eax, core_data_seg_sel
        mov ds,  eax

        cld

        ; .b2 第一层循环
        mov ecx, [es:edi+0x24] ; 用户程序的 SALT 条目数
        add edi, 0x28          ; 用户程序内的 SALT 位于头部内 0x28 处
    .b2:
        push ecx
        push edi

        ; .b3 是第二层循环

        ; 下面遍历 core 提供的公共例程入口点
        ; 如果程序也用到了这个例程, 就把例程段描述符信息追加到用户程序
        mov ecx, salt_items
        mov esi, salt
    .b3:
        push edi
        push esi
        push ecx

        ; 比较 core(DS:ESI), user(ES:EDI) 的数据
        ; cmpsd 指令每次比较 4 个字节, 直到发现不同停止或者完全相同 ECX = 0 停止
        ; 如果完全相同, cpmsd 操作完成之后, ESI 和 EDI 都增加了 256 字节, 因此后续计算里都减去 256 字节
        mov ecx, 64
        repe cmpsd

        ; 不相等说明用户程序对这个 salt 条目不感兴趣, 直接跳过处理
        jnz .b4

        ; 用户用到了这个 salt 条目
        mov eax,          [esi]   ; 若匹配, esi 恰好指向 core salt 后面的地址数据
        mov [es:edi-256], eax     ; 将字符串改写成偏移地址
        mov ax,           [esi+4]
        or  ax,           0x0003  ; 以用户程序自己的特权级使用调用门故 RPL=3
        mov [es:edi-252], ax      ; 写回调用门段选择子

    .b4:
        pop  ecx
        pop  esi
        add  esi, salt_item_len
        ; edi 表示的是用户程序字符串的头, 因为要和下一个 core 条目比较, 因此需要将它恢复到字符串开头的位置
        pop  edi
        loop .b3

        pop  edi
        add  edi, 256 ; 表示一个用户条目已经处理好, 去处理第二个用户条目
        pop  ecx
        loop .b2

        ; 下面位用户程序创建高特权级的栈段 + 登记 LDT 和 TSS 相关内容
        ; ------------------------------------------------
        mov esi, [ebp+11*4] ; 从堆栈中取得 TCB 的基地址

        ; 创建 0 特权级堆栈(4KB)
        mov  ecx,                 4096
        mov  eax,                 ecx                ; 为生成堆栈高端地址做准备
        mov  [es:esi+0x1a],       ecx
        shr  dword [es:esi+0x1a], 12                 ; 登记 0 特权级堆栈尺寸到 TCB
        call sys_routine_seg_sel:allocate_memory
        add  eax,                 ecx                ; 堆栈必须使用高端地址为基地址
        mov  [es:esi+0x1e],       eax                ; 登记 0 特权级堆栈基地址到 TCB
        mov  ebx,                 0xffffe            ; 段长度(界限)
        mov  ecx,                 0x00c09600         ; 4KB 粒度, 读写, 特权级 0
        call sys_routine_seg_sel:make_seg_descriptor
        mov  ebx,                 esi                ; TCB的基地址
        call fill_descriptor_in_ldt
        mov  [es:esi+0x22],       cx                 ; 登记 0 特权级堆栈选择子到 TCB
        mov  dword [es:esi+0x24], 0                  ; 登记 0 特权级堆栈初始 ESP 到 TCB

        ; 创建 1 特权级堆栈
        mov  ecx,                 4096
        mov  eax,                 ecx                  ; 为生成堆栈高端地址做准备
        mov  [es:esi+0x28],       ecx
        shr  dword [es:esi+0x28], 12                   ; 登记 1 特权级堆栈尺寸到 TCB
        call sys_routine_seg_sel:allocate_memory
        add  eax,                 ecx                  ; 堆栈必须使用高端地址为基地址
        mov  [es:esi+0x2c],       eax                  ; 登记 1 特权级堆栈基地址到 TCB
        mov  ebx,                 0xffffe              ; 段长度(界限)
        mov  ecx,                 0x00c0b600           ; 4KB 粒度, 读写, 特权级1
        call sys_routine_seg_sel:make_seg_descriptor
        mov  ebx,                 esi                  ; TCB 的基地址
        call fill_descriptor_in_ldt
        or   cx,                  0000_0000_0000_0001B ; 设置选择子的特权级为 1
        mov  [es:esi+0x30],       cx                   ; 登记1特权级堆栈选择子到 TCB
        mov  dword [es:esi+0x32], 0                    ; 登记1特权级堆栈初始 ESP 到 TCB

        ; 创建 2 特权级堆栈
        mov  ecx,                 4096
        mov  eax,                 ecx                  ; 为生成堆栈高端地址做准备
        mov  [es:esi+0x36],       ecx
        shr  dword [es:esi+0x36], 12                   ; 登记 2 特权级堆栈尺寸到 TCB
        call sys_routine_seg_sel:allocate_memory
        add  eax,                 ecx                  ; 堆栈必须使用高端地址为基地址
        mov  [es:esi+0x3a],       ecx                  ; 登记 2 特权级堆栈基地址到 TCB
        mov  ebx,                 0xffffe              ; 段长度(界限)
        mov  ecx,                 0x00c0d600           ; 4KB 粒度, 读写, 特权级 2
        call sys_routine_seg_sel:make_seg_descriptor
        mov  ebx,                 esi                  ; TCB 的基地址
        call fill_descriptor_in_ldt
        or   cx,                  0000_0000_0000_0010B ; 设置选择子的特权级为 2
        mov  [es:esi+0x3e],       cx                   ; 登记 2 特权级堆栈选择子到 TCB
        mov  dword [es:esi+0x40], 0                    ; 登记 2 特权级堆栈初始 ESP 到 TCB

        ; 在 GDT 中登记 LDT 描述符
        mov   eax,           [es:esi+0x0c]              ; LDT 的起始线性地址
        movzx ebx,           word [es:esi+0x0a]         ; LDT 段界限
        ; 字节粒度/32 位长度/存在/dpl=0/系统段/不执行/上生长/可读 数据段
        mov   ecx,           0x00408200                 ; LDT 描述符, 特权级 0
        call  sys_routine_seg_sel:make_seg_descriptor
        call  sys_routine_seg_sel:set_up_gdt_descriptor
        mov   [es:esi+0x10], cx                         ; 登记 LDT 选择子到 TCB 中

        ; 创建用户程序的 TSS
        mov  ecx,           104                  ; tss 的基本尺寸
        mov  [es:esi+0x12], cx
        dec  word [es:esi+0x12]                  ; 登记 TSS 界限值到 TCB
        call sys_routine_seg_sel:allocate_memory
        mov  [es:esi+0x14], ecx                  ; 登记 TSS 基地址到 TCB

        ; TODO: 思考
        ; 是否可以设计成 TSS 和 TCB 整合在一起的结构, 现在很多内容存了 2 份

        ; 登记基本的 TSS 表格内容

        ; TODO: 没看到其他的 TSS 是怎么维护的呢?
        ; TSS 中的这个 link 应该是 CPU 填写的, 等待找更多相关文档
        mov word [es:ecx+0], 0 ; 反向链 = 0

        mov edx,        [es:esi+0x24] ; 登记 0 特权级堆栈初始 ESP
        mov [es:ecx+4], edx           ; 到 TSS 中

        mov dx,         [es:esi+0x22] ; 登记 0 特权级堆栈段选择子
        mov [es:ecx+8], dx            ; 到 TSS 中

        mov edx,         [es:esi+0x32] ; 登记 1 特权级堆栈初始 ESP
        mov [es:ecx+12], edx           ; 到 TSS 中

        mov dx,          [es:esi+0x30] ; 登记 1 特权级堆栈段选择子
        mov [es:ecx+16], dx            ; 到 TSS 中

        mov edx,         [es:esi+0x40] ; 登记 2 特权级堆栈初始 ESP
        mov [es:ecx+20], edx           ; 到 TSS 中

        mov dx,          [es:esi+0x3e] ; 登记 2 特权级堆栈段选择子
        mov [es:ecx+24], dx            ; 到 TSS 中

        mov dx,          [es:esi+0x10] ; 登记任务的 LDT 选择子
        mov [es:ecx+96], dx            ; 到 TSS 中

        mov dx,           [es:esi+0x12] ; 登记任务的 I/O 位图偏移
        mov [es:ecx+102], dx            ; 到 TSS 中

        mov word [es:ecx+100], 0 ; T=0

        ; 在 GDT 中登记 TSS 描述符
        mov   eax,           [es:esi+0x14]              ; TSS 的起始线性地址
        movzx ebx,           word [es:esi+0x12]         ; 段长度(界限)
        mov   ecx,           0x00408900                 ; TSS 描述符, 特权级 0
        call  sys_routine_seg_sel:make_seg_descriptor
        call  sys_routine_seg_sel:set_up_gdt_descriptor
        mov   [es:esi+0x18], cx                         ; 登记 TSS 选择子到 TCB

        ; -------
        ; mov ax, [es:0x04] ; 本函数要求在 ax 里面存放用户程序头部的段选择子

        pop es ; 恢复到调用此过程前的 es 段
        pop ds ; 恢复到调用此过程前的 ds 段

        popad

        ; 丢弃调用本过程前压入的参数
        ; 分别是 逻辑扇区号和 TCB 基地址, 两个参数, 每个 4 字节
        ret 8

;-------------------------------------------------------------------------------
; 在 TCB 链上追加任务控制块
;     输入:: ECX=TCB 线性基地址
append_to_tcb_link:
        push eax
        push edx
        push ds
        push es

        ; 令 DS 指向内核数据段
        ; 令 ES 指向 0..4GB 段
        mov eax, core_data_seg_sel
        mov ds,  eax
        mov eax, mem_0_4_gb_seg_sel
        mov es,  eax

        ; 当前 TCB 指针域清零, 以指示这是最后一个 TCB
        mov dword [es: ecx+0x00], 0

        ; 遍历链表, 在链表末尾插入当前 TCB
        mov eax, [tcb_chain] ; TCB 表头指针
        or  eax, eax         ; 链表为空
        jz  .notcb

  .searc:
        mov edx, eax
        mov eax, [es: edx+0x00]
        or  eax, eax
        jnz .searc

        mov [es: edx+0x00], ecx
        jmp .retpc

  .notcb:
        mov [tcb_chain], ecx ;若为空表，直接令表头指针指向TCB

  .retpc:
        pop es
        pop ds
        pop edx
        pop eax

        ret

;-------------------------------------------------------------------------------
; 系统入口
start:
        ; clear screen
        call sys_routine_seg_sel:clear_screen

        ; 使 ds 指向核心数据段
        mov ecx, core_data_seg_sel
        mov ds,  ecx

        mov  ebx, message_1
        call sys_routine_seg_sel:put_string

        ; 显示处理器品牌信息
        mov eax, 0x80000002
        cpuid

        mov [cpu_brand + 0x00], eax
        mov [cpu_brand + 0x04], ebx
        mov [cpu_brand + 0x08], ecx
        mov [cpu_brand + 0x0c], edx

        mov eax, 0x80000003
        cpuid

        mov [cpu_brand + 0x10], eax
        mov [cpu_brand + 0x14], ebx
        mov [cpu_brand + 0x18], ecx
        mov [cpu_brand + 0x1c], edx

        mov eax, 0x80000004
        cpuid

        mov [cpu_brand + 0x20], eax
        mov [cpu_brand + 0x24], ebx
        mov [cpu_brand + 0x28], ecx
        mov [cpu_brand + 0x2c], edx

        mov  ebx, cpu_brnd0
        call sys_routine_seg_sel:put_string
        mov  ebx, cpu_brand
        call sys_routine_seg_sel:put_string
        mov  ebx, cpu_brnd1
        call sys_routine_seg_sel:put_string

        ; 以下开始安装为整个系统服务的调用门
        ; 特权级之间的控制转移必须使用门
        mov edi, salt       ; C-SALT 表的起始位置
        mov ecx, salt_items ; C-SALT 表的条目数量
  .b3:
        push ecx
        mov  eax,       [edi+256]                      ; 该条目入口点的 32 位偏移地址
        mov  bx,        [edi+260]                      ; 该条目入口点的段选择子
        ; 特权级 3 的调用门(3以上的特权级才允许访问)，0个参数(因为用寄存器传递参数, 而没有用栈)
        ; P_(DPL-2)_0_(TYPE-1100)_000_(param-args-5)
        mov  cx,        1_11_0_1100_000_00000B
        call sys_routine_seg_sel:make_gate_descriptor
        call sys_routine_seg_sel:set_up_gdt_descriptor
        ; 将返回的门描述符选择子回填
        ; 注意这里只是回填了调用门的选择子, 前面的偏移并没有动它
        mov  [edi+260], cx
        ; 指向下一个 C-SALT 条目
        add  edi,       salt_item_len
        pop  ecx
        loop .b3

        ; 对门进行测试
        ; 通过门显示信息(注意 call 指令里面的偏移量被忽略了, 只使用调用门描述符的选择子)
        mov  ebx, message_2
        call far [salt_1+256]

        ; 在内核中调用例程不需要通过门
        mov  ebx, message_3
        call sys_routine_seg_sel:put_string

        ; 创建任务控制块
        ; 这不是处理器的要求, 而是我们自己为了方便而设立的
        mov  ecx, 0x46
        call sys_routine_seg_sel:allocate_memory ; TCB 的内存首地址在 ECX
        call append_to_tcb_link                  ; 将任务控制块追加到 TCB 链表

        ; 从 50 扇区加载用户程序, 注意栈里面的参数有扇区号和 TCB 的首地址
        push dword 50
        push ecx
        call load_relocate_program

        mov  ebx, do_status
        call sys_routine_seg_sel:put_string

        ; 准备加载 LTR 和 LDT, 为开启用户程序做准备
        mov eax, mem_0_4_gb_seg_sel
        mov ds,  eax

        ltr  [ecx+0x18] ; 加载任务状态段
        lldt [ecx+0x10] ; 加载 LDT

        ; 切换到用户程序头部段
        mov eax, [ecx+0x44]
        mov ds,  eax

        ; 以下假装是从调用门返回, 摹仿处理器压入返回参数
        ; 可以观察一下, DS 外其他的段寄存器可能会因为特权级的原因, 被清零
        push dword [0x08] ; 调用前的堆栈段选择子(SS)
        push dword 0      ; 调用前的 esp

        push dword [0x14] ; 调用前的代码段选择子(CS)
        push dword [0x10] ; 调用前的 eip

        retf

; 用户程序返回点
return_point:
        ; 因为 c14.asm 是以 JMP 的方式使用调用门 @TerminateProgram
        ; 回到这里时, 特权级为 3, 会导致异常
        mov  eax, core_data_seg_sel
        mov  ds,  eax
        mov  ebx, message_6
        call sys_routine_seg_sel:put_string

        hlt

core_code_end:

;===============================================================================
SECTION core_trail

;-------------------------------------------------------------------------------
core_end:
