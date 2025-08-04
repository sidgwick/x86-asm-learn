        # 代码清单17-1
        # 文件名：c17_mbr.asm
        # 文件说明：硬盘主引导扇区代码
        # 创建日期：2012-07-13 11:20        ;设置堆栈段和栈指针

.code16

BOOTSEG=0x7c00

.global _start
.section .text

_start:
        mov %cs, %eax
        mov %eax, %ss
        mov $BOOTSEG, %esp

        # 计算GDT所在的逻辑段地址
        mov %cs:pgdt, %eax # mov    %cs:0x7d6f,%eax
        xor %edx, %edx
        mov $16, %ebx
        div %ebx

        # GDT 所在的段和段选择子
        mov %eax, %ds
        mov %edx, %ebx

        # #1 描述符 - 保护模式下的代码段描述符
        movl $0x0000ffff, 0x08(%ebx)
        movl $0x00cf9800, 0x0C(%ebx)
        
        # #1 描述符 - 保护模式下的数据段和堆栈段描述符
        movl $0x0000ffff, 0x10(%ebx)
        movl $0x00cf9200, 0x14(%ebx)

        # 初始化描述符表寄存器 GDTR
        movw $23, %cs:pgdt

        lgdt %cs:pgdt

        # 南桥芯片内的端口, 打开A20
        in $0x92, %al
        or 0b00000010, %al
        out %al, $0x92

        cli # 中断机制尚未工作

        # 设置 PE 位, 打开保护模式
        mov %cr0, %eax
        or $1, %eax
        mov %eax, %cr0

        # 加载保护模式下的 CS
        ljmpl $0x0008, $flush

.code32

    flush:
        # 加载数据段(4GB)选择子
        mov $0x0010, %eax
        mov %eax, %ds
        mov %eax, %es
        mov %eax, %fs
        mov %eax, %gs
        mov %eax, %ss  # 加载堆栈段(4GB)选择子
        mov $0x7000, %esp # 堆栈指针

/*
  55:	0f 20 c0             	mov    %cr0,%eax
  58:	66 83 c8 01          	or     $0x1,%eax
  5c:	0f 22 c0             	mov    %eax,%cr0
  5f:	66 ea 67 7c 00 00 08 	ljmpl  $0x8,$0x7c67
  66:	00 
  67:	b8 10 00             	mov    $0x10,%ax
  6a:	00 00                	add    %al,(%bx,%si)
  6c:	8e d8                	mov    %ax,%ds
  6e:	8e c0                	mov    %ax,%es
  70:	8e e0                	mov    %ax,%fs
  72:	8e e8                	mov    %ax,%gs
  74:	8e d0                	mov    %ax,%ss
  76:	bc 00 70             	mov    $0x7000,%sp
  79:	00 00                	add    %al,(%bx,%si)
  7b:	bf 00 00             	mov    $0x0,%di
  7e:	04 00                	add    $0x0,%al
  80:	b8 01 00             	mov    $0x1,%ax
  83:	00 00                	add    %al,(%bx,%si)
  85:	89 fb                	mov    %di,%bx
  87:	e8 9c 00             	call   0x126
  8a:	00 00                	add    %al,(%bx,%si)
  8c:	8b 07                	mov    (%bx),%ax
  8e:	31 d2                	xor    %dx,%dx
  90:	b9 00 02             	mov    $0x200,%cx
  93:	00 00                	add    %al,(%bx,%si)
  95:	f7 f1                	div    %cx
  97:	09 d2                	or     %dx,%dx
  99:	75 01                	jne    0x9c
  9b:	48                   	dec    %ax
  9c:	09 c0                	or     %ax,%ax
  9e:	74 10                	je     0xb0
  a0:	89 c1                	mov    %ax,%cx
  a2:	b8 01 00             	mov    $0x1,%ax
  a5:	00 00                	add    %al,(%bx,%si)
  a7:	40                   	inc    %ax
  a8:	e8 7b 00             	call   0x126
  ab:	00 00                	add    %al,(%bx,%si)
  ad:	40                   	inc    %ax
  ae:	e2 f8                	loop   0xa8
  b0:	bb 00 00             	mov    $0x0,%bx
  b3:	02 00                	add    (%bx,%si),%al
  b5:	c7 83 fc 0f 00 00    	movw   $0x0,0xffc(%bp,%di)
  bb:	03 00                	add    (%bx,%si),%ax
  bd:	02 00                	add    (%bx,%si),%al
  bf:	ba 03 10             	mov    $0x1003,%dx
  c2:	02 00                	add    (%bx,%si),%al
  c4:	89 13                	mov    %dx,(%bp,%di)
  c6:	89 93 00 08          	mov    %dx,0x800(%bp,%di)
  ca:	00 00                	add    %al,(%bx,%si)
  cc:	bb 00 10             	mov    $0x1000,%bx
  cf:	02 00                	add    (%bx,%si),%al
  d1:	31 c0                	xor    %ax,%ax
  d3:	31 f6                	xor    %si,%si
  d5:	89 c2                	mov    %ax,%dx
  d7:	83 ca 03             	or     $0x3,%dx
  da:	89 14                	mov    %dx,(%si)
  dc:	b3 05                	mov    $0x5,%bl
  de:	00 10                	add    %dl,(%bx,%si)
  e0:	00 00                	add    %al,(%bx,%si)
  e2:	46                   	inc    %si
  e3:	81 fe 00 01          	cmp    $0x100,%si
  e7:	00 00                	add    %al,(%bx,%si)
  e9:	7c ea                	jl     0xd5
  eb:	b8 00 00             	mov    $0x0,%ax
  ee:	02 00                	add    (%bx,%si),%al
  f0:	0f 22 d8             	mov    %eax,%cr3
  f3:	0f 01 05             	sgdtw  (%di)
  f6:	6d                   	insw   (%dx),%es:(%di)
  f7:	7d 00                	jge    0xf9
  f9:	00 8b 1d 6f          	add    %cl,0x6f1d(%bp,%di)
  fd:	7d 00                	jge    0xff
  ff:	00 81 05 6f          	add    %al,0x6f05(%bx,%di)
 103:	7d 00                	jge    0x105
 105:	00 00                	add    %al,(%bx,%si)
 107:	00 00                	add    %al,(%bx,%si)
 109:	80 0f 01             	orb    $0x1,(%bx)
 10c:	15 6d 7d             	adc    $0x7d6d,%ax
 10f:	00 00                	add    %al,(%bx,%si)
 111:	0f 20 c0             	mov    %cr0,%eax
 114:	0d 00 00             	or     $0x0,%ax
 117:	00 80 0f 22          	add    %al,0x220f(%bx,%si)
 11b:	c0 81 c4 00 00       	rolb   $0x0,0xc4(%bx,%di)
 120:	00 80 ff 25          	add    %al,0x25ff(%bx,%si)
 124:	04 00                	add    $0x0,%al
 126:	04 80                	add    $0x80,%al
 128:	50                   	push   %ax
 129:	51                   	push   %cx
 12a:	52                   	push   %dx
 12b:	50                   	push   %ax
 12c:	66 ba f2 01 b0 01    	mov    $0x1b001f2,%edx
 132:	ee                   	out    %al,(%dx)
 133:	66 42                	inc    %edx
 135:	58                   	pop    %ax
 136:	ee                   	out    %al,(%dx)
 137:	66 42                	inc    %edx
 139:	b1 08                	mov    $0x8,%cl
 13b:	d3 e8                	shr    %cl,%ax
 13d:	ee                   	out    %al,(%dx)
 13e:	66 42                	inc    %edx
 140:	d3 e8                	shr    %cl,%ax
 142:	ee                   	out    %al,(%dx)
 143:	66 42                	inc    %edx
 145:	d3 e8                	shr    %cl,%ax
 147:	0c e0                	or     $0xe0,%al
 149:	ee                   	out    %al,(%dx)
 14a:	66 42                	inc    %edx
 14c:	b0 20                	mov    $0x20,%al
 14e:	ee                   	out    %al,(%dx)
 14f:	ec                   	in     (%dx),%al
 150:	24 88                	and    $0x88,%al
 152:	3c 08                	cmp    $0x8,%al
 154:	75 f9                	jne    0x14f
 156:	b9 00 01             	mov    $0x100,%cx
 159:	00 00                	add    %al,(%bx,%si)
 15b:	66 ba f0 01 66 ed    	mov    $0xed6601f0,%edx
 161:	66 89 03             	mov    %eax,(%bp,%di)
 164:	83 c3 02             	add    $0x2,%bx
 167:	e2 f6                	loop   0x15f
 169:	5a                   	pop    %dx
 16a:	59                   	pop    %cx
 16b:	58                   	pop    %ax
 16c:	c3                   	ret
 16d:	00 00                	add    %al,(%bx,%si)
 16f:	00 80 00 00          	add    %al,0x0(%bx,%si)
	...
 1fb:	00 00                	add    %al,(%bx,%si)
 1fd:	00 55 aa             	add    %dl,-0x56(%di)
*/

.section .data

    pgdt: .word 0
          .long 0x00008000 # GDT的物理/线性地址

.org 510
.word 0xaa55
