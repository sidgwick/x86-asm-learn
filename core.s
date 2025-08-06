.code32
.global _start

.macro alloc_user_linear
        mov 0x06(%esi), %ebx
        addl $0x1000, 0x06(%esi)
        call $flat_4gb_code_seg_sel, $alloc_inst_a_page
.endm

.macro alloc_core_linear
        mov (core_tcb+0x06), %ebx
        addl $0x1000, (core_tcb+0x06)
        call $flat_4gb_code_seg_sel, $alloc_inst_a_page
.endm


.equ flat_4gb_code_seg_sel, 0x0008 # 平坦模型下的4GB代码段选择子
.equ flat_4gb_data_seg_sel, 0x0018 # 平坦模型下的4GB数据段选择子
.equ idt_linear_address, 0x8001f000 # 中断描述符表的线性基地址


.section .data

.section .text

        # 以下是系统核心的头部，用于加载核心程序
        core_length: .long core_end       # 核心程序总长度#00
        core_entry: .long _start          # 核心代码段入口点#04

# 字符串显示例程（适用于平坦内存模型）
# 显示0终止的字符串并移动光标
# 输入：EBX=字符串的线性地址
put_string:
        push %ebx
        push %ecx

        cli # 硬件操作期间，关中断

    .getc:
        mov (%ebx), %cl
        or %cl, %cl
        jz .exit # NULL 字符结束打印
        call put_char
        inc %ebx
        jmp .getc

    .exit:
        sti # 硬件操作完毕，开放中断

        pop %ecx
        pop %ebx

        retf

# 在当前光标处显示一个字符,并推进光标。仅用于段内调用
# 输入：CL=字符ASCII码
put_char:
        pusha

        # 获取光标位置 - 高字
        mov $0x3d4, %dx
        mov $0x0e, %al
        out %al, %dx
        inc %dx
        in %dx, %al
        mov %al, %ah

        # 获取光标位置 - 低字
        dec %dx
        mov $0x0f, %al
        out %al, %dx
        inc %dx
        in %dx, %al

        mov %ax, %bx # BX 保存了当前光标位置
        and $0x0000ffff, %ebx # 准备使用32位寻址方式访问显存

        # 处理回车符号
        cmp $0x0d, %cl
        jnz .pua_0a

        mov %bx, %ax
        mov $80, %bl
        div %bl
        mul %bl
        mov %ax, %bx # 光标现在在行首
        jmp .set_cursor

    .pua_0a:
        cmp $0x0a, %cl
        jnz .put_other
        add $80, %bx
        jmp .roll_screen

    .put_other:
        shl $1, %bx # 一个字符需要 2 字节, 因此光标位置 x2
        mov %cl, 0x800b8000(%ebx)

        shr $1, %bx
        inc %bx

    # 滚屏
    .roll_screen:
        cmp $2000, %bx
        jl .set_cursor

        cld
        mov $0x800b80a0, %esi
        mov $0x800b8000, %edi
        mov $1920, %ecx
        rep movsl # 这里应该使用 movsw 恰当

        # 清理最后一行
        mov $3840, %bx
        mov $80, %ecx
    .cls:
        movw $0x0720, 0x800b8000(%ebx)
        add $2, %bx
        loop .cls

        mov $1920, %bx

    .set_cursor:
        mov $0x3d4, %dx
        mov $0x0e, %al
        out %al, %dx

        inc %dx
        mov %bh, %al
        out %al, %dx

        dec %dx
        mov $0x0f, %al
        out %al, %dx
        inc %dx
        mov %bl, %al
        out %al, %dx

        popa

        ret

# 从硬盘读取一个逻辑扇区（平坦模型）
# EAX=逻辑扇区号
# EBX=目标缓冲区线性地址
# 返回：EBX=EBX+512
read_hard_disk_0:
        cli # 读磁盘的时候忽略中断

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

        sti

        retf

# 汇编语言程序是极难一次成功，而且调试非常困难。这个例程可以提供帮助
# 在当前光标处以十六进制形式显示一个双字并推进光标
# 输入：EDX=要转换并显示的数字
# 输出：无
put_hex_dword:
        pusha

        mov $bin_hex, %ebx # 指向核心地址空间内的转换表
        mov $0x0008, %ecx # 一个双字是 32bits, 需要 8 个 HEX 字符显示
    .xlt:
        rol $4, %edx
        mov %edx, %eax
        and $0x0000000f, %eax

        # 从内存表中读取一个字节, 其地址由 [DS:EBX + AL] 计算得出
        # 并将该字节放入 AL 寄存器
        xlat

        push %ecx
        mov %al, %cl
        call put_char
        pop %ecx

        loop .xlt

        popa

        retf

# 在GDT内安装一个新的描述符
# 输入：EDX:EAX=描述符
# 输出：CX=描述符的选择子
set_up_gdt_descriptor:
        push %eax
        push %ebx
        push %edx

        sgdt pgdt # 取得GDTR的界限和线性地址

        # inc 那一行, 不用 EBX 是因为担心 GDT 16 位界限溢出, 影响后面的 EBX 地址计算
        movzxw pgdt, %ebx # GDT界限
        inc %bx # GDT总字节数，也是下一个描述符偏移
        add pgdt+2, %ebx # 下一个描述符的线性地址

        # 安装描述符
        mov %eax, (%ebx)
        mov %edx, 4(%ebx)

        addw $8, pgdt # 增加一个描述符的大小

        lgdt pgdt # 对GDT的更改生效

        # 下面计算描述符选择子, 并返回给调用者
        mov pgdt, %ax
        xor %dx, %dx
        mov $8, %bx # 除 8 商就是描述符索引
        div %bx
        mov %ax, %cx
        shl $3, %cx # 空出来 TI, RPL 的位置

        pop %edx
        pop %ebx
        pop %eax

        retf

