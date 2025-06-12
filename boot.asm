; 第七章代码

    jmp near start

message:
    db '1+2+3+...+13000='

quotient_H:
    dw 0x0000

start:
    ; 设置数据段的段基地址
    mov ax, 0x07c0
    mov ds, ax

    ; 设置附加段基址到显示缓冲区
    mov ax, 0xb800
    mov es, ax

    ; 以下显示字符串
    mov si, message
    mov di, 0x00
    mov cx, quotient_H - message
@g:
    mov al, [si]
    mov ah, 0x07
    mov [es:di], ax
    add si, 1
    add di, 2
    loop @g

    ; 以下计算1到100的和
    xor ax, ax
    xor dx, dx
    mov cx, 1
@f:
    add ax, cx ; ax 存放结果的低位
    adc dx, 0 ; dx 存放结果的高位
    inc cx
    cmp cx, 13000
    jle @f

    ; 设置堆栈段的段基地址 (0x0000:0x0000)
    ; 注意由于压栈的时候 SP 自减, 因此实际上栈底位置在 0x0FFFF
    xor cx, cx
    mov ss, cx
    mov sp, cx


    ; 以下计算累加和的每个数位
    mov bx, 10
    xor cx, cx ; 将来作为 loop @a 的 counter
@d:
    inc cx

    ; 除法计算的时候, 如果出现商不能被 AX 容纳的情况, CPU 会触发溢出中断
    ; 此时可以采用
    ;   1. 先对被除数高位 DX 除一次, 得到高位部分 `商H` 和高位部分 `余数H`
    ;   2. `商H` 可以认为是原始除法结果的商的高位部分
    ;   3. `余数H` 此时再配合被除数的低位部分, 重新做除法运算, 得到第二部分的 `商L` 和 `余数L`
    ;   4. 最终结果是 商 = `商H` 拼接上 `商L`, 余数就是最后的 `余数L`

    push ax ; 先把 ax 入栈, 腾出地方计算被除数的高位部分
    mov ax, dx
    xor dx, dx
    div bx ; 执行第一步除法, 执行完 AX 是 `商H`, DX 是 `余数H`

    ; 将商的高位保存起来
    mov [quotient_H], ax
    pop ax
    div bx ; 执行第二步除法, 执行完 AX 是 `商L`, DX 是 `余数L`

    ; 转化为 ASCII 码, 压栈保存
    or dl, 0x30 ; ADD 0x30
    push dx

    ; 恢复商的高位信息
    mov dx, [quotient_H]

    cmp ax, 0
    jne @d

    ; 以下显示各个数位
@a:
    pop dx
    mov dh, 0x07
    mov [es:di], dx
    add di, 2
    loop @a

    ; 死循环
    jmp near $

    times 510-($-$$) db 0
                     db 0x55,0xaa
