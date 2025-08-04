.PHONY: clean

all:
	dd if=/dev/zero of=a.img bs=512 count=2880

	nasm -f bin -o boot.bin -l boot.lst boot.asm
	nasm -f bin -o core.bin -l core.lst core.asm
	nasm -f bin -o user1.bin -l user1.lst user1.asm
	nasm -f bin -o user2.bin -l user2.lst user2.asm

	dd if=boot.bin of=a.img bs=512 count=1 conv=notrunc
	dd if=core.bin of=a.img seek=1 bs=512 conv=notrunc
	dd if=user1.bin of=a.img seek=50 bs=512 conv=notrunc
	dd if=user2.bin of=a.img seek=55 bs=512 conv=notrunc
	dd if=diskdata.txt of=a.img seek=100 bs=512 conv=notrunc

	bochs -debugger -f bochsrc.txt

learn:
	nasm -f bin -o boot -l boot.lst boot.asm
	nasm -f bin -o boot1 -l boot1.lst boot1.asm

	ndisasm -b 16 boot > a.txt
	ndisasm -b 16 boot1 > b.txt

boot:
	-rm boot.o boot.bin
	as --32 -o boot.o boot.s
	ld -m elf_i386 -z noexecstack --oformat=binary --Ttext=0x7c00 -o boot.bin boot.o
	objdump -D -b binary -mi386 -Maddr16,data16 boot.bin

clean:
	rm a.img *.bin *.lst
