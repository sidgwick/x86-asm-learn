        ; 代码清单15-1
        ; 文件名：c15_core.asm
        ; 文件说明：保护模式微型核心程序
        ; 创建日期：2011-11-19 21:40

        ; 以下常量定义部分, 内核的大部分内容都应当固定
        core_code_seg_sel   equ 0x38 ; 0011_1_0_00, #7 GDT, 内核代码段选择子
        core_data_seg_sel   equ 0x30 ; 0011_0_0_00, #6 GDT, 内核数据段选择子
        sys_routine_seg_sel equ 0x28 ; 0010_1_0_00, #5 GDT, 系统公共例程代码段的选择子
        video_ram_seg_sel   equ 0x20 ; 0010_0_0_00, #4 GDT, 视频显示缓冲区的段选择子
        core_stack_seg_sel  equ 0x18 ; 0001_1_0_00, #3 GDT, 内核堆栈段选择子
        mem_0_4_gb_seg_sel  equ 0x08 ; 0000_1_0_00, #2 GDT, 整个 0-4GB 内存的段的选择子

; -------------------------------------------------------------------------------
        ; 以下是系统核心的头部, 用于加载核心程序
        code_length dd core_end ; 核心程序总长度 #00

        sys_routine_seg dd section.sys_routine.start ; 系统公用例程段位置 #04
        core_data_seg   dd section.core_data.start   ; 核心数据段位置 #08
        core_code_seg   dd section.core_code.start   ; 核心代码段位置 #0c

        core_entry dd start ; 核心代码段入口点 #10
                   dw core_code_seg_sel

; ===============================================================================
        [bits 32]
; ===============================================================================
SECTION sys_routine vstart=0 ; 系统公共例程代码段
; -------------------------------------------------------------------------------
; 字符串显示例程
; 显示 0 终止的字符串并移动光标
; 输入: DS:EBX=串地址
put_string:
        push ecx

    .getc:
        mov  cl, [ebx]
        or   cl, cl
        jz   .exit
        call put_char
        inc  ebx
        jmp  .getc

    .exit:
        pop ecx

        retf ; 段间返回


; -------------------------------------------------------------------------------
; 在当前光标处显示一个字符, 并推进光标. 仅用于段内调用
; 输入: CL=字符ASCII码
; 输出: 无
put_char:
        pushad

        ; 以下取当前光标位置
        mov dx, 0x3d4
        mov al, 0x0e
        out dx, al
        inc dx        ; 0x3d5
        in  al, dx    ; 高字
        mov ah, al

        dec dx       ; 0x3d4
        mov al, 0x0f
        out dx, al
        inc dx       ; 0x3d5
        in  al, dx   ; 低字
        mov bx, ax   ; BX 代表光标位置的 16 位数

        cmp cl, 0x0d    ; 回车符处理
        jnz .put_0a
        mov ax, bx
        mov bl, 80
        div bl
        mul bl
        mov bx, ax
        jmp .set_cursor

     .put_0a:
        cmp cl, 0x0a     ; 换行符处理
        jnz .put_other
        add bx, 80
        jmp .roll_screen

        ; 正常显示字符
     .put_other:
        push es
        mov  eax,     video_ram_seg_sel ; 0xb8000 段的选择子
        mov  es,      eax
        shl  bx,      1
        mov  [es:bx], cl
        pop  es

        ; 以下将光标位置推进一个字符
        shr bx, 1
        inc bx

        ; 光标超出屏幕, 滚屏
     .roll_screen:
        cmp bx, 2000
        jl  .set_cursor

        push ds
        push es
        mov  eax, video_ram_seg_sel

        mov ds,  eax
        mov es,  eax
        mov esi, 0xa0 ; 小心! 32 位模式下 movsb/w/d
        mov edi, 0x00 ; 使用的是 esi/edi/ecx
        mov ecx, 1920

        cld
        rep movsd

        ; 清除屏幕最底一行
        mov bx,  3840
        mov ecx, 80   ; 32位程序应该使用ECX
     .cls:
        mov  word[es:bx], 0x0720
        add  bx,          2
        loop .cls

        pop es
        pop ds

        mov bx, 1920

     .set_cursor:
        call set_cursor

        popad

        ret

; -------------------------------------------------------------------------------
; 设置光标地址
;   输入: BX=光标地址
set_cursor:
        push eax
        push edx

        ; 向 0x3d4 端口发送 0x0e 指令, 表示希望设置光标的低字节
        mov dx, 0x3d4
        mov al, 0x0e
        out dx, al

        ; 向 0x3d5 端口正式写入光标位置的低字节
        inc dx
        mov al, bh
        out dx, al

        ; 同理, 写入高字节
        dec dx
        mov al, 0x0f
        out dx, al

        inc dx     ; 0x3d5
        mov al, bl
        out dx, al

        pop edx
        pop eax

        ret

; -------------------------------------------------------------------------------
; 清空屏幕
clear_screen:
        push eax
        push ebx
        push ecx
        push ds

        mov ax, video_ram_seg_sel
        mov ds, ax

        mov ecx, 2000
    ._clear_screen:
        mov  word [ecx*2], 0x0720
        loop ._clear_screen

        xor  bx, bx
        call set_cursor

        pop ds
        pop ecx
        pop ebx
        pop eax

        retf


