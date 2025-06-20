; 第8章 - 用户程序

; ===============================================================================
; 头部段, 定义了程序的长度, 程序的入口, 以及各个段的定位信息
SECTION header align=16 vstart=0

    program_leght: dd program_end ; [0x00] - 程序长度

    code_entry:
        dw start              ; [0x04] - 入口点偏移地址
        dd section.code.start ; [0x06] - 入口点所在的段地址

    realloc_tbl_len: dw (header_end - code_segment) / 4 ; [0x0a] - 段重定位表项个数

    ; [0x0a] - 段重定位表
    code_segment:  dd section.code.start
    data_segment:  dd section.data.start
    stack_segment: dd section.stack.start

header_end:

; ===============================================================================
; 代码段 1
SECTION code align=16 vstart=0

putc:
    push ax

    ; AH=0E, 电传打字机输出
    ;   AL=字符，BH=页码，BL=颜色
    mov ah, 0x0e ;
    mov al, cl
    int 0x10

    pop ax
    ret

put_string:
   .w1:
    mov  cl, [bx]
    call putc
    inc  bx
    or   cl, cl
    jnz  .w1

    ret


; -----------------------------------
; 清空屏幕
clear_screen:
    push bx
    push cx
    push dx

    xor bx, bx
    mov cl, ' '
  .w0:
    call putc
    inc  bx
    cmp  bx, 2000
    jl   .w0

    ; AH=02H 设置光标
    ;   BH=页码，DH=行，DL=列
    mov bh, 0
    mov ah, 0x02
    xor dx, dx
    int 0x10

    pop dx
    pop cx
    pop bx

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

    mov  cl, 'D'
    call putc

    mov  bx, msg0
    call put_string

    ; 从键盘缓冲区中读取一个键盘输入
.reps:
    mov ah, 0x00
    int 0x16

; AH[1] = Scan code of the key pressed down
; AL = ASCII character of the button pressed

    mov  cl, al
    call putc

    ; mov ah, 0x0e
    ; mov bl, 0x07
    ; int 0x10

    jmp .reps

.idle:
    hlt       ; 使 CPU 进入低功耗状态, 直到用中断唤醒
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
