#include <stdio.h>

int add(int a, int b) {
    int res = 0;

    asm(
        "movl %1, %%rax\n\t"
        "addl %2, %%rax\n\t"
        "movl %%rax, %0\n\t"
        : "=m"(res)
        : "m"(a), "m"(b));

    return res;
}

int main(int argc, char **argv) {
    int res = add(1, 2);
    printf("HelloWorld, result=%d\n", res);
}
