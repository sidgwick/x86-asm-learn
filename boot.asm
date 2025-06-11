; 第五章代码

    ; ES 段指向文本模式缓冲区
    mov ax, 0xb800
    mov es, ax

    ; CS 会被 BIOS 设置为 0x00, IP 被设置为 0x7c00
    ; DS 设置为从 0x7c00 开始
    mov ax, 0x7c00
    mov ds, ax


    ; 以下显示字符串"Label offset:"
    mov byte [es:0x00], 'L'
    mov byte [es:0x01], 0x07 ; 黑底白字
    mov byte [es:0x02], 'a'
    mov byte [es:0x03], 0x07
    mov byte [es:0x04], 'b'
    mov byte [es:0x05], 0x07
    mov byte [es:0x06], 'e'
    mov byte [es:0x07], 0x07
    mov byte [es:0x08], 'l'
    mov byte [es:0x09], 0x07
    mov byte [es:0x0A], ' '
    mov byte [es:0x0B], 0x07
    mov byte [es:0x0C], 'o'
    mov byte [es:0x0D], 0x07
    mov byte [es:0x0E], 'f'
    mov byte [es:0x0F], 0x07
    mov byte [es:0x10], 'f'
    mov byte [es:0x11], 0x07
    mov byte [es:0x12], 's'
    mov byte [es:0x13], 0x07
    mov byte [es:0x14], 'e'
    mov byte [es:0x15], 0x07
    mov byte [es:0x16], 't'
    mov byte [es:0x17], 0x07
    mov byte [es:0x18], ':'
    mov byte [es:0x19], 0x07

    ; 取得标号number的偏移地址
    mov ax, number

    ; bx 存放的是除数
    mov bx, 10

    ; 求个位上的数字, DX 存放的是被除数高位, AX 存放的是被除数低位
    mov dx, 0
    div bx
    mov [number + 0x00], dl ; 保存个位数字

    ; 求十位数字, 第一次出发完成之后, DX 存放的是商, AX 是余数
    xor dx, dx
    div bx
    mov [number + 0x01], dl

    ; 求百位数字
    xor dx, dx
    div bx
    mov [number + 0x02], dl

    ; 求千位位数字
    xor dx, dx
    div bx
    mov [number + 0x03], dl

    ; 求万位位数字
    xor dx, dx
    div bx
    mov [number + 0x04], dl

    ; 现在显示计算好的数字到屏幕上
    mov al, [number + 0x04]
    add al, 0x30 ; 转换为 ASCII 码
    mov [es:0x1a], al
    mov byte [es:0x1b], 0x04 ; 黑底红字

    mov al, [number + 0x03]
    add al, 0x30 ; 转换为 ASCII 码
    mov [es:0x1c], al
    mov byte [es:0x1d], 0x04 ; 黑底红字

    mov al, [number + 0x02]
    add al, 0x30 ; 转换为 ASCII 码
    mov [es:0x1e], al
    mov byte [es:0x1f], 0x04 ; 黑底红字

    mov al, [number + 0x01]
    add al, 0x30 ; 转换为 ASCII 码
    mov [es:0x20], al
    mov byte [es:0x21], 0x04 ; 黑底红字

    mov al, [number + 0x00]
    add al, 0x30 ; 转换为 ASCII 码
    mov [es:0x22], al
    mov byte [es:0x23], 0x04 ; 黑底红字

    mov byte [es:0x24], 'D'
    mov byte [es:0x25], 0x07

; 无限循环
infi:
    jmp near infi

number:
    db 0, 0, 0, 0, 0

    times 202 db 0
    db 0x55, 0xaa
