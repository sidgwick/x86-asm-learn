; 第七章代码

    jmp near start

message:
    db '1+2+3+...+100='

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
    mov cx, start - message
@g:
    mov al, [si]
    mov ah, 0x07
    mov [es:di], ax
    add si, 1
    add di, 2
    loop @g

    ; 以下计算1到100的和
    xor ax, ax
    mov cx, 1
@f:
    add ax, cx
    inc cx
    cmp cx, 103
    jle @f

    ; 以下计算累加和的每个数位
    mov cx, 5
    add di, 8
dight:
    xor dx, dx
    mov bx, 10
    div bx
    mov bl, dl
    mov bh, 0x07
    add bl, 0x30
    mov [es:di], bx
    sub di, 2
    loop dight


;
;          xor cx,cx              ;设置堆栈段的段基地址
;          mov ss,cx
;          mov sp,cx

;          mov bx,10
;          xor cx,cx
;      @d:
;          inc cx
;          xor dx,dx
;          div bx
;          or dl,0x30
;          push dx
;          cmp ax,0
;          jne @d

;          ;以下显示各个数位
;      @a:
;          pop dx
;          mov [es:di],dl
;          inc di
;          mov byte [es:di],0x07
;          inc di
;          loop @a

    jmp near $

    times 510-($-$$) db 0
    db 0x55,0xaa
