; 第 12 章

; 下面这两个宏定义用来生成描述符
%define descriptor_h(base, _offset, g_db_l_avl, p_dpl_s_type) ( \
    (base        & 0xFF000000) | ((base        & 0x00FF0000) >> 16)  | (_offset & 0x00F0000) | \
    ((g_db_l_avl & 0x0F) << 20) | ((p_dpl_s_type & 0xFF) <<8) \
)
%define descriptor_l(base, _offset) (((base & 0xFFFF) << 16) | _offset & 0xFFFF)

        ;设置堆栈段和栈指针
        mov eax, cs
        mov ss,  eax
        mov sp,  0x7c00

        ;计算GDT所在的逻辑段地址
        mov eax, [cs:pgdt+0x7c00+0x02] ;GDT的32位线性基地址
        xor edx, edx
        mov ebx, 16
        div ebx                        ;分解成16位逻辑地址

        mov ds,  eax ;令DS指向该段以进行操作
        mov ebx, edx ;段内起始偏移地址

        ;创建0#描述符，它是空描述符，这是处理器的要求
        mov dword [ebx+0x00], 0x00000000
        mov dword [ebx+0x04], 0x00000000

        ;创建1#描述符，这是一个数据段，对应0~4GB的线性地址空间
        mov dword [ebx+0x08], 0x0000ffff ;基地址为0，段界限为0xfffff
        mov dword [ebx+0x0c], 0x00cf9200 ;粒度为4KB，存储器段描述符

        ;创建保护模式下初始代码段描述符
        mov dword [ebx+0x10], 0x7c0001ff ;基地址为0x00007c00，512字节
        mov dword [ebx+0x14], 0x00409800 ;粒度为1个字节，代码段描述符

        ;创建以上代码段的别名描述符
        mov dword [ebx+0x18], 0x7c0001ff ;基地址为0x00007c00，512字节
        mov dword [ebx+0x1c], 0x00409200 ;粒度为1个字节，数据段描述符

        mov dword [ebx+0x20], 0x7c00fffe ;基地址为0x00007c00，界限为0xffffe
        mov dword [ebx+0x24], 0x00cf9600 ;粒度为4KB，向下扩展

        ;初始化描述符表寄存器GDTR
        mov word [cs: pgdt+0x7c00], 39 ;描述符表的界限

        lgdt [cs: pgdt+0x7c00]

        in  al,   0x92       ;南桥芯片内的端口
        or  al,   0000_0010B
        out 0x92, al         ;打开A20

        cli ;中断机制尚未工作

        mov eax, cr0
        or  eax, 1
        mov cr0, eax ;设置PE位

        ;以下进入保护模式... ...
        jmp 0x0010:dword flush ;16位的描述符选择子：32位偏移

        [bits 32]
    flush:
        mov eax, 0x0018
        mov ds,  eax

        mov eax, 0x0008 ;加载数据段(0..4GB)选择子
        mov es,  eax
        mov fs,  eax
        mov gs,  eax

        mov eax, 0x0020 ;0000 0000 0010 0000
        mov ss,  eax
        xor esp, esp    ;ESP <- 0

        mov dword [es:0x0b8000], 0x072e0750 ;字符'P'、'.'及其显示属性
        mov dword [es:0x0b8004], 0x072e074d ;字符'M'、'.'及其显示属性
        mov dword [es:0x0b8008], 0x07200720 ;两个空白字符及其显示属性
        mov dword [es:0x0b800c], 0x076b076f ;字符'o'、'k'及其显示属性

        ;开始冒泡排序
        mov ecx, pgdt-string-1 ;遍历次数=串长度-1
    @@1:
        push ecx    ;32位模式下的loop使用ecx
        xor  bx, bx ;32位模式下，偏移量可以是16位，也可以
    @@2: ;是后面的32位
        mov  ax,          [string+bx]
        cmp  ah,          al          ;ah中存放的是源字的高字节
        jge  @@3
        xchg al,          ah
        mov  [string+bx], ax
    @@3:
        inc  bx
        loop @@2
        pop  ecx
        loop @@1

        mov ecx, pgdt-string
        xor ebx, ebx         ;偏移地址是32位的情况
    @@4: ;32位的偏移具有更大的灵活性
        mov  ah,                 0x07
        mov  al,                 [string+ebx]
        mov  [es:0xb80a0+ebx*2], ax           ;演示0~4GB寻址。
        inc  ebx
        loop @@4

        hlt

;-------------------------------------------------------------------------------
    string db 's0ke4or92xap3fv8giuzjcy5l1m7hd6bnqtw.'
