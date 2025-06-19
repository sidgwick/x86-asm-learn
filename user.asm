; 第8章 - 用户程序

; ===============================================================================
; 头部段, 定义了程序的长度, 程序的入口, 以及各个段的定位信息
SECTION header align=16 vstart=0

program_leght:
    dd program_end ; [0x00] - 程序长度

code_entry:
    dw start              ; [0x04] - 入口点偏移地址
    dd section.code.start ; [0x06] - 入口点所在的段地址

realloc_tbl_len:
    dw (header_end - code_segment) / 4 ; [0x0a] - 段重定位表项个数

; [0x0a] - 段重定位表
code_segment:
    dd section.code.start ;
data_segment:
    dd section.data.start ;
stack_segment:
    dd section.stack.start ;

header_end:

; ===============================================================================
; 代码段 1
SECTION code align=16 vstart=0

new_int_0x70:
    push ax
    push bx
    push cx
    push dx
    push es

    ; 关于 CMOS RAM
    ; 端口 0x70, 0x74 是 CMOS 的索引端口可用于指定 CMOS 的内存单元
    ; 端口 0x71, 0x75 是 CMOS 的数据端口, 可以用来读写对应内存单元里面的内容
    ;
    ; 特别注意, 端口 0x70 的最高位是控制 NMI 的开关, 剩下的 7 位才是内存单元索引
    ;
    ; 内存单元 0x0A ~ 0x0D 不是普通内存单元, 他们是 4 个寄存器, 可以通过 0x70 和 0x71 来对他们进行读写操作
    ; 这四个寄存器控制了实时时钟电路的参数和工作状态


    ; 下面的操作都是先通过 0x70 设置目标, 在通过 0x71 读取数据

.w0:
    mov al,   0x0a ; 0x0A 是 A 寄存器
    or  al,   0x80 ; 阻断 NMI
    out 0x70, al

    ; 获取 RCT 寄存器 A 的状态, 并检测 UIP 位, 如果置位则 RCT 状态不稳定, 需要一直等到稳定再读取
    in   al, 0x71
    test al, 0x80
    jnz  .w0

    ; 读RTC当前时间(秒)
    xor  al,   al   ; 0 号 CMOS RAM 单元 - 秒
    or   al,   0x80 ; NMI
    out  0x70, al
    in   al,   0x71 ; 读取
    push ax

    ; 读RTC当前时间(分)
    mov  al,   0x02 ; 2 号 CMOS RAM 单元 - 分
    or   al,   0x80 ; NMI
    out  0x70, al
    in   al,   0x71
    push ax

    ; 读RTC当前时间(时)
    mov  al,   0x04 ; 4 号 CMOS RAM 单元 - 时
    or   al,   0x80
    out  0x70, al
    in   al,   0x71
    push ax

    ; 获取寄存器 C 的索引 + 开放NMI
    mov al,   0x0c
    out 0x70, al
    in  al,   0x71 ; 读一下RTC的寄存器C，否则只发生一次中断
                   ; 此处不考虑闹钟和周期性中断的情况

    ; 下面显示时间到屏幕上
    mov ax, 0xb800
    mov es, ax

    ; hours, 用 2 位十进制显示
    pop  ax
    call bcd_to_ascii
    mov  bx, 12*160 + 36*2 ; 从屏幕上的12行36列开始显示

    mov ch,        0x70
    mov cl,        ah
    mov [es:bx],   cx
    mov cl,        al
    mov [es:bx+2], cx

    mov cl,        ':'
    mov [es:bx+4], cx
    not byte [es:bx+5] ; [es:bx+5] 里面是显示属性, 这里翻转他

    pop  ax
    call bcd_to_ascii
    mov  cl,        ah
    mov  [es:bx+6], cx
    mov  cl,        al
    mov  [es:bx+8], cx

    mov cl,         ':'
    mov [es:bx+10], cx
    not byte [es:bx+11]

    pop  ax
    call bcd_to_ascii
    mov  cl,         ah
    mov  [es:bx+12], cx
    mov  cl,         al
    mov  [es:bx+14], cx

    ; EOI 用于通知 8259 芯片中断处理已经结束, 8259 会清掉当前中断标记, 进而才能允许下一次中断发生
    mov al,   0x20 ; 中断结束命令 EOI
    out 0xa0, al   ; 向从片发送
    out 0x20, al   ; 向主片发送

    pop es
    pop dx
    pop cx
    pop bx
    pop ax

    iret

;-------------------------------------------------------------------------------
; BCD码转ASCII
;     输入: AL = bcd码
;     输出: AX = ascii
bcd_to_ascii:
      mov ah, al   ; 分拆成两个数字
      and al, 0x0f ; 仅保留低4位
      add al, 0x30 ; 转换成ASCII

      shr ah, 4    ; 逻辑右移4位
      and ah, 0x0f
      add ah, 0x30

      ret


; 显示字符串, 字符串以 '0' 结尾
;   DS:BX 是字符串的位置
put_string:
    ; 准备调用 put_char, 这是入参
    mov cl, [bx]

    ; 如果遇到结尾字符, 就退出展示
    or cl, cl
    jz .exit

    call put_char
    inc  bx
    jmp  put_string

.exit:
    ret

; 显示一个字符
put_char:
    push ax
    push bx
    push cx
    push dx
    push ds
    push es

    ; 以下取当前光标位置
    mov dx, 0x03d4
    mov al, 0x0e   ; 高 8 位
    out dx, al
    mov dx, 0x03d5
    in  al, dx
    mov ah, al

    mov dx, 0x03d4
    mov al, 0x0f   ; 低 8 位
    out dx, al
    mov dx, 0x03d5
    in  al, dx

    ; 以后用 BX 代表光标位置的16位数
    mov bx, ax

    cmp cl, 0x0d
    jnz .put_0a

    ; 打印回车 - 将光标移动到当前行开头位置
    mov bl, 80
    div bl
    mul bl
    mov bx, ax
    jmp .set_cursor

.put_0a:
    ; 打印换行
    cmp cl, 0x0a
    jnz .put_other
    add bx, 80
    jmp .roll_screen

.put_other:
    mov ax,      0xb800
    mov es,      ax
    shl bx,      1      ; 显示缓冲区还保存了显示属性, 因此真实位置要用光标位置乘以 2
    mov [es:bx], cl

    ; 光标移动到下一个位置
    shr bx, 1
    add bx, 1

.roll_screen:
    cmp bx, 2000
    jl  .set_cursor

    push bx
    mov  ax, 0xb800

    ; DS:SI -> ES:DI
    mov ds, ax
    mov es, ax
    mov si, 80*2
    mov di, 0

    mov cx, 1920
    cld
    rep movsw

    ; 清除屏幕最底一行
    mov bx, (2000 - 80) * 2
    mov cx, 80
.cls:
    mov  word [es:bx], 0x0720
    add  bx,           2
    loop .cls

    pop bx
    sub bx, 80

.set_cursor:
    call set_cursor

    pop es
    pop ds
    pop dx
    pop cx
    pop bx
    pop ax

    ret

; 设置光标位置
;  BX = 光标位置
set_cursor:
    push ax
    push dx

    mov dx, 0x03d4
    mov al, 0x0e
    out dx, al
    mov dx, 0x3d5
    mov al, bh
    out dx, al

    mov dx, 0x03d4
    mov al, 0x0f
    out dx, al
    mov dx, 0x3d5
    mov al, bl
    out dx, al

    pop dx
    pop ax

    ret

; 清空屏幕
clear_screen:
    push ax
    push bx
    push cx
    push es

    mov ax, 0xb800
    mov es, ax

    xor ax, ax
    mov cl, ' '

._cls:
    cmp  ax, 2000
    call put_char
    inc  ax
    jnz  ._cls

    mov  bx, 0
    call set_cursor

    pop es
    pop cx
    pop bx
    pop ax

    ret

start:
    ; 加载器交出控制权的时候, DS, ES 都指向的是 header 段
    ; 程序上来先设置好自己的栈段
    mov ax, [stack_segment]
    mov ss, ax
    mov sp, stack_end

    mov ax, [data_segment]
    mov ds, ax

    call clear_screen

    mov  bx, msg0
    call put_string


    ; 安装 0x70 号中断
    mov al, 0x70
    mov bl, 4
    mul bl
    mov bx, ax   ; 0x70 中断在 IVT 里面的偏移量

    ; 暂停中断, 防止改动期间发生新的 0x70 号中断
    cli

    push es
    mov  ax,             0x0000       ; IVT 段地址
    mov  es,             ax
    mov  word [es:bx],   new_int_0x70 ; 安装 0x70 中断处理程序
    mov  word [es:bx+2], cs
    pop  es

    ; 配置 RTC, 每秒钟一次中断
    mov al,   0x0b ; RTC 寄存器 B
    or  al,   0x80 ; NMI
    out 0x70, al
    mov al,   0x12 ; 设置寄存器 B, 禁止周期性中断, 开放更新结束后中断, BCD码, 24小时制
    out 0x71, al

    ; 读 RTC 寄存器 C, 复位未决的中断状态
    mov al,   0x0c
    out 0x70, al
    in  al,   0x71

    in  al,   0xa1 ; 读 8259 从片的 IMR 寄存器
    and al,   0xfe ; 清除 bit 0, 此位连接 RTC
    out 0xa1, al   ; 写回去

    ; 放开中断
    sti

    mov cx,                   0xb800
    mov ds,                   cx
    mov byte [12*160 + 33*2], '@'    ; 屏幕第 12 行, 35 列

.idle:
    hlt                        ; 使 CPU 进入低功耗状态, 直到用中断唤醒
    not byte [12*160 + 33*2+1] ; 反转显示属性
    jmp .idle


; ===============================================================================
SECTION data align=16 vstart=0

msg0:
    db '  The above contents is written by LeeChung. ', 0x0d, 0x0a
    db '2011-05-06', 0x0d, 0x0a
    db 'Have a nice day!!!'
    db 0

; ===============================================================================
; 栈段
SECTION stack align=16 vstart=0

    resb 256
stack_end:


; ===============================================================================
; 程序末尾
SECTION tail align=16

program_end:
