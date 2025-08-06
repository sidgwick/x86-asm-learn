#目的:对字符进行计数,直到遇到空字符
#
#输入:字符串地址
#
#输出:将计数值返回到%eax
#
#过程:
#   用到的寄存器:
#       %ecx - 字符计数
#       %al - 当前字符
#       %edx - 当前字符地址
.type count_chars, @function
.globl count_chars

#这是我们的一个参数在栈上的位置
.equ ST_STRING_START_ADDRESS, 8

count_chars:
        pushl %ebp
        movl %esp, %ebp

        movl $0, %ecx # 计数器从0开始
        # 数据的起始地址
        movl ST_STRING_START_ADDRESS(%ebp), %edx
    count_loop_begin:
        movb (%edx), %al #获取当前字符
        cmpb $0, %al #是否为空字符?
        je count_loop_end #若为空字符则结束
        incl %ecx #否则,递增计数器和指针
        incl %edx
        #返回循环起始处
        jmp count_loop_begin
    count_loop_end:
        #结束循环,将计数值移入%eax并返回
        movl %ecx, %eax
        popl %ebp
        ret