;-------------------------------------------------------------------------------
    pgdt dw 0
         dd 0x00007e00 ;GDT的物理地址
;-------------------------------------------------------------------------------
    times 510-($-$$) db 0
                     db 0x55,0xaa






;         ; 设置堆栈段和栈指针
;         mov ax, cs
;         mov ss, ax
;         mov sp, 0x7c00

;         ; 准备操作 GDT, 因此要先算清楚它所在的 `段:偏移` 地址
;         mov ax, [cs:gdt_base+0x7c00]
;         mov dx, [cs:gdt_base+0x7c00+0x02]
;         mov bx, 16
;         div bx
;         mov ds, ax                        ; 商是段地址
;         mov bx, dx                        ; 余数是偏移地址

;         ; 处理器要求 #0 描述符必须是空描述符
;         mov dword [bx+0x00], 0x00000000
;         mov dword [bx+0x04], 0x00000000

;         ; #1 描述符 - MBR 代码段
;         mov dword [bx+0x08], descriptor_l(0x7C00, 0x1FF)
;         mov dword [bx+0x0C], descriptor_h(0x7C00, 0x1FF, 0100B, 1001_1000B)

;         ; #2 描述符 - 显示缓冲区
;         mov dword [bx+0x10], descriptor_l(0xB8000, 0xFFFF)
;         mov dword [bx+0x14], descriptor_h(0xB8000, 0xFFFF, 0100B, 1001_0010B)

;         ; #3 描述符 - 栈
;         mov dword [bx+0x18], descriptor_l(0x0000, 0x7A00)
;         mov dword [bx+0x1C], descriptor_h(0x0000, 0x7A00, 0100B, 1001_0110B)

;         ; #4 描述符 - 代码段当数据段用
;         mov dword [bx+0x20], descriptor_l(0x7C00, 0x1FF)
;         mov dword [bx+0x24], descriptor_h(0x7C00, 0x1FF, 0100B, 1001_0010B)

;         ; 初始化 GDTR 寄存器
;         mov  word [cs:gdt_size+0x7c00], 39 ; 目前有 5 个段 x 8 byte = 共计 40 byte
;         lgdt [cs: gdt_size+0x7c00]

;         ; 打开 A20 地址线
;         in  al,   0x92       ; 南桥芯片内控制复位和 A20 的端口
;         or  al,   0000_0010B
;         out 0x92, al

;         cli ; 清中断

;         ; 设置 CR0, 准备进入保护模式
;         mov eax, cr0
;         or  eax, 0x00000001 ; PE 置位
;         mov cr0, eax

;         ; 已经进入保护模式
;         ; 使用远跳转, 调到 32 位模式代码执行
;         jmp dword 0x0008:flush

; [bits 32]

; flush:
;         ; auto debug breakpoint
;         xchg bx, bx

;         ; 按照保护模式加载 DS 段描述符
;         ; base=0xb800, limit=0xffff
;         mov cx, 10_0_00B ; GDT, idx=2, rpl=0
;         mov ds, cx

;         ; 按照保护模式加载 ES 段描述符
;         ; base=0xb800, limit=0xffff
;         mov cx, 100_0_00B ; GDT, idx=4, rpl=0
;         mov es, cx

;         ; 以下在屏幕上显示"Protect mode OK."
;         xor ecx, ecx
;         mov ebx, msg
;         mov ah,  0x07
;     .print:
;         mov al,         [es:ebx]
;         mov word [ecx], ax
;         inc ebx
;         add ecx,        2
;         cmp al,         0
;         jnz .print

;         ;以下用简单的示例来帮助阐述32位保护模式下的堆栈操作
;         mov cx,  00000000000_11_000B ;加载堆栈段选择子，描述符索引号是 3
;         mov ss,  cx                  ;线性基址 0x000b8000,段界限是 0x0ffff
;         mov esp, 0x7c00

;         mov  ebp, esp ;保存堆栈指针
;         push byte '.' ;压入立即数（字节）

;         sub ebp,    4
;         cmp ebp,    esp ;判断压入立即数时，ESP是否减4
;         jnz ghalt
;         pop eax
;         mov [0x20], al  ;显示句点

;         ghalt:
;         hlt ;已经禁止中断，将不会被唤醒


; ; ;-------------------------------------------------------------------------------

; msg:      db "Protecte mode OK", 0

; gdt_size: dw 0
; gdt_base: dd 0x00007e00            ; GDT 的物理地址

;         times 510-($-$$) db 0
; db 0x55,0xaa
