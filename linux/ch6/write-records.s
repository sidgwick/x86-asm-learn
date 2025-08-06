.include "linux.s"
.include "record-def.s"

.section .data

# 我们想写入的常量数据
# 每个数据项以空字节 0 填充到适当的长度
# .rept 用于填充每一项
# .rept告诉汇编程序将 .rept 和 .endr 之间的段重复指定次数
# 在这个程序中,此指令用于将多余的空白字符增加到每个字段末尾以将之填满

record1:
        .ascii "Fredrick\0"
        .rept 31 # 填充到40字节
        .byte 0
        .endr

        .ascii "Bartlett\0"
        .rept 31 # 填充到40字节
        .byte 0
        .endr

        .ascii "4242 S Prairie\nTulsa, OK 555555\0"
        .rept 209 #填充到240字节
        .byte 0
        .endr

        .long 45

record2:
        .ascii "Marilyn\0"
        .rept 32 #填充到40字节
        .byte 0
        .endr

        .ascii "Taylor\0"
        .rept 33 #Padding to 40 bytes
        .byte 0
        .endr

        .ascii "2224 S Johannan St\nChicago, IL 122345\0"
        .rept 203 #填充到240字节
        .byte 0
        .endr

        .long 29

record3:
        .ascii "Derrick\0"
        .rept 32 #填充到40字节
        .byte 0
        .endr

        .ascii "McIntire\0"
        .rept 31 #填充到40字节
        .byte 0
        .endr

        .ascii "500 W Oakland\nSan Diego, CA 543321\0"
        .rept 206 #填充到240字节
        .byte 0
        .endr

        .long 36

#这是我们要写入文件的文件名:
filename: .asciz "test.dat"
.equ ST_FILE_DESCRIPTOR, -4
.globl _start
_start:
    movl %esp, %ebp #复制栈指针到%ebp
    subl $4, %esp #为文件描述符分配空间

    movl $SYS_OPEN, %eax #打开文件
    movl $filename, %ebx
    movl $0101, %ecx
    movl $0666, %edx #本指令表明如文件不存在则创建, 并打开文件用于写入
    int $LINUX_SYSCALL

    #存储文件描述符
    movl %eax, ST_FILE_DESCRIPTOR(%ebp)

    # 写第一条记录
    pushl ST_FILE_DESCRIPTOR(%ebp)
    pushl $record1
    call write_record
    addl $8, %esp

    # 写第二条记录
    pushl ST_FILE_DESCRIPTOR(%ebp)
    pushl $record2
    call write_record
    addl $8, %esp

    #写第三条记录
    pushl ST_FILE_DESCRIPTOR(%ebp)
    pushl $record3
    call write_record
    addl $8, %esp

    #关闭文件描述符
    movl $SYS_CLOSE, %eax
    movl ST_FILE_DESCRIPTOR(%ebp), %ebx
    int $LINUX_SYSCALL

    #退出程序
    movl $SYS_EXIT, %eax
    movl $0, %ebx
    int $LINUX_SYSCALL
