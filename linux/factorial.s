.code32

.section .data
.section .text

.global _start
.global factorial

_start:
        push $4
        call factorial
        add $4, %esp
        mov %eax, %ebx

        mov $1, %eax
        int $0x80

.type factorial, @function
factorial:
        push %ebp
        mov %esp, %ebp

        movl 8(%ebp), %eax

        # 判断入参是否等于 1
        #   如等于返回 1
        #   如不等于, 则参数减一, 重复调用 factorial, 并将结果与参数相乘
        cmp $1, %eax
        je end_factorial

        # EAX * frac(EAX - 1)
        dec %eax
        push %eax
        call factorial
        add $4, %esp
        mov 8(%ebp), %ebx
        imul %ebx, %eax

    end_factorial:
        mov %ebp, %esp
        pop %ebp

        ret
