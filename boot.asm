; 第 13 章
; 硬盘主引导扇区代码


; 下面这两个宏定义用来生成描述符
%define descriptor_h(base, _offset, g_db_l_avl, p_dpl_s_type) ( \
    (base        & 0xFF000000) | ((base        & 0x00FF0000) >> 16)  | (_offset & 0x00F0000) | \
    ((g_db_l_avl & 0x0F) << 20) | ((p_dpl_s_type & 0xFF) <<8) \
)
%define descriptor_l(base, _offset) (((base & 0xFFFF) << 16) | _offset & 0xFFFF)

        core_base_address equ 0x00040000 ; 常数, 内核加载的起始内存地址
        core_start_sector equ 0x00000001 ; 常数, 内核的起始逻辑扇区号

        ; 设置堆栈段和栈指针
        mov ax, cs
        mov ss, ax
        mov sp, 0x7c00

        ; 计算 GDT 所在的逻辑段地址
        mov eax, [cs:pgdt+0x7c00+0x02]
        xor edx, edx
        mov ebx, 16
        div ebx

        mov ds,  eax ; DS 指向的是 GDT 所在的段
        mov ebx, edx ; EBX 指向的是 GDT 在段内的偏移

        ; 0# 空描述符
        mov dword [ebx+0x00], 0x00000000
        mov dword [ebx+0x04], 0x00000000

        ; 1# 描述符, 数据段, 0~4GB, 可读写, 4KB 粒度
        mov dword [ebx+0x08], descriptor_l(0x0, 0xFFFFF)
        mov dword [ebx+0x0C], descriptor_h(0x0, 0xFFFFF, 1100B, 1001_0010B)

        ; 2# 描述符, MBR 代码段, 只读
        mov dword [ebx+0x10], descriptor_l(0x7c00, 0x1ff)
        mov dword [ebx+0x14], descriptor_h(0x7c00, 0x1ff, 0100B, 1001_1000B)

        ; 3# 描述符, 栈段, 向下生长, 读写, 4KB 粒度
        mov dword [ebx+0x18], descriptor_l(0x7c00, 0xFFFFE)
        mov dword [ebx+0x1C], descriptor_h(0x7c00, 0xFFFFE, 1100B, 1001_0110B)

        ; 4# 显示缓冲区 - 描述符, 数据段, 读写, 1B 粒度
        mov dword [ebx+0x20], descriptor_l(0xb8000, 0x7FFF)
        mov dword [ebx+0x24], descriptor_h(0xb8000, 0x7FFF, 0100B, 1001_0010B)

        ; GDT 的长度 = (5 * 8) - 1
        mov word [cs:pgdt+0x7c00], 39

        ; 初始化描述符表寄存器 GDTR
        lgdt [cs:pgdt+0x7c00]

        ; 打开 A20 地址线
        in  al,   0x92
        or  al,   0000_0010B
        out 0x92, al

        ; 中断机制尚未工作
        cli

        ; 打开 PE 标志
        mov eax, cr0
        or  eax, 0x1
        mov cr0, eax

        ; 进入保护模式
        ; 0x0010 = 0001_0000 = 2# 选择子, MBR 代码段
        jmp dword 0x0010:flush

        [bits 32]

    flush:
        mov eax, 0x0008 ; 1000B, #1 选择子, 0~4GB 数据段
        mov ds,  eax

        mov eax, 0x0018 ; 1_1000B, #3 选择子, 栈段
        mov ss,  eax
        xor esp, esp

        ; 加载系统核心
        mov  edi, core_base_address ; 内核在内存中的目的地
        mov  eax, core_start_sector ; 内核所在扇区(起始)
        mov  ebx, edi
        call read_hard_disk_0       ; 从硬盘读入到内存

        ; 以下判断整个 core 程序有多少个扇区
        mov eax, [edi]
        xor edx, edx
        mov ecx, 512
        div ecx

        or  edx, edx ; 这是看一下 edx 是不是等于 0
        jnz @1       ; 未除尽, 因此结果比实际扇区数少 1, 我们已经读取 1 扇区, 继续读取剩余的即可
        dec eax      ; 刚好除尽, 已近读取 1 扇区, 接下来读其他扇区
    @1:
        or eax, eax ; 判断是不是读完了
        jz setup

        ; 读取剩余的扇区
        mov ecx, eax
        mov eax, core_start_sector
        inc eax
    @2:
        call read_hard_disk_0
        inc  eax
        loop @2

    setup:
        ; 注意此时 edi 指向的是 core 的开头
        ; ESI 将来用来构造新 GDT
        ; 代码段不可读, 因此不可以在代码段内寻址 pgdt, 但可以通过 4GB 的数据段来访问
        mov esi, [pgdt+0x7c00+0x02]

        ; 建立公用例程段描述符
        mov  eax, [edi+0x04]     ; 公用例程代码段起始汇编地址
        mov  ebx, [edi+0x08]     ; 核心数据段汇编地址
        sub  ebx, eax            ; 计算得到 `公用例程代码段` 的长度
        dec  ebx                 ; 公用例程段界限, -1 是因为限长从 0 开始计数
        add  eax, edi            ; 公用例程段基地址
        mov  ecx, 0x00409800     ; 字节粒度的代码段描述符 g_db_l_avl=0100, p_dpl_s_type=1001_1000
        call make_gdt_descriptor

        ; 5#, 安装描述符
        mov [esi+0x28], eax
        mov [esi+0x2c], edx

        ; 建立核心数据段描述符
        mov  eax, [edi+0x08]     ; 核心数据段起始汇编地址
        mov  ebx, [edi+0x0c]     ; 核心代码段汇编地址
        sub  ebx, eax
        dec  ebx                 ; 核心数据段界限
        add  eax, edi            ; 核心数据段基地址
        mov  ecx, 0x00409200     ; 字节粒度的数据段描述符 g_db_l_avl=0100, p_dpl_s_type=1001_0010
        call make_gdt_descriptor

        ; 6#, 安装描述符
        mov [esi+0x30], eax
        mov [esi+0x34], edx

        ; 建立核心代码段描述符
        mov  eax, [edi+0x0c]     ; 核心代码段起始汇编地址
        mov  ebx, [edi+0x00]     ; 程序总长度
        sub  ebx, eax
        dec  ebx                 ; 核心代码段界限
        add  eax, edi            ; 核心代码段基地址
        mov  ecx, 0x00409800     ; 字节粒度的代码段描述符 g_db_l_avl=0100, p_dpl_s_type=1001_1000
        call make_gdt_descriptor

        ; 7#, 安装描述符
        mov [esi+0x38], eax
        mov [esi+0x3c], edx

        ; 描述符表的界限 = 8*8 - 1
        mov word [pgdt+0x7c00], 63

        lgdt [pgdt+0x7c00]

        jmp far [edi+0x10]


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

        ret

;-------------------------------------------------------------------------------
; 构造描述符
;    输入: EAX=线性基地址
;          EBX=段界限
;          ECX=属性(各属性位都在原始位置，其它没用到的位置0)
;    返回: EDX:EAX=完整的描述符
make_gdt_descriptor:
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

        ret

;-------------------------------------------------------------------------------
        pgdt dw 0
             dd 0x00007e00 ; GDT 的物理地址
;-------------------------------------------------------------------------------
         times 510-($-$$) db 0
                          db 0x55,0xaa
