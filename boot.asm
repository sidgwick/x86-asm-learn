; 第六章代码

    jmp near start

mytext:
    db 'L', 0x07, 'a', 0x07, 'b', 0x07, 'e', 0x07, 'l', 0x07, ' ', 0x07, 'o', 0x07, \
            'f', 0x07, 'f', 0x07, 's', 0x07, 'e', 0x07, 't', 0x07, ':', 0x07

number:
    db 0,0,0,0,0

start:
    ; 设置数据段基地址(0x07c0:0x0000)
    mov ax, 0x07c0
    mov ds, ax

    ; 设置附加段基地址(显示缓冲区)
    mov ax, 0xb800
    mov es, ax

    ; movsb, movsw 用于从 DS:SI 往 ES:DI 搬数据
    ; cld, std 用来指定 SI/DI 的方向, cld 之后 SI/DI 自增, std 之后自减
    ; 不配合 rep 指令的时候, movsb/movsw 只执行一次, 配合 rep 使用, 可以执行 CX 次
    cld
    mov si, mytext
    mov di, 0x00
    mov cx, (number - mytext) / 2 ; = 13
    rep movsw

    ; 得到标号所代表的偏移地址, 接下来会在屏幕上显示这个数字
    mov ax, number

    ; 计算各个数位
    mov bx, ax ; bx 现在记录的是 number 在段内偏移, 一会儿往这里写数据
    mov cx, 5 ; 循环次数
    mov si, 10 ; 除数
digit:
    xor dx, dx
    div si
    mov [bx], dl ; 保存计算结果(商)
    inc bx
    loop digit

    ; 显示各个数位
    mov bx, number
    mov si, 4
show:
    mov al, [bx, si]
    add al, 0x30 ; ASCII 码值
    mov ah, 0x04 ; 显示属性
    mov [es:di], ax
    add di, 2
    dec si
    jns show

    mov word [es:di], 0x0744 ; 字符 'D', 黑底白字
    jmp near $

    times 510-($-$$) db 0
    db 0x55,0xaa