; -------------------------------------------------------------------------------
; 从硬盘读取一个逻辑扇区
; 输入: EAX=逻辑扇区号
; DS:EBX=目标缓冲区地址
; 输出: EBX=EBX+512
read_hard_disk_0:
        push eax
        push ecx
        push edx

        push eax

        mov dx, 0x1f2
        mov al, 1
        out dx, al    ; 读取的扇区数

        inc dx     ; 0x1f3
        pop eax
        out dx, al ; LBA 地址 7~0

        inc dx      ; 0x1f4
        mov cl,  8
        shr eax, cl
        out dx,  al ; LBA 地址 15~8

        inc dx      ; 0x1f5
        shr eax, cl
        out dx,  al ; LBA 地址 23~16

        inc dx        ; 0x1f6
        shr eax, cl
        or  al,  0xe0 ; 第一硬盘 + LBA 地址 27~24
        out dx,  al

        inc dx       ; 0x1f7
        mov al, 0x20 ; 读命令
        out dx, al

   .waits:
        in  al, dx
        and al, 0x88
        cmp al, 0x08
        jnz .waits   ; 不忙, 且硬盘已准备好数据传输

        mov ecx, 256   ; 总共要读取的字数
        mov dx,  0x1f0
   .readw:
        in   ax,    dx
        mov  [ebx], ax
        add  ebx,   2
        loop .readw

        pop edx
        pop ecx
        pop eax

        retf ; 段间返回

; -------------------------------------------------------------------------------
; 汇编语言程序是极难一次成功，而且调试非常困难。这个例程可以提供帮助
; 在当前光标处以十六进制形式显示一个双字并推进光标
; 输入：EDX=要转换并显示的数字
; 输出：无
put_hex_dword:
        pushad
        push ds

        mov ax, core_data_seg_sel ; 切换到核心数据段
        mov ds, ax

        mov ebx, bin_hex ; 指向核心数据段内的转换表
        mov ecx, 8
   .xlt:
        rol edx, 4
        mov eax, edx
        and eax, 0x0000000f
        xlat

        push ecx
        mov  cl, al
        call put_char
        pop  ecx

        loop .xlt

        pop ds
        popad
        retf

; -------------------------------------------------------------------------------
; 分配内存
; 输入：ECX=希望分配的字节数
; 输出：ECX=起始线性地址
allocate_memory:
        push ds
        push eax
        push ebx

        mov eax, core_data_seg_sel
        mov ds,  eax

        mov eax, [ram_alloc]
        add eax, ecx         ; 下一次分配时的起始地址

        ; 这里应当有检测可用内存数量的指令

        mov ecx, [ram_alloc] ; 返回分配的起始地址

        mov    ebx,         eax
        and    ebx,         0xfffffffc
        add    ebx,         4          ; 强制对齐, 下次分配的起始地址最好是4字节对齐
        test   eax,         0x00000003 ; 如果没有对齐，则强制对齐, 下次从该地址分配内存
        cmovnz eax,         ebx        ; cmovcc指令可以避免控制转移
        mov    [ram_alloc], eax
        pop    ebx
        pop    eax
        pop    ds

        retf

; -------------------------------------------------------------------------------
; 在GDT内安装一个新的描述符
; 输入：EDX:EAX=描述符
; 输出：CX=描述符的选择子
set_up_gdt_descriptor:
        push eax
        push ebx
        push edx

        push ds
        push es

        mov ebx, core_data_seg_sel ; 切换到核心数据段
        mov ds,  ebx

        sgdt [pgdt] ; 以便开始处理 GDT

        mov ebx, mem_0_4_gb_seg_sel
        mov es,  ebx

        movzx ebx, word [pgdt] ; GDT 界限
        inc   bx               ; GDT 总字节数，也是下一个描述符偏移
        add   ebx, [pgdt+2]    ; 下一个描述符的线性地址

        mov [es:ebx],   eax
        mov [es:ebx+4], edx

        add word [pgdt], 8 ; 增加一个描述符的大小

        lgdt [pgdt] ; 对 GDT 的更改生效

        ; 因为选择子指定的是描述符的位置, 每个描述符 8 个字节, 因此低三位刚好可以不要
        ; 如果需要构造 LDT, 非 0 RPL 的选择子, 则只需要在 or 一次就可以了
        mov cx, [pgdt] ; 得到 GDT 界限值
        and cx, 0xF8   ; 构造 XXXX_X000 这样的描述符选择子

        pop es
        pop ds

        pop edx
        pop ebx
        pop eax

        retf

; -------------------------------------------------------------------------------
; 构造存储器和系统的段描述符
; 输入：EAX=线性基地址
;      EBX=段界限
;      ECX=属性。各属性位都在原始位置，无关的位清零
; 返回：EDX:EAX=描述符
make_seg_descriptor:
        mov edx, eax
        shl eax, 16
        or  ax,  bx  ; 描述符前32位(EAX)构造完毕

        and   edx, 0xffff0000 ; 清除基地址中无关的位
        rol   edx, 8
        bswap edx             ; 装配基址的31~24和23~16  (80486+)

        xor bx,  bx
        or  edx, ebx ; 装配段界限的高4位

        or edx, ecx ; 装配属性

        retf