# 构造存储器和系统的段描述符
# 输入：EAX=线性基地址
#       EBX=段界限
#       ECX=属性。各属性位都在原始
#           位置，无关的位清零
# 返回：EDX:EAX=描述符
make_seg_descriptor:
        # 描述符前32位(EAX)构造 -- BBBB-LLLL
        mov %eax, %edx
        shl $16, %eax
        or %bx, %ax

        # 高 32 位 -- BBRL-RRBB
        and $0xffff0000, %edx
        rol $8, %edx
        bswap %edx

        xor %bx, %bx # ebx 仅保留 19~16 位
        or %ebx, %edx

        or %ecx, %edx # 装配属性

        retf

# 构造门的描述符（调用门等）
# 输入：EAX=门代码在段内偏移地址
#        BX=门代码所在段的选择子
#        CX=段类型及属性等（各属性位都在原始位置）
# 返回：EDX:EAX=完整的描述符
make_gate_descriptor:
        push %ebx
        push %ecx

        # Gate 描述符的高 32 位 -- OOOO-RRRR
        mov %eax, %edx
        and $0xffff0000, %edx
        or %cx, %dx

        # Gate 描述符的低 32 位 -- SSSS-OOOO
        and $0x0000ffff, %eax
        shl $16, %ebx
        or %ebx, %eax

        pop %ecx
        pop %ebx

        retf

# 分配一个4KB的页
# 输入：无
# 输出：EAX=页的物理地址
allocate_a_4k_page:
        push %ebx
        push %ecx
        push %edx

        xor %eax, %eax
    1:
        # 看 page_bit_map 对应的位图里面索引值是 EAX 的位置是 0 还是 1
        # 无论是 0 还是 1, 都会将这一位设置到 eflags 的 CR 位
        bts %eax, page_bit_map
        jnc 2f # 说明原来 bit=0, 意味着页面空闲
        # 否则, 尝试检测下一个页面
        inc %eax
        cmp $(page_bit_len*8), %eax
        jl 1b

        # 没有可以分配的页，停机
        mov $message_3, %ebx
        call $flat_4gb_code_seg_sel, $put_string
        hlt

    2:
        # BTS 检测的是位图索引, 找到后乘以 4Kb 才是内存 frame 的地址
        shl $12, %eax # 乘以4096（0x1000）

        pop %edx
        pop %ecx
        pop %ebx

        ret

# 分配一个页, 并安装在当前活动的层级分页结构中
# 输入：EBX=页的线性地址
alloc_inst_a_page:
        push %eax
        push %ebx
        push %esi

        # 检查该线性地址所对应的页表是否存在
        # 如果 PDT 里面对应的 entry 不存在, 意味着需要创建 PDE 对应的页
        mov %ebx, %esi
        and $0xffc00000, %esi # 取高 10 位, 这 10 位指示了 PDE 的位置
        shr $20, %esi # PDE 索引 = (10bit >> 22) * 4 = (10bit >> 20)
        or $0xfffff000, %esi # **PDE 条目自身** 对应的线性地址

        testl $0x00000001, (%esi)
        jnz 1f # 说明 P=1, 页面存在

        # 否则, 创建该线性地址所对应的页表
        call allocate_a_4k_page # 分配一个页做为页表
        or $0x00000007, %eax # P=1, RW=1, US=1
        mov %eax, (%esi) # 写 PDE 对应的记录

    1:
        # 维护 页目录, 页表的关系
        # 核心想法就是:
        # 为了能修改页表, 我们需要:
        #   1. 把页表自己当做普通数据页使用
        #   2. 为了把页表当做普通数据页, 需要找到页表的页表(也就是页目录), 因此需要把页目录当做页表使用
        #   3. 为了把页目录当做页表使用, 需要线性地址的高 10 位内容指向页目录自己
        #   4. 之前在 PDT 里面, 设置了最后一个元素(第 1023 项)指向的是 PDT 自己
        #   5. 因此我们需要构造一个线性地址, 它的:
        #       a. 高位是 0xCFF
        #       b. 中间十位是 EBX 的高 10 位 也即: EBX[31:22]
        #       c. 低 12 位是 EBX 的中间 10 位, 乘以 4. 也即 EBX[21:12]+00
        #       d. 注意中间 10 位没有乘 4, 是 MMU 自动做了
        # 经过如此设置之后:
        #   1. 线性地址高十位定位到 PDT
        #   2. 中间十位定位到 EBX 对应的一级页表
        #   3. 最后 12 位定位到一级页表里面的页表项 -- 我们需要修改的正是这个项
        # ------------------------------------------------------------
        # 下面是一个比较简洁的实现:
        # ```asm
        #  mov %ebx, %esi
        #  and $0xFFFFF000, %esi
        #  shr $10, %esi
        #  or $0xCFF00000, %esi
        # ```

        # ---------------------------------------------
        # ESI =     AAAAAAAAAA_BBBBBBBBBB_CCCCCCCCCC_CC
        # SHR 10    0000000000_AAAAAAAAAA_BBBBBBBBBB_CC
        # AND       0000000000_1111111111_0000000000_00
        #         = 0000000000_AAAAAAAAAA_0000000000_00
        # OR        1111111111_0000000000_0000000000_00
        #         = 1111111111_AAAAAAAAAA_0000000000_00
        # 这一波操作下来, ESI 对应的就是入参 EBX 对应的线性地址在 PDT 里面的 PDE 对应的那个页表
        # 推导一下如下:
        #   1. ESI 高 10 位(1111111111), 对应 PDT 里面最后一项 PDE,
        #      指向的还是 PDT, 接下来 PDT 被当做一级页表继续使用
        #   2. ESI 中间 10 位(AAAAAAAAAA), 把 PDT 当做一级页表再次索引,
        #      找到的页表项(PTE)就是 EBX 对应的高 10 位对应的 PDE
        #   3. 因此说, ESI 现在指向的就是 EBX 对应的线性地址指向的那个页表的线性地址
        mov %ebx, %esi
        shr $10, %esi
        and $0x003ff000, %esi
        or $0xffc00000, %esi

        # 寻找页面里面对应的页表项
        # 上文已经找到了页表的线性地址, 用 EBX 的中间 10bits, 可以进一步找到 EBX 对应页面的线性地址
        # ---------------------------------------------
        # EBX =     AAAAAAAAAA_BBBBBBBBBB_CCCCCCCCCC_CC
        # AND       0000000000_1111111111_0000000000_00
        #         = 0000000000_BBBBBBBBBB_0000000000_00
        # SHR 10    0000000000_0000000000_BBBBBBBBBB_00
        # OR ESI    1111111111_AAAAAAAAAA_0000000000_00
        #         = 1111111111_AAAAAAAAAA_BBBBBBBBBB_00
        # 这一波操作下来, ESI 对应的就是入参 EBX 对应的线性地址在自己页表里面的 PTE 对应的那个页
        # 推导一下如下:
        #   1. 上文已经说过, EBX 中间 10 位是 EBX 指向的一级页表中的索引
        #   2. 因为 1111111111_AAAAAAAAAA 已经定位到了这个以及页表,
        #      后面加上 BBBBBBBBBB * 4 就能得到在这个一级页表中的索引位置
        #   3. 因此现在 ESI 里面保存的就是指向 EBX 的那个一级页表项(PTE)对应的线性地址
        and $0x003ff000, %ebx
        shr $10, %ebx
        or %ebx, %esi # ESI = 页表项的线性地址
        call allocate_a_4k_page # 分配一个页，这才是要安装的页
        # EAX = 页面的物理地址
        or $0x00000007, %eax
        mov %eax, (%esi) # 安装到对应的位置

        pop %esi
        pop %ebx
        pop %eax

        retf

