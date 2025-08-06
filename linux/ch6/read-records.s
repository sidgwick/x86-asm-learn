.include "linux.s"
.include "record-def.s"

.section .data
    file_name: .asciz "test.dat"

.section .bss
    .lcomm record_buffer, RECORD_SIZE

.section .text

# 打印 string 字段
.type print_string_field, @function
print_string_field:
        .equ FIELD_OFFSET, 8
        .equ BUFFER_OFFSET, 12
        .equ OUTPUT_FD_OFFSET, 16

        push %ebp
        mov %esp, %ebp

        mov BUFFER_OFFSET(%esp), %ebx
        add FIELD_OFFSET(%esp), %ebx

        # 先找找打印长度
        pushl %ebx
        call count_chars
        pop %ebx

        # 打印具体内容
        movl %eax, %edx # 长度
        movl %ebx, %ecx # content buffer
        movl OUTPUT_FD_OFFSET(%esp), %ebx
        movl $SYS_WRITE, %eax
        int $LINUX_SYSCALL

        # 输出换行符
        pushl OUTPUT_FD_OFFSET(%esp)
        call write_newline
        addl $4, %esp

        mov %ebp, %esp
        pop %ebp

        ret

#主程序
.globl _start
_start:
        #这些是我们将存储输入输出描述符的栈位置
        #仅供参考:也可以用一个.data段中的内存地址代替
        .equ ST_INPUT_DESCRIPTOR, -4
        .equ ST_OUTPUT_DESCRIPTOR, -8

        movl %esp, %ebp #复制栈指针到%ebp
        subl $8, %esp #为保存文件描述符分配空间

        movl $SYS_OPEN, %eax #打开文件
        movl $file_name, %ebx
        movl $0, %ecx #表示只读打开
        movl $0666, %edx
        int $LINUX_SYSCALL

        #保存文件描述符
        movl %eax, ST_INPUT_DESCRIPTOR(%ebp)
        # 即使输出文件描述符是常数, 我们也将其保存到本地变量, 这样如果稍后
        # 决定不将其输出到 STDOUT, 很容易加以更改
        movl $STDOUT, ST_OUTPUT_DESCRIPTOR(%ebp)

    record_read_loop:
        pushl ST_INPUT_DESCRIPTOR(%ebp)
        pushl $record_buffer
        call read_record
        addl $8, %esp
        # 返回读取的字节数
        # 如果字节数与我们请求的字节数不同, 说明已到达文件结束处或出现错误, 我们就要退出
        cmpl $RECORD_SIZE, %eax
        jne finished_reading

        # 打印信息
        push ST_OUTPUT_DESCRIPTOR(%ebp)
        push $record_buffer
        push $RECORD_FIRSTNAME
        call print_string_field
        addl $4, %esp

        push $RECORD_LASTNAME
        call print_string_field
        addl $4, %esp

        push $RECORD_ADDRESS
        call print_string_field
        addl $4, %esp

        jmp record_read_loop

    finished_reading:
        movl $SYS_EXIT, %eax
        movl $0, %ebx
        int $LINUX_SYSCALL