; -------------------------------------------------------------------------------
; 构造门的描述符（调用门等）
;     输入：EAX=门代码在段内偏移地址
;          BX=门代码所在段的选择子
;          CX=段类型及属性等（各属性位都在原始位置）
;     返回：EDX:EAX=完整的描述符
;
; 各种描述符(左高右低, 上高下低):
; 段描述符
;    BBXL_YZBB, X = g_db_l_val, Y=p_dpl_s, Z=type(XCRA, XEWA)
;    BBBB_LLLL
; TSS 描述符
;    BBXL_YZBB, X = g_0_0_val, Y=p_dpl_0, Z=type(10_B_1)
;    BBBB_LLLL
; 调用门:
;    OOOO_ABCD, A=p_dpl_0, B=1100, CD=000_(ARGS_NUM)
;    SSSS_OOOO
; 任务门:
;    XXXX_ABXX, AB=p_dpl_00101
;    SSSS_XXXX
make_gate_descriptor:
        push ebx
        push ecx

        mov edx, eax
        and edx, 0xffff0000 ; 得到偏移地址高16位
        or  dx,  cx         ; 组装属性部分到EDX

        and eax, 0x0000ffff ; 得到偏移地址低16位
        shl ebx, 16
        or  eax, ebx        ; 组装段选择子部分

        pop ecx
        pop ebx

        retf

; -------------------------------------------------------------------------------
; 终止当前任务
; 注意，执行此例程时，当前任务仍在运行中。此例程其实也是当前任务的一部分
terminate_current_task:
        pushfd
        mov edx, [esp] ; 获得EFLAGS寄存器内容
        add esp, 4     ; 恢复堆栈指针

        mov eax, core_data_seg_sel
        mov ds,  eax

        ; 这里能从用户程序(3级别)跳转到进程管理器(0级别)的的原因是, 用户程序已经通过调用门调起了此处的
        ; 内核代码(也就是 terminate_current_task), 因此在这一行 CPL=0, 自然也允许跳转
        ; ---------------------------------------------------------------------------------
        test dx,  0100_0000_0000_0000B      ; 测试NT位. NT 置位 `dx & OP ! = 0`, 也就是嵌套了
        jnz  .b1                            ; 当前任务是嵌套的，到.b1执行iretd
        mov  ebx, core_msg1                 ; 当前任务不是嵌套的，直接切换到程序管理器任务
        call sys_routine_seg_sel:put_string
        jmp  far [prgman_tss]

   .b1:
        mov  ebx, core_msg0
        call sys_routine_seg_sel:put_string
        ; IRET 执行返回后
        iretd

sys_routine_end:

; ===============================================================================
SECTION core_data vstart=0 ; 系统核心的数据段
; -------------------------------------------------------------------------------
        pgdt dw 0 ; 用于设置和修改GDT
             dd 0

        ram_alloc dd 0x00100000 ; 下次分配内存时的起始地址

        ; 符号地址检索表
        salt:
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
                                    dd terminate_current_task
                                    dw sys_routine_seg_sel

        salt_item_len equ $-salt_4
        salt_items    equ ($-salt)/salt_item_len

        message_1 db '  If you seen this message,that means we '
                  db 'are now in protect mode,and the system '
                  db 'core is loaded,and the video display '
                  db 'routine works perfectly.',0x0d,0x0a,0

        message_2 db '  System wide CALL-GATE mounted.',0x0d,0x0a,0

        bin_hex db '0123456789ABCDEF' ; put_hex_dword子过程用的查找表

        core_buf times 2048 db 0 ; 内核用的缓冲区

        cpu_brnd0 db 0x0d,0x0a,'  ',0
        cpu_brand times 52 db 0
        cpu_brnd1 db 0x0d,0x0a,0x0d,0x0a,0

        ; 任务控制块链
        tcb_chain dd 0

        ; 程序管理器的任务信息
        prgman_tss dd 0 ; 程序管理器的 TSS 基地址
                   dw 0 ; 程序管理器的 TSS 描述符选择子

        prgman_msg1 db 0x0d,0x0a
                    db '[PROGRAM MANAGER]: Hello! I am Program Manager,'
                    db 'run at CPL=0.Now,create user task and switch '
                    db 'to it by the CALL instruction...',0x0d,0x0a,0

        prgman_msg2 db 0x0d,0x0a
                    db '[PROGRAM MANAGER]: I am glad to regain control.'
                    db 'Now,create another user task and switch to '
                    db 'it by the JMP instruction...',0x0d,0x0a,0

        prgman_msg3 db 0x0d,0x0a
                    db '[PROGRAM MANAGER]: I am gain control again,'
                    db 'HALT...',0

        core_msg0 db 0x0d,0x0a
                  db '[SYSTEM CORE]: Uh...This task initiated with '
                  db 'CALL instruction or an exeception/ interrupt,'
                  db 'should use IRETD instruction to switch back...'
                  db 0x0d,0x0a,0

        core_msg1 db 0x0d,0x0a
                  db '[SYSTEM CORE]: Uh...This task initiated with '
                  db 'JMP instruction,  should switch to Program '
                  db 'Manager directly by the JMP instruction...'
                  db 0x0d,0x0a,0

core_data_end:

; ===============================================================================
SECTION core_code vstart=0
; -------------------------------------------------------------------------------
; 在LDT内安装一个新的描述符
; 输入：EDX:EAX=描述符
;      EBX=TCB基地址
; 输出：CX=描述符的选择子
fill_descriptor_in_ldt:
        push eax
        push edx
        push edi
        push ds

        mov ecx, mem_0_4_gb_seg_sel
        mov ds,  ecx

        mov edi, [ebx+0x0c] ; 获得LDT基地址

        xor ecx, ecx
        mov cx,  [ebx+0x0a] ; 获得LDT界限
        inc cx              ; LDT的总字节数，即新描述符偏移地址

        mov [edi+ecx+0x00], eax
        mov [edi+ecx+0x04], edx ; 安装描述符

        add cx, 8
        dec cx    ; 得到新的LDT界限值

        mov [ebx+0x0a], cx ; 更新LDT界限值到TCB

        mov ax, cx
        xor dx, dx
        mov cx, 8
        div cx

        mov cx, ax
        shl cx, 3                    ; 左移3位，并且
        or  cx, 0000_0000_0000_0100B ; 使TI位=1，指向LDT，最后使RPL=00

        pop ds
        pop edi
        pop edx
        pop eax

        ret

