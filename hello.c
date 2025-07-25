#include <stdio.h>

typedef struct {
    int32_t code_length; // 核心程序总长度 #00

    int32_t sys_routine_seg; // 系统公用例程段位置 #04
    int32_t core_data_seg; // 核心数据段位置 #08
    int32_t core_code_seg; // 核心代码段位置 #0c

    int32_t core_entry; // 核心代码段入口点 #10
    int16_t core_code_seg_sel; // 核心代码段选择子
} core_header_t;

typedef struct {
    int32_t previous_tss : 16; // 前一个任务的指针

    int32_t esp0; // ESP0 - 0 特权级栈指针
    int32_t ss0; // SS0 - 0 特权级栈底(高 16 位未用)
    int32_t esp1; // ESP1 - 1 特权级栈指针
    int32_t ss1; // SS1 - 1 特权级栈底(高 16 位未用)
    int32_t esp2; // ESP2 - 2 特权级栈指针
    int32_t ss2; // SS2 - 2 特权级栈底(高 16 位未用)
    int32_t cr3; // CR3(PDBR)
    int32_t eip; // EIP
    int32_t eflags; // EFLAGS

    // 注意下面一直到 EDI, 刚好就是 pushad 的压栈顺序
    int32_t eax; // EAX
    int32_t ecx; // ECX
    int32_t edx; // EDX
    int32_t ebx; // EBX
    int32_t esp; // ESP
    int32_t ebp; // EBP
    int32_t esi; // ESI
    int32_t edi; // EDI

    int32_t es; // ES(高 16 位未用)
    int32_t cs; // CS(高 16 位未用)
    int32_t ss; // SS(高 16 位未用)
    int32_t ds; // DS(高 16 位未用)
    int32_t fs; // FS(高 16 位未用)
    int32_t gs; // GS(高 16 位未用)
    int32_t ldt; // LDT(高 16 位未用)
    int32_t trace_bitmap; // Trace-Testing 标记(bit 0) 和 IO 映射基址(bit 16-31)
} tss_t;

typedef struct _tcb_t {
    struct _tcb_t *next; // 4 字节指向下一个 TCB 的指针

    int16_t state; // 当前程序状态
    int32_t load_addr; // 程序加载地址
    int16_t ldt_limit; // LDT 当前界限值
    int32_t ldt_base; // LDT 基地址
    int16_t ldt_sel; // LDT 选择子
    int16_t tss_limit; // TSS 当前界限值
    int32_t tss_base; // TSS 基地址
    int16_t tss_sel; // TSS 选择子

    int32_t stack_size_0; // 0 特权级栈以 4KB 为单位的长度
    int32_t stack_base_0; // 0 特权级栈基地址
    int16_t stack_sel_0; // 0 特权级栈选择子
    int32_t stack_pointer_0; // 0 特权级栈的初始 ESP

    int32_t stack_size_1; // 1 特权级栈以 4KB 为单位的长度
    int32_t stack_base_1; // 1 特权级栈基地址
    int16_t stack_sel_1; // 1 特权级栈选择子
    int32_t stack_pointer_1; // 1 特权级栈的初始 ESP

    int32_t stack_size_2; // 2 特权级栈以 4KB 为单位的长度
    int32_t stack_base_2; // 2 特权级栈基地址
    int16_t stack_sel_2; // 2 特权级栈选择子
    int32_t stack_pointer_2; // 2 特权级栈的初始 ESP

    int16_t header_sel; // 头部选择子
} tcb_t;

int main(int argc, char **argv) {
    printf("HelloWorld, result=%ld\n", sizeof(tss_t));
}