# 创建新页目录，并复制当前页目录内容
# 输入：无
# 输出：EAX=新页目录的物理地址
create_copy_cur_pdir:
        push %esi
        push %edi
        push %ebx
        push %ecx

        # 分配 4K 页面, 作为新的 PDT
        call allocate_a_4k_page
        # EAX = 页面的物理地址
        mov %eax, %ebx
        or $0x00000007, %ebx
        mov %ebx, 0xfffffff8 # 更新倒数第二个条目为这个新 PDT 的线性地址

        # 刷新 TLB, TODO: ??? why 现在还没有重载 CR3=PDBR 呢?
        invlpg 0xfffffff8

        mov $0xfffff000, %esi # ESI->当前页目录的线性地址
        mov $0xffffe000, %edi # EDI->新页目录的线性地址
        mov $1024, %ecx # ECX=要复制的目录项数
        cld
        rep movsl

        pop %ecx
        pop %ebx
        pop %edi
        pop %esi

        retf

# 通用的中断处理过程
general_interrupt_handler:
        push %eax

        mov $0x20, %al # 中断结束命令EOI
        out %al, $0xa0 # 向从片发送
        out %al, $0x20 # 向主片发送

        pop %eax

        iret

# 通用的异常处理过程
general_exception_handler:
        mov $excep_msg, %ebx
        call $flat_4gb_code_seg_sel, $put_string

        hlt