; -------------------------------------------------------------------------------
; 加载并重定位用户程序
; 输入:  PUSH 逻辑扇区号
;       PUSH 任务控制块基地址
; 输出：无
load_relocate_program:
        pushad
        ; push eax, ecx, edx, ebx, esp, ebp, esi, edi

        push ds
        push es

        mov ebp, esp ; 为访问通过堆栈传递的参数做准备

        mov ecx, mem_0_4_gb_seg_sel
        mov es,  ecx

        ; 从堆栈中取得TCB的基地址
        ; 之所以在 11 位置, 是因为还有下面这些数据也在栈里面
        ;     1. 在 call load_relocate_program 处理器还会给栈里面压 EIP
        ;     2. 程序入口 pushad 呀如何 EAX, ECX, EDX, EBX, ESP, EBP, ESI, EDI
        ;     3. 程序入口压入了 DS, ES
        mov esi, [ebp+11*4]

        ; 以下申请创建 LDT 所需要的内存
        ; 这地方界限写 0xFFFF 是表示 LDT 现在还是空的的意思
        ; 后续给 LDT 里面追加内容的时候, 界限值会随着调整
        mov  ecx,                160             ; 允许安装 20 个 LDT 描述符
        call sys_routine_seg_sel:allocate_memory
        mov  [es:esi+0x0c],      ecx             ; 登记 LDT 基地址到 TCB 中
        mov  word [es:esi+0x0a], 0xffff          ; 登记 LDT 初始的界限到 TCB 中

        ; 以下开始加载用户程序
        mov eax, core_data_seg_sel
        mov ds,  eax               ; 切换DS到内核数据段

        mov  eax, [ebp+12*4]                      ; 从堆栈中取出用户程序起始扇区号
        mov  ebx, core_buf                        ; 读取程序头部数据
        call sys_routine_seg_sel:read_hard_disk_0

        ; 以下判断整个程序有多大
        mov    eax, [core_buf] ; 程序尺寸
        mov    ebx, eax
        and    ebx, 0xfffffe00 ; 使之512字节对齐（能被512整除的数低
        add    ebx, 512        ; 9位都为0
        test   eax, 0x000001ff ; 程序的大小正好是512的倍数吗?
        cmovnz eax, ebx        ; 不是。使用凑整的结果

        mov  ecx,           eax                  ; 实际需要申请的内存数量
        call sys_routine_seg_sel:allocate_memory
        mov  [es:esi+0x06], ecx                  ; 登记程序加载基地址到 TCB 中

        mov ebx, ecx ; ebx -> 申请到的内存首地址
        xor edx, edx
        mov ecx, 512
        div ecx
        mov ecx, eax ; 总扇区数

        mov eax, mem_0_4_gb_seg_sel ; 切换DS到0-4GB的段
        mov ds,  eax

        mov eax, [ebp+12*4] ; 起始扇区号
   .b1:
        call sys_routine_seg_sel:read_hard_disk_0
        inc  eax
        loop .b1                                  ; 循环读，直到读完整个用户程序

        mov edi, [es:esi+0x06] ; 获得程序加载基地址

        ; 建立程序头部段描述符
        mov  eax, edi                                ; 程序头部起始线性地址
        mov  ebx, [edi+0x04]                         ; 段长度
        dec  ebx                                     ; 段界限
        mov  ecx, 0x0040f200                         ; 字节粒度的数据段描述符，特权级3, g_db_l_avl=0100, p_dpl_s=1111, type=0010
        call sys_routine_seg_sel:make_seg_descriptor

        ; 安装头部段描述符到 LDT 中
        mov  ebx, esi               ; TCB 的基地址
        call fill_descriptor_in_ldt

        or  cx,            0000_0000_0000_0011B ; 设置选择子的特权级为 3
        mov [es:esi+0x44], cx                   ; 登记程序头部段选择子到 TCB
        mov [edi+0x04],    cx                   ; 和头部内

        ; 建立程序代码段描述符
        mov  eax,        edi
        add  eax,        [edi+0x14]                  ; 代码起始线性地址
        mov  ebx,        [edi+0x18]                  ; 段长度
        dec  ebx                                     ; 段界限
        mov  ecx,        0x0040f800                  ; 字节粒度的代码段描述符，特权级3
        call sys_routine_seg_sel:make_seg_descriptor
        mov  ebx,        esi                         ; TCB的基地址
        call fill_descriptor_in_ldt
        or   cx,         0000_0000_0000_0011B        ; 设置选择子的特权级为3
        mov  [edi+0x14], cx                          ; 登记代码段选择子到头部

        ; 建立程序数据段描述符
        mov  eax,        edi
        add  eax,        [edi+0x1c]                  ; 数据段起始线性地址
        mov  ebx,        [edi+0x20]                  ; 段长度
        dec  ebx                                     ; 段界限
        mov  ecx,        0x0040f200                  ; 字节粒度的数据段描述符，特权级3
        call sys_routine_seg_sel:make_seg_descriptor
        mov  ebx,        esi                         ; TCB的基地址
        call fill_descriptor_in_ldt
        or   cx,         0000_0000_0000_0011B        ; 设置选择子的特权级为3
        mov  [edi+0x1c], cx                          ; 登记数据段选择子到头部

        ; 建立程序堆栈段描述符
        mov  ecx,        [edi+0x0c]                  ; 4KB的倍率
        mov  ebx,        0x000fffff
        sub  ebx,        ecx                         ; 得到段界限
        mov  eax,        4096
        mul  ecx
        mov  ecx,        eax                         ; 准备为堆栈分配内存
        call sys_routine_seg_sel:allocate_memory
        add  eax,        ecx                         ; 得到堆栈的高端物理地址
        mov  ecx,        0x00c0f600                  ; 字节粒度的堆栈段描述符，特权级3
        call sys_routine_seg_sel:make_seg_descriptor
        mov  ebx,        esi                         ; TCB的基地址
        call fill_descriptor_in_ldt
        or   cx,         0000_0000_0000_0011B        ; 设置选择子的特权级为3
        mov  [edi+0x08], cx                          ; 登记堆栈段选择子到头部

        ; 重定位SALT
        mov eax, mem_0_4_gb_seg_sel ; 这里和前一章不同，头部段描述符
        mov es,  eax                ; 已安装，但还没有生效，故只能通
                                           ; 过4GB段访问用户程序头部
        mov eax, core_data_seg_sel
        mov ds,  eax

        cld

        mov ecx, [es:edi+0x24] ; U-SALT条目数(通过访问4GB段取得)
        add edi, 0x28          ; U-SALT在4GB段内的偏移
   .b2:
        push ecx
        push edi

        mov ecx, salt_items
        mov esi, salt
   .b3:
        push edi
        push esi
        push ecx

        mov        ecx,          64                ; 检索表中，每条目的比较次数
        repe cmpsd                                 ; 每次比较4字节
        jnz        .b4
        mov        eax,          [esi]             ; 若匹配, 则 esi 恰好指向其后的地址
        mov        [es:edi-256], eax               ; 将字符串改写成偏移地址
        mov        ax,           [esi+4]
        or         ax,           0000000000000011B ; 以用户程序自己的特权级使用调用门, 故RPL=3
        mov        [es:edi-252], ax                ; 回填调用门选择子
   .b4:

        pop  ecx
        pop  esi
        add  esi, salt_item_len
        pop  edi                ; 从头比较
        loop .b3

        pop  edi
        add  edi, 256
        pop  ecx
        loop .b2

        mov esi, [ebp+11*4] ; 从堆栈中取得 TCB 的基地址

        ; 创建0特权级堆栈
        mov  ecx,                 4096
        mov  eax,                 ecx                ; 为生成堆栈高端地址做准备
        mov  [es:esi+0x1a],       ecx
        shr  dword [es:esi+0x1a], 12                 ; 登记0特权级堆栈尺寸到TCB
        call sys_routine_seg_sel:allocate_memory
        add  eax,                 ecx                ; 堆栈必须使用高端地址为基地址
        mov  [es:esi+0x1e],       eax                ; 登记0特权级堆栈基地址到TCB
        mov  ebx,                 0xffffe            ; 段长度（界限）
        mov  ecx,                 0x00c09600         ; 4KB粒度，读写，特权级0
        call sys_routine_seg_sel:make_seg_descriptor
        mov  ebx,                 esi                ; TCB的基地址
        call fill_descriptor_in_ldt
        ; or cx,0000_0000_0000_0000          ; 设置选择子的特权级为0
        mov  [es:esi+0x22],       cx                 ; 登记0特权级堆栈选择子到TCB
        mov  dword [es:esi+0x24], 0                  ; 登记0特权级堆栈初始ESP到TCB

        ; 创建1特权级堆栈
        mov  ecx,                 4096
        mov  eax,                 ecx                 ; 为生成堆栈高端地址做准备
        mov  [es:esi+0x28],       ecx
        shr  dword [es:esi+0x28], 12                  ; 登记1特权级堆栈尺寸到TCB
        call sys_routine_seg_sel:allocate_memory
        add  eax,                 ecx                 ; 堆栈必须使用高端地址为基地址
        mov  [es:esi+0x2c],       eax                 ; 登记1特权级堆栈基地址到TCB
        mov  ebx,                 0xffffe             ; 段长度（界限）
        mov  ecx,                 0x00c0b600          ; 4KB粒度，读写，特权级1
        call sys_routine_seg_sel:make_seg_descriptor
        mov  ebx,                 esi                 ; TCB的基地址
        call fill_descriptor_in_ldt
        or   cx,                  0000_0000_0000_0001 ; 设置选择子的特权级为1
        mov  [es:esi+0x30],       cx                  ; 登记1特权级堆栈选择子到TCB
        mov  dword [es:esi+0x32], 0                   ; 登记1特权级堆栈初始ESP到TCB

        ; 创建2特权级堆栈
        mov  ecx,                 4096
        mov  eax,                 ecx                 ; 为生成堆栈高端地址做准备
        mov  [es:esi+0x36],       ecx
        shr  dword [es:esi+0x36], 12                  ; 登记2特权级堆栈尺寸到TCB
        call sys_routine_seg_sel:allocate_memory
        add  eax,                 ecx                 ; 堆栈必须使用高端地址为基地址
        mov  [es:esi+0x3a],       ecx                 ; 登记2特权级堆栈基地址到TCB
        mov  ebx,                 0xffffe             ; 段长度（界限）
        mov  ecx,                 0x00c0d600          ; 4KB粒度，读写，特权级2
        call sys_routine_seg_sel:make_seg_descriptor
        mov  ebx,                 esi                 ; TCB的基地址
        call fill_descriptor_in_ldt
        or   cx,                  0000_0000_0000_0010 ; 设置选择子的特权级为2
        mov  [es:esi+0x3e],       cx                  ; 登记2特权级堆栈选择子到TCB
        mov  dword [es:esi+0x40], 0                   ; 登记2特权级堆栈初始ESP到TCB

        ; 在 GDT 中登记 LDT 描述符
        mov   eax,           [es:esi+0x0c]              ; LDT 的起始线性地址
        movzx ebx,           word [es:esi+0x0a]         ; LDT 段界限
        mov   ecx,           0x00408200                 ; LDT 描述符, 特权级 0, p_dpl_s=1000
        call  sys_routine_seg_sel:make_seg_descriptor
        call  sys_routine_seg_sel:set_up_gdt_descriptor
        mov   [es:esi+0x10], cx                         ; 登记LDT选择子到TCB中

        ; 创建用户程序的TSS
        mov  ecx,           104                  ; TSS 的基本尺寸
        mov  [es:esi+0x12], cx
        dec  word [es:esi+0x12]                  ; 登记 TSS 界限值到 TCB
        call sys_routine_seg_sel:allocate_memory
        mov  [es:esi+0x14], ecx                  ; 登记 TSS 基地址到 TCB

        ; 登记基本的TSS表格内容
        mov word [es:ecx+0], 0 ; 反向链=0

        mov edx,        [es:esi+0x24] ; 登记0特权级堆栈初始ESP
        mov [es:ecx+4], edx           ; 到TSS中

        mov dx,         [es:esi+0x22] ; 登记0特权级堆栈段选择子
        mov [es:ecx+8], dx            ; 到TSS中

        mov edx,         [es:esi+0x32] ; 登记1特权级堆栈初始ESP
        mov [es:ecx+12], edx           ; 到TSS中

        mov dx,          [es:esi+0x30] ; 登记1特权级堆栈段选择子
        mov [es:ecx+16], dx            ; 到TSS中

        mov edx,         [es:esi+0x40] ; 登记2特权级堆栈初始ESP
        mov [es:ecx+20], edx           ; 到TSS中

        mov dx,          [es:esi+0x3e] ; 登记2特权级堆栈段选择子
        mov [es:ecx+24], dx            ; 到TSS中

        mov dx,          [es:esi+0x10] ; 登记任务的LDT选择子
        mov [es:ecx+96], dx            ; 到TSS中

        mov dx,           [es:esi+0x12] ; 登记任务的 I/O 位图偏移
        mov [es:ecx+102], dx            ; 到 TSS 中

        mov word [es:ecx+100], 0 ; T=0

        mov dword [es:ecx+28], 0 ; 登记CR3(PDBR)

        ; 访问用户程序头部，获取数据填充TSS
        mov ebx, [ebp+11*4]    ; 从堆栈中取得TCB的基地址
        mov edi, [es:ebx+0x06] ; 用户程序加载的基地址

        mov edx,         [es:edi+0x10] ; 登记程序入口点（EIP）
        mov [es:ecx+32], edx           ; 到TSS

        mov dx,          [es:edi+0x14] ; 登记程序代码段（CS）选择子
        mov [es:ecx+76], dx            ; 到TSS中

        mov dx,          [es:edi+0x08] ; 登记程序堆栈段（SS）选择子
        mov [es:ecx+80], dx            ; 到TSS中

        mov dx,               [es:edi+0x04] ; 登记程序数据段（DS）选择子
        mov word [es:ecx+84], dx            ; 到TSS中。注意，它指向程序头部段

        mov word [es:ecx+72], 0 ; TSS中的ES=0

        mov word [es:ecx+88], 0 ; TSS中的FS=0

        mov word [es:ecx+92], 0 ; TSS中的GS=0

        pushfd
        pop edx

        mov dword [es:ecx+36], edx ; EFLAGS

        ; 在GDT中登记TSS描述符
        mov   eax,           [es:esi+0x14]              ; TSS的起始线性地址
        movzx ebx,           word [es:esi+0x12]         ; 段长度（界限）
        mov   ecx,           0x00408900                 ; TSS描述符，特权级0
        call  sys_routine_seg_sel:make_seg_descriptor
        call  sys_routine_seg_sel:set_up_gdt_descriptor
        mov   [es:esi+0x18], cx                         ; 登记TSS选择子到TCB

        pop es ; 恢复到调用此过程前的es段
        pop ds ; 恢复到调用此过程前的ds段

        popad

        ret 8 ; 丢弃调用本过程前压入的参数 -- stdcall 调用约定, C 语言不是这样的

; -------------------------------------------------------------------------------
append_to_tcb_link: ; 在TCB链上追加任务控制块
                                           ; 输入：ECX=TCB线性基地址
        push eax
        push edx
        push ds
        push es

        mov eax, core_data_seg_sel  ; 令DS指向内核数据段
        mov ds,  eax
        mov eax, mem_0_4_gb_seg_sel ; 令ES指向0..4GB段
        mov es,  eax

        mov dword [es: ecx+0x00], 0 ; 当前TCB指针域清零，以指示这是最
                                           ; 后一个TCB

        mov eax, [tcb_chain] ; TCB表头指针
        or  eax, eax         ; 链表为空？
        jz  .notcb

   .searc:
        mov edx, eax
        mov eax, [es: edx+0x00]
        or  eax, eax
        jnz .searc

        mov [es: edx+0x00], ecx
        jmp .retpc

   .notcb:
        mov [tcb_chain], ecx ; 若为空表，直接令表头指针指向TCB

   .retpc:
        pop es
        pop ds
        pop edx
        pop eax

        ret

; -------------------------------------------------------------------------------
start:
        mov ecx, core_data_seg_sel ; 令DS指向核心数据段
        mov ds,  ecx

        mov ecx, mem_0_4_gb_seg_sel ; 令ES指向4GB数据段
        mov es,  ecx

        call sys_routine_seg_sel:clear_screen

        mov  ebx, message_1
        call sys_routine_seg_sel:put_string

        ; 显示处理器品牌信息
        mov eax,                0x80000002
        cpuid
        mov [cpu_brand + 0x00], eax
        mov [cpu_brand + 0x04], ebx
        mov [cpu_brand + 0x08], ecx
        mov [cpu_brand + 0x0c], edx

        mov eax,                0x80000003
        cpuid
        mov [cpu_brand + 0x10], eax
        mov [cpu_brand + 0x14], ebx
        mov [cpu_brand + 0x18], ecx
        mov [cpu_brand + 0x1c], edx

        mov eax,                0x80000004
        cpuid
        mov [cpu_brand + 0x20], eax
        mov [cpu_brand + 0x24], ebx
        mov [cpu_brand + 0x28], ecx
        mov [cpu_brand + 0x2c], edx

        mov  ebx, cpu_brnd0                 ; 显示处理器品牌信息
        call sys_routine_seg_sel:put_string
        mov  ebx, cpu_brand
        call sys_routine_seg_sel:put_string
        mov  ebx, cpu_brnd1
        call sys_routine_seg_sel:put_string

        ; 以下开始安装为整个系统服务的调用门。特权级之间的控制转移必须使用门
        ; 单层循环处理 salt 条目

        mov edi, salt       ; C-SALT 表的起始位置
        mov ecx, salt_items ; C-SALT 表的条目数量
   .b3:
        push ecx


        mov  eax,       [edi+256]                      ; 该条目入口点的32位偏移地址
        mov  bx,        [edi+260]                      ; 该条目入口点的段选择子
        mov  cx,        1_11_0_1100_000_00000B         ; P=1, DPL=3, 调用门(1100), ARGS_NUM=0
        call sys_routine_seg_sel:make_gate_descriptor  ; 创建门描述符
        call sys_routine_seg_sel:set_up_gdt_descriptor
        mov  [edi+260], cx                             ; 将返回的门描述符选择子回填
        add  edi,       salt_item_len                  ; 指向下一个C-SALT条目
        pop  ecx
        loop .b3

        ; 对门进行测试
        mov  ebx, message_2
        call far [salt_1+256] ; 通过门显示信息(偏移量将被忽略)

        ; 为程序管理器的 TSS 分配内存空间
        mov  ecx,               104              ; 为该任务的 TSS 分配内存
        call sys_routine_seg_sel:allocate_memory
        mov  [prgman_tss+0x00], ecx              ; 保存程序管理器的 TSS 基地址

        ; 在程序管理器的 TSS 中设置必要的项目
        ; TSS 结构:
        ;        typedef struct {
        ;  000 ..... int32_t previous_tss : 16; // 前一个任务的指针
        ;  
        ;  004 ..... int32_t esp0; // ESP0 - 0 特权级栈指针
        ;  008 ..... int32_t ss0; // SS0 - 0 特权级栈底(高 16 位未用)
        ;  012 ..... int32_t esp1; // ESP1 - 1 特权级栈指针
        ;  016 ..... int32_t ss1; // SS1 - 1 特权级栈底(高 16 位未用)
        ;  020 ..... int32_t esp2; // ESP2 - 2 特权级栈指针
        ;  024 ..... int32_t ss2; // SS2 - 2 特权级栈底(高 16 位未用)
        ;  028 ..... int32_t cr3; // CR3(PDBR)
        ;  032 ..... int32_t eip; // EIP
        ;  036 ..... int32_t eflags; // EFLAGS
        ;
        ;            // 注意下面一直到 EDI, 刚好就是 pushad 的压栈顺序
        ;  040 ..... int32_t eax; // EAX
        ;  044 ..... int32_t ecx; // ECX
        ;  048 ..... int32_t edx; // EDX
        ;  052 ..... int32_t ebx; // EBX
        ;  056 ..... int32_t esp; // ESP
        ;  060 ..... int32_t ebp; // EBP
        ;  064 ..... int32_t esi; // ESI
        ;  068 ..... int32_t edi; // EDI
        ;
        ;  072 ..... int32_t es; // ES(高 16 位未用)
        ;  076 ..... int32_t cs; // CS(高 16 位未用)
        ;  080 ..... int32_t ss; // SS(高 16 位未用)
        ;  084 ..... int32_t ds; // DS(高 16 位未用)
        ;  088 ..... int32_t fs; // FS(高 16 位未用)
        ;  092 ..... int32_t gs; // GS(高 16 位未用)
        ;  096 ..... int32_t ldt; // LDT(高 16 位未用)
        ;  100 ..... int32_t trace_bitmap; // Trace-Testing 标记(bit 0) 和 IO 映射基址(bit 16-31)
        ;        } tss_t;

        mov word [es:ecx+96],  0   ; 没有LDT, 处理器允许没有 LDT 的任务
        mov word [es:ecx+102], 103 ; 没有 I/O 位图, 0 特权级事实上不需要
        mov word [es:ecx+0],   0   ; 反向链=0
        mov dword [es:ecx+28], 0   ; 登记 CR3, PDBR - Page Directory Base Register
        mov word [es:ecx+100], 0   ; T=0
        
        ; 不需要 0/1/2 特权级堆栈, 0 特级不会向低特权级转移控制
        ; 因此这里没有设置堆栈相关的内容

        ; 创建 TSS 描述符, 并安装到 GDT 中
        ; S=0, TYPE=1001 表示这是一个 32 位的 TSS 描述符
        mov  eax,               ecx                    ; TSS 的起始线性地址
        mov  ebx,               103                    ; 段长度(界限)
        mov  ecx,               0x00408900             ; TSS 描述符, 特权级 0, g_db_l_val=0100, p_dpl_s=1000, type=1001
        call sys_routine_seg_sel:make_seg_descriptor
        call sys_routine_seg_sel:set_up_gdt_descriptor
        mov  [prgman_tss+0x04], cx                     ; 保存程序管理器的 TSS 描述符选择子

        ; 任务寄存器 TR 中的内容是任务存在的标志, 该内容也决定了当前任务是谁
        ; 下面的指令为当前正在执行的 0 特权级任务 "程序管理器" 后补手续(TSS)
        ltr cx

        ; 现在可认为 "程序管理器" 任务正执行中
        mov  ebx, prgman_msg1
        call sys_routine_seg_sel:put_string

        ; 自定义 TCB 的结构如下:
        ;         typedef struct _tcb_t {
        ;  0x00 .....    struct _tcb_t *next; // 4 字节指向下一个 TCB 的指针
        ;
        ;  0x04 .....    int16_t state; // 当前程序状态
        ;  0x06 .....    int32_t load_addr; // 程序加载地址
        ;  0x0A .....    int16_t ldt_limit; // LDT 当前界限值
        ;  0x0C .....    int32_t ldt_base; // LDT 基地址
        ;  0x10 .....    int16_t ldt_sel; // LDT 选择子
        ;  0x12 .....    int16_t tss_limit; // TSS 当前界限值
        ;  0x14 .....    int32_t tss_base; // TSS 基地址
        ;  0x18 .....    int16_t tss_sel; // TSS 选择子
        ;
        ;  0x1A .....    int32_t stack_size_0; // 0 特权级栈以 4KB 为单位的长度
        ;  0x1E .....    int32_t stack_base_0; // 0 特权级栈基地址
        ;  0x22 .....    int16_t stack_sel_0; // 0 特权级栈选择子
        ;  0x24 .....    int32_t stack_pointer_0; // 0 特权级栈的初始 ESP
        ;
        ;  0x28 .....    int32_t stack_size_1; // 1 特权级栈以 4KB 为单位的长度
        ;  0x2C .....    int32_t stack_base_1; // 1 特权级栈基地址
        ;  0x30 .....    int16_t stack_sel_1; // 1 特权级栈选择子
        ;  0x32 .....    int32_t stack_pointer_1; // 1 特权级栈的初始 ESP
        ;
        ;  0x36 .....    int32_t stack_size_2; // 2 特权级栈以 4KB 为单位的长度
        ;  0x3A .....    int32_t stack_base_2; // 2 特权级栈基地址
        ;  0x3E .....    int16_t stack_sel_2; // 2 特权级栈选择子
        ;  0x42 .....    int32_t stack_pointer_2; // 2 特权级栈的初始 ESP
        ;
        ;  0x46 .....    int16_t header_sel; // 头部选择子
        ;            } tcb_t;

        ; 申请 0x46=70 字节的内存, 作为用户程序的 TCB
        mov  ecx, 0x46
        call sys_routine_seg_sel:allocate_memory
        call append_to_tcb_link                  ; 将此 TCB 添加到 TCB 链中

        push dword 50 ; 用户程序位于逻辑 50 扇区
        push ecx      ; 压入任务控制块起始线性地址

        call load_relocate_program

        ; 和上一章不同，任务切换时要恢复 TSS 内容, 所以在创建任务时 TSS 要填写完整
        ; call 指令会导致老任务切出(NT 位置位, B 位清除)
        call far [es:ecx+0x14] ; 执行任务切换 - 通过任务门执行切换

        ; 重新加载并切换任务
        mov  ebx, prgman_msg2
        call sys_routine_seg_sel:put_string

        mov  ecx, 0x46
        call sys_routine_seg_sel:allocate_memory
        call append_to_tcb_link                  ; 将此 TCB 添加到 TCB 链中

        push dword 50 ; 用户程序位于逻辑 50 扇区
        push ecx      ; 压入任务控制块起始线性地址

        call load_relocate_program

        ; JMP + 任务门会导致老任务切出(NT 位保持不变, B 位清除)
        jmp far [es:ecx+0x14] ; 执行任务切换 - 这次使用 JMP + 任务门的形式

        mov  ebx, prgman_msg3
        call sys_routine_seg_sel:put_string

        hlt

core_code_end:

; -------------------------------------------------------------------------------
SECTION core_trail
; -------------------------------------------------------------------------------
core_end:
