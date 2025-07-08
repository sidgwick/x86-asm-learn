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
        mov dword [ebx+0x18], descriptor_l(0xb8000, 0x7FFF)
        mov dword [ebx+0x1C], descriptor_h(0xb8000, 0x7FFF, 0100B, 1001_0010B)

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
        or  cr0, 0x1
        mov cr0, eax

        ; 进入保护模式
        ; 0x0010 = 0001_0000 = 2# 选择子, MBR 代码段
        jmp dword 0x0010:flush

        [bits 32]
    flush:

;          mov eax, 0x0008 ;加载数据段(0..4GB)选择子
;          mov ds,  eax
      
;          mov eax, 0x0018 ;加载堆栈段选择子 
;          mov ss,  eax
;          xor esp, esp    ;堆栈指针 <- 0 
         
;          ;以下加载系统核心程序 
;          mov edi, core_base_address
      
;          mov  eax, core_start_sector
;          mov  ebx, edi               ;起始地址 
;          call read_hard_disk_0       ;以下读取程序的起始部分（一个扇区） 
      
;          ;以下判断整个程序有多大
;          mov eax, [edi] ;核心程序尺寸
;          xor edx, edx
;          mov ecx, 512   ;512字节每扇区
;          div ecx

;          or  edx, edx
;          jnz @1       ;未除尽，因此结果比实际扇区数少1 
;          dec eax      ;已经读了一个扇区，扇区总数减1 
;    @1:
;          or eax, eax ;考虑实际长度≤512个字节的情况 
;          jz setup    ;EAX=0 ?

;          ;读取剩余的扇区
;          mov ecx, eax               ;32位模式下的LOOP使用ECX
;          mov eax, core_start_sector
;          inc eax                    ;从下一个逻辑扇区接着读
;    @2:
;          call read_hard_disk_0
;          inc  eax
;          loop @2               ;循环读，直到读完整个内核 

;  setup:
;          mov esi, [0x7c00+pgdt+0x02] ;不可以在代码段内寻址pgdt，但可以
;                                             ;通过4GB的段来访问
;          ;建立公用例程段描述符
;          mov  eax,        [edi+0x04] ;公用例程代码段起始汇编地址
;          mov  ebx,        [edi+0x08] ;核心数据段汇编地址
;          sub  ebx,        eax
;          dec  ebx                    ;公用例程段界限 
;          add  eax,        edi        ;公用例程段基地址
;          mov  ecx,        0x00409800 ;字节粒度的代码段描述符
;          call make_gdt_descriptor
;          mov  [esi+0x28], eax
;          mov  [esi+0x2c], edx
       
;          ;建立核心数据段描述符
;          mov  eax,        [edi+0x08] ;核心数据段起始汇编地址
;          mov  ebx,        [edi+0x0c] ;核心代码段汇编地址 
;          sub  ebx,        eax
;          dec  ebx                    ;核心数据段界限
;          add  eax,        edi        ;核心数据段基地址
;          mov  ecx,        0x00409200 ;字节粒度的数据段描述符 
;          call make_gdt_descriptor
;          mov  [esi+0x30], eax
;          mov  [esi+0x34], edx
      
;          ;建立核心代码段描述符
;          mov  eax,        [edi+0x0c] ;核心代码段起始汇编地址
;          mov  ebx,        [edi+0x00] ;程序总长度
;          sub  ebx,        eax
;          dec  ebx                    ;核心代码段界限
;          add  eax,        edi        ;核心代码段基地址
;          mov  ecx,        0x00409800 ;字节粒度的代码段描述符
;          call make_gdt_descriptor
;          mov  [esi+0x38], eax
;          mov  [esi+0x3c], edx

;          mov word [0x7c00+pgdt], 63 ;描述符表的界限
                                        
;          lgdt [0x7c00+pgdt]

;          jmp far [edi+0x10]
       
; ;-------------------------------------------------------------------------------
; read_hard_disk_0: ;从硬盘读取一个逻辑扇区
;                                          ;EAX=逻辑扇区号
;                                          ;DS:EBX=目标缓冲区地址
;                                          ;返回：EBX=EBX+512 
;          push eax
;          push ecx
;          push edx
      
;          push eax
         
;          mov dx, 0x1f2
;          mov al, 1
;          out dx, al    ;读取的扇区数

;          inc dx     ;0x1f3
;          pop eax
;          out dx, al ;LBA地址7~0

;          inc dx      ;0x1f4
;          mov cl,  8
;          shr eax, cl
;          out dx,  al ;LBA地址15~8

;          inc dx      ;0x1f5
;          shr eax, cl
;          out dx,  al ;LBA地址23~16

;          inc dx        ;0x1f6
;          shr eax, cl
;          or  al,  0xe0 ;第一硬盘  LBA地址27~24
;          out dx,  al

;          inc dx       ;0x1f7
;          mov al, 0x20 ;读命令
;          out dx, al

;   .waits:
;          in  al, dx
;          and al, 0x88
;          cmp al, 0x08
;          jnz .waits   ;不忙，且硬盘已准备好数据传输 

;          mov ecx, 256   ;总共要读取的字数
;          mov dx,  0x1f0
;   .readw:
;          in   ax,    dx
;          mov  [ebx], ax
;          add  ebx,   2
;          loop .readw

;          pop edx
;          pop ecx
;          pop eax
      
;          ret

; ;-------------------------------------------------------------------------------
; make_gdt_descriptor: ;构造描述符
;                                          ;输入：EAX=线性基地址
;                                          ;      EBX=段界限
;                                          ;      ECX=属性（各属性位都在原始
;                                          ;      位置，其它没用到的位置0） 
;                                          ;返回：EDX:EAX=完整的描述符
;          mov edx, eax
;          shl eax, 16
;          or  ax,  bx  ;描述符前32位(EAX)构造完毕
      
;          and   edx, 0xffff0000 ;清除基地址中无关的位
;          rol   edx, 8
;          bswap edx             ;装配基址的31~24和23~16  (80486+)
      
;          xor bx,  bx
;          or  edx, ebx ;装配段界限的高4位
      
;          or edx, ecx ;装配属性 
      
;          ret
      
; ;-------------------------------------------------------------------------------
;          pgdt dw 0
; dd 0x00007e00 ;GDT的物理地址
; ;-------------------------------------------------------------------------------                             
;          times 510-($-$$) db 0
; db 0x55,0xaa