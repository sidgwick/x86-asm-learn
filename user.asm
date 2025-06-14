; 第8章 - 用户程序

; ===============================================================================
; 头部段, 定义了程序的长度, 程序的入口, 以及各个段的定位信息
SECTION header align=16 vstart=0

program_leght:
    dd program_end           ; [0x00] - 程序长度

code_entry:
    dw start                  ; [0x04] - 入口点偏移地址
    dd section.code_1.start   ; [0x06] - 入口点所在的段地址

realloc_tbl_len:
    dw (header_end - code_1_segment) / 4   ; [0x0a] - 段重定位表项个数

; [0x0a] - 段重定位表
code_1_segment:
    dd section.code_1.start;
code_2_segment:
    dd section.code_2.start;
data_1_segment:
    dd section.data_1.start;
data_2_segment:
    dd section.data_2.start;
stack_segment:
    dd section.stack.start;

header_end:

; ===============================================================================
; 代码段 1
SECTION code_1 align=16 vstart=0

; 显示字符串, 字符串以 '0' 结尾
;   DS:BX 是字符串的位置
put_string:
    ; 准备调用 put_char, 这是入参
    mov cl, [bx]

    ; 如果遇到结尾字符, 就退出展示
    or cl, cl
    jz .exit

    call put_char
    inc bx
    jmp put_string

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
    mov al, 0x0e ; 高 8 位
    out dx, al
    mov dx, 0x03d5
    in al, dx
    mov ah, al

    mov dx, 0x03d4
    mov al, 0x0f ; 低 8 位
    out dx, al
    mov dx, 0x03d5
    in al, dx

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
    mov ax, 0xb800
    mov es, ax
    shl bx, 1 ; 显示缓冲区还保存了显示属性, 因此真实位置要用光标位置乘以 2
    mov [es:bx], cl

    ; 光标移动到下一个位置
    shr bx, 1
    add bx, 1

.roll_screen:
    cmp bx, 2000
    jl .set_cursor

    push bx
    mov ax, 0xb800

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
    mov word [es:bx], 0x0720
    add bx, 2
    loop .cls

    pop bx
    sub bx, 80

.set_cursor:
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

    pop es
    pop ds
    pop dx
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

    mov ax, [data_1_segment]
    mov ds, ax

    mov bx, msg0
    call put_string

    ; 把 code_2_segment 作为栈地址, begin 作为偏移地址入栈
    ; 骗 retf 跳转到这个地址去执行
    push word [es:code_2_segment]
    mov ax, begin
    push ax

    retf

continue:
    mov ax, [es:data_2_segment]
    mov ds, ax

    mov bx, msg1
    call put_string

    jmp $

; ===============================================================================
SECTION code_2 align=16 vstart=0

begin:
    push word [es:code_1_segment]
    mov ax, continue
    push ax

    retf

; ===============================================================================
SECTION data_1 align=16 vstart=0

msg0:
    db '  This is NASM - the famous Netwide Assembler. ',0x0d,0x0a
    db 'Back at SourceForge and in intensive development! ',0x0d,0x0a
    db 'Get the current versions from http://www.nasm.us/.',0x0d,0x0a
    db 0x0d,0x0a,0x0d,0x0a
    db '  Example code for calculate 1+2+...+1000:',0x0d,0x0a,0x0d,0x0a
    db '     xor dx,dx',0x0d,0x0a
    db '     xor ax,ax',0x0d,0x0a
    db '     xor cx,cx',0x0d,0x0a
    db '  @@:',0x0d,0x0a
    db '     inc cx',0x0d,0x0a
    db '     add ax,cx',0x0d,0x0a
    db '     adc dx,0',0x0d,0x0a
    db '     inc cx',0x0d,0x0a
    db '     cmp cx,1000',0x0d,0x0a
    db '     jle @@',0x0d,0x0a
    db '     ... ...(Some other codes)',0x0d,0x0a,0x0d,0x0a
    db 0

; ===============================================================================
SECTION data_2 align=16 vstart=0

msg1:
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
