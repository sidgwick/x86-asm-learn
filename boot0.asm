; 第八章代码

    ; 常数声明, 用户的应用程序保存在第 100 逻辑扇区开始的磁盘空间上
    app_lba_start equ 100

SECTION mbr align=16 vstart=0x7c00

    ; 设置堆栈
    mov ax, 0
    mov ss, ax
    mov sp, ax

    ; 计算用户程序在内存中合适的段地址
    ; 此时的用户程序相当于 MBR 程序的 `数据`, 因此设置 DS, ES 寄存器
    mov ax, [cs:phy_base]
    mov dx, [cs:phy_base+0x02]
    mov bx, 16 ; 16 位对齐
    div bx
    mov ds, ax
    mov es, ax

    ; 先读取程序的起始部分
    ; DI:SI 里面保存的事需要读取的扇区号, DS:BX 是接受的内存缓冲区地址
    xor di, di
    mov si, app_lba_start
    xor bx, bx
    call read_hard_disk_0

    ; 现在 DS:0x0000 里面有用户程序的前 512 字节内容
    ; 用户程序的前面两个字节是程序的长度
    mov dx, [0x02]
    mov ax, [0x00]
    mov bx, 512
    div bx

    ; 除不尽, 扇区数量会比余数 ax 多出来 1 个扇区
    ; 除得尽, 则扇区数量就是 ax 个, 但是现在赢读取了第一个扇区, 因此需要减一
    cmp dx, 0
    jnz @1
    dec ax
@1:
    cmp ax, 0 ; 已经读完了
    jz direct

    ; 继续读取剩余的数据
    push ds
    mov cx, ax
@2:
    mov ax, ds
    add ax, 0x20 ; DS + 512, 是下一个扇区要写入的内存位置
    mov ds, ax

    xor bx, bx
    inc si
    call read_hard_disk_0
    loop @2

    pop ds

; 计算用户程序入口点代码段基址
direct:
    ; 注意应用程序中填写的段地址是一个 20 位地址
    ; 这里处理完之后我们只要它的段地址, 因此后面只使用 [0x06]
    mov dx, [0x08]
    mov ax, [0x06]
    call calc_segment_base
    mov [0x06], ax

    ; 开始处理段重定位表
    mov cx, [0x0a] ; 需要重定位的项目数量
    mov bx, 0x0c   ; 重定位表首地址
realloc:
    mov dx, [bx+0x02]
    mov ax, [bx]
    call calc_segment_base
    mov [bx], ax
    add bx, 4
    loop realloc

    ; 转移到用户程序
    jmp far [0x04]


; 从硬盘读取一个扇区
;   DI:SI 是 LBA28 逻辑扇区号
;   DS:BX 是接受内存缓冲区地址
read_hard_disk_0:
    push ax
    push bx
    push cx
    push dx

    ; 读取一个扇区
    mov al, 1
    mov dx, 0x1f2
    out dx, al

    ; 要读取的扇区号 + 扇区号指定方式(LBA28) + 主盘模式
    inc dx ; 0x1f3 -- LBA28 的 0-7 位
    mov ax, si
    out dx, al

    inc dx ; 0x1f4 -- LBA28 的 8-15 位
    mov al, ah
    out dx, al


    inc dx ; 0x1f5 -- LBA28 的 16-23 位
    mov ax, di
    out dx, al

    inc dx ; 0x1f6 -- LBA28 的 24-28 位, + LBA28 模式 + 主盘
    mov al, 0xe0
    or al, ah
    out dx, al

    ; 读取磁盘状态, 等待数据准备就绪
    inc dx
    mov al, 0x20
    out dx, al
.waits:
    in al, dx
    and al, 0x88
    cmp al, 0x08
    jnz .waits

    ; 读取磁盘内容, 写到内存中
    mov cx, 256
    mov dx, 0x1f0
.readw:
    in ax, dx
    mov [bx], ax
    add bx, 2
    loop .readw

    pop dx
    pop cx
    pop bx
    pop ax

    ret


; 计算 20 位物理地址对应的 16 位段地址
;   DX:AX = 32位物理地址
;   AX = 16位段基地址
calc_segment_base:
    push dx

    ; 用户程序提供的是编译时地址, 因此那些偏移都是相对于 0x00000 开始的
    ; 这里必须要将它被加载的物理内存地址加上, 才好做后面的端地址计算
    add ax, [cs:phy_base]
    add dx, [cs:phy_base+0x02]

    ; 下面没有用除法计算, 使用位移完成了计算
    shr ax, 4
    ror dx, 4
    and dx, 0xf000 ; 只要 dx 里面原来的低 4 位
    or ax, dx      ; shr 之后, ax 高 4 位现在是 0

    pop dx
    ret

phy_base:
    dd 0x10000 ; 用户程序在内存中的物理起始地址

    times 510-($-$$) db 0
    db 0x55,0xaa