# 实时时钟中断处理过程
# 函数内容是遍历 TCB 链表:
#   1. 找到正在执行的任务, 把它挂到链尾
#   2. 找到第一个空闲任务, 把它运行起来
rtm_0x70_interrupt_handle:
        pusha

        mov $0x20, %al # 中断结束命令EOI
        out %al, $0xa0 # 向从片发送
        out %al, $0x20 # 向主片发送

        # 此处不考虑闹钟和周期性中断的情况
        mov $0x0c, %al # 寄存器C的索引。且开放NMI
        out %al, $0x70
        in $0x71, %al # 读一下RTC的寄存器C，否则只发生一次中断

        # TSS 结构
        #   0x18  -->  TSS选择子
        #   0x14  -->  TSS的线性地址
        #   0x12  -->  TSS界限值
        #   0x10  -->  LDT选择子
        #   0x0C  -->  LDT的线性地址
        #   0x0A  -->  LDT当前界限值
        #   0x06  -->  下一个可用的线性地址(4KB边界)
        #   0x04  -->  任务状态
        #   0x00  -->  下一个TCB基地址

        # 找当前任务（状态为忙的任务）在链表中的位置
        # EAX=链表头或当前TCB线性地址
        # EBX=下一个TCB线性地址
        # ------- 用 C 语言的角度理解 EAX, EBX ------------
        # EAX = (Node **)
        # EBX = (Node *)
        # (EBX + 0) = (Next Node **)
        mov $tcb_chain, %eax
    0:
        mov (%eax), %ebx
        or %ebx, %ebx
        jz .irtn # 链表为空，或已到末尾，从中断返回
        cmpw $0xffff, 0x04(%ebx) # TCB+0x04 是任务是否是当前任务的记录
        je 1f # 是忙任务（当前任务）？
        # 否则继续找, 一直到找到当前任务
        mov %ebx, %eax
        jmp 0b
    1:
        # 将当前为忙的任务移到链尾
        # EBX=(Node *) 指向当前忙的 TCB
        # (EBX+0)=(Node **) 指向再下一个 TCB
        # EAX=(Node **) 本来指向的是当前忙 TCB, 这里将它指向再下一个
        mov (%ebx), %ecx # node = p->next; 下游 TCB 的线性地址
        mov %ecx, (%eax) # 将当前任务从链中拆除
    2:
        # 从 1 部分处理完之后
        # EBX = (Node *), 当前忙的 TCB
        # EAX = (Node **), 原来链表里面当前忙的 TCB 的下一个节点
        # -------
        # 本部分循环
        # EBX 没有变化
        # EAX = (Node **), TCB 链里面的下一个节点
        mov (%eax), %edx # EDX = (Node *) TCB 链里面的下一个节点
        or %edx, %edx
        jz 3f # 已到链表尾端?
        # 否则, 遍历下一个节点
        mov %edx, %eax
        jmp 2b
    3:
        # 从 2 部分处理完之后
        # EBX = (Node *), 当前忙的 TCB
        # EAX = (Node **), 链表最后一个节点
        mov %ebx, (%eax) # 将忙任务的TCB挂在链表尾端
        movl $0x0, (%ebx) # 将忙任务的TCB标记为链尾

        # ------- 上面是吧 忙 任务移动到链表尾部
        # ------- 下面要调度执行第一个不忙的任务

        # 从链首搜索第一个空闲任务, 准备调度执行它
        mov $tcb_chain, %eax
    4:
        mov (%eax), %eax
        or %eax, %eax
        jz .irtn # 已到链尾（未发现空闲任务）
        cmpw $0x0, 0x04(%eax) # 否则检查任务是不是忙
        # cmp 相减操作, 0 - (0 不忙) == 0, ZF=1
        # ZF=1 不忙调度执行这个不忙的任务
        # ZF=0 忙直接跳转到循环开始, 再找
        jnz 4b

        # 将空闲任务和当前任务的状态都取反
        notw 0x04(%eax)
        notw 0x04(%ebx)

        ljmp *0x14(%eax)

   .irtn:
        popa

        iret

# 终止当前任务
# 注意，执行此例程时，当前任务仍在运行中。此例程其实也是当前任务的一部分
terminate_current_task:
        # 找当前任务（状态为忙的任务）在链表中的位置
        # EAX=链表头或当前TCB线性地址
        mov $tcb_chain, %eax
    0:
        mov (%eax), %ebx # EBX=(Node *) 当前循环体 TCB 的指针
        cmpw $0xffff, 0x04(%ebx) # 是忙任务（当前任务）？
        je 1f
        mov %ebx, %eax # 定位到下一个TCB（的线性地址）
        jmp 0b

    1:
        movw $0x3333, 0x04(%ebx) # 修改当前任务的状态为“退出”

    2:
        hlt # 停机，等待程序管理器恢复运行时，将其回收
        jmp 2b

# ------------------------- data define

        pgdt: .word 0 # 用于设置和修改 GDT
              .long 0

        pidt: .word 0
              .long 0

        # 任务控制块链
        tcb_chain: .long 0

        core_tcb: .fill 32, 1, 0x00 # 内核（程序管理器）的TCB

        page_bit_map: .byte 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x55, 0x55
                      .byte 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff
                      .byte 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff
                      .byte 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff
                      .byte 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55
                      .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
                      .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
                      .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00

        page_bit_len = . - page_bit_map

        salt:
        salt_1: .ascii  "@PrintString"
                . = salt_1 + 256
                .long put_string
                .word flat_4gb_code_seg_sel

        salt_2: .ascii  "@ReadDiskData"
                . = salt_2 + 256
                .long read_hard_disk_0
                .word flat_4gb_code_seg_sel

        salt_3: .ascii "@PrintDwordAsHexString"
                . = salt_3 + 256
                .long put_hex_dword
                .word flat_4gb_code_seg_sel

        salt_4: .ascii "@TerminateProgram"
                . = salt_4 + 256
                .long terminate_current_task
                .word flat_4gb_code_seg_sel

        salt_item_len   = . - salt_4
        salt_items      = (. - salt) / salt_item_len

        excep_msg: .asciz  "********Exception encounted********"

        message_0: .ascii  "  Working in system core with protection "
                   .ascii  "and paging are all enabled.System core is mapped "
                   .ascii  "to address 0x80000000.",
                   .byte 0x0d, 0x0a, 0x00

        message_1: .ascii "  System wide CALL-GATE mounted.",
                   .byte 0x0d, 0x0a, 0

        message_3: .asciz "********No more pages********"

        core_msg0: .ascii "  System core task running!",
                   .byte 0x0d, 0x0a, 0

        # put_hex_dword 子过程用的查找表
        bin_hex: .ascii "0123456789ABCDEF"

        core_buf: .fill 512, 1, 0 # 内核用的缓冲区

        cpu_brnd0: .byte 0x0d, 0x0a, 0x20, 0x20, 0
        cpu_brand: .fill 52, 1, 0
        cpu_brnd1: .byte 0x0d, 0x0a, 0x0d, 0x0a, 0

