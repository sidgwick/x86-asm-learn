; 第 12 章

; 下面这两个宏定义用来生成描述符
%define descriptor_h(base, _offset, g_db_l_avl, p_dpl_s_type) ( \
    (base        & 0xFF000000) | ((base        & 0x00FF0000) >> 16)  | (_offset & 0x00F0000) | \
    ((g_db_l_avl & 0x0F) << 20) | ((p_dpl_s_type & 0xFF) <<8) \
)
%define descriptor_l(base, _offset) (((base & 0xFFFF) << 16) | _offset & 0xFFFF)


        ; 设置堆栈段和指针, 堆栈从 0x7c00 往下生长
        mov eax, cs
        mov ss,  eax
        mov sp,  0x7c00

        ; 计算 GDT 所在的逻辑段
        mov eax, [cs:pgdt+0x7c00+0x02]
        xor edx, edx
        mov ebx, 16
        div ebx                        ; EAX=SEGMENT, EDX=OFFSET

        mov ds,  eax
        mov ebx, edx

        ; 0# 描述符, 要求是空
        mov dword [ebx+0x00], 0x00000000
        mov dword [ebx+0x04], 0x00000000
        
        ; 1# 描述符, 数据段 0~4GB 线性地址空间
        mov dword [ebx+0x08], descriptor_l(0x00000000, 0xfffff)
        mov dword [ebx+0x0C], descriptor_h(0x00000000, 0xfffff, 1100B, 1001_0010B)
        
        ; 2# 描述符, 保护模式下初始代码段描述符
        mov dword [ebx+0x10], descriptor_l(0x7c00, 0x1ff)
        mov dword [ebx+0x14], descriptor_h(0x7c00, 0x1ff, 0100B, 1001_1000B)

        ; 3# 描述符, 保护模式下初始代码段描述符 - 数据段别名
        mov dword [ebx+0x18], descriptor_l(0x7c00, 0x1ff)
        mov dword [ebx+0x1C], descriptor_h(0x7c00, 0x1ff, 0100B, 1001_0010B)

        ; 4# 描述符, 栈段
        mov dword [ebx+0x20], descriptor_l(0x7c00, 0xffffe)
        mov dword [ebx+0x24], descriptor_h(0x7c00, 0xffffe, 1100B, 1001_0110B)


        ; 描述符表的界限
        mov word [cs: pgdt+0x7c00], (4+1) * 8 - 1

        ; 初始化描述符表寄存器 GDTR
        lgdt [cs: pgdt+0x7c00]

        ; 南桥芯片内的端口, 打开 A20 地址线
        in  al,   0x92
        or  al,   0000_0010B
        out 0x92, al

        ; 清中断
        cli

        ; 设置 PE 位
        mov eax, cr0
        or  eax, 1
        mov cr0, eax

        ;以下进入保护模式... ...
        jmp dword 0x0010:flush ; 16位的描述符选择子 : 32位偏移

        [bits 32]
    flush:
        ; 1_1000, 3# 选择子, 从 GDT 装载数据段
        mov eax, 0x0018
        mov ds,  eax

        ; 0_1000, #1 选择子, 这是 0~4GB 的数据段空间
        mov eax, 0x0008
        mov es,  eax
        mov fs,  eax
        mov gs,  eax

        ; 10_0000, 4# 选择子, 是以 0x7c00 为基址, 0xffffe 为限长的栈
        mov eax, 0x0020
        mov ss,  eax
        xor esp, esp    ; ESP <- 0

        ; 在屏幕上显示字符串
        mov dword [es:0x0b8000], 0x072e0750 ;字符'P'、'.'及其显示属性
        mov dword [es:0x0b8004], 0x072e074d ;字符'M'、'.'及其显示属性
        mov dword [es:0x0b8008], 0x07200720 ;两个空白字符及其显示属性
        mov dword [es:0x0b800c], 0x076b076f ;字符'o'、'k'及其显示属性

        ; 开始冒泡排序

        ; // bx 相当于 j 的地位, cx 在内外两层循环都用到了, 因此在开始内层循环的时候有一个 push 保护的动作
        ; for (i = len(string); i > 0; i++) {
        ;     for (j = 0; j < len(string) - i; j++) {
        ;         if (string[j] > string[j + 1]) {
        ;             swap(string[j], string[j + 1])
        ;         }
        ;     }
        ; }

        mov ecx, pgdt-string-1 ; 遍历次数 = 串长度-1
    @@1:
        push ecx    ; 32 位模式下的 loop 使用 ecx
        xor  bx, bx ; 32 位模式下, 偏移量可以是 16 位，也可以是后面的32位
    @@2:
        mov  ax,          [string+bx] ; 比较 bx 处的两个字节
        cmp  ah,          al          ; ah中存放的是源字的高字节
        jge  @@3                      ; ah >= al, 则无需交换两个内存单元
        xchg al,          ah          ; 交换两个操作数
        mov  [string+bx], ax          ; 把交换结果写回内存, 这时候高字节的数据是比较大的那个
    @@3:
        inc  bx  ; 字符串里面往后移动一位, 开始下一轮比较
        loop @@2
        pop  ecx
        loop @@1

        ; 这里将排好顺序的字符串显示到屏幕上
        mov ecx, pgdt-string
        xor ebx, ebx         ; 偏移地址是32位的情况, 32位的偏移具有更大的灵活性
    @@4:
        mov  ah,                 0x07
        mov  al,                 [string+ebx]
        mov  [es:0xb80a0+ebx*2], ax           ; 演示0~4GB寻址
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
