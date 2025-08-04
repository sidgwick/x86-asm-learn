.code32

.section .data

.section .text

.global _start
_start:
        push $3 # 第二个参数
        push $2 # 第一个参数
        call power
        add $8, %esp # C-Call 约定
        
        push %eax # 保存第一次结果的答案

        push $2
        push $5
        call power
        add $8, %esp

        pop %ebx
        add %eax, %ebx

        mov $1, %eax # exit call
        int $0x80

.type power, @function
power:
        push %ebp
        mov %esp, %ebp # 函数序言

        # 本地变量空间
        sub $4, %esp

        # 取得参数(栈上依次是: RES, BP, IP, ARG1, ARG2. 注意BP寄存器也指向保存 BP 的那个单元, SP 指向 RES)
        mov 8(%ebp), %ebx
        mov 12(%ebp), %ecx

        mov %ebx, -4(%ebp) # RES 中保存 '第一个乘数'

    power_loop_start:
        cmp $1, %ecx
        je end_power

        mov -4(%ebp), %eax
        imul %ebx, %eax
        mov %eax, -4(%ebp)
        dec %ecx

        jmp power_loop_start

    end_power:
        mov -4(%ebp), %eax
        mov %ebp, %esp
        pop %ebp

        ret

