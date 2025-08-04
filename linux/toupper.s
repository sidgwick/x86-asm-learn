.section .data

    # 系统调用号
    .equ SYS_OPEN, 5
    .equ SYS_WRITE, 4
    .equ SYS_READ, 3
    .equ SYS_CLOSE, 6
    .equ SYS_EXIT, 1

    # 文件打开模式
    .equ O_RDONLY, 0
    .equ O_CREAT_WRONLY_TRUNC, 03101

    # 标准文件描述符
    .equ STDIN, 0
    .equ STDOUT, 1
    .equ STDERR, 2

    # 系统调用中断
    .equ LINUX_SYSCALL, 0x80
    .equ END_OF_FILE, 0
    .equ NUMBER_ARGUMENTS, 2

.section .bss
    .equ BUFFER_SIZE, 500
    .lcomm BUFFER_DATA, BUFFER_SIZE

.section .text

    # 参数在栈上的位置
    .equ ST_SIZE_RESERVE, 8
    .equ ST_FD_IN, -4
    .equ ST_FD_OUT, -8
    .equ ST_ARGC, 0
    .equ ST_ARGV_0, 4
    .equ ST_ARGV_1, 8
    .equ ST_ARGV_2, 12

.global _start
_start:
        # stack 结构: agc, argv0, argv1, argv2
        mov %esp, %ebp

        # 在栈上位描述符分配空间
        sub $ST_SIZE_RESERVE, %esp
    
    open_files:

    open_fd_in:
        # open 调用
        mov $SYS_OPEN, %eax
        mov ST_ARGV_1(%ebp), %ebx
        mov $O_RDONLY, %ecx
        mov $0666, %edx
        int $LINUX_SYSCALL
    store_fd_in:
        mov %eax, ST_FD_IN(%ebp)
        

    open_fd_out:
        mov $SYS_OPEN, %eax
        mov ST_ARGV_2(%ebp), %ebx
        mov $O_CREAT_WRONLY_TRUNC, %ecx
        mov $0666, %edx
        int $LINUX_SYSCALL
    store_fd_out:
        mov %eax, ST_FD_OUT(%ebp)

    read_loop_begin:
        # 读入一块数据 - read 系统调用
        mov $SYS_READ, %eax
        mov ST_FD_IN(%ebp), %ebx
        mov $BUFFER_DATA, %ecx
        mov $BUFFER_SIZE, %edx
        int $LINUX_SYSCALL

        # eax 是读到的长度
        cmp $END_OF_FILE, %eax
        jle end_loop
    
    continue_read_loop:
        # 转换大小写
        push $BUFFER_DATA
        push %eax
        call convert_to_upper
        pop %eax
        add $4, %esp

        # 写到输出文件
        mov %eax, %edx
        mov $SYS_WRITE, %eax #####
        mov ST_FD_OUT(%ebp), %ebx
        mov $BUFFER_DATA, %ecx
        int $LINUX_SYSCALL

        jmp read_loop_begin

    end_loop:
        mov $SYS_CLOSE, %eax
        mov ST_FD_IN(%ebp), %ebx
        int $LINUX_SYSCALL

        mov $SYS_CLOSE, %eax
        mov ST_FD_OUT(%ebp), %ebx
        int $LINUX_SYSCALL

        mov $SYS_EXIT, %eax
        mov $0, %ebx
        int $LINUX_SYSCALL
        


convert_to_upper:
    .equ LOWERCASE_A, 'a'
    .equ LOWERCASE_Z, 'z'
    .equ UPPER_CONVERSION, 'A' - 'a'

    .equ ST_BUFFER_LEN, 8
    .equ ST_BUFFER, 12

        push %ebp
        mov %esp, %ebp

        mov ST_BUFFER(%ebp), %eax
        mov ST_BUFFER_LEN(%ebp), %ebx
        mov $0, %edi

        cmp $0, %ebx
        je end_convert_loop

    convert_loop:
        mov (%eax, %edi, 1), %cl
        cmpb $LOWERCASE_A, %cl
        jl next_byte
        cmpb $LOWERCASE_Z, %cl
        jg next_byte

        add $UPPER_CONVERSION, %cl
        mov %cl, (%eax, %edi, 1)

    next_byte:
        inc %edi
        cmp %edi, %ebx
        jne convert_loop

    end_convert_loop:
        mov %ebp, %esp
        pop %ebp
        
        ret
