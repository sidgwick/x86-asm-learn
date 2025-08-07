        # 代码清单17-1
        # 文件名：c17_mbr.asm
        # 文件说明：硬盘主引导扇区代码
        # 创建日期：2012-07-13 11:20        ;设置堆栈段和栈指针

.code16

.global _start

.section .data

.section .text

    .equ core_base_address, 0x00040000 # 常数，内核加载的起始内存地址
    .equ core_start_sector, 0x00000001 # 常数，内核的起始逻辑扇区号

_start:
        mov %cs, %eax
        mov %eax, %ss
        mov $0x7c00, %esp

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

        mov $core_base_address, %edi
        mov $core_start_sector, %eax
        mov %edi, %ebx # 起始地址
        call read_hard_disk_0 # 以下读取程序的起始部分

        # 以下判断整个程序有多大
        mov (%edi), %eax
        xor %edx, %edx
        mov $512, %ecx # 512 字节每扇区
        div %ecx

        # 如果除不尽, 说明需要额外多读一个不满的扇区
        or %edx, %edx
        jnz _1
        dec %eax
    _1:
        or %eax, %eax # 是否已经读完了
        jz pge

        # 读取剩余的扇区数据
        mov %eax, %ecx
        mov $core_start_sector, %eax
        inc %eax # 下一个扇区
    _2:
        # 循环读取, bx 自动在增长
        call read_hard_disk_0
        inc %eax
        loop _2

    # 准备打开分页机制
    pge:
        # 创建系统内核的页目录表PDT

        # PDT 物理地址
        mov $0x00020000, %ebx

        # 在页目录内创建指向页目录表自己的目录项(倒数第一项: 4096-4)
        # 0x00020000 是 PDT 自己所在页面地址, 3 是页面属性 P=1, US=1, RW=1
        movl $0x00020003, 4092(%ebx)

        # 0x00021000 是 PDT 中第 0 项(也是第 2048 项) entry 对应的页表所在的物理地址
        # 虚拟空间 2Gb 指向的页面和 0Gb 指向的页面是一个页面
        mov $0x00021003, %edx
        mov %edx, (%ebx)
        mov %edx, 0x800(%ebx)

        # 创建与上面那个目录项相对应的页表, 初始化页表项
        # 因为内核比较小, 页表里面只需要填充最低的 256 个项(也就是 256x4Kb=1M 的空间)即可.
        mov $0x00021000, %ebx # 页表的物理地址
        xor %eax, %eax # 起始页的物理地址
        xor %esi, %esi
    .b1:
        mov %eax, %edx
        or $0x00000003, %edx
        mov %edx, (%ebx, %esi, 4)
        add $0x1000, %eax
        inc %esi
        cmp $256, %esi
        jl .b1

        # CR3 - PDBR 寄存器指向 PDT 页
        mov $0x00020000, %eax # PCD=PWT=0
        mov %eax, %cr3

        # 修正 GDT 里面的映射地址, 从 0x80000000 开始
        sgdt pgdt
        mov pgdt+2, %ebx
        addl $0x80000000, pgdt+2
        lgdt pgdt

        mov %cr0, %eax
        or $0x80000000, %eax
        mov %eax, %cr0 # PG=1

        # 将堆栈映射到高端，这是非常容易被忽略的一件事。应当把内核的所有东西
        # 都移到高端，否则，一定会和正在加载的用户任务局部空间里的内容冲突，
        # 而且很难想到问题会出在这里。
        add $0x80000000, %esp
        jmp *0x80040004 # 跳转到内核入口



read_hard_disk_0:
        push %eax
        push %ecx
        push %edx

        push %eax

        # 读取的扇区数
        mov $0x1f2, %dx
        mov $1, %al
        out %al, %dx

        # LBA地址7~0
        inc %dx
        pop %eax
        out %al, %dx

        # LBA地址15~8
        inc %dx
        mov $8, %cl
        shr %cl, %eax
        out %al, %dx

        # LBA地址23~16
        inc %dx
        shr %cl, %eax
        out %al, %dx

        # LBA地址27~24 + 第一块硬盘, LBA 模式
        # 1_1_1_0_0000 => bit(4)=0/1-表示主/从硬盘, bit(6)=0/1指定 CHS/LBA 地址模式, bit(5|7) 是保留位始终为 1
        inc %dx
        shr %cl, %eax
        or $0b11100000, %al
        out %al, %dx

        # 读取硬盘状态, 0x1f7 端口
        #   1. 发送 0x20 表示开始读取硬盘数据
        #   2. 直接读取 0x1f7 端口可以获取到硬盘的状态信息
        inc %dx
        mov $0x20, %al # 读取命令
        out %al, %dx
    .waits:
        in %dx, %al
        and $0x88, %al
        cmp $0x08, %al
        jnz .waits # 不忙，且硬盘已准备好数据传输. bit(3)=1 表示硬盘已经准备好和内存交换数据, bit(7)=1 表示硬盘忙

        # 一个扇区 512 字节, 一次可以读 2 字节
        mov $256, %ecx
        mov $0x1f0, %dx
    .readw:
        in %dx, %ax
        mov %ax, (%ebx)
        add $2, %ebx
        loop .readw

        pop %edx
        pop %ecx
        pop %eax

        ret

pgdt: .word 0
      .long 0x00008000 # GDT的物理/线性地址

.org 510, 0x00
.byte 0x55, 0xaa