# ----------------------------------------

# 在LDT内安装一个新的描述符
# 输入：EDX:EAX=描述符
#           EBX=TCB基地址
# 输出：CX=描述符的选择子
fill_descriptor_in_ldt:
        push %eax
        push %edx
        push %edi

        # 获得LDT基地址
        mov 0x0c(%ebx), %edi
        xor %ecx, %ecx

        mov 0x0a(%ebx), %cx # 获得LDT界限
        inc %cx # LDT的总字节数，即新描述符偏移地址

        # 安装描述符
        mov %eax, (%edi, %ecx, 1)
        mov %edx, 0x4(%edi, %ecx, 1)

        add $8, %cx
        dec %cx # 得到新的LDT界限值

        mov %cx, 0x0a(%ebx) # 更新新的 LDT 界限到 TCB

        # 得到这个描述符的选择子, 放在 CX 返回
        mov %cx, %ax
        xor %dx, %dx
        mov $8, %cx
        div %cx

        mov %ax, %cx
        shl $3, %cx
        or $0b0000000000000100, %cx # TI=1~LDT

        pop %edi
        pop %edx
        pop %eax

        ret

# 加载并重定位用户程序
# 输入: PUSH 逻辑扇区号
#       PUSH 任务控制块基地址
# 输出：无
load_relocate_program:
        pusha

        # !(AX, CX, DX, BX, SP, BP, SI, DI), IP, TCB, SECT

        # 为访问通过堆栈传递的参数做准备
        mov %esp, %ebp

        # 清空当前页目录的前半部分（对应低2GB的局部地址空间）
        mov $0xfffff000, %ebx
        xor %esi, %esi
    1:
        movl $0x0, (%ebx, %esi, 4)
        inc %esi
        cmp $512, %esi
        jl 1b

        # 刷新TLB
        mov %cr3, %eax
        mov %eax, %cr3

        mov 40(%ebp), %eax # 从堆栈中取出用户程序起始扇区号
        mov $core_buf, %ebx # 读取程序头部数据
        call $flat_4gb_code_seg_sel, $read_hard_disk_0

        # 以下判断整个程序有多大
        mov core_buf, %eax
        mov %eax, %ebx
        and $0xfffff000, %ebx # 准备 4K 对齐
        add $0x1000, %ebx
        # NZ ==> (eax & FFF != 0) ==> EAX 不是 4K 对齐的
        test $0xfff, %eax # 程序的大小正好是4KB的倍数吗?
        cmovnz %ebx, %eax # 不是。使用凑整的结果

        # 判断需要读入的页数, 开始循环
        mov %eax, %ecx
        shr $12, %ecx # 程序占用的总4KB页数

        mov 40(%ebp), %eax # 起始扇区号
        mov 36(%ebp), %esi # 从堆栈中取得TCB的基地址
    2:
        # 分配一页
        alloc_user_linear # 宏: 在用户任务地址空间上分配内存, EBX 有分配到的内存地址

        # 循环读取, 把这一页读满
        push %ecx
        mov $8, %ecx
    3:
        call $flat_4gb_code_seg_sel, $read_hard_disk_0
        inc %eax
        loop 3b

        pop %ecx
        loop 2b

        # 在内核地址空间内创建用户任务的TSS
        # 用户任务的TSS必须在全局空间上分配
        alloc_core_linear
        mov %ebx, 0x14(%esi) # 在TCB中填写TSS的线性地址
        movw $103, 0x12(%esi) # 在TCB中填写TSS的界限值

        # 在用户任务的局部地址空间内创建 LDT
        alloc_user_linear
        mov %ebx, 0x0c(%esi) # 填写LDT线性地址到TCB中

        # 建立程序代码段描述符
        # g_db_l_avl = 1100, p_dpl_s_type=1_11_1_1000
        mov $0x00000000, %eax
        mov $0x000fffff, %ebx
        mov $0x00c0f800, %ecx # 4Kb, 32-bits, code seg, dpl=3
        call $flat_4gb_code_seg_sel, $make_seg_descriptor
        mov %esi, %ebx # TCB的基地址
        call fill_descriptor_in_ldt
        or $0b0000000000000011, %cx # 设置选择子的特权级为3

        mov 0x14(%esi), %ebx # 从TCB中获取TSS的线性地址
        mov %cx, 76(%ebx) # 填写TSS的CS域

        # 建立程序数据段描述符
        # g_db_l_avl = 1100, p_dpl_s_type=1_11_1_0010
        mov $0x00000000, %eax
        mov $0x000fffff, %ebx
        mov $0x00c0f200, %ecx # 4Kb, 32-bits, data seg, dpl=3
        call $flat_4gb_code_seg_sel, $make_seg_descriptor
        mov %esi, %ebx # TCB的基地址
        call fill_descriptor_in_ldt
        or $0x0003, %cx # 设置选择子的特权级为3

        mov 0x14(%esi), %ebx # 从TCB中获取TSS的线性地址
        mov %cx, 84(%ebx) # 填写TSS的DS域
        mov %cx, 72(%ebx) # 填写TSS的ES域
        mov %cx, 88(%ebx) # 填写TSS的FS域
        mov %cx, 92(%ebx) # 填写TSS的GS域

        # 将数据段作为用户任务的3特权级固有堆栈
        alloc_user_linear
        mov 0x14(%esi), %ebx # 从TCB中获取TSS的线性地址
        mov %cx, 80(%ebx) # 填写TSS的SS域
        mov 0x06(%esi), %edx # 堆栈的高端线性地址
        mov %edx, 56(%ebx) # 填写TSS的ESP域


        # 在用户任务的局部地址空间内创建0特权级堆栈
        # g_db_l_avl = 1100, p_dpl_s_type=1_00_1_0010
        alloc_user_linear
        mov $0x00000000, %eax
        mov $0x000fffff, %ebx
        mov $0x00c09200, %ecx # 4KB粒度的堆栈段描述符，特权级0
        call $flat_4gb_code_seg_sel, $make_seg_descriptor
        mov %esi, %ebx # TCB的基地址
        call fill_descriptor_in_ldt
        or $0x0000, %cx # 设置选择子的特权级为0

        mov 0x14(%esi), %ebx # 从TCB中获取TSS的线性地址
        mov %cx, 8(%ebx) # 填写TSS的SS0域
        mov 0x06(%esi), %edx # 堆栈的高端线性地址
        mov %edx, 4(%ebx) # 填写TSS的ESP0域

        # 在用户任务的局部地址空间内创建1特权级堆栈
        alloc_user_linear
        mov $0x00000000, %eax
        mov $0x000fffff, %ebx
        mov $0x00c0b200, %ecx # 4KB粒度的堆栈段描述符，特权级1
        call $flat_4gb_code_seg_sel, $make_seg_descriptor
        mov %esi, %ebx # TCB的基地址
        call fill_descriptor_in_ldt
        or $0x0001, %cx # 设置选择子的特权级为1

        mov 0x14(%esi), %ebx # 从TCB中获取TSS的线性地址
        mov %cx, 16(%ebx) # 填写TSS的SS1域
        mov 0x06(%esi), %edx # 堆栈的高端线性地址
        mov %edx, 12(%ebx) # 填写TSS的ESP1域

        # 在用户任务的局部地址空间内创建2特权级堆栈
        alloc_user_linear
        mov $0x00000000, %eax
        mov $0x000fffff, %ebx
        mov $0x00c0d200, %ecx # 4KB粒度的堆栈段描述符，特权级2
        call $flat_4gb_code_seg_sel, $make_seg_descriptor
        mov %esi, %ebx # TCB的基地址
        call fill_descriptor_in_ldt
        or $0x0002, %cx # 设置选择子的特权级为2

        mov 0x14(%esi), %ebx # 从TCB中获取TSS的线性地址
        mov %cx, 24(%ebx) # 填写TSS的SS2域
        mov 0x06(%esi), %edx # 堆栈的高端线性地址
        mov %edx, 20(%ebx) # 填写TSS的ESP2域

        # 重定位U-SALT
        cld

        mov 0x0c, %ecx # U-SALT条目数
        mov 0x08, %edi # U-SALT在4GB空间内的偏移
    4:
        push %ecx
        push %edi

        mov $salt_items, %ecx
        mov $salt, %esi
    5:
        push %edi
        push %esi
        push %ecx
        mov $64, %ecx # 检索表中，每条目的比较次数
        repe cmpsl # 每次比较4字节

        jnz 6f # NZ 意味着不匹配 (cmp 使用减法)
        mov (%esi), %eax # 若匹配，则esi恰好指向其后的地址(偏移地址+选择子)
        mov %eax, -256(%edi) # 将字符串改写成偏移地址
        mov 4(%esi), %ax
        or $0x0003, %ax # 以用户程序自己的特权级使用调用门, 故RPL=3
        mov %ax, -252(%edi) # 回填调用门选择子
    6:
        pop %ecx
        pop %esi
        add $salt_item_len, %esi
        pop %edi # 从头比较
        loop 5b

        pop %edi
        add $256, %edi
        pop %ecx
        loop 4b

        # 在GDT中登记LDT描述符
        mov 36(%ebp), %esi # 从堆栈中取得TCB的基地址
        mov 0x0c(%esi), %eax # LDT的起始线性地址
        movzwl 0x0a(%esi), %ebx # LDT段界限
        mov $0x00408200, %ecx # LDT描述符，特权级0
        call $flat_4gb_code_seg_sel, $make_seg_descriptor
        call $flat_4gb_code_seg_sel, $set_up_gdt_descriptor
        mov %cx, 0x10(%esi) # 登记LDT选择子到TCB中

        mov 0x14(%esi), %ebx # 从TCB中获取TSS的线性地址
        mov %cx, 96(%ebx) # 填写TSS的LDT域
        movw $0, (%ebx) # TSS 反向链=0

        mov 0x12(%esi), %dx # 段长度（界限）
        mov %dx, 102(%ebx) # 填写TSS的I/O位图偏移域

        movw $0, 100(%ebx) # T=0

        mov 0x04, %eax # 从任务的4GB地址空间获取入口点
        mov %eax, 32(%ebx) # 填写TSS的EIP域

        # 填写TSS的EFLAGS域
        pushf
        pop %edx
        mov %edx, 36(%ebx)

        # 在GDT中登记TSS描述符
        mov 0x14(%esi), %eax # 从TCB中获取TSS的起始线性地址
        movzwl 0x12(%esi), %ebx # 段长度（界限）
        mov $0x00408900, %ecx # TSS描述符，特权级0
        call $flat_4gb_code_seg_sel, $make_seg_descriptor
        call $flat_4gb_code_seg_sel, $set_up_gdt_descriptor
        mov %cx, 0x18(%esi) # 登记TSS选择子到TCB

        # 创建用户任务的页目录
        # 注意！页的分配和使用是由页位图决定的，可以不占用线性地址空间
        call $flat_4gb_code_seg_sel, $create_copy_cur_pdir
        mov 0x14(%esi), %ebx # 从TCB中获取TSS的线性地址
        movl %eax, 28(%ebx) # 填写TSS的CR3(PDBR)域

        popa

        ret $8 # 丢弃调用本过程前压入的参数

        # TSS 结构
        #   0x18  -->  TSS选择子
        #   0x14  -->  TSS的线性地址
        #   0x12  -->  TSS界限值
        #   0x10  -->  LDT选择子
        #   0x0C  -->  LDT的线性地址
        #   0x0A  -->  LDT当前界限值
        #   0x06  -->  下一个可用的线性地址(4KB边界)
        #   0x04  -->  任务状态
        #   0x00  -->  下一个TCB基地址

# 在TCB链上追加任务控制块
# 输入：ECX=TCB线性基地址
append_to_tcb_link:
        cli

        push %eax
        push %ebx

        mov $tcb_chain, %eax
    0:
        # EAX=链表头或当前TCB线性地址
        mov (%eax), %ebx # EBX=下一个TCB线性地址
        or %ebx, %ebx
        jz 1f # 链表为空，或已到末尾
        mov %ebx, %eax # 定位到下一个TCB（的线性地址）
        jmp 0b
    1:
        mov %ecx, (%eax)
        movl $0, (%ecx) # 当前TCB指针域清零，以指示这是最后一个TCB

        pop %ebx
        pop %eax

        sti

        ret

_start:
        # 创建中断描述符表IDT
        # 在此之前，禁止调用put_string过程，以及任何含有sti指令的过程。

        # 前20个向量是处理器异常使用的
        # OOOO-RRXX, RR=p_dpl_s_type= 1_00_0-1100
        # SSSS-OOOO
        mov $general_exception_handler, %eax # 门代码在段内偏移地址
        mov $flat_4gb_code_seg_sel, %bx # 门代码所在段的选择子
        mov $0x8e00, %cx # 32位中断门，0特权级
        call $flat_4gb_code_seg_sel, $make_gate_descriptor

        mov $idt_linear_address, %ebx # 中断描述符表的线性地址
        xor %esi, %esi
    0:
        mov %eax, (%ebx, %esi, 8)
        mov %edx, 4(%ebx, %esi, 8)
        inc %esi
        cmp $19, %esi # 安装前20个异常中断处理过程
        jle 0b

        # 其余为保留或硬件使用的中断向量
        mov $general_interrupt_handler, %eax # 门代码在段内偏移地址
        mov $flat_4gb_code_seg_sel, %bx # 门代码所在段的选择子
        mov $0x8e00, %cx # 32位中断门，0特权级
        call $flat_4gb_code_seg_sel, $make_gate_descriptor

        mov $idt_linear_address, %ebx # 中断描述符表的线性地址
    1:
        mov %eax, (%ebx, %esi, 8)
        mov %edx, 4(%ebx, %esi, 8)
        inc %esi
        cmp $255, %esi # 安装普通的中断处理过程
        jle 1b

        # 设置实时时钟中断处理过程
        mov $rtm_0x70_interrupt_handle, %eax # 门代码在段内偏移地址
        mov $flat_4gb_code_seg_sel, %bx # 门代码所在段的选择子
        mov $0x8e00, %cx # 32位中断门，0特权级
        call $flat_4gb_code_seg_sel, $make_gate_descriptor

        mov $idt_linear_address, %ebx # 中断描述符表的线性地址
        mov %eax, (0x70*8)(%ebx)
        mov %edx, (0x70*8+4)(%ebx)

        # 准备开放中断
        movw $(256*8-1), pidt # IDT的界限
        movl $idt_linear_address, pidt+2
        lidt pidt # 加载中断描述符表寄存器IDTR

        # 设置8259A中断控制器
        mov $0x11, %al
        out %al, $0x20 # ICW1：边沿触发/级联方式
        mov $0x20, %al
        out %al, $0x21 # ICW2:起始中断向量
        mov $0x04, %al
        out %al, $0x21 # ICW3:从片级联到IR2
        mov $0x01, %al
        out %al, $0x21 # ICW4:非总线缓冲，全嵌套，正常EOI

        mov $0x11, %al
        out %al, $0xa0 # ICW1：边沿触发/级联方式
        mov $0x70, %al
        out %al, $0xa1 # ICW2:起始中断向量
        mov $0x04, %al
        out %al, $0xa1 # ICW3:从片级联到IR2
        mov $0x01, %al
        out %al, $0xa1 # ICW4:非总线缓冲，全嵌套，正常EOI

        # 设置和时钟中断相关的硬件
        mov $0x0b, %al # RTC寄存器B
        or $0x80, %al # 阻断NMI
        out %al, $0x70
        mov $0x12, %al # 设置寄存器B，禁止周期性中断，开放更
        out %al, $0x71 # 新结束后中断，BCD码，24小时制

        in $0xa1, %al # 读8259从片的IMR寄存器
        and $0xfe, %al # 清除bit 0(此位连接RTC)
        out %al, $0xa1 # 写回此寄存器

        mov $0x0c, %al
        out %al, $0x70
        in $0x71, %al # 读RTC寄存器C，复位未决的中断状态

        sti # 开放硬件中断

        mov $message_0, %ebx
        call $flat_4gb_code_seg_sel, $put_string

        # 显示处理器品牌信息
        mov $0x80000002, %eax
        cpuid
        mov %eax, (cpu_brand + 0x00)
        mov %ebx, (cpu_brand + 0x04)
        mov %ecx, (cpu_brand + 0x08)
        mov %edx, (cpu_brand + 0x0c)

        mov $0x80000003, %eax
        cpuid
        mov %eax, (cpu_brand + 0x10)
        mov %ebx, (cpu_brand + 0x14)
        mov %ecx, (cpu_brand + 0x18)
        mov %edx, (cpu_brand + 0x1c)

        mov $0x80000004, %eax
        cpuid
        mov %eax, (cpu_brand + 0x20)
        mov %ebx, (cpu_brand + 0x24)
        mov %ecx, (cpu_brand + 0x28)
        mov %edx, (cpu_brand + 0x2c)

        # 显示处理器品牌信息
        mov $cpu_brnd0, %ebx
        call $flat_4gb_code_seg_sel, $put_string
        mov $cpu_brand, %ebx
        call $flat_4gb_code_seg_sel, $put_string
        mov $cpu_brnd1, %ebx
        call $flat_4gb_code_seg_sel, $put_string

        # 以下开始安装为整个系统服务的调用门。特权级之间的控制转移必须使用门
        mov $salt, %edi # C-SALT表的起始位置
        mov $salt_items, %ecx # C-SALT表的条目数量
  .b4:
        push %ecx
        mov 256(%edi), %eax # 该条目入口点的32位偏移地址
        mov 260(%edi), %bx # 该条目入口点的段选择子
        mov $0xec00, %cx # 特权级3的调用门(3以上的特权级才允许访问)，0个参数(因为用寄存器传递参数，而没有用栈)
        call $flat_4gb_code_seg_sel, $make_gate_descriptor
        call $flat_4gb_code_seg_sel, $set_up_gdt_descriptor
        mov %cx, 260(%edi) # 将返回的门描述符选择子回填
        add $salt_item_len, %edi # 指向下一个C-SALT条目
        pop %ecx
        loop .b4

        # 对门进行测试
        mov $message_1, %ebx
        lcall *(salt_1+256) # 通过门显示信息(偏移量将被忽略)

        # 初始化创建程序管理器任务的任务控制块TCB
        movw $0xffff, (core_tcb+0x04) # 任务状态：忙碌
        movl $0x80100000, (core_tcb+0x06) # 内核虚拟空间的分配从这里开始。
        movw $0xffff, (core_tcb+0x0a) # 登记LDT初始的界限到TCB中（未使用）
        mov $core_tcb, %ecx
        call append_to_tcb_link # 将此TCB添加到TCB链中

        # 为程序管理器的TSS分配内存空间
        alloc_core_linear

        # 在程序管理器的TSS中设置必要的项目
        movw $0, 0(%ebx)                 # 反向链=0
        mov %cr3, %eax
        movl %eax, 28(%ebx)             # 登记CR3(PDBR)
        movw $0, 96(%ebx)                # 没有LDT。处理器允许没有LDT的任务。
        movw $0, 100(%ebx)               # T=0
        movw $103, 102(%ebx)             # 没有I/O位图。0特权级事实上不需要。

        # 创建程序管理器的TSS描述符，并安装到GDT中
        mov %ebx, %eax                        # TSS的起始线性地址
        mov $103, %ebx                        # 段长度（界限）
        mov $0x00408900, %ecx                 # TSS描述符，特权级0
        call $flat_4gb_code_seg_sel, $make_seg_descriptor
        call $flat_4gb_code_seg_sel, $set_up_gdt_descriptor
        mov %cx, (core_tcb+0x18)             # 登记内核任务的TSS选择子到其TCB

        # 任务寄存器TR中的内容是任务存在的标志，该内容也决定了当前任务是谁。
        # 下面的指令为当前正在执行的0特权级任务“程序管理器”后补手续（TSS）。
        ltr %cx

        # 现在可认为“程序管理器”任务正执行中

        # 创建用户任务的任务控制块
        alloc_core_linear
        movw $0, 0x04(%ebx) # 任务状态：空闲
        movl $0, 0x06(%ebx) # 用户任务局部空间的分配从0开始。
        movw $0xffff, 0x0a(%ebx) # 登记LDT初始的界限到TCB中

        push $50                      # 用户程序位于逻辑50扇区
        push %ebx                           # 压入任务控制块起始线性地址
        call load_relocate_program
        mov %ebx, %ecx
        call append_to_tcb_link            # 将此TCB添加到TCB链中

        # 创建用户任务的任务控制块
        alloc_core_linear
        movw $0, 0x04(%ebx) # 任务状态：空闲
        movl $0, 0x06(%ebx) # 用户任务局部空间的分配从0开始。
        movw $0xffff, 0x0a(%ebx) # 登记LDT初始的界限到TCB中

        push $100                     # 用户程序位于逻辑100扇区
        push %ebx                           # 压入任务控制块起始线性地址
        call load_relocate_program
        mov %ebx, %ecx
        call append_to_tcb_link            # 将此TCB添加到TCB链中

    .core:
        mov $core_msg0, %ebx
        call $flat_4gb_code_seg_sel, $put_string

        # 这里可以编写回收已终止任务内存的代码
        jmp .core

core_end: