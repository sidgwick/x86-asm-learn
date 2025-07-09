        ; 第十三章, 内核

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

        cld           ; movsX 指针正向增长
        mov esi, 0xa0
        mov edi, 0x00
        mov ecx, 1920

        ; TODO: 测试疑问
        ; 这不是一口气移动 4 个, 那么只需要 cx 设置 (2000-80)*2/4 = 960 就可以了吗?
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

        ; 设置光标
    .set_cursor:
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

        popad
        ret ; 段内返回

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

        ; 保存当前的 GDTR, 以便待会儿更新 GDT
        sgdt [pgdt]

        mov ebx, mem_0_4_gb_seg_sel
        mov es,  ebx

        ; mov with zero extend
        ; 把 [pgdt] 2 个字节, 移动到 ebx, 高 16 位用 0 填充
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
        div bx         ; 除以8, 去掉余数
        mov cx, ax
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

        message_5 db '  Loading user program...', 0

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

;===============================================================================
; 系统核心代码段
SECTION core_code vstart=0

;-------------------------------------------------------------------------------
; 加载并重定位用户程序
;     输入: ESI=起始逻辑扇区号
;     返回: AX=指向用户程序头部的选择子
load_relocate_program:
        push ebx
        push ecx
        push edx
        push esi
        push edi

        push ds
        push es

        ; 切换DS到内核数据段
        mov eax, core_data_seg_sel
        mov ds,  eax

        ; 注意 ESI 是指向程序的起始逻辑扇区号
        mov  eax, esi
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

        mov  ecx, eax
        call sys_routine_seg_sel:allocate_memory ; ECX 里面有所分配的内存的起始地址
        mov  ebx, ecx
        push ebx

        ; 接下来做一个除法计算, 算一下程序有多少扇区
        ; 因为上面 eax 做了 512 对齐, 因此这里的除法, 一定是整除
        xor edx, edx
        mov ecx, 512
        div ecx
        mov ecx, eax

        mov eax, mem_0_4_gb_seg_sel ; 切换 DS 到 0~4GB 的段
        mov ds,  eax

        ; 把用户程序读取到内存(注意这里重新读取了一遍第一个扇区)
        mov eax, esi ; 起始扇区号
    .b1:
        call sys_routine_seg_sel:read_hard_disk_0
        inc  eax
        loop .b1

        ; 现在程序已经在内存中了, 程序所在内存块的首地址处于栈顶位置
        pop edi

        ; 建立程序 `头部段` 描述符
        ; ------------------------------------------------
        mov eax, edi
        mov ebx, [edi+0x04] ; 段长度, 也是 `头部段` 的长度
        inc ebx             ; 段界限
        mov ecx, 0x00409200 ; 字节粒度, 数据段描述符, g_db_l_val = 0100, p_dpl_s_type = 1001_0010

        call sys_routine_seg_sel:make_seg_descriptor
        call sys_routine_seg_sel:set_up_gdt_descriptor

        ; CX 里面是刚刚创建好的描述符选择子, 把它放到原来记录 `头部段` 长度的位置
        mov [edi+0x04], cx
        ; ------------------------------------------------


        ; 建立程序 `代码段` 描述符
        mov eax, edi
        add eax, [edi+0x14] ; 代码起始线性地址
        mov ebx, [edi+0x18] ; 段长度
        dec ebx
        mov ecx, 0x00409800 ; 字节粒度的代码段描述符, g_db_l_val = 0100, p_dpl_s_type = 1001_1000

        call sys_routine_seg_sel:make_seg_descriptor
        call sys_routine_seg_sel:set_up_gdt_descriptor
        mov  [edi+0x14], cx


        ; 建立程序数据段描述符
        mov eax, edi
        add eax, [edi+0x1c]
        mov ebx, [edi+0x20]
        dec ebx
        mov ecx, 0x00409200 ; 0100, 1001_0010

        call sys_routine_seg_sel:make_seg_descriptor
        call sys_routine_seg_sel:set_up_gdt_descriptor
        mov  [edi+0x1c], cx

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
        mul dword [edi+0x0c]

        ; 准备为堆栈分配内存
        mov  ecx, eax
        call sys_routine_seg_sel:allocate_memory

        add  eax,        ecx                           ; EAX 是栈空间大小, LA=ecx
        mov  ecx,        0x00c09600                    ; 4KB 粒度的堆栈段描述符 g_db_l_avl=1100, p_dpl_s_type=1001_0110
        call sys_routine_seg_sel:make_seg_descriptor
        call sys_routine_seg_sel:set_up_gdt_descriptor
        mov  [edi+0x08], cx
        ; ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~


        ; 系统调用查找表
        ; 做了 2 层循环
        ;    第一层遍历用户程序需要的 SALT 列表
        ;    第二层遍历系统公共例程 SALT 表, 并将系统例程段选择子和偏移信息填充到用户程序
        ; ------------------------
        ; 重定位 SALT
        ; 这里的 SALT 更多的是对系统公共例程的处理

        mov eax, [edi+0x04]        ; 这个内存块放的是用户程序头部段的段选择子
        mov es,  eax               ; es -> 用户程序头部
        mov eax, core_data_seg_sel
        mov ds,  eax

        cld

        ; .b2 第一层循环
        mov ecx, [es:0x24] ; 用户程序的 SALT 条目数
        mov edi, 0x28      ; 用户程序内的 SALT 位于头部内 0x2c 处
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
        mov [es:edi-252], ax      ; 以及段选择子

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

        mov ax, [es:0x04] ; 本函数要求在 ax 里面存放用户程序头部的段选择子

        pop es ; 恢复到调用此过程前的 es 段
        pop ds ; 恢复到调用此过程前的 ds 段

        pop edi
        pop esi
        pop edx
        pop ecx
        pop ebx

        ret

;-------------------------------------------------------------------------------
; 系统入口
start:
        ; 使 ds 指向核心数据段
        mov ecx, core_data_seg_sel
        mov ds,  ecx

        ; clear screen
        ; TODO

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

        mov  ebx, message_5
        call sys_routine_seg_sel:put_string

        ; 用户程序位于逻辑 50 扇区
        mov  esi, 50
        call load_relocate_program

        mov  ebx, do_status
        call sys_routine_seg_sel:put_string

        ; 临时保存堆栈指针
        mov [esp_pointer], esp

        mov ds, ax ; AX 在 load_relocate_program 之后是用户程序的头部选择子

        ; 控制权交给用户程序（入口点）
        ; 堆栈可能切换
        jmp far [0x10] ; 这跳转的是 DS:[0x10] TODO: ???


; 用户程序返回点
return_point:
        ; 使 ds 指向核心数据段
        mov eax, core_data_seg_sel
        mov ds,  eax

        ; 切换回内核自己的堆栈
        mov eax, core_stack_seg_sel
        mov ss,  eax
        mov esp, [esp_pointer]

        mov  ebx, message_6
        call sys_routine_seg_sel:put_string

        ; 这里可以放置清除用户程序各种描述符的指令
        ; 也可以加载并启动其它程序

        hlt

;===============================================================================
SECTION core_trail

;-------------------------------------------------------------------------------
core_end:
